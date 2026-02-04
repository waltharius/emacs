;;; 11-org-appearance.el --- Org-mode visual enhancements -*- lexical-binding: t; -*-
;;; Commentary:
;; Makes org-mode more visually pleasant:
;; - Hides emphasis markers (*bold*, /italic/, _underline_)
;; - Beautiful heading sizes and colors
;; - Mixed fonts (variable pitch for text, monospace for code)
;; - First-line indent for paragraphs (like in books!)

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
;; MIXED FONTS (Variable pitch for text, monospace for code)
;; ============================================================

;; Enable variable-pitch-mode in org-mode (like a book!)
(add-hook 'org-mode-hook 'variable-pitch-mode)

;; Keep monospace for code, tables, etc.
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
;; FIRST-LINE INDENT (Like in books!)
;; ============================================================
;;
;; This creates paragraph indentation where:
;; - First line of each paragraph is indented
;; - Wrapped lines start at left margin (no indent)
;;
;; Example:
;;     This is the first line with indent.
;; But when text wraps, it starts at the left
;; margin.
;;     Next paragraph also starts with indent.
;;

(defun my/org-indent-first-line ()
  "Add first-line indent to paragraphs in org-mode."
  ;; Set indent to 4 spaces (adjust as needed)
  (setq-local paragraph-start "\\*\\|[ \t]*$")
  (setq-local paragraph-separate "[ \t]*$")
  
  ;; Use adaptive-fill for proper indentation
  (setq-local adaptive-fill-mode t)
  (setq-local adaptive-fill-first-line-regexp "[ \t]*")
  
  ;; Visual indent for first line
  (setq-local left-margin-width 4))

(add-hook 'org-mode-hook 'my/org-indent-first-line)

;; ============================================================
;; ADDITIONAL VISUAL IMPROVEMENTS
;; ============================================================

;; Indent content under headings (like outlining)
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
;; EMPHASIS FACES (Make them more visible)
;; ============================================================

(with-eval-after-load 'org
  ;; Bold - more prominent
  (set-face-attribute 'org-bold nil
                      :weight 'bold
                      :foreground nil)
  
  ;; Italic - clearly different
  (set-face-attribute 'org-italic nil
                      :slant 'italic
                      :foreground nil)
  
  ;; Underline - visible
  (set-face-attribute 'org-underline nil
                      :underline t)
  
  ;; Code - monospace with background
  (set-face-attribute 'org-code nil
                      :inherit 'fixed-pitch
                      :background "#f0f0f0"
                      :foreground nil)
  
  ;; Verbatim - like code but different color
  (set-face-attribute 'org-verbatim nil
                      :inherit 'fixed-pitch
                      :background "#fff8dc"
                      :foreground nil))

;; ============================================================
;; LINE SPACING (More breathing room)
;; ============================================================

(add-hook 'org-mode-hook
          (lambda ()
            (setq line-spacing 0.2)))  ; 20% extra space between lines

(provide '11-org-appearance)
;;; 11-org-appearance.el ends here
