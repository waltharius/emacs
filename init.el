;;; init.el --- Modular Emacs configuration for Denote note-taking  -*- lexical-binding: t; -*-
;;; Commentary:
;; Author: Marcin
;; Created: 2025-10-03
;; Description: Modułowa konfiguracja Emacsa z systemem notatek Denote
;;
;; Struktura:
;;   - modules/00-variables.el        : Plik ze wszystkimi zmiennymi.  MUSI być na początku!!
;;   - modules/01-packages.el         : Zarządzanie pakietami
;;   - modules/02-spelling.el         : Sprawdzanie pisowni i gramatyki
;;   - modules/03-ui.el               : Ustawienia interfejsu
;;   - modules/04-denote-core.el      : Konfiguracja Denote
;;   - modules/05-denote-functions.el : Custom funkcje Denote
;;   - modules/06-keybindings.el      : Skróty klawiszowe
;;   - modules/07-git.el              : Konfiguracja git
;;   - modules/08-modern-conveniences : Usprawnienia Emacs bez pisania kodu
;;   - modules/09-themes-gallery      : Galeria szablonów zmieniających wygląd Emacs
;;   - modules/10-org-formatting      : Skróty do formatowania tekstu i inne przydatne bajery z tekstem związane
;;   - modules/11-org-journal         : Integracja z calendar i nawigacja
;;   - modules/21-readwise            : Integracja z serwisem readwise.io
;;   - modules/13-project-management  : Org-agenda, kanban, time tracking
;;   - modules/14-transient-menus     : Unified transient menus
;;
;;; Code:

;; ============================================================
;; PERFORMANCE: Garbage collection optimization (startup only)
;; ============================================================

(setq gc-cons-threshold most-positive-fixnum)  ; Disable GC during startup

;; Reset GC after startup (add to hook)
(add-hook 'after-init-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024))  ; 16MB (reasonable)
            (message "GC threshold reset to 16MB")))

;; ============================================================
;; CRITICAL: Load fresh .el files (prevent cache issues)
;; ============================================================

(setq load-prefer-newer t)

;; ============================================================
;; RECENTF MODE (before modules)
;; ============================================================

(recentf-mode 1)
(setq recentf-max-saved-items 100
      recentf-auto-cleanup 'never
      recentf-exclude '("\\.git/"
                        "COMMIT_EDITMSG"
                        "\\.elc$"
                        "/elpa/"
                        "^/tmp/"
                        "^#.*#$"        ; Auto-save files
                        "^\\.#"))       ; Lock files

;; ============================================================
;; LOAD MODULES
;; ============================================================

(let ((modules-dir (expand-file-name "modules/" user-emacs-directory)))
  ;; 00-variables.el MUST BE FIRST - defines all paths and settings
  (load (concat modules-dir "00-variables.el"))
  (load (concat modules-dir "01-packages.el"))
  (load (concat modules-dir "02-spelling.el"))
  (load (concat modules-dir "03-ui.el"))
  (load (concat modules-dir "04-denote-core.el"))
  (load (concat modules-dir "05-denote-functions.el"))
  (load (concat modules-dir "05b-denote-export.el"))
  (load (concat modules-dir "05c-denote-statistics.el"))
  (load (concat modules-dir "05d-denote-wellbeing.el"))
  (load (concat modules-dir "05a-folgezettel.el"))
  (load (concat modules-dir "05j-fleeting-quote.el"))
  (load (concat modules-dir "07-git.el"))
  (load (concat modules-dir "08-modern-conveniences.el"))
  (load (concat modules-dir "09-themes-gallery.el"))
  (load (concat modules-dir "10-org-formatting.el"))
  (load (concat modules-dir "11-org-journal.el"))
  (load (concat modules-dir "12-readwise.el"))
  (load (concat modules-dir "13-project-management.el"))
  (load (concat modules-dir "14-transient-menus.el"))
  (load (concat modules-dir "03b-fonts.el"))
;;  (load (concat modules-dir "15-sidebars.el"))
  
  ;; ← 06-keybindings.el MUST BE LAST (after all function definitions)
  (load (concat modules-dir "06-keybindings.el")))

(message "Emacs configuration loaded successfully! ✨")

;; ============================================================
;; CUSTOM FILE (keep custom-set-variables out of init.el)
;; ============================================================

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;; ============================================================
;; ORG-MODE ENHANCEMENTS
;; ============================================================

;; Auto clock-out on Emacs exit
(add-hook 'kill-emacs-hook 'org-clock-out nil t)

;; Auto-update statistics cookies
(setq org-checkbox-hierarchical-statistics nil)  ; Count all, not just direct children

;; Disable code execution during export
(setq org-export-use-babel nil)

(setq auth-sources '("~/.authinfo.gpg"))

(provide 'init)
;;; init.el ends here
