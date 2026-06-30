;;; 04-denote.el --- Denote configuration with multi-silo support -*- lexical-binding: t; -*-
;;; Commentary:
;; Denote note-taking system with 3 silos:
;; - ~/notes/journal/ - Private daily notes
;; - ~/notes/pks/     - Personal Knowledge System
;; - ~/notes/docu/    - Documentation and technical notes
;;
;; Updated to use new Denote 4.1.0 API (no deprecation warnings)
;;
;; NOTE: Visual-fill-column setup is handled entirely by 10-visual-fill.el.
;; Do not add visual-fill or fill-column hooks here.

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

;; Require y-or-n confirmation before executing elisp links.
;; Rationale: notes imported from Readwise or synced via Syncthing are
;; external input. A malicious [[elisp:...]] link in an .org file would
;; execute silently if this were nil.  y-or-n-p costs one keypress and
;; keeps the protection without being disruptive for own notes.
(setq org-confirm-elisp-link-function #'y-or-n-p)

(provide '04-denote)
;;; 04-denote.el ends here
