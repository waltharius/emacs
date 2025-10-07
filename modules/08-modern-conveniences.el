;;; 08-modern-conveniences.el --- Modern Emacs conveniences (CUA, line numbers, etc.) -*- lexical-binding: t; -*-

;;; Commentary:
;; Modern improvements for Emacs - inspired by contemporary editors
;; while keeping Emacs power!

;;; Code:

;; ============================================================
;; CUA MODE (Ctrl-C/V/X for Copy/Paste/Cut)
;; ============================================================

;; Enable CUA mode for modern keybindings
;; C-c = Copy (when region active)
;; C-v = Paste
;; C-x = Cut (when region active)
;; C-z = Undo
;; IMPORTANT: C-c and C-x work NORMALLY when nothing is selected!

(cua-mode t)

;; Configure CUA to not override C-x/C-c when no selection
(setq cua-keep-region-after-copy t)  ; Keep selection after copy

;; Additional modern keybindings
(global-set-key (kbd "C-a") 'mark-whole-buffer)  ; Ctrl-A = Select all
(global-set-key (kbd "C-f") 'isearch-forward)    ; Ctrl-F = Find/Search
(global-set-key (kbd "C-s") 'save-buffer)        ; Ctrl-S = Save (override isearch)

;; Make isearch more intuitive
(define-key isearch-mode-map (kbd "C-f") 'isearch-repeat-forward)
(define-key isearch-mode-map (kbd "C-g") 'isearch-abort)

;; ============================================================
;; LINE NUMBERS (Always visible!)
;; ============================================================

;; Enable line numbers globally
(global-display-line-numbers-mode t)

;; Configure line number display
(setq display-line-numbers-type 'relative)  ; 'relative or 'absolute or t
;; Try each:
;; - 'relative   → Shows distance from current line (good for navigation!)
;; - 'absolute   → Shows actual line numbers (classic)
;; - t           → Same as 'absolute

;; Disable line numbers in certain modes (where they don't make sense)
(dolist (mode '(org-mode-hook
                term-mode-hook
                shell-mode-hook
                eshell-mode-hook
                vterm-mode-hook
                dashboard-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))

;; ============================================================
;; HIGHLIGHT CURRENT LINE
;; ============================================================

;; Highlight the line where cursor is (easier to see!)
(global-hl-line-mode t)

;; Customize hl-line color (optional - uncomment to use)
;; (set-face-background 'hl-line "#2a2a2a")  ; Dark gray for dark themes
;; (set-face-foreground 'highlight nil)      ; Don't change text color

;; ============================================================
;; SHOW MATCHING PARENTHESES
;; ============================================================

;; Highlight matching parentheses
(show-paren-mode t)

;; Configure paren matching
(setq show-paren-delay 0)              ; No delay
(setq show-paren-style 'mixed)         ; Highlight both paren and expression

;; Color for matching parens (optional - uncomment to customize)
;; (set-face-attribute 'show-paren-match nil
;;                     :background "#44475a"
;;                     :foreground "#ff79c6"
;;                     :weight 'bold)

;; ============================================================
;; AUTO-PAIRS (Automatic bracket/quote closing)
;; ============================================================

;; Electric pair mode - auto-close brackets, quotes, etc.
(electric-pair-mode t)

;; Configure which pairs to auto-close
(setq electric-pair-pairs
      '(
        (?\" . ?\")   ; Double quotes
        (?\' . ?\')   ; Single quotes
        (?\( . ?\))   ; Parentheses
        (?\[ . ?\])   ; Brackets
        (?\{ . ?\})   ; Braces
        ))

;; Disable in certain modes (if needed)
;; (add-hook 'org-mode-hook (lambda () (electric-pair-local-mode -1)))

;; ============================================================
;; SMOOTH SCROLLING
;; ============================================================

;; Scroll line by line instead of jumping
(setq scroll-step 1)
(setq scroll-conservatively 10000)
(setq auto-window-vscroll nil)

;; Mouse scroll settings
(setq mouse-wheel-scroll-amount '(1 ((shift) . 1)))  ; One line at a time
(setq mouse-wheel-progressive-speed t)             ; Don't accelerate
(setq mouse-wheel-follow-mouse 't)                   ; Scroll window under mouse

;; ============================================================
;; WHICH-KEY ENHANCEMENTS
;; ============================================================

;; Which-key is already enabled, but let's make it faster!
(setq which-key-idle-delay 0.3)        ; Show faster (default: 1.0)
(setq which-key-popup-type 'side-window)  ; Show in side window
(setq which-key-side-window-location 'bottom)
(setq which-key-side-window-max-height 0.25)  ; 25% of frame height

;; Sort by alphabetical order
(setq which-key-sort-order 'which-key-key-order-alpha)

;; ============================================================
;; BETTER DEFAULTS
;; ============================================================

;; Replace selection when typing (modern editor behavior)
(delete-selection-mode t)

;; Show column number in modeline
(column-number-mode t)

;; Show file size in modeline
(size-indication-mode t)

;; Highlight TODO/FIXME/NOTE in comments
(add-hook 'prog-mode-hook
          (lambda ()
            (font-lock-add-keywords nil
                                    '(("\\<\\(FIXME\\|TODO\\|NOTE\\|BUG\\|HACK\\):"
                                       1 font-lock-warning-face t)))))

;; Visual line mode for text files (wrap at word boundaries)
(add-hook 'text-mode-hook 'visual-line-mode)
(add-hook 'org-mode-hook 'visual-line-mode)

;; ============================================================
;; IMPROVED SEARCH (isearch)
;; ============================================================

;; Case-insensitive search by default
(setq case-fold-search t)

;; Incremental search highlights all matches
(setq isearch-lazy-highlight t)
(setq lazy-highlight-initial-delay 0)

;; Wrap search around buffer edges
(setq isearch-wrap-around t)

;; ============================================================
;; BETTER BUFFER SWITCHING
;; ============================================================

;; Use ibuffer instead of list-buffers
(global-set-key (kbd "C-x C-b") 'ibuffer)

;; Improved buffer switching with ido (alternative to ivy/helm)
(ido-mode t)
(setq ido-enable-flex-matching t)      ; Fuzzy matching
(setq ido-everywhere t)                ; Use ido everywhere
(setq ido-create-new-buffer 'always)   ; Create new buffer without asking

;; ============================================================
;; MOUSE SUPPORT IN TERMINAL
;; ============================================================

;; Enable mouse in terminal Emacs
(unless (display-graphic-p)
  (xterm-mouse-mode t)
  (global-set-key (kbd "<mouse-4>") 'scroll-down-line)
  (global-set-key (kbd "<mouse-5>") 'scroll-up-line))

;; ============================================================
;; FONT SIZE SHORTCUTS (Already work, but documenting here!)
;; ============================================================

;; C-x C-+ : Increase font size
;; C-x C-- : Decrease font size
;; C-x C-0 : Reset to default

;; Set default font size (optional - uncomment and adjust)
;; (set-face-attribute 'default nil :height 120)  ; 120 = 12pt

;; ============================================================
;; FRAME TITLE (Show current file in window title)
;; ============================================================

;; Show current file + project in frame title
(setq frame-title-format
      '((:eval (if (buffer-file-name)
                   (abbreviate-file-name (buffer-file-name))
                 "%b"))
        " - Emacs PKM System"))

;; ============================================================
;; RECENT FILES (Better recentf)
;; ============================================================

;; Increase number of recent files remembered
(setq recentf-max-saved-items 50)  ; Default: 20

;; Exclude certain files from recentf
(setq recentf-exclude
      '("/tmp/"
        "/ssh:"
        "/sudo:"
        "COMMIT_EDITMSG"
        "recentf"
        "\\.gpg$"))

;; Auto-cleanup old entries
(setq recentf-auto-cleanup 'never)  ; Don't cleanup on startup (slow!)

;; ============================================================
;; BETTER COMPLETION (Company mode tweaks)
;; ============================================================

;; Make company completion faster and more responsive
(with-eval-after-load 'company
  (setq company-idle-delay 0.1)          ; Show faster (default: 0.2)
  (setq company-minimum-prefix-length 2) ; After 2 characters (default: 3)
  (setq company-show-numbers t)          ; Show numbers for quick selection
  (setq company-tooltip-align-annotations t)
  
  ;; Better navigation keys
  (define-key company-active-map (kbd "C-n") 'company-select-next)
  (define-key company-active-map (kbd "C-p") 'company-select-previous)
  (define-key company-active-map (kbd "C-d") 'company-show-doc-buffer))

;; ============================================================
;; WHITESPACE VISUALIZATION (Optional - toggle with M-x whitespace-mode)
;; ============================================================

;; Configure whitespace mode (show tabs, trailing spaces, etc.)
(setq whitespace-style
      '(face
        tabs
        trailing
        space-before-tab
        indentation
        empty
        space-after-tab))

;; Customize whitespace colors (optional)
;; (set-face-attribute 'whitespace-tab nil
;;                     :background "#282a36"
;;                     :foreground "#44475a")

;; ============================================================
;; WINNER MODE (Undo/Redo window configurations)
;; ============================================================

;; Enable winner-mode (C-c left/right to undo/redo window changes)
(winner-mode t)

;; Keybindings:
;; C-c <left>  → Undo window configuration
;; C-c <right> → Redo window configuration

;; ============================================================
;; UNIQUIFY (Better buffer names for duplicate filenames)
;; ============================================================

;; When you have multiple files with same name (e.g., two init.el),
;; show unique path instead of init.el<1>, init.el<2>

(require 'uniquify)
(setq uniquify-buffer-name-style 'forward)  ; Show path: project1/init.el
(setq uniquify-separator "/")
(setq uniquify-after-kill-buffer-p t)       ; Rename buffers after killing
(setq uniquify-ignore-buffers-re "^\\*")    ; Ignore special buffers

;; ============================================================
;; AUTOMATICALLY REFRESH BUFFERS (Auto-revert)
;; ============================================================

;; Auto-reload files when they change on disk
(global-auto-revert-mode t)

;; Also auto-refresh dired buffers
(setq global-auto-revert-non-file-buffers t)
(setq auto-revert-verbose nil)  ; Don't show "Reverting buffer..." message

;; ============================================================
;; SAVE PLACE (Remember cursor position in files)
;; ============================================================

;; Remember where you were in each file
(save-place-mode t)
(setq save-place-file (expand-file-name "places" user-emacs-directory))

;; ============================================================
;; CONFIRM BEFORE QUIT
;; ============================================================

;; Ask "Really quit?" before closing Emacs (prevent accidental quits!)
(setq confirm-kill-emacs 'yes-or-no-p)

;; ============================================================
;; BETTER YES/NO PROMPTS
;; ============================================================

;; Use y/n instead of yes/no (faster!)
(defalias 'yes-or-no-p 'y-or-n-p)

;; ============================================================
;; MISC IMPROVEMENTS
;; ============================================================

;; Flash screen instead of beeping
(setq visible-bell t)

;; Don't show startup message
(setq inhibit-startup-message t)

;; Show keystrokes immediately
(setq echo-keystrokes 0.1)

;; Increase undo limit
(setq undo-limit 80000000)
(setq undo-strong-limit 120000000)

;; Don't create lockfiles (those .# files)
(setq create-lockfiles nil)

;; ============================================================
;; PRETTY SYMBOLS (Optional - λ instead of lambda, etc.)
;; ============================================================

;; Show pretty symbols in programming modes
(global-prettify-symbols-mode t)

;; Customize symbols (optional)
;; (add-hook 'emacs-lisp-mode-hook
;;           (lambda ()
;;             (push '("lambda" . ?λ) prettify-symbols-alist)))

;; ============================================================
;; END OF MODERN CONVENIENCES
;; ============================================================

;; ============================================================
;; WORKSPACES + SESSION SAVE (Better than desktop!)
;; ============================================================

;; Enable tab-bar for workspaces
(tab-bar-mode 1)
(setq tab-bar-show 1) ; Always show tabs

;; Session management (lightweight, reliable!)
(require 'session)
(add-hook 'after-init-hook 'session-initialize)

;; What to save in sessions
(setq session-save-file (expand-file-name ".session" user-emacs-directory))
(setq session-name-disable-regexp "\\(?:\\`'/tmp\\|\\.git/\\|/\\.#\\|#.*#\\'\\)")
(setq session-save-file-coding-system 'utf-8)

;; Auto-save session every 5 minutes
(run-with-idle-timer 300 t 'session-save-session)

;; Save on exit
(add-hook 'kill-emacs-hook 'session-save-session)

;; Create default workspaces
(defun my/setup-workspaces ()
  "Set up default workspaces after init."
  (tab-bar-new-tab)
  (tab-bar-rename-tab "PKM")
  (tab-bar-new-tab) 
  (tab-bar-rename-tab "Config")
  (tab-bar-select-tab 1)) ; Go back to first tab

(add-hook 'emacs-startup-hook 'my/setup-workspaces)


(provide '08-modern-conveniences)
;;; 08-modern-conveniences.el ends here
