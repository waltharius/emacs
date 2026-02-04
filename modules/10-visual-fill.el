;;; 10-visual-fill.el --- Centered text layout -*- lexical-binding: t; -*-
;;; Commentary:
;; Creates beautiful centered text layout with equal margins on both sides
;; Like reading a book! Text limited to 80 characters width.
;;
;; NO BOUNDARY LINES - just clean margins!

;;; Code:

;; ============================================================
;; VISUAL-FILL-COLUMN: Center text with margins
;; ============================================================

(use-package visual-fill-column
  :ensure t
  :hook ((org-mode . visual-fill-column-mode)
         (text-mode . visual-fill-column-mode))
  :config
  ;; Text width (80 characters)
  (setq-default visual-fill-column-width 80)
  
  ;; Center the text (equal margins on both sides!)
  (setq-default visual-fill-column-center-text t)
  
  ;; Don't show fringes (the gray area on sides)
  (setq-default visual-fill-column-fringes-outside-margins nil)
  
  ;; DISABLE fill-column-indicator (no boundary lines!)
  (add-hook 'visual-fill-column-mode-hook
            (lambda ()
              (display-fill-column-indicator-mode -1))))

;; ============================================================
;; GLOBALLY DISABLE FILL-COLUMN-INDICATOR
;; ============================================================
;; Turn off the thick colored lines that show column boundaries
(global-display-fill-column-indicator-mode -1)

;; ============================================================
;; EXPLANATION
;; ============================================================
;;
;; This creates the "book-like" layout WITHOUT boundary lines:
;;
;; Before (full width with ugly lines):
;; |│Text starts here and goes all the way...                      │|
;;
;; After (centered, clean margins):
;; |        Text is centered with invisible margins                  |
;; |        Clean and professional look!                             |
;;
;; Benefits:
;; - Easier to read (optimal line length)
;; - Looks more professional
;; - Less visual clutter
;; - Perfect for writing
;;
;; What changed:
;; - Removed display-fill-column-indicator-mode
;; - Kept centering and margins
;; - Result: Clean, centered text without boundary lines

;; ============================================================
;; TOGGLE FUNCTION (optional)
;; ============================================================

(defun my/toggle-visual-fill-column ()
  "Toggle centered text layout."
  (interactive)
  (if visual-fill-column-mode
      (progn
        (visual-fill-column-mode -1)
        (message "Centered layout: OFF"))
    (progn
      (visual-fill-column-mode 1)
      (message "Centered layout: ON"))))
  
;; Optional: Bind to a key (uncomment if you want)
;; (global-set-key (kbd "C-c v") 'my/toggle-visual-fill-column)

(provide '10-visual-fill)
;;; 10-visual-fill.el ends here
