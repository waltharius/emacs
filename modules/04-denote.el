;;; 04-denote.el --- Denote configuration with multi-silo support -*- lexical-binding: t; -*-
;;; Commentary:
;; Denote note-taking system with 3 silos:
;; - ~/notes/journal/ - Private daily notes
;; - ~/notes/pks/     - Personal Knowledge System
;; - ~/notes/docu/    - Documentation and technical notes

;;; Code:

;; ============================================================
;; DENOTE: Core package
;; ============================================================

(use-package denote
  :ensure t
  :config
  ;; Main directory (parent of all silos)
  (setq denote-directory my-notes-dir)
  
  ;; Multiple directories (silos)
  (setq denote-silo-directories
        (list my-notes-journal
              my-notes-pks
              my-notes-docu))
  
  ;; File naming template
  (setq denote-file-name-slug-functions
        '((title . denote-sluggify-title)
          (signature . denote-sluggify-signature)
          (keyword . denote-sluggify-keywords)))
  
  ;; Known keywords (you can add more as needed)
  (setq denote-known-keywords
        '("journal" "docu" "wellbeing" "esej" "philosophy"))
  
  ;; Templates support
  (setq denote-templates
        '((essay . "* Main Thesis\n\n* Arguments\n\n* Bibliography\n"))))

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

(provide '04-denote)
;;; 04-denote.el ends here
