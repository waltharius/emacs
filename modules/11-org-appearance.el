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
;; INLINE IMAGES: scale once instead of on every redisplay
;; ============================================================
;; With `org-image-actual-width' unset, Org displays images at their
;; intrinsic size.  A phone photo is 3,000-4,000 px wide, so every screen
;; line of that image is computed against a bitmap far larger than the
;; window, and scrolling past it recomputes window metrics for the whole
;; thing.  This is the usual cause of "notes with photos scroll slowly";
;; Obsidian sidesteps it because a browser engine rasterises and caches
;; at the displayed size.
;;
;; A fixed width makes Emacs produce one scaled image and reuse it from
;; the image cache.  Per-image overrides still work:
;;   #+ATTR_ORG: :width 900
;;
;; TUNING.  This is a pixel count, so what it looks like depends on the
;; display and on its scaling factor; 800 read as too small and is now
;; 1100.  Raise it further if images still look cramped, but not much
;; beyond 1600: `my/org-image-max-pixels' in 31-org-images.el caps
;; stored attachments at that, and asking for more than a file contains
;; upscales a bitmap, which only adds blur.  Raise both together if
;; genuinely larger images are wanted.
;;
;; A float in the list -- '(0.9) -- would instead track the window
;; width.  It is not used here: the scaled bitmap then has to be rebuilt
;; whenever the window is resized, which happens on every writeroom
;; toggle and every window split, and Org measures against the window
;; rather than the text column, so with the centred layout of
;; 10-visual-fill.el the result can be wider than the text it sits in.

(setq org-image-actual-width '(1100))

;; Keep scaled images in the cache long enough to survive scrolling back
;; and forth through a note (default is 300 seconds).
(setq image-cache-eviction-delay 900)

;; ============================================================
;; ORG FACES ARE NOT SET HERE
;; ============================================================
;; This module used to call `set-face-attribute' on org-table, org-code,
;; org-block, org-verbatim and others, passing `:foreground 'unspecified'
;; with a comment claiming that this left the colour to custom.el.  It
;; does the opposite: `unspecified' ERASES the attribute, so every colour
;; set through `M-x customize-face' was wiped the moment Org loaded and
;; had to be set again in every session.
;;
;; Worse, the erasure was invisible in new frames.  `set-face-attribute'
;; changes the realised attributes of existing frames; a new frame
;; recomputes its faces from the theme and `custom-set-faces' specs, in
;; which the erasure does not appear.  The same face therefore looked
;; one way in the main frame and another in a frame made by
;; `my/detach-buffer-to-frame' -- which is what "every file looks
;; different" turned out to be.
;;
;; Org face appearance is now owned entirely by custom.el, which is what
;; 01-ui.el already said was the rule.  `:inherit fixed-pitch' -- the one
;; thing these calls were really for, keeping code monospace inside
;; journal buffers that use a handwriting font -- is expressed there
;; too, so nothing is lost.

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
