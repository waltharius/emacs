;;; 03-ui.el --- UI settings and desktop save mode
;;
;; Description: Ustawienia interfejsu, desktop-save-mode,
;;              save-place-mode, auto-fill dla org-mode
;;
;;; Code:

;; --- Podstawowe ustawienia interfejsu ---
(setq inhibit-startup-screen t)
(tool-bar-mode 1)
(menu-bar-mode 1)
(scroll-bar-mode 1)
(setq system-time-locale "pl_PL.UTF-8")

;; --- Desktop Save: zapamiętywanie sesji ---
(use-package desktop
  :ensure nil
  :init
  (setq desktop-dirname             "~/.emacs.d/desktop/"
        desktop-base-file-name      "emacs-desktop"
        desktop-base-lock-name      "lock"
        desktop-path               (list desktop-dirname)
        desktop-save               t
        desktop-load-locked-desktop t)
  :config
  (unless (file-exists-p desktop-dirname)
    (make-directory desktop-dirname t))
  (desktop-save-mode 1))

;; --- Zapamiętywanie pozycji kursora ---
(save-place-mode 1)
(setq save-place-file "~/.emacs.d/saveplace")

;; --- Hard wrap na 80 znaków dla org-mode ---
(add-hook 'org-mode-hook (lambda ()
                           (auto-fill-mode 1)
                           (setq fill-column 80)))

;; --- Funkcja: szybkie otwarcie init.el ---
(defun open-init-el-bottom-split ()
  "Otwórz ~/.emacs.d/init.el w dolnej połowie okna."
  (interactive)
  (let ((init-file (expand-file-name "~/.emacs.d/init.el")))
    (split-window-below)
    (other-window 1)
    (find-file init-file)))

(provide '03-ui)
;;; 03-ui.el ends here
