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
  (denote-directory my-notes-dir)
  (denote-known-keywords my-denote-keywords)
  (denote-infer-keywords t)
  (denote-sort-keywords t)
  (denote-file-type nil)
  (denote-prompts '(title keywords)))

;; ============================================================
;; CONSULT-DENOTE: Better search integration
;; ============================================================

(use-package consult-denote
  :ensure t
  :after (denote consult)
  :config
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
;; Individual note creation functions explicitly set target directory.

;; ============================================================
;; DENOTE CONVENIENCE SETTINGS
;; ============================================================

(add-hook 'denote-after-new-note-hook 'denote-rename-buffer-mode)
(setq denote-link-button-action 'find-file)

;; ============================================================
;; ORG-MODE SETTINGS FOR DENOTE
;; ============================================================

;; Disable auto-indent in org-mode (controlled separately)
(add-hook 'org-mode-hook
          (lambda ()
            (electric-indent-local-mode -1)
            (setq-local electric-indent-chars nil)))

(setq org-list-allow-alphabetical t)
(setq org-list-demote-modify-bullet
      '(("+" . "-") ("-" . "+") ("*" . "-") ("1." . "a.")))
(setq org-columns-default-format
      "%40ITEM(Title) %10STATUS %8YEAR %6PAGES %10PROJECT")
(setq org-return-follows-link t)
(setq org-mouse-1-follows-link t)

;; Confirm before executing elisp links (security: external .org files)
(setq org-confirm-elisp-link-function #'y-or-n-p)

;; ============================================================
;; E4 — DISABLE ORG-CLOCK PERSISTENCE
;; ============================================================
;; org-clock-persist is enabled by default in modern Emacs.
;; It writes ~/.emacs.d/.org-clock.save.el on every quit and reads
;; it on every startup, causing a noticeable delay even when you
;; never use org-clock.  Disabled here because org-agenda and
;; time-clocking are not part of this workflow.

(setq org-clock-persist nil)
(setq org-clock-persist-file nil)

(provide '04-denote)
;;; 04-denote.el ends here
