;;; 07-git.el --- Git integration with Magit  -*- lexical-binding: t; -*-
;;
;; Description: Magit (Git interface), automatyczne commity notatek + config,
;;              działa z C-x C-c i krzyżykiem w oknie!
;;
;;; Code:

;; --- Magit: Git interface dla Emacsa ---
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

;; --- Funkcja: Auto-commit notatek ---
(defun my/auto-commit-notes ()
  "Auto-commit notes TYLKO gdy coś się zmieniło, z lepszym message."
  (interactive)
  (let ((notes-dir (expand-file-name "~/notes/")))
    (when (file-directory-p (concat notes-dir ".git"))
      (let ((default-directory notes-dir))
        ;; Check if there are changes
        (when (> (length (shell-command-to-string "git status --porcelain")) 0)
          ;; Get list of changed files (only filenames, not paths)
          (let* ((changed-files-raw (shell-command-to-string 
                                     "git diff --name-only HEAD | head -5"))
                 (changed-files (mapconcat 
                                 (lambda (f) 
                                   (file-name-nondirectory f))
                                 (split-string changed-files-raw "\n" t)
                                 "\n"))
                 (commit-msg (format "Auto-commit: %s\n\nChanged:\n%s"
                                     (format-time-string "%Y-%m-%d %H:%M")
                                     changed-files)))
            (shell-command "git add -A 2>&1")
            (shell-command (format "git commit -m '%s' 2>&1 || true" commit-msg))
            (message "✅ Notes committed: %s" changed-files)))))))

;; --- Funkcja: Auto-commit konfiguracji Emacsa ---
;; --- Funkcja: Auto-commit konfiguracji Emacsa ---
(defun my/auto-commit-emacs-config ()
  "Auto-commit Emacs config TYLKO gdy coś się zmieniło, z lepszym message."
  (interactive)
  (let ((default-directory user-emacs-directory))
    ;; Check if there are changes
    (when (> (length (shell-command-to-string "git status --porcelain")) 0)
      ;; Get list of changed files (only module names)
      (let* ((changed-files-raw (shell-command-to-string 
                                 "git diff --name-only HEAD | head -5"))
             (changed-files (mapconcat 
                             (lambda (f) 
                               (file-name-nondirectory f))
                             (split-string changed-files-raw "\n" t)
                             "\n"))
             (commit-msg (format "Auto-commit config: %s\n\nChanged:\n%s"
                                 (format-time-string "%Y-%m-%d %H:%M")
                                 changed-files)))
        (shell-command "git add -A 2>&1")
        (shell-command (format "git commit -m '%s' 2>&1 || true" commit-msg))
        (message "✅ Emacs config committed: %s" changed-files)))))

;; --- Funkcja zbiorowa: Commit wszystkiego ---
(defun my/auto-commit-all ()
  "Auto-commit: notatki + konfiguracja."
  (interactive)
  (my/auto-commit-notes)
  (my/auto-commit-emacs-config)
  (message "Auto-commit: zakończono (notes + config)"))

;; --- Flaga: zapobiegaj podwójnemu commitowi ---
(defvar my/auto-commit-done nil
  "Flaga: czy commit już został wykonany w tej sesji.")

;; --- Wrapper z flagą ---
(defun my/auto-commit-all-once ()
  "Auto-commit (tylko raz na sesję)."
  (unless my/auto-commit-done
    (my/auto-commit-all)
    (setq my/auto-commit-done t)))

;; --- Hook 1: Przy zamykaniu Emacsa (C-x C-c) ---
(add-hook 'kill-emacs-hook 'my/auto-commit-all-once)

;; --- Hook 2: Przy zamykaniu ostatniego okna (krzyżyk X) ---
(defun my/auto-commit-on-frame-delete (frame)
  "Commit jeśli zamykamy ostatnie okno Emacsa."
  (when (= (length (frame-list)) 1)
    (my/auto-commit-all-once)))

(add-hook 'delete-frame-functions 'my/auto-commit-on-frame-delete)

;; --- Hook 3: Przed save-buffers-kill-emacs (dodatkowe zabezpieczenie) ---
(advice-add 'save-buffers-kill-emacs :before
            (lambda (&rest _) (my/auto-commit-all-once)))

;; --- Funkcja: Commit notatek TERAZ (manual) ---
(defun my/commit-notes-now ()
  "Zacommituj wszystkie zmiany w notatkach (interactive)."
  (interactive)
  (let ((default-directory (expand-file-name "~/notes/")))
    (magit-stage-all)
    (magit-commit-create)))

;; --- Funkcja: Commit config TERAZ (manual) ---
(defun my/commit-config-now ()
  "Zacommituj zmiany w konfiguracji (interactive)."
  (interactive)
  (let ((default-directory (expand-file-name "~/.emacs.d/")))
    (shell-command "git add init.el modules/ .gitignore")
    (magit-status)))

;; --- Funkcja: Status Git notatek ---
(defun my/notes-git-status ()
  "Otwórz Magit status dla ~/notes/."
  (interactive)
  (let ((default-directory (expand-file-name "~/notes/")))
    (magit-status)))

;; --- Funkcja: Status Git config ---
(defun my/config-git-status ()
  "Otwórz Magit status dla ~/.emacs.d/."
  (interactive)
  (let ((default-directory (expand-file-name "~/.emacs.d/")))
    (magit-status)))

;; --- Funkcja: Log Git notatek ---
(defun my/notes-git-log ()
  "Pokaż historię zmian notatek."
  (interactive)
  (let ((default-directory (expand-file-name "~/notes/")))
    (magit-log-current)))

;; --- Funkcja: Log Git config ---
(defun my/config-git-log ()
  "Pokaż historię zmian konfiguracji."
  (interactive)
  (let ((default-directory (expand-file-name "~/.emacs.d/")))
    (magit-log-current)))

;; --- Funkcja: Diff aktualnego pliku ---
(defun my/git-diff-current-file ()
  "Pokaż zmiany w aktualnym pliku (diff z ostatnim commitem)."
  (interactive)
  (when buffer-file-name
    (magit-diff-buffer-file)))

;; --- Funkcja: Historia aktualnego pliku ---
(defun my/git-log-current-file ()
  "Pokaż historię zmian aktualnego pliku."
  (interactive)
  (when buffer-file-name
    (magit-log-buffer-file)))

;; --- Skróty klawiszowe ---
;; Notatki
(global-set-key (kbd "C-c v s") 'my/notes-git-status)
(global-set-key (kbd "C-c v l") 'my/notes-git-log)
(global-set-key (kbd "C-c v c") 'my/commit-notes-now)

;; Konfiguracja
(global-set-key (kbd "C-c v S") 'my/config-git-status)     ; Shift+S
(global-set-key (kbd "C-c v L") 'my/config-git-log)        ; Shift+L
(global-set-key (kbd "C-c v C") 'my/commit-config-now)     ; Shift+C

;; Ogólne
(global-set-key (kbd "C-c v d") 'my/git-diff-current-file)
(global-set-key (kbd "C-c v h") 'my/git-log-current-file)

;; --- Debug message ---
(message "✓ Git auto-commit: notes + config (C-x C-c + X)")

(provide '07-git)
;;; 07-git.el ends here
