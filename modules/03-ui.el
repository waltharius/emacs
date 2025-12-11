;;; 03-ui.el --- UI settings and desktop save mode  -*- lexical-binding: t; -*-
;;; Commentary:
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
        desktop-base-file-name      "vanilla-desktop"
        desktop-base-lock-name      "vanilla-desktop.lock"
        desktop-path               (list desktop-dirname)
        desktop-save               t
        desktop-load-locked-desktop t)
  :config
  (unless (file-exists-p desktop-dirname)
    (make-directory desktop-dirname t))
  (desktop-save-mode 1))

;; --- Desktop-save: ignoruj pliki tymczasowe ---
(add-to-list 'desktop-modes-not-to-save 'fundamental-mode)
(setq desktop-files-not-to-save
      (concat desktop-files-not-to-save
              "\\|\\(\\.aux\\|\\.log\\|\\.out\\|\\.toc\\|\\.tex\\)$"))

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

;; --- Auto-close auxiliary files (LaTeX, Org export) ---
(defun my/kill-auxiliary-buffers (&rest _args)
  "Automatycznie zamknij bufory pomocnicze (.aux, .log, .tex)."
  (interactive)
  (dolist (buf (buffer-list))
    (let ((name (buffer-file-name buf)))
      (when (and name
                 (or (string-suffix-p ".aux" name)
                     (string-suffix-p ".log" name)
                     (string-suffix-p ".out" name)
                     (string-suffix-p ".toc" name)
                     (string-suffix-p ".tex" name)))
        (kill-buffer buf)))))

;; Wywołaj przy starcie Emacsa
(add-hook 'emacs-startup-hook 'my/kill-auxiliary-buffers)

;; Wywołaj po eksporcie Org
(add-hook 'org-export-before-processing-hook 'my/kill-auxiliary-buffers)

;; --- Desktop-save: wyłącz flyspell przed zapisem sesji ---
(defun my/disable-flyspell-before-desktop-save ()
  "Wyłącz 'flyspell-mode' we wszystkich buforach przed zapisem sesji."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (bound-and-true-p flyspell-mode)
        (flyspell-mode -1)))))

(add-hook 'desktop-save-hook 'my/disable-flyspell-before-desktop-save)

;; --- Winner-mode: UNDO/REDO dla layout okien ---
(use-package winner
  :ensure nil
  :init
  (winner-mode 1)
  :bind (("C-c <left>"  . winner-undo)   ;; Cofnij layout (lub C-c LEFT arrow)
         ("C-c <right>" . winner-redo))) ;; Przywróć layout (lub C-c RIGHT arrow)

;; --- Funkcja: Zapisz desktop manualnie ---
(defun my/desktop-save-now ()
  "Zapisz desktop TERAZ (nie czekaj na auto-save)."
  (interactive)
  (desktop-save desktop-dirname)
  (message "Desktop zapisany!"))

(global-set-key (kbd "C-c d s") 'my/desktop-save-now)

;; --- Tab-bar: workspace'y (jak zakładki w przeglądarce) ---
(use-package tab-bar
  :ensure nil
  :init
  (tab-bar-mode 1)
  :bind (("C-c t n" . tab-bar-new-tab)        ;; Nowy tab
         ("C-c t c" . tab-bar-close-tab)      ;; Zamknij tab
         ("C-c t o" . tab-bar-switch-to-tab)  ;; Przełącz tab
         ("C-c t r" . tab-bar-rename-tab))    ;; Nazwij tab
  :config
  (setq tab-bar-show t)                       ;; Pokaż bar ZAWSZE, nawet gdy tylko 1
  (setq tab-bar-new-tab-choice "*scratch*")   ;; Nowy tab = scratch
  (setq tab-bar-close-button-show t))          ;; POKAŻ przycisk X

;; --- Word count w modeline (PRZED nazwą pliku) ---
(defun my/word-count-modeline ()
  "Zwróć licznik słów jako krótki string."
  (when (derived-mode-p 'org-mode 'text-mode)
    (let ((words (count-words (point-min) (point-max))))
      (propertize (format "%d " words)
                  'face '(:foreground "purple" :weight bold)))))

;; Custom modeline: [COUNT] na początku!
(setq-default mode-line-format
              '((:eval (my/word-count-modeline))  ; COUNT PIERWSZY!
                "%e"
                mode-line-front-space
                mode-line-mule-info
                mode-line-client
                mode-line-modified
                mode-line-remote
                mode-line-frame-identification
                mode-line-buffer-identification  ; Nazwa pliku
                "   "
                mode-line-position
                (vc-mode vc-mode)
                "  "
                mode-line-modes
                mode-line-misc-info
                mode-line-end-spaces))

;; Zmiana wyglądu bloków cytatów w Org-mode
(custom-set-faces
 '(org-block-begin-line ((t (:background "#f5f5f5" :foreground "#999999"
                             :slant italic :height 0.85))))
 '(org-block ((t (:background "#fefcf5" :extend t))))
 '(org-block-end-line ((t (:background "#f5f5f5" :foreground "#999999"
                           :slant italic :height 0.85)))))
(setq org-fontify-quote-and-verse-blocks t)

;; Zamień znaczniki bloków na symbole Unicode
(setq-default prettify-symbols-alist
              '(("#+BEGIN_QUOTE" . "💬")  ; lewy cudzysłów
                ("#+END_QUOTE" . "💬")    ; prawy cudzysłów
                ("#+begin_quote" . "💬")
                ("#+end_quote" . "💬")
                ("#+BEGIN_SRC" . "λ")    ; dla bloków kodu
                ("#+END_SRC" . "λ")
                ("#+begin_src" . "λ")
                ("#+end_src" . "λ")))

;; Pokaż prawdziwy tekst gdy kursor jest obok
(setq prettify-symbols-unprettify-at-point 'right-edge)

;; Włącz dla Org-mode
(add-hook 'org-mode-hook 'prettify-symbols-mode)

(provide '03-ui)
;;; 03-ui.el ends here
