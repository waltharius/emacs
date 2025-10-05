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
  :config
  (dashboard-setup-startup-hook)
  
  ;; Podstawowe ustawienia
  (setq dashboard-banner-logo-title "📚 Emacs PKM System - Filozofia")
  (setq dashboard-startup-banner 'logo)
  (setq dashboard-center-content t)
  (setq dashboard-set-footer t)
  (setq dashboard-footer-messages 
        '("Free as free speech, free as free Beer"
          "Emacs: A lisp interpreter pretending to be a text editor"
          "The extensible, customizable, self-documenting real-time display editor"))
  
  ;; Ikony (opcjonalne - wymaga all-the-icons)
  (setq dashboard-set-heading-icons t)
  (setq dashboard-set-file-icons t)
  
  ;; Co pokazać
  (setq dashboard-items '((recents  . 10)
                          (bookmarks . 5)))
  
  ;; Custom widgets (KLUCZOWE!)
  (setq dashboard-startupify-list '(dashboard-insert-banner
                                    dashboard-insert-newline
                                    dashboard-insert-banner-title
                                    dashboard-insert-newline
                                    dashboard-insert-init-info
                                    dashboard-insert-items
                                    my/dashboard-insert-pkm-stats  ; <-- CUSTOM!
                                    dashboard-insert-newline
                                    dashboard-insert-footer))
  
  ;; Skróty klawiszowe w Dashboard
  (define-key dashboard-mode-map (kbd "j") 'my/denote-journal)
  (define-key dashboard-mode-map (kbd "n") 'my/denote-base)
  (define-key dashboard-mode-map (kbd "z") 'my/denote-zettel-smart)
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
