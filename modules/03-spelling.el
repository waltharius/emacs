;;; 03-spelling.el --- Smart spellchecking configuration -*- lexical-binding: t; -*-
;;; Commentary:
;; Intelligent spellchecking with automatic program detection
;; Prefers hunspell (best multi-language support)
;; Falls back to aspell or ispell with warnings
;; 
;; Features:
;; - Simultaneous Polish + English checking (no manual switching!)
;; - Personal dictionary support
;; - Safe: only enables if spellchecker is available

;;; Code:

;; ============================================================
;; DETECT AVAILABLE SPELLCHECKER
;; ============================================================

(defvar my/spellcheck-program nil
  "Detected spellcheck program (hunspell, aspell, or ispell).")

(defvar my/spellcheck-available nil
  "Whether any spellchecker is available.")

;; Check what's available (in order of preference)
(cond
 ((executable-find "hunspell")
  (setq my/spellcheck-program "hunspell")
  (setq my/spellcheck-available t)
  (message "✓ Spellcheck: Using hunspell (recommended for PL+EN)"))
 
 ((executable-find "aspell")
  (setq my/spellcheck-program "aspell")
  (setq my/spellcheck-available t)
  (message "⚠ Spellcheck: Using aspell (multi-language support weaker than hunspell)"))
 
 ((executable-find "ispell")
  (setq my/spellcheck-program "ispell")
  (setq my/spellcheck-available t)
  (message "⚠ Spellcheck: Using ispell (multi-language support weaker than hunspell)"))
 
 (t
  (setq my/spellcheck-available nil)
  (message "✗ Spellcheck: No program found! Install hunspell (recommended) or aspell.")))

;; ============================================================
;; FLYSPELL: Only configure if spellchecker available
;; ============================================================

(when my/spellcheck-available
  (use-package flyspell
    :ensure nil
    :hook ((org-mode . flyspell-mode)
           (text-mode . flyspell-mode))
    :config
    ;; Set the program
    (setq ispell-program-name my/spellcheck-program)
    
    ;; ============================================================
    ;; HUNSPELL: Simultaneous Polish + English
    ;; ============================================================
    (when (string= my/spellcheck-program "hunspell")
      ;; CRITICAL FIX: Auto-detect dictionary paths
      (setq ispell-hunspell-dict-paths-alist nil)  ; Let hunspell auto-detect
      
      ;; Use BOTH dictionaries at once (no switching!)
      (setq ispell-dictionary "pl_PL,en_US")
      
      ;; Tell hunspell we're using multiple dictionaries
      (setq ispell-local-dictionary-alist
            '(("pl_PL,en_US"
               "[[:alpha:]]"
               "[^[:alpha:]]"
               "[']" t
               ("-d" "pl_PL,en_US") nil utf-8)))
      
      ;; Personal dictionary
      (setq ispell-personal-dictionary "~/.hunspell_personal")
      
      (message "✓ Hunspell: Checking Polish + English simultaneously"))
    
    ;; ============================================================
    ;; ASPELL: Best approximation (less ideal)
    ;; ============================================================
    (when (string= my/spellcheck-program "aspell")
      ;; Aspell can't check multiple languages simultaneously
      ;; Default to Polish, user can switch with keybindings
      (setq ispell-dictionary "pl_PL")
      (setq ispell-personal-dictionary "~/.aspell.pl.pws")
      
      (message "⚠ Aspell: Default Polish (use C-c F e for English)
   Note: Aspell can't check PL+EN simultaneously like hunspell"))
    
    ;; ============================================================
    ;; ISPELL: Fallback (least capable)
    ;; ============================================================
    (when (string= my/spellcheck-program "ispell")
      (setq ispell-dictionary "polish")
      (message "⚠ Ispell: Limited multi-language support
   Consider installing hunspell for better PL+EN checking"))
    
    ;; Don't check code blocks in org-mode
    (add-to-list 'ispell-skip-region-alist '("^#\\+BEGIN_SRC" . "^#\\+END_SRC"))
    (add-to-list 'ispell-skip-region-alist '("^#\\+begin_src" . "^#\\+end_src"))))

;; ============================================================
;; PERSISTENT FLYSPELL: Force it to stay on
;; ============================================================

(when my/spellcheck-available
  (defun my/ensure-flyspell-enabled ()
    "Force flyspell to stay enabled in org/text modes."
    (when (and (derived-mode-p 'org-mode 'text-mode)
               (not flyspell-mode))
      (flyspell-mode 1)))

  ;; Check and re-enable after every command (lightweight check)
  (add-hook 'post-command-hook 'my/ensure-flyspell-enabled)

  ;; Also ensure it's on after buffer switches
  (add-hook 'buffer-list-update-hook 'my/ensure-flyspell-enabled))

;; ============================================================
;; LANGUAGE SWITCHING (for aspell/ispell only)
;; ============================================================

(defun my/switch-dictionary-pl ()
  "Switch to Polish dictionary (mainly for aspell/ispell).
   With hunspell, both languages are always active."
  (interactive)
  (if (string= my/spellcheck-program "hunspell")
      (message "Hunspell: Already checking Polish + English simultaneously")
    (ispell-change-dictionary "pl_PL")
    (flyspell-buffer)
    (message "Dictionary: Polski")))

(defun my/switch-dictionary-en ()
  "Switch to English dictionary (mainly for aspell/ispell).
   With hunspell, both languages are always active."
  (interactive)
  (if (string= my/spellcheck-program "hunspell")
      (message "Hunspell: Already checking Polish + English simultaneously")
    (ispell-change-dictionary "en_US")
    (flyspell-buffer)
    (message "Dictionary: English")))

;; ============================================================
;; SPELL CORRECTION COMMANDS
;; ============================================================

;; Only bind keys if spellchecker is available
(when my/spellcheck-available
  ;; Language switching (only useful for aspell/ispell)
  (global-set-key (kbd "C-c F m") 'my/switch-dictionary-pl)
  (global-set-key (kbd "C-c F e") 'my/switch-dictionary-en)
  
  ;; Navigation and correction
  (global-set-key (kbd "C-c F n") 'flyspell-goto-next-error)
  (global-set-key (kbd "C-c F c") 'flyspell-correct-word-before-point)
  (global-set-key (kbd "C-c F b") 'flyspell-buffer)
  (global-set-key (kbd "C-c F a") 'ispell-word))

;; ============================================================
;; INSTALLATION HELP MESSAGE
;; ============================================================

(unless my/spellcheck-available
  (defun my/spellcheck-install-help ()
    "Show installation instructions for spellcheckers."
    (interactive)
    (message "
═══════════════════════════════════════════════════════
  Spellcheck Not Available
═══════════════════════════════════════════════════════

To enable spellchecking, install hunspell (recommended):

NixOS:
  Add to configuration.nix:
    environment.systemPackages = with pkgs; [
      hunspell
      hunspellDicts.pl_PL
      hunspellDicts.en_US
    ];
  
  Then: sudo nixos-rebuild switch

Other Linux:
  sudo apt install hunspell hunspell-pl hunspell-en-us

Why hunspell?
  ✓ Checks Polish + English simultaneously (no switching!)
  ✓ Best multi-language support
  ✓ Used by LibreOffice, Firefox, etc.

After installing, restart Emacs.
═══════════════════════════════════════════════════════"))
  
  ;; Bind help message to keybinding
  (global-set-key (kbd "C-c F h") 'my/spellcheck-install-help))

(provide '03-spelling)
;;; 03-spelling.el ends here
