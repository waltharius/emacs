;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically positioned cursor while writing.
;; Only recenters when you actually TYPE, not on every command.
;; Smart positioning: adjusts for different fonts (journal vs technical notes).
;;
;; KEY FEATURES:
;; - Keeps cursor at configured position WHILE TYPING
;; - Different positions for journal (variable-pitch) vs technical (monospace)
;; - Does NOT recenter when scrolling, clicking, or navigating
;; - Works with visual-fill-column (horizontal centering preserved!)
;;
;; USAGE:
;; - Transient menu: C-c n W (toggle writing mode)
;; - Manual: M-x my/toggle-centered-writing

;;; Code:

;; ============================================================
;; CONFIGURATION
;; ============================================================

(defvar my/writing-cursor-position-monospace 0.65
  "Vertical position for monospace fonts (technical notes).
0.5 = center, 0.65 = slightly below center [DEFAULT]

This is used for files with fixed-pitch/monospace fonts.")

(defvar my/writing-cursor-position-variable 0.60
  "Vertical position for variable-pitch fonts (journal notes).
0.5 = center, 0.60 = slightly below center [DEFAULT]

This is used for journal files with Playpen Sans font.
Slightly higher than monospace (0.60 vs 0.65) to compensate
for fewer lines fitting in the window with larger fonts.")

;; ============================================================
;; VERTICAL CURSOR POSITIONING (SMART VERSION)
;; ============================================================

(defvar-local my/centered-writing-mode nil
  "Non-nil if centered writing mode is enabled in this buffer.")

(defun my/get-current-writing-position ()
  "Get the appropriate cursor position based on current buffer font.
Returns different value for journal (variable-pitch) vs technical (monospace)."
  (if (and (boundp 'variable-pitch-mode) variable-pitch-mode)
      ;; Variable pitch (journal) - use slightly higher position
      my/writing-cursor-position-variable
    ;; Fixed pitch (technical) - use default position
    my/writing-cursor-position-monospace))

(defun my/recenter-at-position ()
  "Recenter cursor at the configured writing position.
Automatically adjusts for journal vs technical notes."
  (let* ((window-height (window-height))
         (position (my/get-current-writing-position))
         (target-line (round (* window-height position))))
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
Automatically adjusts for journal notes (variable-pitch) vs technical notes.
Scrolling and navigation are NOT affected.

Your horizontal text centering (visual-fill-column) is preserved!"
  (interactive)
  (if my/centered-writing-mode
      (progn
        (my/disable-centered-writing)
        (message "✍️ Writing mode: OFF"))
    (progn
      (my/enable-centered-writing)
      (let* ((position (my/get-current-writing-position))
             (note-type (if (and (boundp 'variable-pitch-mode) variable-pitch-mode)
                            "journal"
                          "technical")))
        (message "✍️ Writing mode: ON (%s: %.0f%% from top)"
                 note-type
                 (* 100 position))))))

;; Alias for transient menu compatibility
(defalias 'my/toggle-writeroom 'my/toggle-centered-writing)

;; ============================================================
;; ADJUSTMENT FUNCTIONS
;; ============================================================

(defun my/set-writing-position-center ()
  "Set cursor to exact center (50/50) for current note type."
  (interactive)
  (if (and (boundp 'variable-pitch-mode) variable-pitch-mode)
      (setq my/writing-cursor-position-variable 0.5)
    (setq my/writing-cursor-position-monospace 0.5))
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: center (50%% from top)"))

(defun my/set-writing-position-lower ()
  "Set cursor lower for current note type."
  (interactive)
  (if (and (boundp 'variable-pitch-mode) variable-pitch-mode)
      (setq my/writing-cursor-position-variable 0.60)
    (setq my/writing-cursor-position-monospace 0.65))
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: lower (journal: 60%%, technical: 65%%)"))

(defun my/set-writing-position-higher ()
  "Set cursor higher for current note type."
  (interactive)
  (if (and (boundp 'variable-pitch-mode) variable-pitch-mode)
      (setq my/writing-cursor-position-variable 0.35)
    (setq my/writing-cursor-position-monospace 0.40))
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: higher (journal: 35%%, technical: 40%%)"))

(defun my/set-writing-position-very-low ()
  "Set cursor very low for current note type."
  (interactive)
  (if (and (boundp 'variable-pitch-mode) variable-pitch-mode)
      (setq my/writing-cursor-position-variable 0.70)
    (setq my/writing-cursor-position-monospace 0.75))
  (when my/centered-writing-mode
    (my/recenter-at-position))
  (message "Writing position: very low (journal: 70%%, technical: 75%%)"))

;; ============================================================
;; EXPLANATION: Why different positions?
;; ============================================================
;;
;; PROBLEM:
;; - Journal notes use Playpen Sans (large, variable-width font)
;; - Technical notes use JetBrains Mono (small, monospace font)
;; - window-height returns FEWER lines for larger fonts
;; - Same percentage × fewer lines = LOWER visual position
;;
;; EXAMPLE:
;; Journal:    30 lines fit → 0.65 × 30 = line 19.5 (very low!)
;; Technical:  40 lines fit → 0.65 × 40 = line 26 (higher)
;;
;; SOLUTION:
;; - Use LOWER percentage for journal (0.60 instead of 0.65)
;; - Use HIGHER percentage for technical (0.65)
;; - Result: Similar VISUAL position despite different line counts
;;
;; The code detects variable-pitch-mode and adjusts automatically!

;; ============================================================
;; ADJUSTMENT GUIDE
;; ============================================================
;;
;; Default positions:
;; - Journal (variable-pitch): 0.60 (60% from top, 40% below)
;; - Technical (monospace):    0.65 (65% from top, 35% below)
;;
;; To adjust for your preferences, change the defvar values above:
;;
;; (setq my/writing-cursor-position-variable 0.55)  ; Journal lower
;; (setq my/writing-cursor-position-monospace 0.70) ; Technical lower
;;
;; Or use the helper functions:
;; M-x my/set-writing-position-center
;; M-x my/set-writing-position-higher
;; M-x my/set-writing-position-lower
;; M-x my/set-writing-position-very-low
;;
;; These adjust the appropriate variable based on current buffer.

;; ============================================================
;; DEBUGGING TIPS
;; ============================================================
;;
;; Check current settings:
;; M-: my/writing-cursor-position-variable RET
;; M-: my/writing-cursor-position-monospace RET
;;
;; Check if variable-pitch is active:
;; M-: variable-pitch-mode RET
;;
;; Check window height:
;; M-: (window-height) RET
;;
;; Disable if issues:
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
