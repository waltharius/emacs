;;; 03-spelling.el --- Spellchecking configuration -*- lexical-binding: t; -*-
;;; Commentary:
;; Spellchecking for Polish and English:
;; - Flyspell for real-time checking
;; - Aspell backend
;; - PERSISTENT mode (doesn't disable randomly)
;; - FIXED: No quote expansion in org-mode

;;; Code:

;; ============================================================
;; ASPELL CONFIGURATION
;; ============================================================

(setq ispell-program-name "aspell")
(setq ispell-list-command "--list")

;; Use Polish and English dictionaries
(setq ispell-dictionary "pl")

;; Personal dictionary location
(setq ispell-personal-dictionary "~/.aspell.pl.pws")

;; Better suggestions
(setq ispell-extra-args '("--sug-mode=ultra" "--lang=pl"))

;; ============================================================
;; FLYSPELL MODE (Real-time spellchecking)
;; ============================================================

(use-package flyspell
  :ensure nil
  :hook ((org-mode . flyspell-mode)
         (text-mode . flyspell-mode))
  :config
  ;; Don't print messages (reduces noise)
  (setq flyspell-issue-message-flag nil)
  
  ;; Use popup for corrections (faster than minibuffer)
  (setq flyspell-use-meta-tab nil))

;; ============================================================
;; FIX: PREVENT RANDOM DISABLING
;; ============================================================

;; Force flyspell to stay enabled in org-mode
(defun my/ensure-flyspell-enabled ()
  "Ensure flyspell-mode is enabled in org/text buffers."
  (when (and (derived-mode-p 'org-mode 'text-mode)
             (not flyspell-mode))
    (flyspell-mode 1)))

;; Check every time we switch buffers or windows
(add-hook 'buffer-list-update-hook 'my/ensure-flyspell-enabled)
(add-hook 'window-configuration-change-hook 'my/ensure-flyspell-enabled)

;; Re-enable after save
(add-hook 'after-save-hook 'my/ensure-flyspell-enabled)

;; ============================================================
;; FIX: DISABLE QUOTE EXPANSION IN ORG-MODE
;; ============================================================

;; IMPORTANT: Disable electric-pair for quotes in org-mode
;; This prevents '' from becoming "”" automatically

(add-hook 'org-mode-hook
          (lambda ()
            ;; Remove quote pairs from electric-pair in org-mode
            (setq-local electric-pair-inhibit-predicate
                        (lambda (c)
                          (if (or (char-equal c ?\') (char-equal c ?\"))
                              t  ; Disable for quotes
                            (electric-pair-default-inhibit c))))))

;; Also disable org-mode's smart quotes during export
(setq org-export-with-smart-quotes nil)

;; ============================================================
;; LANGUAGE SWITCHING
;; ============================================================

(defun my/switch-dictionary-to-polish ()
  "Switch spellcheck to Polish."
  (interactive)
  (ispell-change-dictionary "pl")
  (flyspell-buffer)
  (message "🇵🇱 Dictionary: Polish"))

(defun my/switch-dictionary-to-english ()
  "Switch spellcheck to English."
  (interactive)
  (ispell-change-dictionary "en_US")
  (flyspell-buffer)
  (message "🇬🇧 Dictionary: English"))

;; ============================================================
;; CORRECTION KEYBINDINGS
;; ============================================================

;; These will be bound in 08-keybindings.el:
;; C-c F m  - Switch to Polish
;; C-c F e  - Switch to English  
;; C-c F c  - Correct word at point
;; C-c F b  - Check buffer
;; C-c F r  - Check region
;; C-c F n  - Next error
;; C-c F p  - Previous error

(provide '03-spelling)
;;; 03-spelling.el ends here
