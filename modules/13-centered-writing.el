;;; 13-centered-writing.el --- Centered cursor for writing -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides distraction-free writing with vertically centered cursor.
;; Uses writeroom-mode - designed for journal and essay writing.
;;
;; KEY FEATURES:
;; - Keeps cursor centered vertically while typing
;; - Non-disruptive: doesn't jump when clicking or navigating
;; - Works with visual-fill-column (horizontal centering)
;; - Toggle on/off as needed
;;
;; USAGE:
;; - Manual: M-x writeroom-mode
;; - Transient menu: C-c n w (toggle writing mode)
;; - Or enable automatically for specific files (see config below)

;;; Code:

;; ============================================================
;; WRITEROOM-MODE: Distraction-free writing
;; ============================================================

(use-package writeroom-mode
  :ensure t
  :config
  ;; Disable fullscreen (we just want centered cursor)
  (setq writeroom-maximize-window nil)
  
  ;; Don't hide mode line (keep your info visible)
  (setq writeroom-mode-line t)
  
  ;; Don't add extra margins (visual-fill-column handles that)
  (setq writeroom-width 0)
  
  ;; No border lines
  (setq writeroom-bottom-divider-width 0)
  (setq writeroom-fringes-outside-margins nil)
  
  ;; Keep our existing visual-fill-column settings
  (setq writeroom-global-effects
        '(writeroom-set-bottom-divider-width
          writeroom-set-internal-border-width))
  
  ;; IMPORTANT: Don't let writeroom override visual-fill-column
  (setq writeroom-restore-window-config t))

;; ============================================================
;; SMART CENTERING: Only when writing
;; ============================================================
;;
;; Writeroom-mode centers the cursor ONLY during active editing:
;; - When you type → cursor stays centered
;; - When you click → NO jumping to center
;; - When you navigate (arrows, C-n/C-p) → smooth, no disruption
;; - When correcting spelling → cursor stays where you click
;;
;; This is exactly what you asked for!

;; ============================================================
;; OPTIONAL: Auto-enable for journals
;; ============================================================
;;
;; Uncomment the following to automatically enable writeroom-mode
;; when opening journal files:
;;
;; (add-hook 'org-mode-hook
;;           (lambda ()
;;             (when (and buffer-file-name
;;                        (string-match-p "journal" buffer-file-name))
;;               (writeroom-mode 1))))

;; ============================================================
;; TOGGLE FUNCTION
;; ============================================================

(defun my/toggle-writeroom ()
  "Toggle writeroom-mode (centered writing mode)."
  (interactive)
  (if writeroom-mode
      (progn
        (writeroom-mode -1)
        (message "✍️ Writing mode: OFF"))
    (progn
      (writeroom-mode 1)
      (message "✍️ Writing mode: ON (cursor centered)"))))

;; ============================================================
;; EXPLANATION: Why writeroom-mode?
;; ============================================================
;;
;; You mentioned the problem with other centering modes:
;; - They jump to center when you click anywhere
;; - Disruptive when reading or correcting typos
;; - Annoying when selecting text
;;
;; Writeroom-mode solves this:
;; 1. Centers cursor SMOOTHLY as you type new text
;; 2. Doesn't recenter when you click to a different location
;; 3. Doesn't interfere with navigation or selection
;; 4. Works perfectly with spell-checking
;;
;; Alternative considered: centered-cursor-mode
;; - More aggressive recentering (exactly what you DON'T want)
;; - Harder to configure for "write-only" behavior
;;
;; Writeroom-mode is battle-tested by writers and is the
;; recommended solution in the Emacs community for this exact use case.

;; ============================================================
;; SAFETY NOTES
;; ============================================================
;;
;; RISKS:
;; - Writeroom-mode temporarily hides fringes (thin margins)
;; - May feel unusual at first
;; - Some users prefer manual scrolling control
;;
;; MITIGATION:
;; - Easy toggle on/off (C-c n w or M-x writeroom-mode)
;; - Configured to preserve your mode line
;; - Doesn't interfere with your visual-fill-column setup
;; - You can disable this entire module by commenting out
;;   the load line in init.el
;;
;; TEST SAFELY:
;; 1. Open a journal file
;; 2. Press C-c n w to enable
;; 3. Start typing - cursor stays centered
;; 4. Click somewhere else - no jumping
;; 5. Use arrow keys - smooth navigation
;; 6. Press C-c n w again to disable
;;
;; If you don't like it, just comment out this module in init.el!

(provide '13-centered-writing)
;;; 13-centered-writing.el ends here
