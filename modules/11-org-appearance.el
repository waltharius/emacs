;;; 11-org-appearance.el --- Org-mode visual enhancements -*- lexical-binding: t; -*-
;;; Commentary:
;; Makes org-mode more visually pleasant:
;; - Hides emphasis markers (*bold*, /italic/, _underline_)
;; - Beautiful heading sizes and colors
;; - Pretty bullet points
;; - Extra line spacing for breathing room
;; - TOGGLE indentation with: M-x my/toggle-org-indent
;;
;; NOTE: Font settings (variable-pitch) moved to 03b-fonts.el
;;       to enable selective font control (journals vs other notes)

;;; Code:

;; ============================================================
;; HIDE EMPHASIS MARKERS (stars, slashes, underscores)
;; ============================================================

;; Hide markers for *bold*, /italic/, _underline_, ~code~, etc.
(setq org-hide-emphasis-markers t)

;; ============================================================
;; BEAUTIFUL HEADINGS (Larger, Colorful)
;; ============================================================

(with-eval-after-load 'org
  (custom-set-faces
   ;; Level 1 - Largest, most prominent
   '(org-level-1 ((t (:height 1.3 :weight bold))))
   
   ;; Level 2 - Medium large
   '(org-level-2 ((t (:height 1.2 :weight bold))))
   
   ;; Level 3 - Slightly larger
   '(org-level-3 ((t (:height 1.1 :weight bold))))
   
   ;; Level 4+ - Normal size
   '(org-level-4 ((t (:height 1.0 :weight bold))))
   '(org-level-5 ((t (:height 1.0))))
   '(org-level-6 ((t (:height 1.0))))
   '(org-level-7 ((t (:height 1.0))))
   '(org-level-8 ((t (:height 1.0))))))

;; ============================================================
;; MONOSPACE FOR CODE/TABLES (even when variable-pitch enabled)
;; ============================================================

;; These faces stay monospace even in journal notes with handwriting font
(with-eval-after-load 'org
  (set-face-attribute 'org-table nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-code nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-block nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-verbatim nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-special-keyword nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-meta-line nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-checkbox nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-link nil :inherit 'fixed-pitch))

;; ============================================================
;; VISUAL IMPROVEMENTS
;; ============================================================

;; Indent content under headings (like outlining)
;; This is ON by default, but can be toggled with my/toggle-org-indent
(setq org-startup-indented t)

;; Show inline images by default
(setq org-startup-with-inline-images t)

;; Prettier bullet points (● instead of -)
(use-package org-bullets
  :ensure t
  :hook (org-mode . org-bullets-mode)
  :config
  (setq org-bullets-bullet-list '("●" "○" "●" "○" "●" "○" "●")))

;; ============================================================
;; LINE SPACING (More breathing room)
;; ============================================================

(add-hook 'org-mode-hook
          (lambda ()
            (setq line-spacing 0.2)))  ; 20% extra space between lines

;; ============================================================
;; TOGGLE INDENTATION
;; ============================================================

(defun my/toggle-org-indent ()
  "Toggle org-indent-mode (visual indentation based on heading level).
   
   When ON:  Text indents under headings (nice hierarchy)
   When OFF: All text starts at left margin (better for deep nesting)
   
   Use this when you have many nested headings and text becomes too narrow."
  (interactive)
  (if org-indent-mode
      (progn
        (org-indent-mode -1)
        (message "✗ Indentation OFF - All text at left margin"))
    (progn
      (org-indent-mode 1)
      (message "✓ Indentation ON - Visual hierarchy enabled"))))

;; ============================================================
;; HOW IT LOOKS
;; ============================================================
;;
;; Before: *bold* /italic/ _underline_
;; After:  bold   italic   underline   (markers hidden!)
;;
;; Headings are bigger and bolder:
;; # Heading 1  <- 1.3x size
;; ## Heading 2 <- 1.2x size
;; ### Heading 3 <- 1.1x size
;;
;; Font control (variable-pitch) handled by 03b-fonts.el:
;; - Journal notes: Playpen Sans Hebrew (handwriting)
;; - Other notes: JetBrains Mono (monospace)
;; - Code/tables: Always monospace
;; Pretty bullets: ● ○ ● ○
;;
;; INDENTATION TOGGLE:
;; M-x my/toggle-org-indent
;; or add keybinding like: (global-set-key (kbd "C-c i") 'my/toggle-org-indent)

(provide '11-org-appearance)
;;; 11-org-appearance.el ends here
