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
;; THEME SWITCHER: Toggle light/dark
;; ============================================================

(defun my/toggle-modus-theme ()
  "Toggle between modus-operandi-tinted (light) and modus-vivendi-tinted (dark)."
  (interactive)
  (if (member 'modus-vivendi-tinted custom-enabled-themes)
      (progn
        (disable-theme 'modus-vivendi-tinted)
        (load-theme 'modus-operandi-tinted t)
        (message "Light theme (tinted)"))
    (progn
      (disable-theme 'modus-operandi-tinted)
      (load-theme 'modus-vivendi-tinted t)
      (message "Dark theme (tinted)"))))

;; Optional: Bind to a key (uncomment if you want)
;; (global-set-key (kbd "C-c T") 'my/toggle-modus-theme)

;; ============================================================
;; QUICK THEME LOADERS
;; ============================================================

(defun my/load-theme-light ()
  "Load modus-operandi-tinted (light theme)."
  (interactive)
  (load-theme 'modus-operandi-tinted t)
  (message "Light theme loaded"))

(defun my/load-theme-dark ()
  "Load modus-vivendi-tinted (dark theme)."
  (interactive)
  (load-theme 'modus-vivendi-tinted t)
  (message "Dark theme loaded"))

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
