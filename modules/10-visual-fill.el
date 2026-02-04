;;; 10-visual-fill.el --- Centered text layout -*- lexical-binding: t; -*-
;;; Commentary:
;; Creates beautiful centered text layout with equal margins on both sides
;; Like reading a book! Text limited to 80 characters width.
;;
;; This gives you the centered look from your main branch.

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
  (setq-default visual-fill-column-fringes-outside-margins nil))

;; ============================================================
;; EXPLANATION
;; ============================================================
;;
;; This creates the "book-like" layout you see in your main branch:
;;
;; Before (full width):
;; |Text starts here and goes all the way to the edge...             |
;;
;; After (centered):
;; |        Text is centered with nice margins on both               |
;; |        sides, making it easier to read!                         |
;;
;; Benefits:
;; - Easier to read (optimal line length)
;; - Looks more professional
;; - Less eye movement
;; - Perfect for writing

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
