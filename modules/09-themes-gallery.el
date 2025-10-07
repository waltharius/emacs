;;; 09-themes-gallery.el --- Theme switcher and gallery -*- lexical-binding: t; -*-

;;; Commentary:
;; Quick theme switching and popular themes showcase

;;; Code:

;; ============================================================
;; THEME GALLERY (Popular themes)
;; ============================================================

;; BUILT-IN THEMES (already available!):
;;
;; DARK THEMES:
;; - modus-vivendi     → High contrast, elegant (RECOMMENDED!)
;; - tango-dark        → Colorful, vibrant
;; - wombat            → Soft, easy on eyes
;; - deeper-blue       → Blue-themed
;; - manoj-dark        → Minimalist dark
;;
;; LIGHT THEMES:
;; - modus-operandi    → High contrast, elegant (RECOMMENDED!)
;; - leuven            → Clean, org-mode optimized
;; - tango             → Colorful, vibrant
;; - adwaita           → GNOME-style
;; - whiteboard        → Pure white

;; ============================================================
;; QUICK THEME SWITCHER
;; ============================================================

(defun my/load-theme-modus-vivendi ()
  "Load modus-vivendi (dark, high contrast)."
  (interactive)
  (load-theme 'modus-vivendi t))

(defun my/load-theme-modus-operandi ()
  "Load modus-operandi (light, high contrast)."
  (interactive)
  (load-theme 'modus-operandi t))

(defun my/load-theme-tango-dark ()
  "Load tango-dark (colorful dark)."
  (interactive)
  (load-theme 'tango-dark t))

(defun my/load-theme-leuven ()
  "Load leuven (clean light)."
  (interactive)
  (load-theme 'leuven t))

(defun my/load-theme-wombat ()
  "Load wombat (soft dark)."
  (interactive)
  (load-theme 'wombat t))

;; ============================================================
;; THEME TOGGLE (Dark ↔ Light)
;; ============================================================

(defun my/toggle-theme ()
  "Toggle between dark and light theme."
  (interactive)
  (if (member 'modus-vivendi custom-enabled-themes)
      (progn
        (disable-theme 'modus-vivendi)
        (load-theme 'modus-operandi t)
        (message "Switched to LIGHT theme (modus-operandi)"))
    (progn
      (disable-theme 'modus-operandi)
      (load-theme 'modus-vivendi t)
      (message "Switched to DARK theme (modus-vivendi)"))))

;; Keybinding: C-c  = toggle theme
(global-set-key (kbd "C-c T") 'my/toggle-theme)

;; ============================================================
;; DEFAULT THEME (Set your favorite!)
;; ============================================================

;; Uncomment ONE of these:

;;   (load-theme 'modus-vivendi t)    ; Dark (RECOMMENDED!)
;; (load-theme 'modus-operandi t)   ; Light (RECOMMENDED!)
;; (load-theme 'tango-dark t)       ; Colorful dark
;; (load-theme 'leuven t)           ; Clean light
;; (load-theme 'wombat t)           ; Soft dark

;; ============================================================
;; MANUAL THEME LOADING
;; ============================================================

;; To try themes manually:
;; M-x load-theme RET modus-vivendi RET
;; M-x load-theme RET leuven RET
;; etc.

;; To disable current theme:
;; M-x disable-theme RET

;; ============================================================
;; THEME CUSTOMIZATION (Optional)
;; ============================================================

;; Customize Modus themes (if using them)
(with-eval-after-load 'modus-themes
  ;; Modus theme options
  (setq modus-themes-bold-constructs t)      ; Use bold for keywords
  (setq modus-themes-italic-constructs t)    ; Use italic for comments
  (setq modus-themes-org-blocks 'gray-background)  ; Gray background for code blocks
  (setq modus-themes-headings
        '((1 . (1.3))      ; Level 1 headers = 1.3x size
          (2 . (1.2))      ; Level 2 = 1.2x
          (3 . (1.1))      ; Level 3 = 1.1x
          (t . (1.0))))    ; Rest = normal
  )

;; ============================================================
;; INSTALL EXTERNAL THEMES (Optional - requires package installation)
;; ============================================================

;; Popular external themes you can install:
;;
;; 1. Doom Themes (popular, beautiful!)
;;    (use-package doom-themes
;;      :ensure t
;;      :config
;;      (load-theme 'doom-one t))
;;
;; 2. Dracula (purple, vibrant)
;;    (use-package dracula-theme
;;      :ensure t
;;      :config
;;      (load-theme 'dracula t))
;;
;; 3. Solarized (classic, timeless)
;;    (use-package solarized-theme
;;      :ensure t
;;      :config
;;      (load-theme 'solarized-dark t))
;;
;; 4. Zenburn (easy on eyes)
;;    (use-package zenburn-theme
;;      :ensure t
;;      :config
;;      (load-theme 'zenburn t))
;;
;; 5. Gruvbox (retro, warm)
    (use-package gruvbox-theme
    :ensure t
    :config
    ;; Customize Gruvbox before loading
    (setq gruvbox-bold t)              ; Use bold
    (setq gruvbox-italic t)            ; Use italic
    (setq gruvbox-underline t)         ; Use underline
    (setq gruvbox-undercurl t)         ; Use undercurl
  
    ;; Contrast options:
    ;; - 'soft   → Soft contrast (easy on eyes!)
    ;; - 'medium → Medium contrast (default)
    ;; - 'hard   → Hard contrast (high contrast!)
    (setq gruvbox-contrast 'medium)    ; Try: soft, medium, hard
    ;; Load theme
    (load-theme 'gruvbox-light-medium t))
(with-eval-after-load 'gruvbox-theme
  ;; Custom faces (after theme loads)
  (set-face-foreground 'org-level-1 "#fb4934")  ; Red headers
  (set-face-foreground 'org-level-2 "#b8bb26")  ; Green
  (set-face-foreground 'org-level-3 "#fabd2f")  ; Yellow
  (set-face-attribute 'org-level-1 nil :height 1.0)) 
;; ============================================================
;; END OF THEMES GALLERY
;; ============================================================

(provide '09-themes-gallery)
;;; 09-themes-gallery.el ends here
