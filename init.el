;;; init.el --- Modular Emacs configuration for Denote note-taking  -*- lexical-binding: t; -*-
;;
;; Author: Marcin
;; Created: 2025-10-03
;; Description: Modułowa konfiguracja Emacsa z systemem notatek Denote
;;
;; Struktura:
;;   - modules/01-packages.el         : Zarządzanie pakietami
;;   - modules/02-spelling.el         : Sprawdzanie pisowni i gramatyki
;;   - modules/03-ui.el               : Ustawienia interfejsu
;;   - modules/04-denote-core.el      : Konfiguracja Denote
;;   - modules/05-denote-functions.el : Custom funkcje Denote
;;   - modules/06-keybindings.el      : Skróty klawiszowe
;;   - modules/07-git.el              : Konfiguracja git
;;   - modules/08-modern-conveniences : Usprawnienia Emacs bez pisania kodu
;;   - modules/09-themes-gallery      : Galeria szablonów zmieniających wygląd Emacs
;;
;;; Code:
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

;; Load all modules in order
(message "Loading Emacs configuration...")
(my/load-module "01-packages.el")
(my/load-module "02-spelling.el")
(my/load-module "03-ui.el")
(my/load-module "04-denote-core.el")
(my/load-module "05-denote-functions.el")
(my/load-module "05a-folgezettel.el")
(my/load-module "06-keybindings.el")
(my/load-module "07-git.el")
(my/load-module "08-modern-conveniences")
(my/load-module "09-themes-gallery")

;; ============================================================
;; DASHBOARD FIX: Refresh after startup
;; ============================================================

(when (fboundp 'dashboard-refresh-buffer)
  (add-hook 'emacs-startup-hook
            (lambda ()
              (when (get-buffer "*dashboard*")
                (with-current-buffer "*dashboard*"
                  (dashboard-refresh-buffer)))
              (message "✅ Dashboard refreshed!"))))

(message "Emacs configuration loaded successfully! ✨")

(provide 'init)
;;; init.el ends here
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(ample-theme consult-denote diff-hl flyspell-correct-ivy htmlize
		 langtool magit org-contrib org-roam org-roam-ql
		 org-transclusion))
 '(recentf-filename-handlers '(abbreviate-file-name)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
