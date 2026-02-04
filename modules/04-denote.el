;;; 04-denote.el --- Denote configuration with multi-silo support -*- lexical-binding: t; -*-
;;; Commentary:
;; Denote note-taking system with 3 silos:
;; - ~/notes/journal/ - Private daily notes
;; - ~/notes/pks/     - Personal Knowledge System
;; - ~/notes/docu/    - Documentation and technical notes
;;
;; Updated to use new Denote 4.1.0 API (no deprecation warnings)

;;; Code:

;; ============================================================
;; DENOTE: Core package
;; ============================================================

(use-package denote
  :ensure t
  :custom
  ;; Main directory (default silo)
  (denote-directory my-notes-journal)
  
  ;; NO hardcoded keywords - let Denote discover from existing notes
  (denote-known-keywords nil)
  
  ;; Auto-discover keywords from ALL notes (including other silos)
  (denote-infer-keywords t)
  
  ;; Sort keywords alphabetically in completion
  (denote-sort-keywords t)
  
  ;; File type (nil = org-mode)
  (denote-file-type nil)
  
  ;; What to prompt for when creating notes
  (denote-prompts '(title keywords))
  
  :config
  ;; Tell Denote to scan ALL silos for keywords (not just current directory)
  (setq denote-directory-files-matching-regexp-function
        (lambda (regexp)
          (let ((files '()))
            ;; Scan all three silos
            (dolist (dir (list my-notes-journal my-notes-pks my-notes-docu))
              (when (file-exists-p dir)
                (setq files (append files
                                    (directory-files-recursively dir regexp t)))))
            files))))

;; ============================================================
;; CONSULT-DENOTE: Better search integration
;; ============================================================

(use-package consult-denote
  :ensure t
  :after (denote consult)
  :config
  ;; Make consult-denote work with silos
  (consult-denote-mode 1))

;; ============================================================
;; DENOTE CONVENIENCE SETTINGS
;; ============================================================

;; Automatically rename buffer to note title
(add-hook 'denote-after-new-note-hook 'denote-rename-buffer-mode)

;; Link using title instead of ID
(setq denote-link-button-action 'find-file)

;; ============================================================
;; VISUAL WRAPPING FOR NOTES
;; ============================================================

(defun my/denote-visual-wrap-setup ()
  "Enable visual-line-mode + visual-fill-column for Denote notes.
Documentation (:docu:): 100 chars, centered.
Normal notes: 84 chars, centered."
  (when (and (buffer-file-name)
             (or (string-match-p (expand-file-name my-notes-journal)
                                 (buffer-file-name))
                 (string-match-p (expand-file-name my-notes-pks)
                                 (buffer-file-name))
                 (string-match-p (expand-file-name my-notes-docu)
                                 (buffer-file-name))))
    ;; Enable visual modes
    (visual-line-mode 1)
    (visual-fill-column-mode 1)
    
    ;; Check if file has :docu: tag in #+filetags:
    (let ((is-documentation nil))
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^#\\+filetags:.*:docu:" nil t)
          (setq is-documentation t)))
      
      ;; Set width depending on type
      (if is-documentation
          (progn
            (setq fill-column 100)
            (setq-local visual-fill-column-width 100))
        (progn
          (setq fill-column 84)
          (setq-local visual-fill-column-width 84)))
      
      ;; BOTH TYPES: centering ON
      (setq-local visual-fill-column-center-text t)
      
      ;; Column indicator + apply changes
      (display-fill-column-indicator-mode 1)
      (visual-fill-column--adjust-window))))

(add-hook 'find-file-hook 'my/denote-visual-wrap-setup)
(add-hook 'org-mode-hook 'my/denote-visual-wrap-setup)

;; Toggle centering (manual override)
(defun my/toggle-visual-fill-column-center ()
  "Toggle text centering in current buffer."
  (interactive)
  (if (bound-and-true-p visual-fill-column-mode)
      (progn
        (setq-local visual-fill-column-center-text 
                    (not visual-fill-column-center-text))
        (visual-fill-column--adjust-window)
        (message "Centering: %s" 
                 (if visual-fill-column-center-text "✅ ON" "❌ OFF")))
    (message "⚠️ visual-fill-column-mode not active!")))

;; ============================================================
;; ORG-MODE SETTINGS FOR DENOTE
;; ============================================================

;; Disable auto-indent in org-mode
(add-hook 'org-mode-hook
          (lambda ()
            (electric-indent-local-mode -1)
            (setq-local electric-indent-chars nil)))

;; Alphabetical lists
(setq org-list-allow-alphabetical t)
(setq org-list-demote-modify-bullet
      '(("+" . "-") ("-" . "+") ("*" . "-") ("1." . "a.")))

;; Columns for PROPERTIES display
(setq org-columns-default-format 
      "%40ITEM(Title) %10STATUS %8YEAR %6PAGES %10PROJECT")

;; RET follows links
(setq org-return-follows-link t)

;; Left mouse click follows links
(setq org-mouse-1-follows-link t)

;; Don't ask for confirmation when executing elisp links
(setq org-confirm-elisp-link-function nil)

(provide '04-denote)
;;; 04-denote.el ends here
