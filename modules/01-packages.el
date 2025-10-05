;;; 01-packages.el --- Package management and basic tools  -*- lexical-binding: t; -*-
;;
;; Description: Konfiguracja repozytoriów pakietów (MELPA, GNU),
;;              use-package, which-key i htmlize
;;
;;; Code:

;; --- Repozytoria pakietów ---
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(package-initialize)

;; --- use-package (menadżer pakietów) ---
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;; --- Wyłącz native compilation warnings ---
(setq native-comp-async-report-warnings-errors nil)

;; --- Which-key: podpowiedzi skrótów ---
(use-package which-key
  :ensure t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.5))

;; --- Htmlize: kolorowy eksport do HTML ---
(use-package htmlize
  :ensure t)

;; --- Org-transclusion: embed notes (jak Obsidian ![[link]]) ---
(use-package org-transclusion
  :ensure t
  :after org)

;; --- Gnuplot dla wykresów Org-mode ---
(use-package gnuplot
  :ensure t)

;; ============================================================
;; DASHBOARD: Custom PKM Dashboard
;; ============================================================

(use-package dashboard
  :ensure t
  :init
  ;; Musi być PRZED :config żeby funkcje były dostępne!
  (defun my/dashboard-insert-pkm-stats (list-size)
    "Wstaw statystyki PKM do Dashboard."
    (let* ((my-notes-dir (expand-file-name "~/notes"))
           (all-notes (directory-files my-notes-dir nil "\\.org$"))
           (total-notes (length all-notes))
           (today-str (format-time-string "%Y-%m-%d"))
           (notes-today 0)
           (words-today 0)
           (fleeting 0)
           (literature 0)
           (zettel 0)
           (daily-goal 500))
      
      ;; Policz notatki
      (dolist (file all-notes)
        (let ((full-path (expand-file-name file my-notes-dir)))
          (when (string-match today-str file)
            (setq notes-today (1+ notes-today)))
          
          (with-temp-buffer
            (insert-file-contents full-path nil nil 500) ; Tylko pierwsze 500 znaków (szybciej!)
            
            ;; Typy notatek
            (goto-char (point-min))
            (when (re-search-forward "^#\\+filetags:" nil t)
              (let ((tags (buffer-substring (line-beginning-position) (line-end-position))))
                (cond
                 ((string-match ":fleeting:" tags) (setq fleeting (1+ fleeting)))
                 ((string-match ":lektura:" tags) (setq literature (1+ literature)))
                 ((string-match ":zettel:" tags) (setq zettel (1+ zettel))))))
            
            ;; Słowa dzisiaj (tylko dla dzisiejszych notatek)
            (when (string-match today-str file)
              (goto-char (point-min))
              (setq words-today (+ words-today 
                                  (count-words (point-min) (point-max))))))))
      
      ;; Wstaw do Dashboard
      (insert "\n")
      (insert (propertize "📊 PKM Statistics" 
                         'face 'dashboard-heading))
      (insert "\n\n")
      
      ;; Notatki
      (insert (format "    📝 Total Notes:        %d\n" total-notes))
      (insert (format "       ├─ Fleeting:        %d\n" fleeting))
      (insert (format "       ├─ Literature:      %d\n" literature))
      (insert (format "       └─ Zettel:          %d\n\n" zettel))
      
      ;; Dzisiaj
      (insert (format "    📅 Today:              %d notes, %d words\n" 
                     notes-today words-today))
      (insert (format "    🎯 Daily Goal:         %d/%d words (%d%%)\n\n" 
                     words-today daily-goal
                     (if (> daily-goal 0)
                         (/ (* words-today 100) daily-goal)
                       0)))
      
      ;; Quick actions - ROZSZERZONE!
      (insert (propertize "⚡ Quick Actions" 
                         'face 'dashboard-heading))
      (insert "\n\n")
      (insert "    [j] Journal      [b] Quick Note    [z] Zettel      [l] Literature\n")
      (insert "    [p] Filozof      [d] Delete Note   [s] Shortcuts   [c] Cockpit\n")
      (insert "    [q] Quit\n\n")))
  
  :config
  (dashboard-setup-startup-hook)
  
  ;; Podstawowe ustawienia
  (setq dashboard-banner-logo-title "📚 Emacs PKM System - Filozofia")
  (setq dashboard-startup-banner 'logo)
  (setq dashboard-center-content t)
  (setq dashboard-set-footer t)
  (setq dashboard-footer-messages 
      '("Free as free speech, free as free Beer"
        "The unexamined life is not worth living — Socrates"
        "I think, therefore I am — Descartes"
        "What we cannot speak about we must pass over in silence — Wittgenstein"
        "Man is condemned to be free — Sartre"
        "The owl of Minerva spreads its wings only with the falling of the dusk — Hegel"
        "There are no facts, only interpretations — Nietzsche"
        "Cogito, ergo sum: I doubt, therefore I think, therefore I am"
        "Being and Nothingness: consciousness is always consciousness of something"
        "The Cave: we see only shadows, not the forms themselves — Plato"
        "Dasein: being-in-the-world, thrown into existence — Heidegger"
        "The absurd is born of confrontation between human need and unreasonable silence — Camus"
        "Hell is other people — Sartre"
        "Whereof one cannot speak, thereof one must be silent — Wittgenstein"
        "The mind is furnished with ideas by experience alone — Locke"))
  
  ;; Ikony
  (setq dashboard-set-heading-icons t)
  (setq dashboard-set-file-icons t)
  
  ;; Items + Custom widget!
  (setq dashboard-items '((recents  . 5)
                          (pkm-stats . 1)))  ; <-- DODANE!
  
  ;; Zarejestruj custom widget
  (add-to-list 'dashboard-item-generators 
               '(pkm-stats . my/dashboard-insert-pkm-stats))
  
  ;; Skróty klawiszowe - ROZSZERZONE!
  (defun my/dashboard-open-shortcuts ()
    "Otwórz plik ze skrótami."
    (interactive)
    (find-file "~/notes/20251003T010032--skróty-klawiszowe-quick-reference__doku_skróty.org"))
  
  (define-key dashboard-mode-map (kbd "j") 'my/denote-journal)
  (define-key dashboard-mode-map (kbd "b") 'my/denote-base)
  (define-key dashboard-mode-map (kbd "z") 'my/denote-zettel-smart)
  (define-key dashboard-mode-map (kbd "l") 'my/denote-literature)
  (define-key dashboard-mode-map (kbd "p") 'my/denote-filozof)
  (define-key dashboard-mode-map (kbd "d") 'my/denote-delete-from-list)
  (define-key dashboard-mode-map (kbd "s") 'my/dashboard-open-shortcuts)
  (define-key dashboard-mode-map (kbd "c") 'my/denote-cockpit)
  (define-key dashboard-mode-map (kbd "q") 'quit-window))

;; --- Org-roam UI (graf)
(use-package org-roam-ui
  :ensure t
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t)
  (setq org-roam-ui-follow t)
  (setq org-roam-ui-update-on-save t))
(provide '01-packages)

;; --- Better minibuffer ---
(use-package vertico
  :ensure t
  :init
  (vertico-mode))

(use-package marginalia
  :ensure t
  :init
  (marginalia-mode))

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic)))

;;; 01-packages.el ends here
