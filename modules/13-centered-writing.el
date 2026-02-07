;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically positioned cursor while writing.
;; Only recenters when you actually TYPE, not on every command.
;; Smart recentering: only moves view UP when cursor goes too low.
;;
;; KEY FEATURES:
;; - Keeps cursor at 60% from top while typing (when below that line)
;; - Does NOT recenter if cursor is already above 60% (at top of file)
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

Recentering only happens when cursor goes BELOW this line.
If cursor is ABOVE this line (e.g., at top of file), no recentering occurs.

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
                'help-echo "Writing mode: cursor at 60% from top (smart recentering)")))

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
;; SMART VERTICAL CURSOR POSITIONING
;; ============================================================

(defun my/get-cursor-position-percentage ()
  "Get current cursor position as percentage from top of window.
Returns value between 0.0 (top) and 1.0 (bottom)."
  (let* ((window-height (window-height))
         (cursor-line (- (line-number-at-pos (point))
                        (line-number-at-pos (window-start))))
         (percentage (/ (float cursor-line) window-height)))
    percentage))

(defun my/recenter-at-position ()
  "Recenter cursor at the configured writing position (60% from top).
But ONLY if cursor is currently BELOW that position.

If cursor is ABOVE the target (e.g., at top of file), do nothing.
This prevents annoying jumps when writing at the top of a file."
  (let* ((window-height (window-height))
         (target-percentage my/writing-cursor-position)
         (current-percentage (my/get-cursor-position-percentage))
         (target-line (round (* window-height target-percentage))))
    ;; Only recenter if cursor is below (greater than) the target position
    (when (> current-percentage target-percentage)
      (recenter target-line))))

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
  ;; Position cursor at configured location immediately (if below target)
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
Smart recentering: only moves view when cursor goes below 60%.
If you're at the top of the file, view stays put.

Scrolling and navigation are NOT affected.
Your horizontal text centering (visual-fill-column) is preserved!

When enabled, shows 'W' in mode line (next to word count).
This is buffer-local, so each note can have it on or off."
  (interactive)
  (if my/centered-writing-mode
      (progn
        (my/disable-centered-writing)
        (message "✍️ Writing mode: OFF"))
    (progn
      (my/enable-centered-writing)
      (message "✍️ Writing mode: ON (smart recentering at 60%%)"))))

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
;; EXPLANATION: Smart recentering
;; ============================================================
;;
;; PROBLEM:
;; - When writing at TOP of file, don't want view to jump down
;; - When writing at BOTTOM of file, want cursor to move up to 60%
;;
;; SOLUTION:
;; - Calculate current cursor position as percentage from top
;; - Only recenter if current position > target (60%)
;; - If current position < target (above 60%), do nothing
;;
;; EXAMPLES:
;; Cursor at 10% (near top) → Do nothing, keep writing at top
;; Cursor at 40% (above 60%) → Do nothing, stay where you are
;; Cursor at 70% (below 60%) → Recenter up to 60%
;; Cursor at 90% (near bottom) → Recenter up to 60%
;;
;; RESULT:
;; - Natural writing flow at top of file (no jumping)
;; - Comfortable position maintained when writing new content
;; - View only adjusts when you actually need it
;;
;; This is "smart" recentering - only when beneficial!

;; ============================================================
;; POSITION ADJUSTMENT GUIDE
;; ============================================================
;;
;; Default: 0.60 (60% from top, 40% empty below)
;;
;; To change permanently, add to custom.el:
;; (setq my/writing-cursor-position 0.55)  ; Higher threshold
;; (setq my/writing-cursor-position 0.65)  ; Lower threshold
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
;; Check current cursor position percentage:
;; M-: (my/get-cursor-position-percentage) RET
;;
;; Check if enabled in current buffer:
;; M-: my/centered-writing-mode RET
;;
;; Check target position:
;; M-: my/writing-cursor-position RET
;;
;; Disable immediately:
;; C-c n W (or M-x my/toggle-centered-writing)

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
