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
;;
;; NOTE: Face colours/sizes (org-level-*, org-link, org-scheduled,
;;       org-deadline-announce, org-special-keyword) are defined
;;       exclusively in custom.el (the Customize authoritative source).
;;       This file only handles *behaviour* (inheritance, monospace
;;       enforcement) via set-face-attribute.  Do not add custom-set-faces
;;       calls here — they will silently conflict with custom.el after
;;       every load-theme call.

;;; Code:

;; ============================================================
;; HIDE EMPHASIS MARKERS (stars, slashes, underscores)
;; ============================================================

;; Hide markers for *bold*, /italic/, _underline_, ~code~, etc.
(setq org-hide-emphasis-markers t)

;; ============================================================
;; MONOSPACE FOR CODE/TABLES (even when variable-pitch enabled)
;; ============================================================

;; These faces stay monospace even in journal notes with handwriting font.
;; Only :inherit is set here; all colour/size attributes are left as
;; 'unspecified so they inherit from the face hierarchy (or custom.el).
(with-eval-after-load 'org
  (set-face-attribute 'org-table          nil :inherit 'fixed-pitch :height 'unspecified :foreground 'unspecified)
  (set-face-attribute 'org-code           nil :inherit 'fixed-pitch :height 'unspecified :foreground 'unspecified)
  (set-face-attribute 'org-block          nil :inherit 'fixed-pitch :height 'unspecified :foreground 'unspecified)
  (set-face-attribute 'org-verbatim       nil :inherit 'fixed-pitch :height 'unspecified :foreground 'unspecified)
  (set-face-attribute 'org-special-keyword nil :inherit 'fixed-pitch :height 'unspecified :foreground 'unspecified)
  (set-face-attribute 'org-meta-line      nil :inherit 'fixed-pitch :height 'unspecified :foreground 'unspecified)
  (set-face-attribute 'org-checkbox       nil :inherit 'fixed-pitch :height 'unspecified :foreground 'unspecified))

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
;; TOGGLE EMPHASIS MARKERS (C-c n E)
;; ============================================================

(defun my/toggle-emphasis-markers ()
  "Toggle visibility of Org-mode emphasis markers (*bold*, /italic/, etc.).

When markers are HIDDEN (default): text looks pretty, markers invisible.
When markers are VISIBLE: raw syntax shown, useful for debugging extra
asterisks or mismatched markers.

Note: this changes org-hide-emphasis-markers globally (all org buffers).
Toggle: C-c n E  (in notes transient menu)"
  (interactive)
  (if org-hide-emphasis-markers
      (progn
        (setq org-hide-emphasis-markers nil)
        (font-lock-fontify-buffer)
        (message "👁 Markers VISIBLE - raw syntax: *bold* /italic/ _under_"))
    (progn
      (setq org-hide-emphasis-markers t)
      (font-lock-fontify-buffer)
      (message "✨ Markers HIDDEN - pretty rendering active"))))

;; ============================================================
;; HOW IT LOOKS
;; ============================================================
;;
;; Before: *bold* /italic/ _underline_
;; After:  bold   italic   underline   (markers hidden!)
;;
;; Heading sizes/colours: defined in custom.el (org-level-1..8)
;;
;; Font control (variable-pitch) handled by 03b-fonts.el:
;; - Journal notes: Playpen Sans Hebrew (handwriting)
;; - Other notes: JetBrains Mono (monospace)
;; - Code/tables: Always monospace (enforced above via :inherit fixed-pitch)
;; Pretty bullets: ● ○ ● ○
;;
;; INDENTATION:
;; - Default: OFF (better for older notes)
;; - Hook explicitly disables it on file open
;; - Toggle: C-c n I (available in transient menu)
;; - Use when: You want visual hierarchy in new notes
;; - Emacs remembers your choice per-file automatically
;;
;; EMPHASIS MARKERS:
;; - Default: HIDDEN (org-hide-emphasis-markers = t)
;; - Toggle: C-c n E (available in transient menu)
;; - Use when: Debugging extra asterisks or markup errors

(provide '11-org-appearance)
;;; 11-org-appearance.el ends here
