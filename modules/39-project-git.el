;;; 39-project-git.el --- Project repositories: remote, fetch, staleness -*- lexical-binding: t; -*-
;;; Commentary:
;; Every writing project is its own git repository.  28-writing-projects
;; creates it; this module gives it a remote, keeps an eye on whether it
;; has fallen behind that remote, and says so before any editing starts.
;;
;;   C-c n p G     the menu
;;   C-c n p G c   check this project against its remote now
;;   C-c n p G p   push
;;   C-c n p G r   attach a remote to a project that has none
;;
;; WHY THIS EXISTS.  The projects tree is deliberately outside
;; ~/notes/, so Syncthing does not carry it, so a second machine only
;; has what git gave it.  That is the right trade -- Syncthing
;; replicating .git/ across devices corrupts it -- but it moves the
;; failure from "corrupt repository" to "silently working on a stale
;; copy", and the second failure is quieter.
;;
;; Quieter, not smaller.  Syncthing writing a conflict file is
;; recoverable; three hours of writing on top of a three-week-old copy
;; is a merge nobody wants to do.  The whole point of this module is
;; that git can answer "am I behind" and Syncthing cannot, so the answer
;; gets asked for automatically rather than remembered.
;;
;; WHAT IT DOES NOT DO.  It does not commit, and it does not merge
;; anything that is not a fast-forward.  Committing is a judgement about
;; what a change was for; merging is a judgement about which of two
;; versions is right.  Magit is already bound to C-x g for both.
;;
;; PUSH TO CREATE.  A GitLab project does not have to exist before the
;; first push: pushing to a path that is free in a namespace where you
;; may create projects makes GitLab create it.  So `my/project-git-init'
;; needs no API token and no secret in this configuration -- it just
;; pushes.  Paths that were used before and renamed are the exception;
;; those redirect, and have to be made in the web interface.
;; https://docs.gitlab.com/topics/git/project
;;
;; RELATION TO OTHER MODULES
;; - 28-writing-projects.el supplies the project list and runs
;;   `my/writing-project-created-hook', which is how a new project gets
;;   a remote.  Without that module every command here reports that
;;   there are no projects and does nothing.
;; - 07-git.el owns Magit and the auto-commit of ~/notes and
;;   ~/.emacs.d.  Nothing here touches either.
;; - 12-transient.el, via `my/transient-append'.
;;
;; Docs: ~/.emacs.d/function_helper.org::#project-git

;;; Code:

(require 'subr-x)
(require 'seq)

;; ============================================================
;; OPTIONS
;; ============================================================

(defgroup my/project-git nil
  "Remotes and staleness checks for writing project repositories."
  :group 'my)

(defcustom my/project-git-remote-format
  "ssh://git@gitlab.home.lan:2424/heniekk/%s.git"
  "Remote URL of a project, with %s replaced by the project slug.

The local GitLab instance, in the form its existing repositories
already use.  Change the host here and every project created
afterwards follows; projects that already exist keep the remote they
were given, which is what `my/project-git-set-remote' is for.

SSH rather than HTTP, because the key already exists and is already
managed: modules/services/ssh.nix in the NixOS configuration deploys
`~/.ssh/id_ed25519_gitlab' from sops and matches it to the
`gitlab.home.lan' host, which DNS resolves on the LAN.

HTTP would work as well, but every push would want credentials, and
the usual answer -- `git config --global credential.helper store' --
cannot be given on this system: `~/.config/git/config' is a read-only
symlink into the Nix store, managed by home-manager.  It would have to
go into users/marcin/base/git.nix, and the password would then need a
home of its own.  A key that exists is simpler than a secret that does
not.

The port is explicit because the instance does not listen on 22.  Any
project's clone dropdown shows the exact form."
  :type 'string
  :group 'my/project-git)

