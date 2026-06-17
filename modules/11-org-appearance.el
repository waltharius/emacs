;;; 11-org-appearance.el --- Org-mode visual enhancements -*- lexical-binding: t; -*-
;;; Commentary:
;; Makes org-mode more visually pleasant:
;; - Hides emphasis markers (*bold*, /italic/, _underline_)
;; - Beautiful heading sizes and colors
;; - Pretty bullet points
;; - Extra line spacing for breathing room
;; - INDENT OFF BY DEFAULT - toggle with: C-c n I
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
   '(org-level-8 ((t (:height 1.0))))

   '(org-link ((t (:foreground "#555555" :underline nil :weight normal))))

      ;; SCHEDULED line: small, grey, unobtrusive
   '(org-scheduled ((t (:height 0.8 :foreground "#777777"))))
   ;; DEADLINE line: small, slightly warm red so it's visible but not loud
   '(org-deadline-announce ((t (:height 0.8 :foreground "#aa5555"))))
   ;; The actual timestamp text inside <...>
   '(org-date ((t (:height 0.8 :foreground "#888888" :underline nil))))
   ;; The keyword words "SCHEDULED:" and "DEADLINE:" themselves
   '(org-special-keyword ((t (:height 0.75 :foreground "#666666" :inherit fixed-pitch))))))

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
  ;;(set-face-attribute 'org-link nil :inherit 'fixed-pitch))

;; ============================================================
;; VISUAL IMPROVEMENTS
;; ============================================================

;; INDENT OFF BY DEFAULT (older notes work better without it)
;; This setting alone isn't always enough, so we also use a hook below
(setq org-startup-indented nil)

;; FORCE indent OFF when opening org files
;; Some packages re-enable it, so we explicitly disable it
(add-hook 'org-mode-hook
          (lambda ()
            (org-indent-mode -1))  ; Force OFF
          90)  ; Run late (after other hooks)

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
;; TOGGLE INDENTATION (C-c n I)
;; ============================================================

(defun my/toggle-org-indent ()
  "Toggle org-indent-mode (visual indentation based on heading level).
   
   When ON:  Text indents under headings (nice hierarchy)
   When OFF: All text starts at left margin (better for deep nesting)
   
   Use this when you want visual hierarchy or when working with new notes.
   Older notes work better with indent OFF (the default)."
  (interactive)
  (if org-indent-mode
      (progn
        (org-indent-mode -1)
        (message "❌ Indentation OFF - All text at left margin"))
    (progn
      (org-indent-mode 1)
      (message "✅ Indentation ON - Visual hierarchy enabled"))))

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
;; INDENTATION:
;; - Default: OFF (better for older notes)
;; - Hook explicitly disables it on file open
;; - Toggle: C-c n I (available in transient menu)
;; - Use when: You want visual hierarchy in new notes
;; - Emacs remembers your choice per-file automatically

(provide '11-org-appearance)
;;; 11-org-appearance.el ends here
