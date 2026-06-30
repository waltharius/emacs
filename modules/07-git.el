;;; 07-git.el --- Git integration with auto-commit -*- lexical-binding: t; -*-
;;; Commentary:
;; Magit interface + automatic commits for notes and config
;; Auto-commits happen on Emacs exit (C-x C-c or window close)

;;; Code:

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
;; AUTO-COMMIT: Notes
;; ============================================================

(defun my/auto-commit-notes ()
  "Auto-commit notes if changes exist."
  (interactive)
  (let ((notes-dir (expand-file-name "~/notes/")))
    (when (file-directory-p (concat notes-dir ".git"))
      (let ((default-directory notes-dir))
        (when (> (length (shell-command-to-string "git status --porcelain")) 0)
          (let* ((changed-files-raw (shell-command-to-string
                                     "git diff --name-only HEAD | head -5"))
                 (changed-files (mapconcat
                                 (lambda (f) (file-name-nondirectory f))
                                 (split-string changed-files-raw "\n" t)
                                 "\n"))
                 (commit-msg (format "Auto-commit: %s\n\nChanged:\n%s"
                                     (format-time-string "%Y-%m-%d %H:%M")
                                     changed-files)))
            ;; call-process bypasses the shell — safe against filenames
            ;; with apostrophes, semicolons, or other special characters.
            (call-process "git" nil nil nil "add" "-A")
            (call-process "git" nil nil nil "commit" "-m" commit-msg)
            (message "✅ Notes committed: %s" changed-files)))))))

;; ============================================================
;; AUTO-COMMIT: Emacs config
;; ============================================================

(defun my/auto-commit-emacs-config ()
  "Auto-commit Emacs config if changes exist."
  (interactive)
  (let ((default-directory user-emacs-directory))
    (when (> (length (shell-command-to-string "git status --porcelain")) 0)
      (let* ((changed-files-raw (shell-command-to-string
                                 "git diff --name-only HEAD | head -5"))
             (changed-files (mapconcat
                             (lambda (f) (file-name-nondirectory f))
                             (split-string changed-files-raw "\n" t)
                             "\n"))
             (commit-msg (format "Auto-commit config: %s\n\nChanged:\n%s"
                                 (format-time-string "%Y-%m-%d %H:%M")
                                 changed-files)))
        ;; call-process bypasses the shell — safe against filenames
        ;; with apostrophes, semicolons, or other special characters.
        (call-process "git" nil nil nil "add" "-A")
        (call-process "git" nil nil nil "commit" "-m" commit-msg)
        (message "✅ Config committed: %s" changed-files)))))

;; ============================================================
;; AUTO-COMMIT: Combined function
;; ============================================================

(defun my/auto-commit-all ()
  "Auto-commit both notes and config."
  (interactive)
  (my/auto-commit-notes)
  (my/auto-commit-emacs-config)
  (message "Auto-commit: done (notes + config)"))

;; Prevent double commits
(defvar my/auto-commit-done nil
  "Flag to prevent double auto-commits in one session.")

(defun my/auto-commit-all-once ()
  "Auto-commit once per session."
  (unless my/auto-commit-done
    (my/auto-commit-all)
    (setq my/auto-commit-done t)))

;; ============================================================
;; HOOKS: Auto-commit on exit
;; ============================================================

;; Hook 1: On Emacs exit (C-x C-c)
(add-hook 'kill-emacs-hook 'my/auto-commit-all-once)

;; Hook 2: On window close (X button)
(defun my/auto-commit-on-frame-delete (frame)
  "Commit when closing last Emacs window."
  (when (= (length (frame-list)) 1)
    (my/auto-commit-all-once)))

(add-hook 'delete-frame-functions 'my/auto-commit-on-frame-delete)

;; Hook 3: Additional safety
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

(provide '07-git)
;;; 07-git.el ends here
