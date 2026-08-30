;;; 07-git.el --- Git integration with auto-commit -*- lexical-binding: t; -*-
;;; Commentary:
;; Magit, plus automatic commits and pushes for the repositories that
;; hold text rather than decisions.
;;
;; Runs after five minutes of idleness and again on exit.  Which
;; repositories are covered comes from
;; `my/auto-commit-repository-sources', to which other modules
;; contribute; this one contributes ~/notes/.
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

(defcustom my/auto-commit-repository-sources
  (list (lambda () (list (expand-file-name "~/notes/"))))
  "Functions returning directories to auto-commit.

A list of functions rather than a list of directories so that a module
can contribute repositories this one has never heard of, and so that
the set can be computed rather than fixed: 39-project-git.el adds every
writing project, and the number of those changes during a session."
  :type '(repeat function)
  :group 'my)

(defcustom my/auto-commit-config-enabled nil
  "When non-nil, the Emacs configuration repository is auto-committed too.

Disabled 2026-08.  Notes are a working log and \"Auto-commit: <date>\"
on exit is an accurate description of what happened to them.  Config
changes are deliberate and each one has a reason worth writing down; an
auto-commit on exit buries that reason and, worse, silently absorbs
half-finished edits into the history.  `my/commit-config-now' still
commits by hand."
  :type 'boolean
  :group 'my)

(defcustom my/auto-commit-push t
  "When non-nil, push after committing.

A commit protects against an editing mistake.  Only a push protects
against the disk, and the local GitLab exists for exactly that."
  :type 'boolean
  :group 'my)

(defcustom my/auto-commit-idle-seconds 300
  "Seconds of idleness before an automatic commit and push.

Five minutes: long enough that it never fires mid-sentence, short
enough that a coffee break is a backup."
  :type 'integer
  :group 'my)

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

(defun my/auto-commit-repository (dir)
  "Commit and push DIR when there is anything to commit or push.

Returns a short description of what happened, or nil when nothing did."
  (setq dir (expand-file-name dir))
  (when (and (file-directory-p dir)
             (file-directory-p (expand-file-name ".git" dir)))
    (let ((name (file-name-nondirectory (directory-file-name dir)))
          (committed nil))
      (when (my/auto-commit--dirty-p dir)
        (let* ((default-directory (file-name-as-directory dir))
               (changed (mapconcat
                         #'file-name-nondirectory
                         (split-string
                          (shell-command-to-string
                           "git diff --name-only HEAD | head -5")
                          "\n" t)
                         "\n"))
               (message-text (format "Auto-commit: %s\n\nChanged:\n%s"
                                     (format-time-string "%Y-%m-%d %H:%M")
                                     changed)))
          ;; call-process rather than a shell: safe against file names
          ;; with apostrophes, semicolons or spaces, of which a Denote
          ;; collection with Polish titles has plenty.
          (my/auto-commit--git dir "add" "-A")
          (setq committed (eq 0 (my/auto-commit--git
                                 dir "commit" "-m" message-text)))))
      (let ((pushed
             (when (and my/auto-commit-push (my/auto-commit--unpushed-p dir))
               (eq 0 (my/auto-commit--git dir "push")))))
        (cond ((and committed pushed) (format "%s: committed, pushed" name))
              (committed              (format "%s: committed" name))
              (pushed                 (format "%s: pushed" name))
              (t nil))))))

(defun my/auto-commit-directories ()
  "Return every directory that should be committed automatically."
  (delete-dups
   (append (seq-mapcat (lambda (fn) (ignore-errors (funcall fn)))
                       my/auto-commit-repository-sources)
           (when my/auto-commit-config-enabled
             (list (expand-file-name user-emacs-directory))))))

;;;###autoload
(defun my/auto-commit-all ()
  "Commit and push every repository that needs it."
  (interactive)
  (let ((results (delq nil (mapcar #'my/auto-commit-repository
                                   (my/auto-commit-directories)))))
    (when results
      (message "%s" (string-join results "; ")))
    results))

;;;###autoload
(defun my/auto-commit-show-log ()
  "Show the git output of automatic commits and pushes."
  (interactive)
  (pop-to-buffer (get-buffer-create my/auto-commit-log-buffer)))

;; ============================================================
;; WHEN IT RUNS
;; ============================================================

(defvar my/auto-commit--idle-timer nil
  "Repeating idle timer running `my/auto-commit-all'.")

(defun my/auto-commit--on-idle ()
  "Commit and push, quietly, after a period of idleness."
  (let ((inhibit-message t))
    (ignore-errors (my/auto-commit-all))))

(setq my/auto-commit--idle-timer
      (run-with-idle-timer my/auto-commit-idle-seconds t
                           #'my/auto-commit--on-idle))

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

(advice-add 'save-buffers-kill-emacs :before
            (lambda (&rest _) (my/auto-commit-all-once)))

;; ============================================================
;; MANUAL COMMIT FUNCTIONS
;; ============================================================

(defun my/commit-notes-now ()
  "Manually commit notes changes."
  (interactive)
  (let ((default-directory (expand-file-name "~/notes/")))
    (magit-stage-all)
    (magit-commit-create)))

(defun my/commit-config-now ()
  "Manually commit config changes."
  (interactive)
  (let ((default-directory (expand-file-name "~/.emacs.d/")))
    (shell-command "git add init.el modules/ .gitignore")
    (magit-status)))

;; ============================================================
;; GIT STATUS FUNCTIONS
;; ============================================================

(defun my/notes-git-status ()
  "Open Magit status for notes."
  (interactive)
  (let ((default-directory (expand-file-name "~/notes/")))
    (magit-status)))

(defun my/config-git-status ()
  "Open Magit status for config."
  (interactive)
  (let ((default-directory (expand-file-name "~/.emacs.d/")))
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

(provide '07-git)
;;; 07-git.el ends here
