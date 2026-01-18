;;; 03-spelling.el --- Spellchecking configuration -*- lexical-binding: t; -*-
;;; Commentary:
;; Spellchecking with flyspell for Polish and English
;; Fixed to stay enabled persistently in org-mode

;;; Code:

;; ============================================================
;; FLYSPELL: Spell checking
;; ============================================================

(use-package flyspell
  :ensure nil
  :hook ((org-mode . flyspell-mode)
         (text-mode . flyspell-mode))
  :config
  ;; Use aspell (better than ispell)
  (setq ispell-program-name "aspell")
  
  ;; Polish and English dictionaries
  (setq ispell-dictionary "pl_PL")
  
  ;; Personal dictionary for unknown words
  (setq ispell-personal-dictionary "~/.aspell.pl.pws")
  
  ;; Don't check code blocks in org-mode
  (add-to-list 'ispell-skip-region-alist '("^#\\+BEGIN_SRC" . "^#\\+END_SRC"))
  (add-to-list 'ispell-skip-region-alist '("^#\\+begin_src" . "^#\\+end_src")))

;; ============================================================
;; PERSISTENT FLYSPELL: Force it to stay on
;; ============================================================
;; This fixes the issue where flyspell randomly disables

(defun my/ensure-flyspell-enabled ()
  "Force flyspell to stay enabled in org/text modes."
  (when (and (derived-mode-p 'org-mode 'text-mode)
             (not flyspell-mode))
    (flyspell-mode 1)))

;; Check and re-enable after every command (lightweight check)
(add-hook 'post-command-hook 'my/ensure-flyspell-enabled)

;; Also ensure it's on after buffer switches
(add-hook 'buffer-list-update-hook 'my/ensure-flyspell-enabled)

;; ============================================================
;; LANGUAGE SWITCHING
;; ============================================================

(defun my/switch-dictionary-pl ()
  "Switch to Polish dictionary."
  (interactive)
  (ispell-change-dictionary "pl_PL")
  (flyspell-buffer)
  (message "Dictionary: Polski"))

(defun my/switch-dictionary-en ()
  "Switch to English dictionary."
  (interactive)
  (ispell-change-dictionary "en_US")
  (flyspell-buffer)
  (message "Dictionary: English"))

;; ============================================================
;; SPELL CORRECTION COMMANDS
;; ============================================================

;; Keybindings:
;; C-c F m - Switch to Polish (main language)
;; C-c F e - Switch to English
;; C-c F n - Next spelling error
;; C-c F c - Correct word at point
;; C-c F b - Check whole buffer
;; C-c F a - Add word to personal dictionary

(global-set-key (kbd "C-c F m") 'my/switch-dictionary-pl)
(global-set-key (kbd "C-c F e") 'my/switch-dictionary-en)
(global-set-key (kbd "C-c F n") 'flyspell-goto-next-error)
(global-set-key (kbd "C-c F c") 'flyspell-correct-word-before-point)
(global-set-key (kbd "C-c F b") 'flyspell-buffer)
(global-set-key (kbd "C-c F a") 'ispell-word)  ; Add to dictionary if correct

(provide '03-spelling)
;;; 03-spelling.el ends here
