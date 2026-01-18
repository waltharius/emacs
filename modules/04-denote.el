;;; 04-denote.el --- Denote note-taking system -*- lexical-binding: t; -*-
;;; Commentary:
;; Denote configuration:
;; - Multi-silo support (journal, pks, docu)
;; - File naming conventions
;; - Link support
;; - Consult integration

;;; Code:

;; ============================================================
;; DENOTE PACKAGE
;; ============================================================

(use-package denote
  :ensure t
  :config
  ;; File naming
  (setq denote-directory my-notes-dir)
  (setq denote-known-keywords '("journal" "pks" "docu" "essay" "literature"))
  (setq denote-infer-keywords t)
  (setq denote-sort-keywords t)
  
  ;; File type (always org)
  (setq denote-file-type 'org)
  
  ;; Prompts
  (setq denote-prompts '(title keywords))
  
  ;; Date format
  (setq denote-date-format "%Y-%m-%d")
  (setq denote-date-prompt-use-org-read-date t)
  
  ;; Link format
  (setq denote-link-button-action 'find-file)
  
  ;; Backlinks in dedicated buffer
  (setq denote-backlinks-show-context t))

;; ============================================================
;; MULTI-SILO SUPPORT
;; ============================================================

;; Denote can work with multiple directories
;; Each silo is independent:
;; - ~/notes/journal/  - Private daily notes
;; - ~/notes/pks/      - Personal knowledge system
;; - ~/notes/docu/     - Technical documentation

(with-eval-after-load 'denote
  (setq denote-directory my-notes-dir)
  ;; Note: denote-silo-directories is defined in 00-core.el
  )

;; Helper: Choose silo when creating notes
(defun my/denote-choose-silo ()
  "Choose which silo to create note in."
  (let ((choice (completing-read "Directory: "
                                 '("journal" "pks" "docu" "main")
                                 nil t)))
    (cond
     ((string= choice "journal") (expand-file-name "journal/" my-notes-dir))
     ((string= choice "pks") (expand-file-name "pks/" my-notes-dir))
     ((string= choice "docu") (expand-file-name "docu/" my-notes-dir))
     (t my-notes-dir))))

;; ============================================================
;; CONSULT-DENOTE (Better search/navigation)
;; ============================================================

(use-package consult-denote
  :ensure t
  :after denote
  :config
  ;; Search across all silos
  (consult-denote-mode 1))

;; ============================================================
;; DENOTE-MENU (Optional visual menu)
;; ============================================================

(use-package denote-menu
  :ensure t
  :after denote)

;; ============================================================
;; ORG-MODE INTEGRATION
;; ============================================================

;; Org-mode settings for denote files
(with-eval-after-load 'org
  ;; Hide emphasis markers (*/_ etc)
  (setq org-hide-emphasis-markers t)
  
  ;; Better heading display
  (setq org-startup-indented t)
  (setq org-startup-folded 'overview)
  
  ;; Don't execute code blocks during export (safety)
  (setq org-export-use-babel nil)
  
  ;; Auto-update statistics cookies [0/3]
  (setq org-checkbox-hierarchical-statistics nil))

;; ============================================================
;; DENOTE ORG-ROAM COMPATIBILITY (Optional)
;; ============================================================

;; If you want org-roam features later, uncomment:
;; (use-package org-roam
;;   :ensure t
;;   :config
;;   (setq org-roam-directory my-notes-dir)
;;   (org-roam-db-autosync-mode))

(provide '04-denote)
;;; 04-denote.el ends here
