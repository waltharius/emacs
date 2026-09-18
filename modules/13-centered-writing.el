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
;; - Holds its position in notes containing inline images (see
;;   `my/writing-recenter-pixelwise')
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

(defvar my/writing-recenter-pixelwise t
  "When non-nil, correct the recentring afterwards by pixel position.

WHY THIS EXISTS
`recenter' counts SCREEN LINES.  An inline image is one screen line
several hundred pixels tall, so in a note containing pictures the line
that `recenter' calls the middle of the window can sit anywhere on
screen -- typically far too low, because the image above it has eaten
the space the line count assumed.  The cursor then stops holding its
position while typing, which is the whole point of the mode.

The correction below scrolls the window one screen line at a time until
the cursor is within `my/writing-recenter-tolerance' of where it should
be measured in PIXELS.  In a buffer of uniform line heights `recenter'
is already inside that tolerance, so the loop does not run and costs one
`pos-visible-in-window-p' call per keystroke.

The other half of the same problem is solved by not drawing the images
at all: `C-c u i' (44-image-display.el).")

(defvar my/writing-recenter-tolerance nil
  "How far from the wanted pixel position the cursor may sit, in pixels.
nil means one default line height, which is the smallest value that does
not make the window scroll an extra line on ordinary text -- `recenter'
is accurate to within half a line there, and a tighter tolerance would
trade the image problem for visible jitter.")

(defvar my/writing-recenter-max-steps 60
  "Upper bound on scrolling steps per correction.
An image taller than the window can make the wanted position
unreachable; the loop then stops rather than scrolling forever.")

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

(defun my/writing--target-pixel (window)
  "Return where in WINDOW the cursor should sit, in pixels from the top.
Derived from `my/writing-recenter-position' so that both spellings of
the setting -- nil for the middle, a line number from the top --
continue to mean the same thing."
  (let ((height (window-body-height window t)))
    (if (null my/writing-recenter-position)
        (/ height 2)
      (max 0 (min height (* my/writing-recenter-position (default-line-height)))))))

(defun my/writing--point-pixel (window)
  "Return the cursor's pixel offset from the top of WINDOW, or nil.
Nil when point is not visible, which is the signal to stop correcting
rather than to scroll blindly."
  (let ((posn (pos-visible-in-window-p (point) window t)))
    (and posn (nth 1 posn))))

(defun my/writing--screen-line (position window lines)
  "Return the buffer position LINES screen lines from POSITION in WINDOW.
Nil when the buffer ends first.  Screen lines rather than logical ones,
because notes are soft-wrapped and a paragraph is one logical line."
  (save-excursion
    (goto-char position)
    (and (= (abs lines) (abs (vertical-motion lines window)))
         (point))))

(defun my/writing-recenter ()
  "Put the cursor where `my/writing-recenter-position' asks, in pixels.

`recenter' does the coarse work, which is enough whenever every line in
the window is the same height.  The loop then corrects what a tall line
-- in practice an inline image -- has thrown off, by moving the window
start one screen line at a time.  It stops when the cursor is close
enough, when a step changes nothing, when the cursor would leave the
window, or after `my/writing-recenter-max-steps' steps."
  (recenter my/writing-recenter-position)
  (when my/writing-recenter-pixelwise
    (let* ((window (selected-window))
           (target (my/writing--target-pixel window))
           (tolerance (or my/writing-recenter-tolerance (default-line-height)))
           (steps my/writing-recenter-max-steps)
           (previous nil)
           (current (my/writing--point-pixel window)))
      (while (and current
                  (> steps 0)
                  (not (equal current previous))
                  (> (abs (- current target)) tolerance))
        (setq previous current
              steps (1- steps))
        (let* ((start (window-start window))
               (next (my/writing--screen-line
                      start window (if (> current target) 1 -1))))
          (if (and next
                   (/= next start)
                   ;; Never scroll the cursor's own line out of sight.
                   (or (< current target) (< next (point))))
              (set-window-start window next t)
            (setq steps 0)))
        (setq current (my/writing--point-pixel window))))))

(defun my/recenter-on-typing ()
  "Recenter cursor ONLY when typing new characters.
Calls `my/writing-recenter' after typing, which is `recenter' plus a
pixel correction for buffers containing images.
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
      (my/writing-recenter))))

;; ============================================================
;; ENABLE/DISABLE FUNCTIONS
;; ============================================================

(defun my/enable-centered-writing ()
  "Enable centered cursor for writing.
Only recenters when typing - all scrolling works normally!"
  (setq my/centered-writing-mode t)
  ;; Recenter immediately
  (my/writing-recenter)
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
    (my/writing-recenter))
  (message "Writing position: center"))

(defun my/set-writing-position-upper ()
  "Set cursor to upper third (more space below)."
  (interactive)
  (setq my/writing-recenter-position (round (/ (window-height) 3)))
  (when my/centered-writing-mode
    (my/writing-recenter))
  (message "Writing position: upper third"))

(defun my/set-writing-position-lower ()
  "Set cursor to lower third (more space above)."
  (interactive)
  (setq my/writing-recenter-position (round (* 2 (/ (window-height) 3))))
  (when my/centered-writing-mode
    (my/writing-recenter))
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
;; NOTES CONTAINING IMAGES:
;; - An image is one screen line but many pixels tall, so plain
;;   `recenter' misplaces the cursor.  `my/writing-recenter' corrects
;;   that afterwards by measuring in pixels.
;; - To take the images out of the way entirely: C-c u i
;;   (`my/image-display-toggle', 44-image-display.el).
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
