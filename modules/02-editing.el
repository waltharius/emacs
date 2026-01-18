;;; 02-editing.el --- Modern editing conveniences -*- lexical-binding: t; -*-
;;; Commentary:
;; Modern editor features:
;; - Sensible keybindings (C-s save, C-f find, C-a select all)
;; - Line numbers
;; - Auto-pairs
;; - Better completion
;; - Smooth scrolling

;;; Code:

;; ============================================================
;; MODERN KEYBINDINGS
;; ============================================================

;; Standard shortcuts (without breaking Emacs)
(global-set-key (kbd "C-a") 'mark-whole-buffer)  ;; Select all
(global-set-key (kbd "C-f") 'isearch-forward)    ;; Find
(global-set-key (kbd "C-s") 'save-buffer)        ;; Save
(global-set-key (kbd "C-z") 'undo)               ;; Undo

;; Better isearch
(define-key isearch-mode-map (kbd "C-f") 'isearch-repeat-forward)
(define-key isearch-mode-map (kbd "C-g") 'isearch-abort)

;; ============================================================
;; LINE NUMBERS
;; ============================================================

(global-display-line-numbers-mode t)
(setq display-line-numbers-type 'relative)  ;; relative numbers (vim-style)

;; Disable in certain modes
(dolist (mode '(org-mode-hook
                term-mode-hook
                shell-mode-hook
                eshell-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))

;; ============================================================
;; HIGHLIGHT CURRENT LINE
;; ============================================================

(global-hl-line-mode t)

;; ============================================================
;; PARENTHESES
;; ============================================================

;; Show matching parentheses
(show-paren-mode t)
(setq show-paren-delay 0)
(setq show-paren-style 'mixed)

;; Auto-close brackets and quotes
(electric-pair-mode t)

;; NOTE: Quote expansion in org-mode is DISABLED in 03-spelling.el

;; ============================================================
;; SMOOTH SCROLLING
;; ============================================================

(setq scroll-step 1
      scroll-conservatively 10000
      auto-window-vscroll nil)

;; Mouse scrolling
(setq mouse-wheel-scroll-amount '(1 ((shift) . 1))
      mouse-wheel-progressive-speed t
      mouse-wheel-follow-mouse 't)

;; ============================================================
;; BETTER DEFAULTS
;; ============================================================

;; Replace selection when typing
(delete-selection-mode t)

;; Visual line mode for text (wrap at word boundaries)
(add-hook 'text-mode-hook 'visual-line-mode)
(add-hook 'org-mode-hook 'visual-line-mode)

;; Auto-reload files when changed on disk
(global-auto-revert-mode t)
(setq global-auto-revert-non-file-buffers t
      auto-revert-verbose nil)

;; Flash screen instead of beeping
(setq visible-bell t)

;; Show keystrokes immediately
(setq echo-keystrokes 0.1)

;; Better undo limits
(setq undo-limit 80000000
      undo-strong-limit 120000000)

;; ============================================================
;; SEARCH SETTINGS
;; ============================================================

(setq case-fold-search t)              ;; Case-insensitive
(setq isearch-lazy-highlight t)        ;; Highlight all matches
(setq lazy-highlight-initial-delay 0)
(setq isearch-wrap-around t)           ;; Wrap around buffer

;; ============================================================
;; WHICH-KEY (Show available keybindings)
;; ============================================================

(use-package which-key
  :ensure t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.3
        which-key-popup-type 'side-window
        which-key-side-window-location 'bottom
        which-key-side-window-max-height 0.25
        which-key-sort-order 'which-key-key-order-alpha))

;; ============================================================
;; COMPLETION (Company mode)
;; ============================================================

(use-package company
  :ensure t
  :config
  (global-company-mode 1)
  (setq company-idle-delay 0.1
        company-minimum-prefix-length 2
        company-show-numbers t
        company-tooltip-align-annotations t)
  :bind (:map company-active-map
              ("C-n" . company-select-next)
              ("C-p" . company-select-previous)
              ("C-d" . company-show-doc-buffer)))

;; ============================================================
;; IBUFFER (Better buffer list)
;; ============================================================

(global-set-key (kbd "C-x C-b") 'ibuffer)

;; ============================================================
;; VISUAL FILL COLUMN (Center text in buffer)
;; ============================================================

(use-package visual-fill-column
  :ensure t
  :hook (org-mode . visual-fill-column-mode)
  :config
  (setq visual-fill-column-width 100
        visual-fill-column-center-text t))

(defun my/toggle-visual-fill-column-center ()
  "Toggle centered text view."
  (interactive)
  (if visual-fill-column-mode
      (visual-fill-column-mode -1)
    (visual-fill-column-mode 1))
  (message "Centered text: %s" (if visual-fill-column-mode "ON" "OFF")))

(provide '02-editing)
;;; 02-editing.el ends here
