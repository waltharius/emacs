;;; 02-editing.el --- Modern editing conveniences -*- lexical-binding: t; -*-
;;; Commentary:
;; Modern editor features: line numbers, matching parens, smooth scrolling, etc.

;;; Code:

;; ============================================================
;; MODERN KEYBINDINGS (without CUA conflicts)
;; ============================================================

(global-set-key (kbd "C-a") 'mark-whole-buffer)  ; Select all
(global-set-key (kbd "C-f") 'isearch-forward)    ; Find
(global-set-key (kbd "C-s") 'save-buffer)        ; Save
(global-set-key (kbd "C-z") 'undo)               ; Undo

;; Better isearch
(define-key isearch-mode-map (kbd "C-f") 'isearch-repeat-forward)
(define-key isearch-mode-map (kbd "C-g") 'isearch-abort)

;; ============================================================
;; LINE NUMBERS
;; ============================================================

(global-display-line-numbers-mode t)
(setq display-line-numbers-type 'relative)  ; or 'absolute or t

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
;; MATCHING PARENTHESES
;; ============================================================

(show-paren-mode t)
(setq show-paren-delay 0)
(setq show-paren-style 'mixed)

;; ============================================================
;; AUTO-PAIRS (Electric pair mode)
;; ============================================================

(electric-pair-mode t)
(setq electric-pair-pairs
      '((?\" . ?\")
        (?' . ?')
        (?\( . ?\))
        (?\[ . ?\])
        (?\{ . ?\})))

;; ============================================================
;; SMOOTH SCROLLING
;; ============================================================

(setq scroll-step 1)
(setq scroll-conservatively 10000)
(setq auto-window-vscroll nil)

;; Mouse scrolling
(setq mouse-wheel-scroll-amount '(1 ((shift) . 1)))
(setq mouse-wheel-progressive-speed t)
(setq mouse-wheel-follow-mouse 't)

;; ============================================================
;; WHICH-KEY: Show available keybindings
;; ============================================================

(use-package which-key
  :ensure t
  :init
  (which-key-mode 1)
  :config
  (setq which-key-idle-delay 0.3)
  (setq which-key-popup-type 'side-window)
  (setq which-key-side-window-location 'bottom)
  (setq which-key-side-window-max-height 0.25)
  (setq which-key-sort-order 'which-key-key-order-alpha))

;; ============================================================
;; BETTER DEFAULTS
;; ============================================================

(delete-selection-mode t)     ; Replace selection when typing
(column-number-mode t)        ; Show column in modeline
(size-indication-mode t)      ; Show file size

;; Visual line mode for text
(add-hook 'text-mode-hook 'visual-line-mode)
(add-hook 'org-mode-hook 'visual-line-mode)

;; ============================================================
;; IMPROVED SEARCH
;; ============================================================

(setq case-fold-search t)              ; Case-insensitive
(setq isearch-lazy-highlight t)        ; Highlight all matches
(setq lazy-highlight-initial-delay 0)
(setq isearch-wrap-around t)           ; Wrap at buffer edges

;; ============================================================
;; BETTER BUFFER SWITCHING
;; ============================================================

(global-set-key (kbd "C-x C-b") 'ibuffer)

;; IDO mode for fuzzy matching
(use-package ido
  :ensure nil
  :init
  (ido-mode t)
  :config
  (setq ido-enable-flex-matching t)
  (setq ido-everywhere t)
  (setq ido-create-new-buffer 'always))

;; ============================================================
;; UNIQUIFY: Better duplicate buffer names
;; ============================================================

(use-package uniquify
  :ensure nil
  :config
  (setq uniquify-buffer-name-style 'forward)
  (setq uniquify-separator "/")
  (setq uniquify-after-kill-buffer-p t)
  (setq uniquify-ignore-buffers-re "^\\*"))

;; ============================================================
;; AUTO-REVERT: Reload files when changed externally
;; ============================================================

(global-auto-revert-mode t)
(setq global-auto-revert-non-file-buffers t)
(setq auto-revert-verbose nil)

;; ============================================================
;; MISC IMPROVEMENTS
;; ============================================================

(setq visible-bell t)                ; Flash instead of beep
(setq echo-keystrokes 0.1)           ; Show keystrokes immediately
(setq undo-limit 80000000)           ; Large undo limit
(setq undo-strong-limit 120000000)

;; Confirm before quit
(setq confirm-kill-emacs 'yes-or-no-p)

;; y/n instead of yes/no
(defalias 'yes-or-no-p 'y-or-n-p)

;; Pretty symbols
(global-prettify-symbols-mode t)

(provide '02-editing)
;;; 02-editing.el ends here
