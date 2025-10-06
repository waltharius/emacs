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
;;
;;; Code:
;; ============================================================
;; CRITICAL: Prevent byte-compilation cache issues
;; ============================================================

;; Always load .el files even if .elc exists (slower but safer)
;;(setq load-prefer-newer t)

;; --- Funkcja ładująca moduły ---
(defun my/load-module (filename)
  "Load module from ~/.emacs.d/modules/ with error handling."
  (let ((file (expand-file-name 
               (concat "modules/" filename) 
               user-emacs-directory)))
    (condition-case err
        (progn
          (load file)
          (message "✓ Loaded: %s" filename))
      (error
       (message "✗ Failed to load %s: %s" filename (error-message-string err))
       (display-warning 'init 
                        (format "Failed to load module %s: %s" 
                                filename (error-message-string err))
                        :error)))))

;; --- Ładowanie modułów (kolejność ma znaczenie!) ---
(message "Loading Emacs configuration...")

(my/load-module "01-packages.el")
(my/load-module "02-spelling.el")
(my/load-module "03-ui.el")
(my/load-module "04-denote-core.el")
(my/load-module "05-denote-functions.el")
(my/load-module "05a-folgezettel.el")
(my/load-module "06-keybindings.el")
(my/load-module "07-git.el")

;; ============================================================
;; DASHBOARD FIX: Reload po załadowaniu wszystkich modułów
;; ============================================================
(when (fboundp 'dashboard-refresh-buffer)
  (dashboard-refresh-buffer))

;; ============================================================
;; AUTO-RELOAD: Dashboard functions after startup
;; ============================================================

;; Fix: Dashboard loads before functions are fully loaded
;; Solution: Force reload after Emacs startup completes
(add-hook 'emacs-startup-hook
          (lambda ()
            ;; Reload 01-packages.el to ensure fresh functions
            (load-file (expand-file-name "modules/01-packages.el" user-emacs-directory))
            
            ;; Refresh Dashboard if it exists
            (when (get-buffer "*dashboard*")
              (with-current-buffer "*dashboard*"
                (let ((inhibit-read-only t))
                  (erase-buffer)
                  (dashboard-insert-startupify-lists))))
            
            (message "✅ Dashboard reloaded with fresh stats!")))

(provide 'init)

(message "Emacs configuration loaded successfully! ✨")

;;; init.el ends here
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(ample-theme consult-denote diff-hl flyspell-correct-ivy htmlize
		 langtool magit org-contrib org-roam org-roam-ql
		 org-transclusion)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
