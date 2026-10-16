;;; 07-git.el --- Git integration with auto-commit -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: no

;;; Commentary:
;; Magit, plus automatic commits and pushes for the repositories that
;; hold text rather than decisions.
;;
;; Runs after five minutes of idleness and again on exit.  Which
;; repositories are covered comes from
;; `my/auto-commit-repository-sources', to which other modules
;; contribute; this one contributes ~/notes/.
;;
;; Before every push, and once when Emacs starts, each repository is
;; brought up to date with its upstream (`git pull --rebase'), so that
;; two machines editing the same notes one after the other stay in
;; step.  A conflict is never resolved automatically: the pull is
;; undone, nothing is pushed, and a warning says how to resolve it.
;;
;; Docs: ~/.emacs.d/function_helper.org::#auto-commit

;;; Code:

(require 'seq)
(require 'subr-x)

;; ============================================================
;; MAGIT: Git interface for Emacs
;; ============================================================

(use-package magit
  :ensure t
  :bind (("C-x g"   . magit-status)
         ("C-x M-g" . magit-dispatch)
         ("C-c g s" . magit-status)
         ("C-c g l" . magit-log-current)
         ("C-c g b" . magit-blame))
  :config
  (setq magit-refresh-status-buffer t)
  (setq git-commit-summary-max-length 72)
  (setq git-commit-fill-column 72)
  (add-hook 'after-save-hook 'magit-after-save-refresh-status t))


;; ============================================================
;; AUTO-COMMIT AND PUSH
;; ============================================================
;; One mechanism, several repositories.  There used to be two nearly
;; identical functions, one per directory, which meant adding a third
;; directory meant copying thirty lines and remembering to change every
;; string in them.
;;
;; WHAT IS COMMITTED AUTOMATICALLY AND WHAT IS NOT.  Notes and writing
;; projects are a working log: text accumulates, "Auto-commit: <date>"
;; is an accurate description of what happened, and the value is being
;; able to get yesterday's paragraph back.  The Emacs configuration is
;; not: each change there is a decision with a reason worth writing
;; down, and an auto-commit buries the reason and silently absorbs
;; half-finished edits.  That asymmetry is why the config is opt-in.
;;
;; PUSHING is what makes any of this a backup.  A local commit protects
;; against an editing mistake; only a push protects against the disk.
;;
;; TWO MOMENTS.  On five minutes of idleness, and on exit.  Idleness is
;; the important one: it happens while the machine is still on and the
;; network still reachable, and it costs nothing because nobody is
;; typing.  Exit is the safety net.

(defgroup my/git nil
  "Automatic commits of the notes repository (07-git.el)."
  :tag "Automatic commits"
  :group 'mypks-git)

(defun my/auto-commit--notes-directory ()
  "Return the notes folder, the first repository committed automatically."
  (list (expand-file-name my-notes-dir)))

(defvar my/auto-commit-repository-sources
  (list #'my/auto-commit--notes-directory)
  "Functions returning directories to auto-commit.

A list of functions rather than a list of directories so that a module
can contribute repositories this one has never heard of, and so that
the set can be computed rather than fixed: 39-project-git.el adds every
writing project, and the number of those changes during a session;
37-tasks.el adds the planner folder.

A variable for modules, not an option: it was a `defcustom' holding a
lambda, which Customize can neither show nor save meaningfully.")

(defcustom my/auto-commit-config-enabled nil
  "When non-nil, the Emacs configuration repository is auto-committed too.

Disabled 2026-08.  Notes are a working log and \"Auto-commit: <date>\"
on exit is an accurate description of what happened to them.  Config
changes are deliberate and each one has a reason worth writing down; an
auto-commit on exit buries that reason and, worse, silently absorbs
half-finished edits into the history.  `my/commit-config-now' still
commits by hand."
  :type 'boolean
  :group 'my/git)

(defcustom my/auto-commit-push t
  "When non-nil, push after committing.

A commit protects against an editing mistake.  Only a push protects
against the disk, and the local GitLab exists for exactly that.

Turned off, nothing reaches the other machines -- every cycle and
`C-c v ?' say so.  To keep one folder from pushing (a test copy of the
notes), list it in `my/auto-commit-no-push-directories' instead."
  :type 'boolean
  :group 'my/git)

(defcustom my/auto-commit-no-push-directories nil
  "Repositories committed automatically but never pushed.

For a copy of the notes with the same remote as the original, made to
test a new notes folder: its commits must not reach the server.  Added
by the question after such a copy (00-core.el).  Every other repository
keeps pushing; until 2026-10-16 that question turned pushing off for
all of them, and switching back to the original folder left it off."
  :type '(repeat directory)
  :group 'my/git)

(defun my/auto-commit--push-p (dir)
  "Return non-nil when commits in DIR are to be pushed."
  (and my/auto-commit-push
       (not (member (file-name-as-directory (expand-file-name dir))
                    (mapcar (lambda (d) (file-name-as-directory (expand-file-name d)))
                            my/auto-commit-no-push-directories)))))

(defcustom my/auto-commit-pull t
  "When non-nil, pull from the upstream at startup and before each push.

The notes live on several machines and are synchronised
through the local GitLab only.  Without pulling, the second machine
keeps writing on top of an old state: its push is rejected and its
automatic commits silently diverge from the server.  Pulling with
--rebase puts this machine's commits on top of what the other one
pushed, which is exactly what happened in time when the machines are
used one after the other."
  :type 'boolean
  :group 'my/git)

(defcustom my/auto-commit-idle-seconds 300
  "Seconds of idleness before an automatic commit and push.

Five minutes: long enough that it never fires mid-sentence, short
enough that a coffee break is a backup.  Takes effect at once."
  :type 'integer
  :set (my/settings-apply-on-set #'my/auto-commit--arm-timer)
  :group 'my/git)

(defcustom my/auto-commit-confirm-exit t
  "When non-nil, quitting Emacs asks first if work is not on the server.

Before Emacs exits, every repository is committed and pushed once more.
If one still has uncommitted changes, commits its server does not have,
a stopped rebase or a lock left by an interrupted git command, the
question names it, and answering no keeps Emacs open.  Away from the
server this asks every time, which is the point: the other machine
will not see the work."
  :type 'boolean
  :group 'my/git)

(defvar my/auto-commit-log-buffer "*auto-commit*"
  "Buffer collecting git output from automatic commits and pushes.")

(defun my/auto-commit--env ()
  "Return a process environment in which git cannot hang.

`GIT_TERMINAL_PROMPT=0' stops git asking for credentials it has no
terminal to ask on.  The SSH timeout bounds the other way this can
hang: a push on `kill-emacs-hook' runs synchronously, so an unreachable
server would otherwise hold Emacs open for the full TCP timeout, and
the symptom would be an editor that will not close."
  (append '("GIT_TERMINAL_PROMPT=0"
            "GIT_SSH_COMMAND=ssh -o ConnectTimeout=5 -o BatchMode=yes")
          process-environment))

(defun my/auto-commit--git (dir &rest args)
  "Run git ARGS in DIR, logging output.  Return the exit status."
  (let* ((default-directory (file-name-as-directory dir))
         (process-environment (my/auto-commit--env))
         output
         (status (with-temp-buffer
                   (prog1 (apply #'call-process "git" nil t nil args)
                     (setq output (string-trim (buffer-string)))))))
    (with-current-buffer (get-buffer-create my/auto-commit-log-buffer)
      (goto-char (point-max))
      (insert (format "\n[%s] %s\n$ git %s\n%s(exit %s)\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")
                      dir (string-join args " ")
                      (if (string-empty-p output) "" (concat output "\n"))
                      status)))
    status))

(defun my/auto-commit--dirty-p (dir)
  "Return non-nil when DIR has uncommitted changes."
  (let ((default-directory (file-name-as-directory dir)))
    (not (string-empty-p
          (string-trim
           (shell-command-to-string "git status --porcelain"))))))

(defun my/auto-commit--unpushed-p (dir)
  "Return non-nil when DIR has commits its upstream does not."
  (let ((default-directory (file-name-as-directory dir)))
    (not (string-empty-p
          (string-trim
           (shell-command-to-string
            "git rev-list --count @{u}..HEAD 2>/dev/null | grep -v '^0$'"))))))

;; ============================================================
;; PULL: KEEPING SEVERAL MACHINES IN STEP
;; ============================================================
;; `git pull --rebase --autostash' replays this machine's commits on
;; top of the upstream.  Three outcomes:
;;
;;   ok        up to date; buffers visiting changed files are reloaded
;;             by `global-auto-revert-mode' (02-editing.el)
;;   offline   the server could not be reached (away from home, GitLab
;;             down).  Nothing changes; work goes on locally and is
;;             pushed by a later cycle.
;;   conflict  the same lines were changed here and on the server.  The
;;             rebase is aborted at once, so the repository is exactly
;;             as before the pull and no file holds conflict markers.
;;             Nothing is pushed and a warning appears once.  Automatic
;;             commits continue locally; `my/auto-commit-resolve' runs
;;             the pull by hand and opens Magit on the conflict.
;;
;; While a rebase or merge is in progress (someone resolving a conflict
;; by hand), the repository is left alone completely: an automatic
;; `git add -A' at that moment would commit the conflict markers.

(defvar my/auto-commit--conflicts nil
  "Repositories whose last pull stopped on a conflict (already warned).")

(defun my/auto-commit--git-path (dir path)
  "Return the absolute path of PATH inside DIR's git directory."
  (let ((default-directory (file-name-as-directory dir)))
    (expand-file-name
     (string-trim
      (shell-command-to-string
       (format "git rev-parse --git-path %s" (shell-quote-argument path)))))))

(defun my/auto-commit--busy-p (dir)
  "Return non-nil when a rebase or merge is in progress in DIR."
  (seq-some (lambda (path)
              (file-exists-p (my/auto-commit--git-path dir path)))
            '("rebase-merge" "rebase-apply" "MERGE_HEAD")))

(defun my/auto-commit--has-upstream-p (dir)
  "Return non-nil when DIR's current branch tracks an upstream branch."
  (let ((default-directory (file-name-as-directory dir)))
    (eq 0 (call-process "git" nil nil nil
                        "rev-parse" "--abbrev-ref" "--symbolic-full-name" "@{u}"))))

(defun my/auto-commit--head (dir)
  "Return the commit DIR's HEAD points to."
  (let ((default-directory (file-name-as-directory dir)))
    (string-trim (shell-command-to-string "git rev-parse HEAD"))))

(defun my/auto-commit--warn-conflict (dir)
  "Warn once that pulling DIR stopped on a conflict."
  (unless (member dir my/auto-commit--conflicts)
    (push dir my/auto-commit--conflicts)
    (display-warning
     'auto-commit
     (format "%s: the server has changes to the same lines as this machine.

Nothing was overwritten and nothing was pushed; the pull was undone.
Your work keeps being committed locally.  To merge both versions:

  M-x my/auto-commit-resolve   pull again and open Magit on the conflict
                               (resolve in the file with C-c ^ ...,
                               then `r r' in Magit to continue)

Details: M-x my/auto-commit-show-log"
             (abbreviate-file-name dir))
     :warning)))

(defun my/auto-commit--pull (dir)
  "Rebase DIR's local commits onto its upstream.

Return `ok', `offline', `conflict', `busy' or `no-upstream'.  On a
conflict the rebase is aborted, leaving DIR exactly as it was."
  (cond
   ((my/auto-commit--busy-p dir) 'busy)
   ((not (my/auto-commit--has-upstream-p dir)) 'no-upstream)
   ((eq 0 (my/auto-commit--git dir "pull" "--rebase" "--autostash"))
    (setq my/auto-commit--conflicts (delete dir my/auto-commit--conflicts))
    'ok)
   ((my/auto-commit--busy-p dir)
    (my/auto-commit--git dir "rebase" "--abort")
    (my/auto-commit--warn-conflict dir)
    'conflict)
   (t 'offline)))

;; ============================================================
;; WHEN SOMETHING STOPS IT
;; ============================================================
;; The idle cycle is quiet by design, and that made two failures
;; invisible: a `.git/index.lock' left by a git command that was
;; interrupted (Emacs killed during the exit commit, a crash), on which
;; every `git add' fails; and a rebase or merge left in progress, during
;; which the repository is skipped on purpose.  Either stopped commits
;; and pushes for good while the editor looked normal.  After every
;; cycle each repository is now asked what, if anything, keeps its work
;; off the server, and a new answer is shown as a warning -- once, until
;; it changes or clears.

(defvar my/auto-commit--reported nil
  "Alist of (DIRECTORY . REASON) already shown as a warning.")

(defun my/auto-commit--locked-p (dir)
  "Return non-nil when DIR's index is locked by another git command."
  (file-exists-p (my/auto-commit--git-path dir "index.lock")))

(defconst my/auto-commit--push-off-reason
  "commits not pushed: pushing is turned off"
  "The reason `my/auto-commit-pending' gives when pushing was turned off.")

(defun my/auto-commit-pending (dir)
  "Return why DIR's work is not on its server, or nil when it is.

Nil for a repository without an upstream branch, a local one by
choice.  Unpushed commits while pushing is turned off for DIR are
reported too, with their own reason: a switch turned off and forgotten
looks exactly like a push that silently stopped."
  (setq dir (expand-file-name dir))
  (when (file-directory-p (expand-file-name ".git" dir))
    (cond
     ((my/auto-commit--busy-p dir) "a rebase or merge is in progress")
     ((my/auto-commit--locked-p dir) "git is locked (.git/index.lock)")
     ((my/auto-commit--dirty-p dir) "changes not committed")
     ((not (and (my/auto-commit--has-upstream-p dir)
                (my/auto-commit--unpushed-p dir)))
      nil)
     ((my/auto-commit--push-p dir) "commits not pushed")
     (t my/auto-commit--push-off-reason))))

(defun my/auto-commit--advice (dir reason)
  "Return what to do about REASON in DIR, as text."
  (let ((git (abbreviate-file-name (expand-file-name ".git" dir))))
    (pcase reason
      ("git is locked (.git/index.lock)"
       (format "  A git command was interrupted and left its lock.  If no git
  is running now, remove it:  rm %s/index.lock" git))
      ("a rebase or merge is in progress"
       "  Finish or abort it: M-x my/auto-commit-resolve, or in Magit
  `r r' (continue) / `r a' (abort).")
      ("changes not committed"
       "  The commit failed; the reason is in the log (C-c v l).")
      ((pred (equal my/auto-commit--push-off-reason))
       (if my/auto-commit-push
           (format "  %s is in `my/auto-commit-no-push-directories' (C-c n , ,
  -> Tools -> Git).  Remove it there to push again."
                   (abbreviate-file-name dir))
         "  `my/auto-commit-push' is off: M-x customize-option RET
  my/auto-commit-push (or C-c n , , -> Tools -> Git).  Turn it on,
  Apply and Save; C-c v a pushes at once."))
      (_
       "  The server was unreachable or refused the push; the log
  (C-c v l) says which.  Pushed by the next cycle once it is back."))))

(defun my/auto-commit--report (dirs)
  "Warn about every repository in DIRS whose work is not on its server.
Each (directory . reason) is shown once; it is forgotten when it clears,
so that the next failure is shown again."
  (let (new)
    (dolist (dir dirs)
      (let* ((dir (expand-file-name dir))
             (reason (condition-case err (my/auto-commit-pending dir)
                       (error (error-message-string err))))
             (old (assoc dir my/auto-commit--reported)))
        (cond
         ((null reason)
          (setq my/auto-commit--reported (delq old my/auto-commit--reported)))
         ((equal reason (cdr old)) nil)
         (t
          (setq my/auto-commit--reported
                (cons (cons dir reason) (delq old my/auto-commit--reported)))
          (push (cons dir reason) new)))))
    (when new
      (display-warning
       'auto-commit
       (concat "Work that is NOT on the server:\n\n"
               (mapconcat (lambda (entry)
                            (format "%s: %s\n%s"
                                    (abbreviate-file-name (car entry))
                                    (cdr entry)
                                    (my/auto-commit--advice (car entry) (cdr entry))))
                          (nreverse new) "\n\n")
               "\n\nCheck at any time: C-c v ?   Git output: C-c v l")
       :warning))))

;;;###autoload
(defun my/auto-commit-status ()
  "Say, for every auto-committed repository, whether its work is on the server."
  (interactive)
  (let ((lines (mapcar (lambda (dir)
                         (format "%s: %s" (abbreviate-file-name dir)
                                 (or (ignore-errors (my/auto-commit-pending dir))
                                     "on the server")))
                       (seq-filter (lambda (d) (file-directory-p
                                                (expand-file-name ".git" d)))
                                   (my/auto-commit-directories)))))
    (message "%s" (string-join lines "\n"))
    lines))

(defun my/auto-commit-repository (dir)
  "Commit and push DIR when there is anything to commit or push.

Returns a short description of what happened, or nil when nothing did."
  (setq dir (expand-file-name dir))
  (when (and (file-directory-p dir)
             (file-directory-p (expand-file-name ".git" dir))
             (not (my/auto-commit--busy-p dir)))
    (let ((name (file-name-nondirectory (directory-file-name dir)))
          (committed nil)
          (pulled nil)
          (pull-result nil))
      (when (my/auto-commit--dirty-p dir)
        ;; call-process rather than a shell: safe against file names
        ;; with apostrophes, semicolons or spaces, of which a Denote
        ;; collection with Polish titles has plenty.
        (my/auto-commit--git dir "add" "-A")
        ;; Listed AFTER staging, from the index.  `git diff --name-only
        ;; HEAD' before staging left out new files -- new notes, the most
        ;; common change of all -- and failed in a repository without a
        ;; first commit.
        (let* ((default-directory (file-name-as-directory dir))
               (files (ignore-errors
                        (process-lines "git" "diff" "--cached" "--name-only")))
               (message-text
                (format "Auto-commit: %s\n\nChanged (%d):\n%s%s"
                        (format-time-string "%Y-%m-%d %H:%M")
                        (length files)
                        (mapconcat #'file-name-nondirectory (seq-take files 5) "\n")
                        (if (> (length files) 5)
                            (format "\n... and %d more" (- (length files) 5))
                          ""))))
          (setq committed (eq 0 (my/auto-commit--git
                                 dir "commit" "-m" message-text)))))
      ;; Pull before pushing: a push on top of an old state is rejected,
      ;; and a rejected push is easy to miss in an idle cycle.
      (when my/auto-commit-pull
        (let ((before (my/auto-commit--head dir)))
          (setq pull-result (my/auto-commit--pull dir))
          (setq pulled (and (eq pull-result 'ok)
                            (not (equal before (my/auto-commit--head dir)))))))
      (let ((pushed
             (when (and (my/auto-commit--push-p dir)
                        (memq pull-result '(nil ok no-upstream))
                        (my/auto-commit--unpushed-p dir))
               (eq 0 (my/auto-commit--git dir "push")))))
        (let ((parts (delq nil (list (and committed "committed")
                                     (and pulled "pulled")
                                     (and pushed "pushed")
                                     (and (eq pull-result 'offline)
                                          "server unreachable")
                                     (and (eq pull-result 'conflict)
                                          "CONFLICT, not pushed")))))
          (when parts
            (format "%s: %s" name (string-join parts ", "))))))))

(defun my/auto-commit-directories ()
  "Return every directory that should be committed automatically."
  (delete-dups
   (append (seq-mapcat (lambda (fn) (ignore-errors (funcall fn)))
                       my/auto-commit-repository-sources)
           (when my/auto-commit-config-enabled
             (list (expand-file-name user-emacs-directory))))))

(defun my/auto-commit--save-buffers ()
  "Save modified buffers visiting files inside the auto-committed repositories.

Without this, the exit-time commit records what is on disk while the
last paragraph is still only in a buffer.  Nothing is lost -- the next
session's idle timer catches it -- but a commit that reports success
and does not contain the work is worse than no commit, because it will
be believed.

Only files under those directories, and never anything inside `.git/':
saving every modified buffer would reach scratch buffers and files
opened for reference, and git's own COMMIT_EDITMSG is not text anyone
wants preserved."
  (let ((dirs (my/auto-commit-directories)))
    (dolist (buffer (buffer-list))
      (let ((file (buffer-file-name buffer)))
        (when (and file
                   (buffer-modified-p buffer)
                   (not (string-match-p "/\\.git/" file))
                   (seq-some (lambda (dir)
                               (string-prefix-p (file-name-as-directory dir)
                                                (expand-file-name file)))
                             dirs))
          (with-current-buffer buffer
            (ignore-errors (save-buffer))))))))

;;;###autoload
(defun my/auto-commit-all ()
  "Commit and push every repository that needs it."
  (interactive)
  (my/auto-commit--save-buffers)
  (let* ((dirs (my/auto-commit-directories))
         ;; One repository failing must not stop the others.
         (results (delq nil (mapcar
                             (lambda (dir)
                               (condition-case err
                                   (my/auto-commit-repository dir)
                                 (error (format "%s: ERROR %s"
                                                (abbreviate-file-name dir)
                                                (error-message-string err)))))
                             dirs))))
    (when results
      (message "%s" (string-join results "; ")))
    (my/auto-commit--report dirs)
    results))

;;;###autoload
(defun my/auto-commit-show-log ()
  "Show the git output of automatic commits and pushes."
  (interactive)
  (pop-to-buffer (get-buffer-create my/auto-commit-log-buffer)))

;;;###autoload
(defun my/auto-commit-pull-all ()
  "Bring every auto-committed repository up to date with its upstream."
  (interactive)
  (let ((results
         (delq nil
               (mapcar
                (lambda (dir)
                  (when (file-directory-p (expand-file-name ".git" dir))
                    (let* ((name (file-name-nondirectory
                                  (directory-file-name dir)))
                           (before (my/auto-commit--head dir))
                           (result (my/auto-commit--pull dir)))
                      (pcase result
                        ('ok (unless (equal before (my/auto-commit--head dir))
                               (format "%s: updated from the server" name)))
                        ('offline (format "%s: server unreachable, working offline"
                                          name))
                        ('conflict (format "%s: CONFLICT, see *Warnings*" name))
                        ('busy (format "%s: rebase or merge in progress" name))
                        (_ nil)))))
                (mapcar #'expand-file-name (my/auto-commit-directories))))))
    (when results
      (message "%s" (string-join results "; ")))
    results))

;;;###autoload
(defun my/auto-commit-resolve (&optional dir)
  "Pull DIR (default ~/notes/) with --rebase and leave a conflict open in Magit.

The automatic pull undoes a conflicting rebase so that nothing is ever
left half-done.  This command does the same pull by hand and stops on
the conflict: Magit lists the conflicted files, `C-c ^' (smerge) picks
between the versions inside a file, and `r r' in Magit continues the
rebase.  The next automatic cycle pushes the result."
  (interactive)
  (let* ((dir (file-name-as-directory
               (expand-file-name (or dir my-notes-dir))))
         (default-directory dir))
    (my/auto-commit--save-buffers)
    (when (my/auto-commit--dirty-p dir)
      (my/auto-commit-repository dir))
    (unless (my/auto-commit--busy-p dir)
      (my/auto-commit--git dir "pull" "--rebase"))
    (setq my/auto-commit--conflicts (delete dir my/auto-commit--conflicts))
    (magit-status dir)))

;; ============================================================
;; WHEN IT RUNS
;; ============================================================

;; At startup, before `desktop-save-mode' reopens the files of the last
;; session (it does so from `after-init-hook' at the default depth), so
;; buffers open on the latest version.  All modules are loaded by then,
;; so the writing projects of 39-project-git.el are included.  Away from
;; home this costs at most the SSH connect timeout (5 s) per repository.
(add-hook 'after-init-hook
          (lambda ()
            (when my/auto-commit-pull
              (ignore-errors (my/auto-commit-pull-all))))
          -90)

(defvar my/auto-commit--idle-timer nil
  "Repeating idle timer running `my/auto-commit-all'.")

(defun my/auto-commit--on-idle ()
  "Commit and push, quietly, after a period of idleness."
  (let ((inhibit-message t))
    (ignore-errors (my/auto-commit-all))))

(defun my/auto-commit--arm-timer ()
  "Start the idle timer, replacing a running one.
Called at load and whenever `my/auto-commit-idle-seconds' changes."
  (when (timerp my/auto-commit--idle-timer)
    (cancel-timer my/auto-commit--idle-timer))
  (setq my/auto-commit--idle-timer
        (run-with-idle-timer my/auto-commit-idle-seconds t
                             #'my/auto-commit--on-idle)))

(my/auto-commit--arm-timer)

;; The exit path still runs once per session.  With the idle timer in
;; place it usually finds nothing to do, which is the point: the work
;; has already happened, on a machine that was on and a network that was
;; up.
(defvar my/auto-commit-done nil
  "Set once the exit-time commit has run, to prevent it running twice.")

(defun my/auto-commit-all-once ()
  "Commit and push once per session, on the way out."
  (unless my/auto-commit-done
    (ignore-errors (my/auto-commit-all))
    (setq my/auto-commit-done t)))

(add-hook 'kill-emacs-hook 'my/auto-commit-all-once)

(defun my/auto-commit-on-frame-delete (frame)
  "Commit when closing the last Emacs window."
  (when (= (length (frame-list)) 1)
    (my/auto-commit-all-once)))

(add-hook 'delete-frame-functions 'my/auto-commit-on-frame-delete)

(defun my/auto-commit--before-kill (&rest _)
  "Commit before `save-buffers-kill-emacs' asks about anything.
Named so that it can be removed with `advice-remove'."
  (my/auto-commit-all-once))

(advice-add 'save-buffers-kill-emacs :before #'my/auto-commit--before-kill)

;; The last word before quitting.  `kill-emacs-query-functions' run
;; after the buffers have been saved, so one more cycle commits what
;; the save just wrote; a function returning nil cancels the quit.
(defun my/auto-commit--confirm-exit ()
  "Commit and push once more; ask before quitting if work is still only here."
  (if (or noninteractive (not my/auto-commit-confirm-exit))
      t
    (ignore-errors (my/auto-commit-all))
    (setq my/auto-commit-done t)
    (let ((pending
           (delq nil (mapcar (lambda (dir)
                               (let ((reason (ignore-errors
                                               (my/auto-commit-pending dir))))
                                 ;; A folder kept from pushing on
                                 ;; purpose (a test copy) is not asked
                                 ;; about at every exit.
                                 (and reason
                                      (not (and (equal reason my/auto-commit--push-off-reason)
                                                my/auto-commit-push))
                                      (format "%s (%s)"
                                              (abbreviate-file-name dir)
                                              reason))))
                             (my/auto-commit-directories)))))
      (or (null pending)
          (yes-or-no-p (format "Not on the server: %s.  Quit anyway? "
                               (string-join pending "; ")))))))

(add-hook 'kill-emacs-query-functions #'my/auto-commit--confirm-exit)

;; ============================================================
;; MANUAL COMMIT FUNCTIONS
;; ============================================================

(defun my/commit-notes-now ()
  "Manually commit notes changes."
  (interactive)
  (let ((default-directory (expand-file-name my-notes-dir)))
    (magit-stage-all)
    (magit-commit-create)))

(defun my/commit-config-now ()
  "Manually commit config changes."
  (interactive)
  (let ((default-directory (expand-file-name user-emacs-directory)))
    (call-process "git" nil nil nil "add" "init.el" "modules/" ".gitignore")
    (magit-status)))

;; ============================================================
;; GIT STATUS FUNCTIONS
;; ============================================================

(defun my/notes-git-status ()
  "Open Magit status for notes."
  (interactive)
  (let ((default-directory (expand-file-name my-notes-dir)))
    (magit-status)))

(defun my/config-git-status ()
  "Open Magit status for config."
  (interactive)
  (let ((default-directory (expand-file-name user-emacs-directory)))
    (magit-status)))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

;; Notes
(global-set-key (kbd "C-c v s") 'my/notes-git-status)
(global-set-key (kbd "C-c v c") 'my/commit-notes-now)

;; Config
(global-set-key (kbd "C-c v S") 'my/config-git-status)
(global-set-key (kbd "C-c v C") 'my/commit-config-now)

;; Current file
(global-set-key (kbd "C-c v d") 'magit-diff-buffer-file)
(global-set-key (kbd "C-c v h") 'magit-log-buffer-file)

;; Auto-commit
(global-set-key (kbd "C-c v a") 'my/auto-commit-all)
(global-set-key (kbd "C-c v l") 'my/auto-commit-show-log)
(global-set-key (kbd "C-c v ?") 'my/auto-commit-status)

(provide '07-git)
;;; 07-git.el ends here
