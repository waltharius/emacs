;;; init.el --- Modular Emacs configuration for Denote note-taking
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
;;
;;; Code:

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
(my/load-module "06-keybindings.el")

(message "Emacs configuration loaded successfully! ✨")

;;; init.el ends here
