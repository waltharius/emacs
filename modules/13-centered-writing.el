;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically centered cursor while writing.
;; Uses native Emacs scroll settings - no external packages needed!
;;
;; KEY FEATURES:
;; - Keeps cursor vertically positioned while typing
;; - Works with visual-fill-column (horizontal centering preserved!)
;; - Lightweight - uses built-in Emacs features
;; - Toggle on/off as needed
;; - Configurable position (default: 65% from top)
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
0.65 = slightly below center (65% from top, 35% empty below)
0.7 = even lower (70% from top, 30% empty below)
0.35 = higher up (35% from top, 65% empty below)

Adjust this value to your preference!")

;; ============================================================
;; VERTICAL CURSOR POSITIONING: Native Emacs solution
;; ============================================================
;;
;; This uses Emacs's built-in scroll settings combined with
;; recenter to position the cursor at your preferred location.
;;
;; How it works:
;; - scroll-margin: Forces recentering when approaching edges
;; - recenter: Positions cursor at specific line
;; - We calculate the line based on window height and your preference
;;
;; Result: Cursor stays at your chosen position while you type!

(defvar-local my/centered-writing-mode nil
  "Non-nil if centered writing mode is enabled in this buffer.")

(defun my/recenter-at-position ()
  "Recenter cursor at the configured writing position."
  (let* ((window-height (window-height))
         (target-line (round (* window-height my/writing-cursor-position))))
    (recenter target-line)))

(defun my/enable-centered-writing ()
  "Enable vertically positioned cursor for writing."
  (setq-local scroll-preserve-screen-position t)
  (setq-local scroll-conservatively 0)
  (setq-local maximum-scroll-margin 0.5)
  (setq-local scroll-margin 99999)  ; Large number = always recenter
  (setq my/centered-writing-mode t)
  ;; Position cursor at configured location
  (my/recenter-at-position)
  ;; Ensure recentering happens after each command
  (add-hook 'post-command-hook #'my/recenter-at-position nil t))

(defun my/disable-centered-writing ()
  "Disable vertically positioned cursor."
  (setq-local scroll-preserve-screen-position nil)
  (setq-local scroll-conservatively 101)  ; Back to smooth scrolling
  (setq-local maximum-scroll-margin 0.125)
  (setq-local scroll-margin 0)
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
;;
;; Want to quickly test different positions?
;; Use these helper functions:

(defun my/set-writing-position-center ()
  "Set cursor to exact center (50/50)."
  (interactive)
  (setq my/writing-cursor-position 0.5)
  (when my/centered-writing-mode
    (my/recenter-at-position)
    (message "Writing position: center (50%% from top)")))

(defun my/set-writing-position-lower ()
  "Set cursor lower (65% from top, 35% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.65)
  (when my/centered-writing-mode
    (my/recenter-at-position)
    (message "Writing position: lower (65%% from top)")))

(defun my/set-writing-position-higher ()
  "Set cursor higher (35% from top, 65% empty below)."
  (interactive)
  (setq my/writing-cursor-position 0.35)
  (when my/centered-writing-mode
    (my/recenter-at-position)
    (message "Writing position: higher (35%% from top)")))

;; ============================================================
;; EXPLANATION: Position adjustment
;; ============================================================
;;
;; The variable my/writing-cursor-position controls where the
;; cursor sits vertically in the window:
;;
;; 0.5  = Exact center (50% from top, 50% below)
;; 0.65 = Slightly lower (65% from top, 35% below) [DEFAULT]
;; 0.7  = Even lower (70% from top, 30% below)
;; 0.35 = Higher up (35% from top, 65% below)
;;
;; TO CHANGE THE POSITION:
;;
;; Method 1: Edit this file
;; Change the default value in the defvar above (line 27)
;;
;; Method 2: Set in your custom.el or init.el
;; Add this line:
;; (setq my/writing-cursor-position 0.7)  ; 70% from top
;;
;; Method 3: While writing mode is active
;; M-x my/set-writing-position-center    ; Try center
;; M-x my/set-writing-position-lower     ; Try lower
;; M-x my/set-writing-position-higher    ; Try higher
;;
;; The position is stored in the variable, so once you find
;; your preferred value, you can set it permanently.

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
;;
;; CONSIDERATIONS:
;; - Cursor will recenter after each command
;; - This is intentional for consistent writing position
;; - Uses post-command-hook (minimal performance impact)
;;
;; TESTING:
;; 1. Open a journal file
;; 2. Press C-c n W to enable
;; 3. Start typing - cursor stays at configured position
;; 4. Too high/low? M-x my/set-writing-position-* to adjust
;; 5. Press C-c n W again to disable
;;
;; Your horizontal centering (visual-fill-column) will work
;; perfectly with this!

(provide '13-centered-writing)
;;; 13-centered-writing.el ends here
