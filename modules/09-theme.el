;;; 09-theme.el --- Theme configuration -*- lexical-binding: t; -*-
;;; Commentary:
;; Light theme setup with modus-operandi-tinted
;; Based on your preference from main branch

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
  
  ;; Headings - larger, colorful, variable pitch
  (setq modus-themes-headings
        '((1 . (rainbow variable-pitch 1.3))
          (2 . (rainbow variable-pitch 1.2))
          (3 . (rainbow variable-pitch 1.1))
          (t . (variable-pitch 1.0))))
  
  :config
  ;; Load light TINTED theme as default
  (load-theme 'modus-operandi-tinted t))

;; ============================================================
;; THEME SWITCHING
;; ============================================================
;; One entry point.  `load-theme' adds to `custom-enabled-themes' rather
;; than replacing it, so loading a second theme without disabling the
;; first leaves both active and the result depends on the order they
;; happen to be applied in.  Every switch below therefore disables what
;; is enabled first.

(defun my/load-theme (theme)
  "Enable THEME as the only active theme."
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t))

(defun my/load-theme-light ()
  "Load modus-operandi-tinted (light theme)."
  (interactive)
  (my/load-theme 'modus-operandi-tinted)
  (message "Light theme loaded"))

(defun my/load-theme-dark ()
  "Load modus-vivendi-tinted (dark theme)."
  (interactive)
  (my/load-theme 'modus-vivendi-tinted)
  (message "Dark theme loaded"))

(defun my/toggle-modus-theme ()
  "Toggle between modus-operandi-tinted (light) and modus-vivendi-tinted (dark).

KNOWN LIMITATION: custom.el sets a dozen Org faces to literal light
colours (`org-block' on #fef8e0, `org-link' on #555555, and so on).
`custom-set-faces' overrides theme faces and survives `load-theme', so
the dark theme currently produces light blocks on a dark background.
Fixing that means either dropping those face definitions in favour of
`modus-themes-common-palette-overrides', or accepting that this
configuration is light-only and removing the dark commands.  Neither is
decided, so the command stays and this note stays with it."
  (interactive)
  (if (member 'modus-vivendi-tinted custom-enabled-themes)
      (my/load-theme-light)
    (my/load-theme-dark)))

;; Optional: Bind to a key (uncomment if you want)
;; (global-set-key (kbd "C-c T") 'my/toggle-modus-theme)

;; ============================================================
;; BUILT-IN THEME ALTERNATIVES (no installation needed)
;; ============================================================
;;
;; If you want to try other themes, use: M-x load-theme RET
;;
;; LIGHT THEMES:
;; - modus-operandi         → High contrast, clean
;; - modus-operandi-tinted  → Softer, warmer (CURRENT)
;; - leuven                 → Org-mode optimized
;; - tango                  → Colorful, vibrant
;; - adwaita                → GNOME-style
;;
;; DARK THEMES:
;; - modus-vivendi          → High contrast
;; - modus-vivendi-tinted   → Softer, warmer
;; - tango-dark             → Colorful dark
;; - wombat                 → Soft, easy on eyes
;; - deeper-blue            → Blue-themed

(provide '09-theme)
;;; 09-theme.el ends here
