;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically positioned cursor while writing.
;; Uses native Emacs recenter function - no external packages needed!
;;
;; KEY FEATURES:
;; - Keeps cursor at configured vertical position while typing
;; - Works with visual-fill-column (horizontal centering preserved!)
;; - Lightweight - uses built-in Emacs features
;; - Toggle on/off as needed
;; - Configurable position (default: 65% from top, 35% empty below)
;;
;; USAGE:
;; - Transient menu: C-c n W (toggle writing mode)
;; - Manual: M-x my/toggle-centered-writing

;;; Code:

;; ============================================================
;; CONFIGURATION
;; ============================================================

(defvar my/writing-cursor-position 0.65
  "Vertical position of cursor as fraction from top of window.
0.5 = center (50% from top)
0.65 = slightly below center (65% from top, 35% empty below) [DEFAULT]
0.7 = even lower (70% from top, 30% empty below)
0.35 = higher up (35% from top, 65% empty below)

Adjust this value to your preference!")

;; ============================================================
;; VERTICAL CURSOR POSITIONING
;; ============================================================

(defvar-local my/centered-writing-mode nil
  "Non-nil if centered writing mode is enabled in this buffer.")

(defun my/recenter-at-position ()
  "Recenter cursor at the configured writing position."
  (when my/centered-writing-mode
    (let* ((window-height (window-height))
           ;; Calculate line position from top
           (target-line (round (* window-height my/writing-cursor-position))))
      ;; Recenter to place cursor at target line from top
      (recenter target-line))))

(defun my/enable-centered-writing ()
  "Enable vertically positioned cursor for writing."
  (setq my/centered-writing-mode t)
  ;; Position cursor at configured location immediately
  (my/recenter-at-position)
  ;; Keep recentering after each command
  (add-hook 'post-command-hook #'my/recenter-at-position nil t))

(defun my/disable-centered-writing ()
  "Disable vertically positioned cursor."
  (setq my/centered-writing-mode nil)
  ;; Remove our recentering hook
  (remove-hook 'post-command-hook #'my/recenter-at-position t))

;; ============================================================
;; TOGGLE FUNCTION
;; ============================================================

(defun my/toggle-centered-writing ()
  "Toggle vertically positioned cursor for writing.

This keeps your cursor at a comfortable writing position.
Your horizontal text centering (visual-fill-column) is preserved!

Default position: 65% from top (35% empty space below)
Change 'my/writing-cursor-position' to adjust (0.5 = center)."
  (interactive)
  (if my/centered-writing-mode
      (progn
        (my/disable-centered-writing)
        (message "✍️ Writing mode: OFF"))
    (progn
      (my/enable-centered-writing)
      (message "✍️ Writing mode: ON (cursor at %.0f%% from top)"
               (* 100 my/writing-cursor-position)))))

;; Alias for transient menu compatibility
(defalias 'my/toggle-writeroom 'my/toggle-centered-writing)

;; ============================================================
;; EASY ADJUSTMENT FUNCTIONS
;; ============================================================

(defun my/set-writing-position-center ()
  "Set cursor to exact center (50/50)."
  (interactive)
  (setq my/writing-cursor-position 0.5)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: center (50%% from top)"))

(defun my/set-writing-position-lower ()
  "Set cursor lower (65% from top, 35% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.65)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: lower (65%% from top)"))

(defun my/set-writing-position-higher ()
  "Set cursor higher (35% from top, 65% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.35)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: higher (35%% from top)"))

(defun my/set-writing-position-very-low ()
  "Set cursor very low (75% from top, 25% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.75)
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: very low (75%% from top)"))

;; ============================================================
;; EXPLANATION: How this works
;; ============================================================
;;
;; This uses Emacs's built-in 'recenter' function in a post-command-hook:
;;
;; 1. After EVERY command (typing, moving, clicking), we call recenter
;; 2. Recenter positions the current line at a specific screen line
;; 3. We calculate which screen line based on window height and your preference
;;
;; Example with 0.65 setting and 40-line window:
;; - Window height: 40 lines
;; - Target position: 40 * 0.65 = 26 lines from top
;; - Result: Cursor stays at line 26 (65% down, 35% empty below)
;;
;; IMPORTANT: This runs after EVERY command, so:
;; - When you type → cursor stays at configured position
;; - When you click → view recenters to keep cursor at configured position
;; - When you scroll → cursor returns to configured position
;;
;; This is the trade-off: consistent cursor position = view adjusts to you

;; ============================================================
;; POSITION ADJUSTMENT GUIDE
;; ============================================================
;;
;; The variable my/writing-cursor-position controls where the
;; cursor sits vertically in the window:
;;
;; 0.35 = Higher up (35% from top, 65% empty below)
;; 0.5  = Exact center (50% from top, 50% below)
;; 0.65 = Slightly lower (65% from top, 35% below) [DEFAULT]
;; 0.7  = Even lower (70% from top, 30% below)
;; 0.75 = Very low (75% from top, 25% below)
;;
;; TO CHANGE THE POSITION:
;;
;; Method 1: Edit this file
;; Change the default value in the defvar above (line 23)
;;
;; Method 2: Set in your custom.el
;; Add this line:
;; (setq my/writing-cursor-position 0.7)  ; 70% from top
;;
;; Method 3: While writing mode is active
;; M-x my/set-writing-position-center    ; Try center (50%)
;; M-x my/set-writing-position-higher    ; Try higher (35%)
;; M-x my/set-writing-position-lower     ; Try lower (65%) [default]
;; M-x my/set-writing-position-very-low  ; Try very low (75%)
;;
;; The position is stored globally, so once you find your
;; preferred value, it persists across buffers.

;; ============================================================
;; OPTIONAL: Auto-enable for journal files
;; ============================================================
;;
;; Uncomment to automatically enable centered writing
;; when opening journal files:
;;
;; (add-hook 'org-mode-hook
;;           (lambda ()
;;             (when (and buffer-file-name
;;                        (string-match-p "journal" buffer-file-name))
;;               (my/enable-centered-writing))))

;; ============================================================
;; SAFETY NOTES
;; ============================================================
;;
;; BENEFITS:
;; - Native Emacs solution (no external packages)
;; - Fast and reliable
;; - Preserves visual-fill-column horizontal centering
;; - Easy to toggle on/off
;; - Fully configurable position
;; - Simple implementation (just recenter + hook)
;;
;; CONSIDERATIONS:
;; - Cursor will recenter after EVERY command
;; - This includes typing, clicking, and navigating
;; - The view adjusts to keep cursor at configured position
;; - Some users find this natural, others prefer manual control
;;
;; TESTING:
;; 1. Open a journal file
;; 2. Press C-c n W to enable
;; 3. Observe cursor position - should be 65% from top
;; 4. Try: M-x my/set-writing-position-center (should move to 50%)
;; 5. Try: M-x my/set-writing-position-higher (should move to 35%)
;; 6. Start typing - cursor stays at configured position
;; 7. Press C-c n W again to disable
;;
;; Your horizontal centering (visual-fill-column) will work
;; perfectly with this!

(provide '13-centered-writing)
;;; 13-centered-writing.el ends here
