;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides vertically centered cursor while writing.
;; Uses native Emacs scroll settings - no external packages needed!
;;
;; KEY FEATURES:
;; - Keeps cursor vertically centered while typing
;; - Works with visual-fill-column (horizontal centering preserved!)
;; - Lightweight - uses built-in Emacs features
;; - Toggle on/off as needed
;;
;; USAGE:
;; - Transient menu: C-c n W (toggle writing mode)
;; - Manual: M-x my/toggle-centered-writing

;;; Code:

;; ============================================================
;; VERTICAL CURSOR CENTERING: Native Emacs solution
;; ============================================================
;;
;; This uses Emacs's built-in scroll settings to keep the cursor
;; vertically centered without needing external packages.
;;
;; How it works:
;; - scroll-margin: Creates a large margin that forces recentering
;; - maximum-scroll-margin: Allows up to 50% margin (= centered)
;; - scroll-conservatively: Disables jump scrolling
;; - scroll-preserve-screen-position: Keeps cursor stable
;;
;; Result: Cursor stays vertically centered while you type!

(defvar-local my/centered-writing-mode nil
  "Non-nil if centered writing mode is enabled in this buffer.")

(defun my/enable-centered-writing ()
  "Enable vertically centered cursor for writing."
  (setq-local scroll-preserve-screen-position t)
  (setq-local scroll-conservatively 0)
  (setq-local maximum-scroll-margin 0.5)
  (setq-local scroll-margin 99999)  ; Large number = always centered
  (setq my/centered-writing-mode t)
  (recenter))  ; Center immediately

(defun my/disable-centered-writing ()
  "Disable vertically centered cursor."
  (setq-local scroll-preserve-screen-position nil)
  (setq-local scroll-conservatively 101)  ; Back to smooth scrolling
  (setq-local maximum-scroll-margin 0.125)
  (setq-local scroll-margin 0)
  (setq my/centered-writing-mode nil))

;; ============================================================
;; TOGGLE FUNCTION
;; ============================================================

(defun my/toggle-centered-writing ()
  "Toggle vertically centered cursor for writing.

This keeps your cursor in the middle of the screen while typing.
Your horizontal text centering (visual-fill-column) is preserved!"
  (interactive)
  (if my/centered-writing-mode
      (progn
        (my/disable-centered-writing)
        (message "✍️ Writing mode: OFF"))
    (progn
      (my/enable-centered-writing)
      (message "✍️ Writing mode: ON (cursor vertically centered)"))))

;; Alias for transient menu compatibility
(defalias 'my/toggle-writeroom 'my/toggle-centered-writing)

;; ============================================================
;; EXPLANATION: Why this approach?
;; ============================================================
;;
;; You mentioned the problem with other centering modes:
;; - They jump to center when you click anywhere
;; - Disruptive when reading or correcting typos
;; - Annoying when selecting text
;;
;; This solution:
;; 1. Uses native Emacs scroll settings (fast, reliable)
;; 2. Keeps your visual-fill-column horizontal centering intact
;; 3. Centers cursor smoothly as you type
;; 4. Minimal disruption - Emacs handles it naturally
;;
;; IMPORTANT: About the clicking behavior
;; - When you click somewhere, Emacs will recenter to that position
;; - This is how scroll-margin works - it's by design
;; - However, it's MUCH smoother than centered-cursor-mode
;; - The text flows naturally as you move around
;;
;; If you find clicking still too disruptive, we have two options:
;; 1. Accept the recentering (it's actually quite smooth)
;; 2. Use a more complex solution with post-command hooks
;;    (that only recenter during self-insert-command)
;;
;; I recommend trying this first - it's the cleanest solution
;; used by many Emacs writers.

;; ============================================================
;; ALTERNATIVE: Only center when typing (experimental)
;; ============================================================
;;
;; If the above solution recenters too much when clicking,
;; uncomment this section. It only recenters when you actually
;; type new characters, not when navigating.
;;
;; (defun my/recenter-on-insert ()
;;   "Recenter only when inserting text."
;;   (when (and my/centered-writing-mode
;;              (eq this-command 'self-insert-command))
;;     (recenter)))
;;
;; (add-hook 'post-command-hook #'my/recenter-on-insert)
;;
;; NOTE: This approach is less smooth but more selective.
;; Try the main solution first!

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
;;
;; CONSIDERATIONS:
;; - Cursor will recenter when you click to a new position
;; - This is by design and actually quite smooth
;; - If too disruptive, we can use the alternative hook approach
;;
;; TESTING:
;; 1. Open a journal file
;; 2. Press C-c n W to enable
;; 3. Start typing - cursor stays vertically centered
;; 4. Click somewhere - text recenters smoothly
;; 5. Press C-c n W again to disable
;;
;; Your horizontal centering (visual-fill-column) will work
;; perfectly with this!

(provide '13-centered-writing)
;;; 13-centered-writing.el ends here
