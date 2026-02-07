;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically positioned cursor while writing.
;; Only recenters when you actually TYPE, not on every command.
;;
;; KEY FEATURES:
;; - Keeps cursor at 60% from top while typing (40% empty below)
;; - Shows "W" indicator in mode line when enabled
;; - Does NOT recenter when scrolling, clicking, or navigating
;; - Works with visual-fill-column (horizontal centering preserved!)
;; - Buffer-local: enable per note
;;
;; USAGE:
;; - Transient menu: C-c n W (toggle writing mode)
;; - Manual: M-x my/toggle-centered-writing

;;; Code:

;; ============================================================
;; CONFIGURATION
;; ============================================================

(defvar my/writing-cursor-position 0.60
  "Vertical position of cursor as fraction from top of window.
0.5 = center (50% from top)
0.60 = slightly below center (60% from top, 40% empty below) [DEFAULT]
0.7 = even lower (70% from top, 30% empty below)

Adjust this value to your preference!")

;; ============================================================
;; BUFFER-LOCAL MODE VARIABLE
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
                'help-echo "Writing mode: cursor at 60% from top")))

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
;; VERTICAL CURSOR POSITIONING
;; ============================================================

(defun my/recenter-at-position ()
  "Recenter cursor at the configured writing position (60% from top)."
  (let* ((window-height (window-height))
         (target-line (round (* window-height my/writing-cursor-position))))
    (recenter target-line)))

(defun my/recenter-on-typing ()
  "Recenter only when typing new characters.
This runs in post-command-hook but checks if we're actually inserting text."
  (when (and my/centered-writing-mode
             (or (eq this-command 'self-insert-command)
                 (eq this-command 'org-self-insert-command)
                 (eq this-command 'newline)
                 (eq this-command 'electric-newline-and-maybe-indent)
                 (eq this-command 'org-return)
                 (eq this-command 'yank)))
    ;; Only recenter if we're actually in a writable buffer
    (unless buffer-read-only
      (my/recenter-at-position))))

(defun my/enable-centered-writing ()
  "Enable vertically positioned cursor for writing."
  (setq my/centered-writing-mode t)
  ;; Position cursor at configured location immediately
  (my/recenter-at-position)
  ;; Add hook that only recenters when typing
  (add-hook 'post-command-hook #'my/recenter-on-typing nil t)
  ;; Update mode line
  (force-mode-line-update))

(defun my/disable-centered-writing ()
  "Disable vertically positioned cursor."
  (setq my/centered-writing-mode nil)
  ;; Remove our recentering hook
  (remove-hook 'post-command-hook #'my/recenter-on-typing t)
  ;; Update mode line
  (force-mode-line-update))

;; ============================================================
;; TOGGLE FUNCTION
;; ============================================================

(defun my/toggle-centered-writing ()
  "Toggle vertically positioned cursor for writing.

This keeps your cursor at 60% from top WHILE YOU TYPE.
Scrolling and navigation are NOT affected.
Your horizontal text centering (visual-fill-column) is preserved!

When enabled, shows 'W' in mode line (next to word count).
This is buffer-local, so each note can have it on or off.

NOTE: This will recenter even if you're at the top of the file.
This is a trade-off - consistent position vs. natural top-of-file writing.
If you find it annoying at the top, just toggle it off temporarily."
  (interactive)
  (if my/centered-writing-mode
      (progn
        (my/disable-centered-writing)
        (message "✍️ Writing mode: OFF"))
    (progn
      (my/enable-centered-writing)
      (message "✍️ Writing mode: ON (cursor at 60%% from top)"))))

;; Alias for transient menu compatibility
(defalias 'my/toggle-writeroom 'my/toggle-centered-writing)

;; ============================================================
;; ADJUSTMENT FUNCTIONS
;; ============================================================

(defun my/set-writing-position-center ()
  "Set cursor to exact center (50/50)."
  (interactive)
  (setq my/writing-cursor-position 0.5)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: center (50%% from top)"))

(defun my/set-writing-position-default ()
  "Set cursor to default position (60% from top)."
  (interactive)
  (setq my/writing-cursor-position 0.60)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: default (60%% from top)"))

(defun my/set-writing-position-lower ()
  "Set cursor lower (70% from top, 30% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.70)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: lower (70%% from top)"))

(defun my/set-writing-position-higher ()
  "Set cursor higher (50% from top, 50% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.50)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: higher (50%% from top)"))

;; ============================================================
;; EXPLANATION: How this works
;; ============================================================
;;
;; RECENTERING:
;; - Only happens when you TYPE (self-insert-command, newline, yank)
;; - Does NOT happen when: scrolling, clicking, navigating
;; - Cursor stays at 60% from top (40% empty below)
;;
;; MODE-LINE INDICATOR:
;; - Shows black "W" next to word count when enabled
;; - Buffer-local: each buffer has its own state
;; - Hover over "W" to see tooltip
;;
;; WHY 60%?
;; - Not too high (like 50% center)
;; - Not too low (like 70%)
;; - Comfortable for most writing
;; - Works well with both large and small fonts
;;
;; SAFE:
;; - Only recenters on actual typing commands
;; - Minimal performance impact
;; - Preserves scrolling ability
;; - No blocking issues
;;
;; TRADE-OFF:
;; - Will recenter even at top of file
;; - This is intentional for consistent cursor position
;; - If annoying, just toggle off when writing at top
;; - Smart recentering (only when below target) was attempted
;;   but broke the feature, so we use simple consistent recentering

;; ============================================================
;; POSITION ADJUSTMENT GUIDE
;; ============================================================
;;
;; Default: 0.60 (60% from top, 40% empty below)
;;
;; To change permanently, add to custom.el:
;; (setq my/writing-cursor-position 0.55)  ; Higher
;; (setq my/writing-cursor-position 0.65)  ; Lower
;;
;; Or use helper functions while writing:
;; M-x my/set-writing-position-center   ; 50%
;; M-x my/set-writing-position-default  ; 60% (default)
;; M-x my/set-writing-position-lower    ; 70%
;; M-x my/set-writing-position-higher   ; 50%

;; ============================================================
;; DEBUGGING
;; ============================================================
;;
;; Check if enabled in current buffer:
;; M-: my/centered-writing-mode RET
;;
;; Check current position:
;; M-: my/writing-cursor-position RET
;;
;; Check if hook is active:
;; M-: (member 'my/recenter-on-typing post-command-hook) RET
;;
;; Disable immediately:
;; C-c n W (or M-x my/toggle-centered-writing)
;;
;; Remove hook manually if needed:
;; M-: (remove-hook 'post-command-hook #'my/recenter-on-typing t)

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
;;               (my/enable-centered-writing))))

(provide '13-centered-writing)
;;; 13-centered-writing.el ends here
