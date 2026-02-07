;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically positioned cursor while writing.
;; Only recenters when you actually TYPE, not on every command.
;;
;; KEY FEATURES:
;; - Keeps cursor at configured position WHILE TYPING
;; - Does NOT recenter when scrolling, clicking, or navigating
;; - Works with visual-fill-column (horizontal centering preserved!)
;; - Lightweight and safe
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
;; VERTICAL CURSOR POSITIONING (SAFE VERSION)
;; ============================================================

(defvar-local my/centered-writing-mode nil
  "Non-nil if centered writing mode is enabled in this buffer.")

(defun my/recenter-at-position ()
  "Recenter cursor at the configured writing position.
This function is safe and only calculates line position."
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
  (add-hook 'post-command-hook #'my/recenter-on-typing nil t))

(defun my/disable-centered-writing ()
  "Disable vertically positioned cursor."
  (setq my/centered-writing-mode nil)
  ;; Remove our recentering hook
  (remove-hook 'post-command-hook #'my/recenter-on-typing t))

;; ============================================================
;; TOGGLE FUNCTION
;; ============================================================

(defun my/toggle-centered-writing ()
  "Toggle vertically positioned cursor for writing.

This keeps your cursor at a comfortable writing position WHILE YOU TYPE.
Scrolling and navigation are NOT affected.
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
;; ADJUSTMENT FUNCTIONS
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
;; EXPLANATION: How this SAFE version works
;; ============================================================
;;
;; PREVIOUS PROBLEM:
;; - Running recenter after EVERY command was too aggressive
;; - Caused blocking, freezing, and disabled scrolling
;; - Made Emacs unresponsive
;;
;; NEW APPROACH:
;; - Only recenter when you ACTUALLY TYPE (self-insert-command)
;; - Checks specific typing commands: typing, newline, paste
;; - Does NOT run on: scrolling, clicking, navigating, mouse movements
;; - Much lighter weight and safer
;;
;; Result:
;; - When you type new text → cursor recenters to configured position
;; - When you scroll → normal scrolling works fine
;; - When you click → no recentering
;; - When you navigate (arrows) → no recentering
;;
;; This is the "write-only centering" you originally asked for!

;; ============================================================
;; DEBUGGING TIPS
;; ============================================================
;;
;; If you still experience issues:
;;
;; 1. Disable the mode immediately:
;;    C-c n W (or M-x my/toggle-centered-writing)
;;
;; 2. Check if hook is still active:
;;    M-x describe-variable RET post-command-hook RET
;;    Look for 'my/recenter-on-typing'
;;
;; 3. Remove hook manually if needed:
;;    M-: (remove-hook 'post-command-hook #'my/recenter-on-typing t)
;;
;; 4. If Emacs freezes, kill from terminal:
;;    killall emacs
;;
;; 5. Comment out this entire module in init.el:
;;    ;; (load (concat modules-dir "13-centered-writing.el"))

;; ============================================================
;; POSITION ADJUSTMENT GUIDE
;; ============================================================
;;
;; Values for my/writing-cursor-position:
;;
;; 0.35 = Higher up (35% from top, 65% empty below)
;; 0.5  = Exact center (50% from top, 50% below)
;; 0.65 = Slightly lower (65% from top, 35% below) [DEFAULT]
;; 0.7  = Even lower (70% from top, 30% below)
;; 0.75 = Very low (75% from top, 25% below)
;;
;; To change permanently, add to custom.el:
;; (setq my/writing-cursor-position 0.7)

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

;; ============================================================
;; SAFETY NOTES
;; ============================================================
;;
;; BENEFITS:
;; - Much safer than previous version
;; - Only recenters when actually typing
;; - Preserves normal scrolling and navigation
;; - Preserves visual-fill-column horizontal centering
;; - Minimal performance impact
;;
;; BEHAVIOR:
;; - Typing new text → cursor recenters to configured position
;; - Scrolling → works normally, no interference
;; - Clicking → no recentering, cursor stays where you clicked
;; - Arrow keys → no recentering, normal navigation
;; - Correcting spelling → works normally
;;
;; This is exactly what you asked for:
;; "centre the writing line only when I write, not when just
;; reading a note, and jumping with the cursor"

(provide '13-centered-writing)
;;; 13-centered-writing.el ends here
