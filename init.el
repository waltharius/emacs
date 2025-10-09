;;; init.el --- Modular Emacs configuration for Denote note-taking  -*- lexical-binding: t; -*-
;;
;; Author: Marcin
;; Created: 2025-10-03
;; Description: Modułowa konfiguracja Emacsa z systemem notatek Denote
;;
;; Struktura:
;;   - modules/00-variables.el        : Plik ze wszystkimi zmiennymi. MUSI być na początku!!
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
;;
;;; Code:
;; ============================================================
;; PERFORMANCE: Garbage collection optimization (startup only)
;; ============================================================

(setq gc-cons-threshold most-positive-fixnum)  ; Disable GC during startup

;; ============================================================
;; CRITICAL: Load fresh .el files (prevent cache issues)
;; ============================================================

(setq load-prefer-newer t)
;; Enable recentf mode GLOBALLY (before loading modules!)
(recentf-mode 1)
(setq recentf-max-saved-items 100)
(setq recentf-auto-cleanup 'never)
(setq recentf-exclude '("\\.git/"
                        "COMMIT_EDITMSG"
                        "\\.elc$"
                        "/elpa/"
                        "^/tmp/"
                        "^#.*#$"        ; Ignore auto-save files
                        "^\\.#"))       ; Ignore lock files!

;; ============================================================
;; LOAD MODULES
;; ============================================================
;; Helper function to load modules
(defun my/load-module (module-name)
  "Load module from ~/.emacs.d/modules/ directory."
  (let ((module-file (expand-file-name
                      (concat "modules/" module-name)
                      user-emacs-directory)))
    (if (file-exists-p module-file)
        (progn
          (message "Loading %s..." module-name)
          (load-file module-file))
      (message "Warning: Module %s not found!" module-name))))

(message "Loading Emacs configuration...")
;; 00-variables.el MUST BE FIRST - defines all paths and settings
(my/load-module "00-variables.el")
(my/load-module "01-packages.el")
(my/load-module "02-spelling.el")
(my/load-module "03-ui.el")
(my/load-module "04-denote-core.el")
(my/load-module "05-denote-functions.el")
(my/load-module "05a-folgezettel.el")
(my/load-module "07-git.el")
(my/load-module "08-modern-conveniences.el")
(my/load-module "09-themes-gallery.el")
(my/load-module "10-org-formatting.el")
(my/load-module "11-org-journal.el")
(my/load-module "13-project-management.el")
(my/load-module "14-transient-menus.el")

;; ← 06-keybindings.el MUST BE LAST (after all function definitions)
(my/load-module "06-keybindings.el")
(message "Emacs configuration loaded successfully! ✨")

;; ============================================================
;; CUSTOM FILE (keep custom-set-variables out of init.el)
;; ============================================================

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;; Auto clock-out on Emacs exit
(add-hook 'kill-emacs-hook 'org-clock-out nil t)

;; Auto-update statistics cookies
(setq org-checkbox-hierarchical-statistics nil)  ; Count all, not just direct children

;; Disable code execution during export
(setq org-export-use-babel nil)

(provide 'init)
;;; init.el ends here