(defcustom my/project-git-remote-name "origin"
  "Name of the remote each project repository is given."
  :type 'string
  :group 'my/project-git)

(defcustom my/project-git-branch "main"
  "Branch pushed and tracked.

Set before the first project is created.  Changing it afterwards
renames nothing."
  :type 'string
  :group 'my/project-git)

(defcustom my/project-git-gitignore
  '("# Editor and OS leftovers"
    "*~"
    "\\#*\\#"
    ".\\#*"
    ".DS_Store"
    ""
    "# LaTeX and export by-products"
    "auto/"
    "*.tex.bak")
  "Lines written into a new project's .gitignore.

Exports are NOT ignored.  A .docx sent to a supervisor is a thing that
happened on a date, and a repository that holds it can answer which
version they read."
  :type '(repeat string)
  :group 'my/project-git)

(defcustom my/project-git-auto-pull nil
  "What to do when a project is found to be behind its remote.

nil     say so and stop.
t       pull, but only when the working tree is clean and the pull is
        a fast-forward; otherwise say so and stop.

Off by default, and the two conditions are not negotiable when it is
on.  A pull that merges is a decision about which of two versions is
right, and a program that makes that decision while attention is
elsewhere is worse than one that asks."
  :type '(choice (const :tag "Only warn" nil)
                 (const :tag "Fast-forward a clean tree" t))
  :group 'my/project-git)

(defcustom my/project-git-check-interval 900
  "Seconds before the same repository is checked against its remote again.

Opening six files from one project should cost one fetch, not six."
  :type 'integer
  :group 'my/project-git)

(defcustom my/project-git-check-on-visit t
  "When non-nil, check a project the first time a file in it is opened.

This is the whole mechanism, in the sense that it is the part that
does not rely on remembering.  Turning it off leaves the commands and
removes the reminders."
  :type 'boolean
  :group 'my/project-git)

;; ============================================================
;; RUNNING GIT
;; ============================================================

(defvar my/project-git-log-buffer "*project-git*"
  "Buffer collecting the output of every git command run by this module.

`call-process' with a nil destination discards output, which turns any
failure into a return code with no explanation.  Everything is kept
here instead, so that a push that failed can say why.")

(defun my/project-git--log (dir command output status)
  "Record COMMAND run in DIR, its OUTPUT and exit STATUS."
  (with-current-buffer (get-buffer-create my/project-git-log-buffer)
    (goto-char (point-max))
    (insert (format "\n[%s] %s\n$ git %s\n%s(exit %s)\n"
                    (format-time-string "%Y-%m-%d %H:%M:%S")
                    dir (string-join command " ")
                    (if (string-empty-p output) "" (concat output "\n"))
                    status))))

(defun my/project-git--env ()
  "Return a process environment in which git cannot block on a prompt.

An asynchronous git asked for a password has no terminal to ask on and
would wait forever, holding a process Emacs never reports.  Failing
immediately with a message in the log is the better outcome: it is
visible, and it names the thing that needs configuring."
  (append '("GIT_TERMINAL_PROMPT=0") process-environment))

(defun my/project-git--run (dir &rest args)
  "Run git ARGS in DIR.  Return (STATUS . OUTPUT)."
  (let* ((default-directory (file-name-as-directory dir))
         (process-environment (my/project-git--env))
         (output nil)
         (status
          (with-temp-buffer
            (prog1 (apply #'call-process "git" nil t nil args)
              (setq output (string-trim (buffer-string)))))))
    (my/project-git--log dir args output status)
    (cons status output)))

(defun my/project-git--ok (result)
  "Return the output of RESULT when it succeeded, nil otherwise."
  (and (eq (car result) 0) (cdr result)))

(defun my/project-git--repo-p (dir)
  "Return non-nil when DIR is the root of a git repository."
  (file-directory-p (expand-file-name ".git" dir)))

;; ============================================================
;; PROJECTS
;; ============================================================

(defun my/project-git--slugs ()
  "Return the project slugs, or nil when 28-writing-projects is absent."
  (when (fboundp 'my/writing-project-slugs)
    (ignore-errors (my/writing-project-slugs))))

(defun my/project-git--directory (slug)
  "Return the directory of project SLUG, or nil."
  (when (fboundp 'my/writing--project-directory)
    (ignore-errors (my/writing--project-directory slug))))

(defun my/project-git--read-slug (prompt)
  "Prompt for a project slug."
  (let ((slugs (my/project-git--slugs)))
    (unless slugs (user-error "No writing projects"))
    (completing-read prompt slugs nil t nil nil
                     (when (fboundp 'my/writing--current-project)
                       (my/writing--current-project)))))

(defun my/project-git--current-directory ()
  "Return the project directory the current buffer is in, or nil."
  (let ((file (buffer-file-name)))
    (when file
      (seq-find
       (lambda (dir)
         (and dir (string-prefix-p dir (expand-file-name file))))
       (mapcar #'my/project-git--directory (my/project-git--slugs))))))

;; ============================================================
;; GIVING A PROJECT A REMOTE
;; ============================================================

(defun my/project-git--write-gitignore (dir)
  "Write .gitignore into DIR unless one is already there."
  (let ((file (expand-file-name ".gitignore" dir)))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert (string-join my/project-git-gitignore "\n") "\n")))))

(defun my/project-git--has-remote-p (dir)
  "Return non-nil when DIR already has the configured remote."
  (my/project-git--ok
   (my/project-git--run dir "remote" "get-url" my/project-git-remote-name)))

;;;###autoload
(defun my/project-git-set-remote (slug)
  "Give project SLUG its remote, replacing any existing one."
  (interactive (list (my/project-git--read-slug "Set remote of: ")))
  (let ((dir (my/project-git--directory slug))
        (url (format my/project-git-remote-format slug)))
    (unless (and dir (my/project-git--repo-p dir))
      (user-error "`%s' is not a git repository" slug))
    (my/project-git--run
     dir "remote" (if (my/project-git--has-remote-p dir) "set-url" "add")
     my/project-git-remote-name url)
    (message "%s: %s -> %s" slug my/project-git-remote-name url)))

;;;###autoload
(defun my/project-git-init (slug &optional quiet)
  "Prepare project SLUG for its remote and push it, creating it on GitLab.

Initialises the repository if it has none, writes a .gitignore, makes
the first commit if there is nothing committed yet, attaches the
remote and pushes with upstream tracking.

The push is what creates the GitLab project; nothing has to exist
there first.  QUIET suppresses the report, for the creation hook."
  (interactive (list (my/project-git--read-slug "Publish project: ")))
  (let ((dir (my/project-git--directory slug)))
    (unless (and dir (file-directory-p dir))
      (user-error "No directory for project `%s'" slug))
    (unless (executable-find "git")
      (user-error "git not found"))
    (unless (my/project-git--repo-p dir)
      (my/project-git--run dir "init" "--quiet"
                           "--initial-branch" my/project-git-branch))
    (my/project-git--write-gitignore dir)
    ;; An empty repository has no HEAD, and pushing one pushes nothing.
    (unless (my/project-git--ok (my/project-git--run dir "rev-parse" "HEAD"))
      (my/project-git--run dir "add" "-A")
      (my/project-git--run dir "commit" "-m"
                           (format "Start project '%s'" slug)))
    (my/project-git-set-remote slug)
    (let ((result (my/project-git--run
                   dir "push" "--set-upstream"
                   my/project-git-remote-name my/project-git-branch)))
      (cond
       ((eq (car result) 0)
        (unless quiet (message "%s pushed to %s" slug
                               (format my/project-git-remote-format slug))))
       (t
        (message "%s: push failed, see %s" slug my/project-git-log-buffer))))))

;; The creation hook, so that nothing has to be remembered after
;; `my/writing-project-new'.  Adding to a hook rather than advising the
;; command keeps the dependency one-directional: 28-writing-projects
;; does not know this module exists.
(defun my/project-git--on-project-created (slug _dir)
  "Publish a newly created project.  For `my/writing-project-created-hook'."
  (my/project-git-init slug))

(with-eval-after-load '28-writing-projects
  (when (boundp 'my/writing-project-created-hook)
    (add-hook 'my/writing-project-created-hook
              #'my/project-git--on-project-created)))

;; ============================================================
;; PUSHING
;; ============================================================

;;;###autoload
(defun my/project-git-push (&optional slug)
  "Push the current project, or SLUG."
  (interactive)
  (let* ((dir (or (and slug (my/project-git--directory slug))
                  (my/project-git--current-directory)
                  (my/project-git--directory
                   (my/project-git--read-slug "Push project: ")))))
    (unless (my/project-git--repo-p dir)
      (user-error "Not a git repository: %s" dir))
    (let ((result (my/project-git--run dir "push")))
      (message (if (eq (car result) 0)
                   "Pushed %s"
                 "Push of %s failed, see %s")
               (file-name-nondirectory (directory-file-name dir))
               my/project-git-log-buffer))))

;; ============================================================
;; STALENESS
;; ============================================================
;; The order matters: fetch first, then ask how far behind.  Without the
;; fetch the answer is about whatever the last fetch saw, which on a
;; laptop opened once a month is nothing at all -- and an answer of
;; "up to date" that is three weeks old is worse than no answer, because
;; it will be believed.

(defvar my/project-git--checked (make-hash-table :test #'equal)
  "Directory -> time of last remote check.")

(defun my/project-git--due-p (dir)
  "Return non-nil when DIR has not been checked recently."
  (let ((last (gethash dir my/project-git--checked)))
    (or (null last)
        (> (float-time (time-subtract nil last))
           my/project-git-check-interval))))

(defun my/project-git--divergence (dir)
  "Return (AHEAD . BEHIND) for DIR against its upstream, or nil.
nil means the branch has no upstream, which is not an error: a project
that was never published simply has nothing to be behind."
  (let ((out (my/project-git--ok
              (my/project-git--run dir "rev-list" "--count" "--left-right"
                                   (concat my/project-git-branch "...@{u}")))))
    (when out
      (let ((parts (split-string out "[ \t]+" t)))
        (when (= (length parts) 2)
          (cons (string-to-number (nth 0 parts))
                (string-to-number (nth 1 parts))))))))

(defun my/project-git--clean-p (dir)
  "Return non-nil when DIR has no uncommitted changes."
  (let ((out (my/project-git--ok
              (my/project-git--run dir "status" "--porcelain"))))
    (and out (string-empty-p out))))

(defun my/project-git--revert-buffers (dir)
  "Re-read unmodified buffers visiting files under DIR.

A pull that changes a file already on screen leaves the buffer showing
the old text, and the next save writes it back over the pull.  Buffers
with unsaved edits are left alone: reverting those would discard the
edits, which is the thing this is supposed to prevent."
  (dolist (buffer (buffer-list))
    (let ((file (buffer-file-name buffer)))
      (when (and file
                 (string-prefix-p dir (expand-file-name file))
                 (not (buffer-modified-p buffer))
                 (file-exists-p file))
        (with-current-buffer buffer
          (revert-buffer :ignore-auto :noconfirm))))))

(defun my/project-git--report (dir)
  "Report, and possibly act on, how DIR stands against its remote."
  (let* ((name (file-name-nondirectory (directory-file-name dir)))
         (divergence (my/project-git--divergence dir)))
    (when divergence
      (let ((ahead (car divergence))
            (behind (cdr divergence)))
        (cond
         ((and (= behind 0) (= ahead 0)) nil)
         ((= behind 0)
          (message "%s: %d commit(s) not pushed" name ahead))
         ((> ahead 0)
          ;; Both directions: not a fast-forward whatever the setting.
          (message "%s: diverged -- %d ahead, %d behind.  C-x g to merge"
                   name ahead behind))
         ((not my/project-git-auto-pull)
          (message "%s: %d commit(s) behind.  C-c n p G u to pull"
                   name behind))
         ((not (my/project-git--clean-p dir))
          (message "%s: %d behind, but the working tree is dirty.  C-x g"
                   name behind))
         (t
          (if (eq 0 (car (my/project-git--run dir "merge" "--ff-only" "@{u}")))
              (progn
                (my/project-git--revert-buffers dir)
                (message "%s: pulled %d commit(s)" name behind))
            (message "%s: fast-forward refused, see %s"
                     name my/project-git-log-buffer))))))))

(defun my/project-git--fetch-and-report (dir)
  "Fetch DIR in the background, then report where it stands.

Asynchronous because a fetch talks to the network, and a synchronous
one freezes Emacs for as long as the server takes -- which on a laptop
that is not on the same network is a timeout, not a moment."
  (let ((default-directory (file-name-as-directory dir))
        (process-environment (my/project-git--env))
        (buffer (generate-new-buffer " *project-git-fetch*")))
    (puthash dir (current-time) my/project-git--checked)
    (make-process
     :name "project-git-fetch"
     :buffer buffer
     :command (list "git" "fetch" "--quiet" my/project-git-remote-name)
     :noquery t
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (let ((status (process-exit-status process))
               (output (with-current-buffer buffer
                         (string-trim (buffer-string)))))
           (kill-buffer buffer)
           (my/project-git--log dir '("fetch") output status)
           (if (eq status 0)
               (my/project-git--report dir)
             ;; Not an error worth interrupting for: the server is
             ;; simply not reachable, which on a laptop away from that
             ;; network is the normal case.
             (my/project-git--log
              dir '("fetch") "remote unreachable, staleness unknown" status))))))))

;;;###autoload
(defun my/project-git-check (&optional slug)
  "Fetch the current project, or SLUG, and report where it stands."
  (interactive)
  (let ((dir (or (and slug (my/project-git--directory slug))
                 (my/project-git--current-directory)
                 (my/project-git--directory
                  (my/project-git--read-slug "Check project: ")))))
    (unless (my/project-git--repo-p dir)
      (user-error "Not a git repository: %s" dir))
    (my/project-git--fetch-and-report dir)
    (message "Checking %s..." (file-name-nondirectory
                               (directory-file-name dir)))))

;;;###autoload
(defun my/project-git-check-all ()
  "Fetch every project and report the ones that are not up to date."
  (interactive)
  (let ((dirs (seq-filter #'my/project-git--repo-p
                          (delq nil (mapcar #'my/project-git--directory
                                            (my/project-git--slugs))))))
    (dolist (dir dirs) (my/project-git--fetch-and-report dir))
    (message "Checking %d project(s)..." (length dirs))))

;;;###autoload
(defun my/project-git-pull (&optional slug)
  "Fast-forward the current project, or SLUG, when that is possible."
  (interactive)
  (let* ((dir (or (and slug (my/project-git--directory slug))
                  (my/project-git--current-directory)
                  (my/project-git--directory
                   (my/project-git--read-slug "Pull project: "))))
         (my/project-git-auto-pull t))
    (unless (my/project-git--repo-p dir)
      (user-error "Not a git repository: %s" dir))
    (my/project-git--fetch-and-report dir)))

;; ============================================================
;; THE PART THAT DOES NOT RELY ON REMEMBERING
;; ============================================================

(defun my/project-git--maybe-check ()
  "Check the project of the file just opened, at most occasionally.
For `find-file-hook'."
  (when my/project-git-check-on-visit
    (let ((dir (my/project-git--current-directory)))
      (when (and dir
                 (my/project-git--repo-p dir)
                 (my/project-git--due-p dir))
        (my/project-git--fetch-and-report dir)))))

(add-hook 'find-file-hook #'my/project-git--maybe-check)

;; ============================================================
;; MENU
;; ============================================================

;;;###autoload
(defun my/project-git-show-log ()
  "Show the buffer collecting git output from this module."
  (interactive)
  (pop-to-buffer (get-buffer-create my/project-git-log-buffer)))

(transient-define-prefix my/project-git-menu ()
  "Project repositories."
  [["Remote state"
    ("c" "Check this project"  my/project-git-check)
    ("C" "Check all projects"  my/project-git-check-all)
    ("u" "Pull (fast-forward)" my/project-git-pull)
    ("p" "Push"                my/project-git-push)]
   ["Setup"
    ("i" "Publish to GitLab"   my/project-git-init)
    ("r" "Set remote"          my/project-git-set-remote)]
   ["Elsewhere"
    ("g" "Magit status"        magit-status)
    ("l" "Log buffer"          my/project-git-show-log)]
   [("q" "Quit" transient-quit-one)]])

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    ;; Inside the writing-projects menu, which is where a project is
    ;; already being thought about.  Skipped when that module is absent,
    ;; which is correct: without projects there is nothing to publish.
    (my/transient-append 'my/writing-projects-menu "U"
                         '("G" "Git →" my/project-git-menu))))

(provide '39-project-git)
;;; 39-project-git.el ends here
