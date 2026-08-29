;;; 13-centered-writing.el --- Simple centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Simple, reliable cursor centering that ONLY recenters when you type.
;; Mouse scrolling and all navigation work normally - no interference!
;;
;; KEY FEATURES:
;; - Recenters cursor ONLY when typing (not on scrolling/clicking)
;; - Mouse scrolling works perfectly (no interference)
;; - Keyboard scrolling works perfectly
;; - Works with soft wrapping
;; - Works when editing anywhere in document
;; - Shows "W" indicator in mode line
;; - Buffer-local: enable per note
;;
;; USAGE:
;; - Transient menu: C-c n W (toggle writing mode)
;; - Manual: M-x my/toggle-centered-writing

;;; Code:

;; ============================================================
;; CONFIGURATION
;; ============================================================

(defvar my/writing-recenter-position nil
  "Position for recentering cursor while writing.
nil = center of window (default)
Number = specific line from top (e.g., 10 = 10 lines from top)

Recommended: nil (center) - works well for all window sizes.")

;; ============================================================
;; BUFFER-LOCAL MODE VARIABLE
;; ============================================================

(defvar-local my/centered-writing-mode nil
  "Non-nil if centered writing mode is enabled in this buffer.
This is buffer-local so each note can have its own state.")

;; ============================================================
;; MODE-LINE INDICATOR
;; ============================================================

(defface my/writing-mode-indicator
  '((t :inherit (bold success)))
  "Face for the writing-mode indicator in the mode line.
Inherits rather than naming a colour: the previous literal \"black\"
was invisible against a dark mode line."
  :group 'mode-line-faces)

(defvar my/writing-mode-line-construct
  '(:eval (when my/centered-writing-mode
            (propertize " W" 'face 'my/writing-mode-indicator
                        'help-echo "Writing mode: cursor centered when typing")))
  "Mode-line construct showing W while centred writing is on.")
(put 'my/writing-mode-line-construct 'risky-local-variable t)

;; CONTRIBUTE A SEGMENT, DO NOT REDEFINE THE MODE LINE
;; --------------------------------------------------
;; This file used to `setq-default mode-line-format' to its own copy of
;; the format from 01-ui.el, plus this indicator.  Two files then
;; declared the same variable and load order decided which one held:
;; editing the format in 01-ui.el had no visible effect, because
;; 13-centered-writing.el loads later and overwrote it.
;;
;; `mode-line-misc-info' is the seam meant for this.  01-ui.el owns the
;; format and lists that variable in it; a module appends its own
;; construct and stays out of the rest.  Deleting this file now removes
;; one indicator instead of reverting the mode line to a stale copy.

(unless (memq 'my/writing-mode-line-construct mode-line-misc-info)
  (add-to-list 'mode-line-misc-info 'my/writing-mode-line-construct))

;; ============================================================
;; SIMPLE RECENTERING ON TYPING
;; ============================================================

(defun my/recenter-on-typing ()
  "Recenter cursor ONLY when typing new characters.
This is simple and reliable - just calls (recenter) after typing.
Does NOT interfere with scrolling, clicking, or navigation."
  (when (and my/centered-writing-mode
             ;; Only trigger on actual text insertion
             (or (eq this-command 'self-insert-command)
                 (eq this-command 'org-self-insert-command)
                 (eq this-command 'newline)
                 (eq this-command 'electric-newline-and-maybe-indent)
                 (eq this-command 'org-return)
                 (eq this-command 'yank)
                 (eq this-command 'delete-backward-char)
                 (eq this-command 'backward-delete-char-untabify)))
    ;; Only recenter if in a writable buffer
    (unless buffer-read-only
      (recenter my/writing-recenter-position))))

;; ============================================================
;; ENABLE/DISABLE FUNCTIONS
;; ============================================================

(defun my/enable-centered-writing ()
  "Enable centered cursor for writing.
Only recenters when typing - all scrolling works normally!"
  (setq my/centered-writing-mode t)
  ;; Recenter immediately
  (recenter my/writing-recenter-position)
  ;; Add hook that ONLY recenters when typing
  (add-hook 'post-command-hook #'my/recenter-on-typing nil t)
  ;; Update mode line
  (force-mode-line-update))

(defun my/disable-centered-writing ()
  "Disable centered cursor."
  (setq my/centered-writing-mode nil)
  ;; Remove our hook
  (remove-hook 'post-command-hook #'my/recenter-on-typing t)
  ;; Update mode line
  (force-mode-line-update))

;; ============================================================
;; TOGGLE FUNCTION
;; ============================================================

(defun my/toggle-centered-writing ()
  "Toggle centered cursor for writing.

This is a SIMPLE, RELIABLE implementation that:
- Recenters cursor ONLY when you type
- Does NOT interfere with mouse scrolling
- Does NOT interfere with keyboard scrolling
- Does NOT interfere with clicking or navigation
- Works with soft wrapping
- Works when editing anywhere in document

When enabled:
- Shows 'W' in mode line (next to word count)
- Cursor centers after typing
- All scrolling and navigation work normally

This is buffer-local, so each note can have it on or off."
  (interactive)
  (if my/centered-writing-mode
      (progn
        (my/disable-centered-writing)
        (message "✍️ Writing mode: OFF"))
    (progn
      (my/enable-centered-writing)
      (message "✍️ Writing mode: ON (mouse scrolling works normally)"))))

;; Alias for transient menu compatibility
(defalias 'my/toggle-writeroom 'my/toggle-centered-writing)

;; ============================================================
;; POSITION ADJUSTMENT FUNCTIONS
;; ============================================================

(defun my/set-writing-position-center ()
  "Set cursor to window center."
  (interactive)
  (setq my/writing-recenter-position nil)
  (when my/centered-writing-mode
    (recenter my/writing-recenter-position))
  (message "Writing position: center"))

(defun my/set-writing-position-upper ()
  "Set cursor to upper third (more space below)."
  (interactive)
  (setq my/writing-recenter-position (round (/ (window-height) 3)))
  (when my/centered-writing-mode
    (recenter my/writing-recenter-position))
  (message "Writing position: upper third"))

(defun my/set-writing-position-lower ()
  "Set cursor to lower third (more space above)."
  (interactive)
  (setq my/writing-recenter-position (round (* 2 (/ (window-height) 3))))
  (when my/centered-writing-mode
    (recenter my/writing-recenter-position))
  (message "Writing position: lower third"))

;; ============================================================
;; USAGE INSTRUCTIONS
;; ============================================================
;;
;; BASIC USAGE:
;; - C-c n W : Toggle writing mode on/off
;;
;; PRESET POSITIONS:
;; - M-x my/set-writing-position-center (default - window center)
;; - M-x my/set-writing-position-upper (upper third)
;; - M-x my/set-writing-position-lower (lower third)
;;
;; BEHAVIOR:
;; - Cursor recenters AFTER you type a character or newline
;; - Mouse scrolling works perfectly (no interference)
;; - Keyboard scrolling (C-v, M-v) works perfectly
;; - Clicking to move cursor works normally
;; - All navigation commands work normally
;;
;; WHY CENTER?
;; - Simple and works for all window sizes
;; - Provides equal context above and below
;; - Tested and reliable
;; - You can adjust to upper/lower if preferred
;;
;; WORKS WITH:
;; ✓ Soft wrapping (visual-line-mode)
;; ✓ Editing anywhere in documents
;; ✓ Long paragraphs that wrap
;; ✓ Window resizing
;; ✓ Multiple buffers (buffer-local)
;; ✓ Horizontal centering (visual-fill-column)
;; ✓ Mouse wheel scrolling (perfect!)
;; ✓ Keyboard scrolling (perfect!)
;;
;; SIMPLE & SAFE:
;; - Only 30 lines of actual code
;; - Only hooks into typing commands
;; - Uses built-in (recenter) function
;; - No external packages
;; - No interference with any other features
;; - Minimal performance impact

;; ============================================================
;; CUSTOMIZATION EXAMPLES
;; ============================================================
;;
;; To change default position permanently, add to custom.el:
;;
;; ;; Upper portion (1/3 from top)
;; (setq my/writing-recenter-position (round (/ (window-height) 3)))
;;
;; ;; Lower portion (2/3 from top)
;; (setq my/writing-recenter-position (round (* 2 (/ (window-height) 3))))
;;
;; ;; Fixed 15 lines from top
;; (setq my/writing-recenter-position 15)
;;
;; ;; Center (default)
;; (setq my/writing-recenter-position nil)

;; ============================================================
;; DEBUGGING
;; ============================================================
;;
;; Check if enabled in current buffer:
;; M-: my/centered-writing-mode RET
;;
;; Check current position setting:
;; M-: my/writing-recenter-position RET
;;
;; Check if hook is active:
;; M-: (member 'my/recenter-on-typing post-command-hook) RET
;;
;; Test recentering manually:
;; M-x recenter RET
;;
;; Disable immediately:
;; C-c n W (or M-x my/toggle-centered-writing)
;;
;; Remove hook manually if needed:
;; M-: (remove-hook 'post-command-hook #'my/recenter-on-typing t) RET

;; ============================================================
;; WHY THIS APPROACH?
;; ============================================================
;;
;; After testing multiple approaches:
;;
;; 1. centered-cursor-mode package:
;;    ✗ Breaks mouse scrolling
;;    ✗ Has compilation warnings
;;    ✗ Overly complex
;;
;; 2. Custom visual-line counting:
;;    ✗ Cursor jumps when editing mid-document
;;    ✗ Complex calculations
;;    ✗ Fragile with soft wrapping
;;
;; 3. Simple recenter on typing (THIS APPROACH):
;;    ✓ Mouse scrolling works perfectly
;;    ✓ No compilation warnings
;;    ✓ Simple and maintainable (30 lines)
;;    ✓ Works everywhere in document
;;    ✓ Works with soft wrapping
;;    ✓ Only recenters when typing
;;    ✓ Uses built-in (recenter) function
;;
;; The key insight: Don't try to be smart about scrolling.
;; Just recenter after typing and leave everything else alone!

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
