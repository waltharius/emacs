;;; 09-theme.el --- Theme configuration -*- lexical-binding: t; -*-
;;; Commentary:
;; One theme: modus-operandi-tinted, light.
;;
;; This configuration is deliberately light-only.  The dark commands that
;; used to live here were unusable in practice: custom.el pins a dozen Org
;; faces to literal light colours (org-block on #fef8e0, org-link on
;; #555555, and so on), and `custom-set-faces' outranks a theme, so
;; loading modus-vivendi-tinted produced light blocks on a dark
;; background.  Rather than keep a broken switch and a note explaining
;; that it is broken, the switch is gone.
;;
;; Restoring dark mode later is a real piece of work, not a toggle: the
;; colours in custom.el would have to move into
;; `modus-themes-common-palette-overrides', which expresses them as
;; palette names that each theme resolves for itself.

;;; Code:

;; ============================================================
;; MODUS THEMES: High-quality, accessible themes
;; ============================================================

(use-package modus-themes
  :ensure t
  :init
  ;; Configure BEFORE loading theme
  (setq modus-themes-italic-constructs t)     ; Use italics
  (setq modus-themes-bold-constructs t)       ; Use bold
  (setq modus-themes-mixed-fonts t)           ; Mixed fonts (important!)
  (setq modus-themes-variable-pitch-ui nil)   ; Don't use variable pitch in UI
  (setq modus-themes-org-blocks 'gray-background)  ; Gray background for code blocks

  ;; Headings - larger, colorful, variable pitch.
  ;; NOTE: custom.el also sets org-level-1..8 heights, and being a user
  ;; customisation it wins.  These settings still decide colour and
  ;; variable-pitch; the heights here are effectively documentation of
  ;; intent.  Change sizes in custom.el, not here.
  (setq modus-themes-headings
        '((1 . (rainbow variable-pitch 1.3))
          (2 . (rainbow variable-pitch 1.2))
          (3 . (rainbow variable-pitch 1.1))
          (t . (variable-pitch 1.0))))

  :config
  (load-theme 'modus-operandi-tinted t))

(provide '09-theme)
;;; 09-theme.el ends here
