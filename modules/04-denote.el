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
  ;; Main directory set to root for better search across all silos
  (denote-directory my-notes-dir)
  
  ;; Base keyword list (Denote will add more automatically)
  (denote-known-keywords my-denote-keywords)
  
  ;; Auto-discover keywords from existing notes and ADD to known list
  (denote-infer-keywords t)
  
  ;; Sort keywords alphabetically in completion
  (denote-sort-keywords t)
  
  ;; File type (nil = org-mode)
  (denote-file-type nil)
  
  ;; What to prompt for when creating notes
  (denote-prompts '(title keywords)))

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
;; HOW MULTI-SILO SEARCH WORKS
;; ============================================================
;;
;; KEY INSIGHT: denote-directory is set to ~/notes/ (root)
;;
;; This means ALL denote functions automatically search:
;; - ~/notes/journal/
;; - ~/notes/pks/
;; - ~/notes/docu/
;; - Any other subdirectories
;;
;; Functions that benefit:
;; - consult-denote-grep  (C-c n g) - searches all subdirs
;; - denote-link          (C-c n i) - links to any file
;; - denote-open-or-create (C-c n F) - finds any file
;;
;; Individual note creation functions (journal, essay, etc.)
;; explicitly set their target directory, so they still
;; save to the correct silo.

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
Normal notes: my-fill-column (80), centered.
NO BOUNDARY LINES - clean margins!"
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
          (setq fill-column my-fill-column)  ; Use variable (80)
          (setq-local visual-fill-column-width my-fill-column)))
      
      ;; BOTH TYPES: centering ON
      (setq-local visual-fill-column-center-text t)
      
      ;; NO BOUNDARY LINES! (removed display-fill-column-indicator-mode)
      ;; Apply changes
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

;; Disable auto-indent in org-mode (controlled separately)
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
