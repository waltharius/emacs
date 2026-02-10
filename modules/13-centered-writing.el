;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically positioned cursor while writing.
;; Only recenters when you actually TYPE, not on every command.
;;
;; KEY FEATURES:
;; - Keeps cursor at configured position from top while typing
;; - Shows "W" indicator in mode line when enabled
;; - Does NOT recenter when scrolling, clicking, or navigating
;; - Works with visual-fill-column (horizontal centering preserved!)
;; - Works correctly with soft wrapping (visual-line-mode)
;; - Buffer-local: enable per note
;;
;; USAGE:
;; - Transient menu: C-c n W (toggle writing mode)
;; - Manual: M-x my/toggle-centered-writing

;;; Code:

;; ============================================================
;; CONFIGURATION
;; ============================================================

(defvar my/writing-cursor-position 0.4
  "Vertical position of cursor as fraction from top of window.
0.4 = upper portion (40% from top, 60% empty below) [DEFAULT]
0.5 = center (50% from top)
0.6 = slightly below center (60% from top, 40% empty below)

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
                'help-echo (format "Writing mode: cursor at %d%% from top"
                                  (round (* my/writing-cursor-position 100))))))

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
;; VERTICAL CURSOR POSITIONING (VISUAL LINES)
;; ============================================================

(defun my/recenter-at-position ()
  "Recenter cursor at the configured writing position using VISUAL lines.
This works correctly with soft wrapping (visual-line-mode) because it
counts screen lines, not logical lines."
  (let* ((window-height (window-text-height))  ; Visible text lines
         ;; Calculate target: how many visual lines from window-start
         (target-line (round (* window-height my/writing-cursor-position)))
         ;; Count visual lines from window-start to cursor
         (current-visual-line (count-screen-lines (window-start) (point) nil (selected-window))))
    
    ;; Calculate how many lines to scroll
    (let ((lines-to-scroll (- current-visual-line target-line)))
      (when (not (zerop lines-to-scroll))
        ;; Scroll window without moving point
        (scroll-down lines-to-scroll)))))

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
      (condition-case err
          (my/recenter-at-position)
        ;; Catch any errors to prevent breaking typing
        (error (message "Writing mode recentering error: %s" err))))))

(defun my/enable-centered-writing ()
  "Enable vertically positioned cursor for writing."
  (setq my/centered-writing-mode t)
  ;; Position cursor at configured location immediately
  (condition-case nil
      (my/recenter-at-position)
    (error nil))  ; Ignore errors on initial positioning
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

This keeps your cursor at the configured position from top WHILE YOU TYPE.
Scrolling and navigation are NOT affected.
Your horizontal text centering (visual-fill-column) is preserved!

Works correctly with soft wrapping (visual-line-mode) - counts visual lines
on screen, not logical lines in the buffer.

When enabled, shows 'W' in mode line (next to word count).
This is buffer-local, so each note can have it on or off."
  (interactive)
  (if my/centered-writing-mode
      (progn
        (my/disable-centered-writing)
        (message "✍️ Writing mode: OFF"))
    (progn
      (my/enable-centered-writing)
      (message "✍️ Writing mode: ON (cursor at %d%% from top)"
               (round (* my/writing-cursor-position 100))))))

;; Alias for transient menu compatibility
(defalias 'my/toggle-writeroom 'my/toggle-centered-writing)

;; ============================================================
;; ADJUSTMENT FUNCTIONS
;; ============================================================

(defun my/set-writing-position-upper ()
  "Set cursor to upper portion (40% from top, 60% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.4)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: upper (40%% from top)"))

(defun my/set-writing-position-center ()
  "Set cursor to exact center (50/50)."
  (interactive)
  (setq my/writing-cursor-position 0.5)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: center (50%% from top)"))

(defun my/set-writing-position-lower ()
  "Set cursor lower (60% from top, 40% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.6)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: lower (60%% from top)"))

;; ============================================================
;; EXPLANATION: How this works
;; ============================================================
;;
;; VISUAL vs LOGICAL LINES:
;; - This now works with VISUAL lines (what you see on screen)
;; - Not logical lines (actual newlines in buffer)
;; - Perfect for soft-wrapped text in visual-line-mode
;; - Long paragraphs wrap correctly, cursor stays at target position
;;
;; RECENTERING:
;; - Only happens when you TYPE (self-insert-command, newline, yank)
;; - Does NOT happen when: scrolling, clicking, navigating
;; - Cursor stays at configured position from top
;;
;; MODE-LINE INDICATOR:
;; - Shows black "W" next to word count when enabled
;; - Buffer-local: each buffer has its own state
;; - Hover over "W" to see current position percentage
;;
;; DEFAULT POSITION (40%):
;; - Upper portion of screen (40% from top)
;; - Gives you 60% of screen space below for context
;; - Comfortable for most writing
;; - Adjustable via helper functions
;;
;; SAFE:
;; - Only recenters on actual typing commands
;; - Error handling prevents breaking typing
;; - Minimal performance impact
;; - Preserves scrolling ability

;; ============================================================
;; POSITION ADJUSTMENT GUIDE
;; ============================================================
;;
;; Default: 0.4 (40% from top, 60% empty below)
;;
;; To change permanently, add to custom.el:
;; (setq my/writing-cursor-position 0.4)  ; Upper (default)
;; (setq my/writing-cursor-position 0.5)  ; Center
;; (setq my/writing-cursor-position 0.6)  ; Lower
;;
;; Or use helper functions while writing:
;; M-x my/set-writing-position-upper   ; 40% (default)
;; M-x my/set-writing-position-center  ; 50%
;; M-x my/set-writing-position-lower   ; 60%

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
;; Test visual line counting:
;; M-: (count-screen-lines (window-start) (point)) RET
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
