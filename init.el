;;; init.el --- Clean Emacs configuration (Refactor 2026-01) -*- lexical-binding: t; -*-
;;; Commentary:
;; Minimal configuration - only essential features
;; Built from scratch, tested incrementally

;;; Code:

;; ============================================================
;; PERFORMANCE: Startup optimization
;; ============================================================

(setq gc-cons-threshold most-positive-fixnum)

(add-hook 'after-init-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024))
            (message "✨ Emacs ready (refactor-clean)!")))

;; ============================================================
;; WINDOW TITLE: Identify this is refactor branch
;; ============================================================

(setq frame-title-format
      '("Emacs [REFACTOR-CLEAN] - " 
        (:eval (if (buffer-file-name)
                   (file-name-nondirectory (buffer-file-name))
                 "%b"))))

;; ============================================================
;; LOAD MODULES (in correct order)
;; ============================================================

(let ((modules-dir (expand-file-name "modules/" user-emacs-directory)))
  (load (concat modules-dir "00-core.el"))          ; Package system + variables
  (load (concat modules-dir "01-ui.el"))            ; Interface + sessions
  (load (concat modules-dir "02-editing.el"))       ; Modern conveniences
  (load (concat modules-dir "02b-bold-marker.el"))  ; Obsidian-style bold (word*)
  (load (concat modules-dir "03-spelling.el"))      ; Spellcheck (WORKING!)
  (load (concat modules-dir "03b-fonts.el"))        ; Fonts (PlaypenSans for journals)
  (load (concat modules-dir "04-denote.el"))        ; Denote multi-silo
  (load (concat modules-dir "05-notes.el"))         ; Note functions
  (load (concat modules-dir "06-capture.el"))       ; Org-capture (SMART DATE!)
  (load (concat modules-dir "07-git.el"))           ; Git auto-commit
  (load (concat modules-dir "08-keybindings.el"))   ; Keybindings
  (load (concat modules-dir "09-theme.el"))         ; Theme (light)
  (load (concat modules-dir "10-visual-fill.el"))   ; Centered text
  (load (concat modules-dir "11-org-appearance.el")) ; Org visual enhancements
  (load (concat modules-dir "12-transient.el"))     ; Transient menu (C-c n)
  (load (concat modules-dir "13-centered-writing.el")) ; Writeroom mode (C-c n W)
  (load (concat modules-dir "14-typing-analytics.el")) ; Typing statistics (keyfreq + keylog)
  (load (concat modules-dir "15-workspace.el"))     ; Obsidian-like panels (EXPERIMENTAL)
  (load (expand modules-dir "16-org-export.el"))
  (load (concat modules-dir "17-bibliography.el"))  ; Citar + org-noter + pdf-tools
  (load (concat modules-dir "18-zotero-transient.el")) ; Zotero transient menu
  )

;; ============================================================
;; CUSTOM FILE
;; ============================================================

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

(provide 'init)
;;; init.el ends here
