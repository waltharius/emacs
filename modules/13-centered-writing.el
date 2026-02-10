;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically positioned cursor while writing using the proven
;; centered-cursor-mode package. This handles all edge cases correctly:
;; - Works with soft wrapping (visual-line-mode)
;; - Works when editing anywhere in the document (not just at end)
;; - Handles window resizing properly
;; - Mouse scrolling works normally
;;
;; KEY FEATURES:
;; - Keeps cursor at configured position from top WHEN TYPING
;; - Mouse scrolling works normally (doesn't recenter)
;; - Shows "W" indicator in mode line when enabled
;; - Works with visual-fill-column (horizontal centering preserved!)
;; - Buffer-local: enable per note
;; - Adjustable position with M-C-+ and M-C-- keys
;;
;; USAGE:
;; - Transient menu: C-c n W (toggle writing mode)
;; - Manual: M-x my/toggle-centered-writing
;; - Adjust position: M-C-+ (higher) or M-C-- (lower)

;;; Code:

;; ============================================================
;; SUPPRESS COMPILATION WARNINGS
;; ============================================================
;; The centered-cursor-mode package uses some obsolete APIs
;; (last updated 2023). The warnings are harmless - the package
;; works fine. We suppress them to keep compilation clean.

(with-eval-after-load 'warnings
  (add-to-list 'warning-suppress-types '(bytecomp))
  (add-to-list 'warning-suppress-log-types '(bytecomp)))

;; ============================================================
;; CENTERED-CURSOR-MODE PACKAGE
;; ============================================================

(use-package centered-cursor-mode
  :ensure t
  :config
  ;; Set default vertical position (40% from top)
  (setq ccm-vpos-init '(round (* 0.4 (window-text-height))))
  
  ;; Recenter at end of file (important for writing!)
  (setq ccm-recenter-at-end-of-file t)
  
  ;; CRITICAL: Disable recentering on scroll to fix mouse wheel!
  ;; This makes it only recenter when typing/moving cursor,
  ;; NOT when scrolling with mouse or keyboard
  (setq ccm-recenter-on-scroll-up nil
        ccm-recenter-on-scroll-down nil)
  
  ;; Smooth mouse wheel scrolling
  (setq mouse-wheel-scroll-amount '(1 ((shift) . 1))
        mouse-wheel-progressive-speed nil
        mouse-wheel-follow-mouse t)
  
  (message "✓ Centered-cursor-mode configured (40%% from top, mouse scrolling fixed)"))

;; ============================================================
;; BUFFER-LOCAL MODE TRACKING
;; ============================================================

(defvar-local my/centered-writing-mode nil
  "Non-nil if centered writing mode is enabled in this buffer.
This is buffer-local so each note can have its own state.")

;; ============================================================
;; MODE-LINE INDICATOR
;; ============================================================

(defun my/writing-mode-indicator ()
  "Display 'W' in mode line when writing mode is enabled."
  (when my/centered-writing-mode
    (propertize "W "
                'face '(:foreground "black" :weight bold)
                'help-echo "Writing mode: cursor centered (M-C-+ / M-C-- to adjust)")))

;; Add indicator to mode line (after word count)
(setq-default mode-line-format
              '((:eval (my/word-count-modeline))
                (:eval (my/writing-mode-indicator))  ; <-- Writing mode indicator
                "%e"
                mode-line-front-space
                mode-line-mule-info
                mode-line-client
                mode-line-modified
                mode-line-remote
                mode-line-frame-identification
                mode-line-buffer-identification
                "   "
                mode-line-position
                (vc-mode vc-mode)
                "  "
                mode-line-modes
                mode-line-misc-info
                mode-line-end-spaces))

;; ============================================================
;; TOGGLE FUNCTION
;; ============================================================

(defun my/toggle-centered-writing ()
  "Toggle vertically centered cursor for writing.

This uses the proven centered-cursor-mode package which handles
all edge cases correctly:
- Works with soft wrapping (visual-line-mode)
- Works when editing anywhere in the document
- No jumping issues when text wraps
- Mouse scrolling works normally

Your horizontal text centering (visual-fill-column) is preserved!

When enabled:
- Shows 'W' in mode line (next to word count)
- Cursor recenters to 40% from top WHEN YOU TYPE
- Mouse scrolling works normally (doesn't recenter)
- Press M-C-+ to move cursor higher
- Press M-C-- to move cursor lower
- Use C-u N M-C-+ to move N lines at once

This is buffer-local, so each note can have it on or off."
  (interactive)
  (if my/centered-writing-mode
      (progn
        ;; Disable
        (centered-cursor-mode -1)
        (setq my/centered-writing-mode nil)
        (force-mode-line-update)
        (message "✍️ Writing mode: OFF"))
    (progn
      ;; Enable
      (centered-cursor-mode 1)
      (setq my/centered-writing-mode t)
      (force-mode-line-update)
      (message "✍️ Writing mode: ON (mouse scrolling works normally)"))))

;; Alias for transient menu compatibility
(defalias 'my/toggle-writeroom 'my/toggle-centered-writing)

;; ============================================================
;; PRESET POSITION FUNCTIONS
;; ============================================================

(defun my/set-writing-position-upper ()
  "Set cursor to upper portion (40% from top, 60% empty below)."
  (interactive)
  (setq ccm-vpos-init '(round (* 0.4 (window-text-height))))
  (when my/centered-writing-mode
    (ccm-position-cursor))
  (message "Writing position: upper (40%% from top)"))

(defun my/set-writing-position-center ()
  "Set cursor to exact center (50% from top)."
  (interactive)
  (setq ccm-vpos-init '(round (window-text-height) 2))
  (when my/centered-writing-mode
    (ccm-position-cursor))
  (message "Writing position: center (50%% from top)"))

(defun my/set-writing-position-golden ()
  "Set cursor to golden ratio position (~62% from top)."
  (interactive)
  (setq ccm-vpos-init '(round (* 21 (window-text-height)) 34))
  (when my/centered-writing-mode
    (ccm-position-cursor))
  (message "Writing position: golden ratio (~62%% from top)"))

(defun my/set-writing-position-lower ()
  "Set cursor lower (60% from top, 40% empty below)."
  (interactive)
  (setq ccm-vpos-init '(round (* 0.6 (window-text-height))))
  (when my/centered-writing-mode
    (ccm-position-cursor))
  (message "Writing position: lower (60%% from top)"))

;; ============================================================
;; USAGE INSTRUCTIONS
;; ============================================================
;;
;; BASIC USAGE:
;; - C-c n W : Toggle writing mode on/off
;; - M-C-+ : Move cursor UP (make position higher on screen)
;; - M-C-- : Move cursor DOWN (make position lower on screen)
;; - C-u 5 M-C-+ : Move 5 lines higher at once
;;
;; PRESET POSITIONS:
;; - M-x my/set-writing-position-upper (40% - default)
;; - M-x my/set-writing-position-center (50%)
;; - M-x my/set-writing-position-golden (62% - golden ratio)
;; - M-x my/set-writing-position-lower (60%)
;;
;; BEHAVIOR:
;; - Cursor recenters to configured position WHEN YOU TYPE
;; - Mouse scrolling works normally (doesn't recenter)
;; - Keyboard scrolling (C-v, M-v) also works normally
;; - Only typing/cursor movement triggers recentering
;;
;; WHY 40% FROM TOP?
;; - Comfortable typing position
;; - More context visible below (60%)
;; - Not too high (like 30%) or too centered (50%)
;; - Works well with different window sizes
;;
;; WORKS WITH:
;; ✓ Soft wrapping (visual-line-mode)
;; ✓ Editing in middle of documents
;; ✓ Long paragraphs that wrap
;; ✓ Window resizing
;; ✓ Multiple buffers (buffer-local)
;; ✓ Horizontal centering (visual-fill-column)
;; ✓ Mouse wheel scrolling (fixed!)
;;
;; SAFE & PROVEN:
;; - Uses centered-cursor-mode package (maintained since 2012)
;; - Configured to not interfere with mouse scrolling
;; - Compilation warnings suppressed (package uses old APIs)
;; - Minimal performance impact

;; ============================================================
;; CUSTOMIZATION EXAMPLES
;; ============================================================
;;
;; To change default position permanently, add to custom.el:
;;
;; ;; 30% from top (higher - more space below)
;; (setq ccm-vpos-init '(round (* 0.3 (window-text-height))))
;;
;; ;; Golden ratio (~62% from top)
;; (setq ccm-vpos-init '(round (* 21 (window-text-height)) 34))
;;
;; ;; Fixed 20 lines from top
;; (setq ccm-vpos-init 20)
;;
;; To disable recentering at end of file:
;; (setq ccm-recenter-at-end-of-file nil)

;; ============================================================
;; DEBUGGING
;; ============================================================
;;
;; Check if enabled in current buffer:
;; M-: my/centered-writing-mode RET
;;
;; Check centered-cursor-mode state:
;; M-: centered-cursor-mode RET
;;
;; Check current position setting:
;; M-: ccm-vpos-init RET
;;
;; Check scroll settings:
;; M-: ccm-recenter-on-scroll-up RET
;; M-: ccm-recenter-on-scroll-down RET
;;
;; Disable immediately:
;; C-c n W (or M-x my/toggle-centered-writing)

;; ============================================================
;; ABOUT THE WARNINGS
;; ============================================================
;;
;; The package shows compilation warnings about obsolete APIs:
;; - mouse-wheel-up-event (obsolete in Emacs 30.1)
;; - mouse-wheel-down-event (obsolete in Emacs 30.1)
;; - interactive-p (obsolete since Emacs 23.2)
;; - etc.
;;
;; These warnings are from the PACKAGE SOURCE CODE, not your config.
;; The package was last updated in 2023 and hasn't been modernized
;; for Emacs 30.1 yet.
;;
;; The warnings are HARMLESS - the package works correctly despite them.
;; We suppress the warnings to keep your compilation output clean.
;;
;; If you want to see the warnings again, comment out the
;; "SUPPRESS COMPILATION WARNINGS" section at the top of this file.

;; ============================================================
;; OPTIONAL: Auto-enable for journal files
;; ============================================================
;;
;; Uncomment to automatically enable for journal files:
;;
;; (add-hook 'org-mode-hook
;;           (lambda ()
;;             (when (and buffer-file-name
;;                        (string-match-p "journal" buffer-file-name))
;;               (my/toggle-centered-writing))))

(provide '13-centered-writing)
;;; 13-centered-writing.el ends here
