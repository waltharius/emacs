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

;; --- Dashboard ---
(use-package dashboard
  :ensure t
  :config
  (dashboard-setup-startup-hook)
  (setq dashboard-banner-logo-title "📚 Emacs PKM System")
  (setq dashboard-startup-banner 'logo)
  (setq dashboard-center-content t)
  (setq dashboard-items '((recents  . 5)
                          (bookmarks . 5)
                          (projects . 5)))
  (setq dashboard-set-footer nil))

;; --- Org-roam UI (graf)
(use-package org-roam-ui
  :ensure t
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t)
  (setq org-roam-ui-follow t)
  (setq org-roam-ui-update-on-save t))
(provide '01-packages)

;;; 01-packages.el ends here
