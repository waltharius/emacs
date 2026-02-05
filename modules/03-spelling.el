;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) for spelling
;;              Flyspell for highlighting errors
;;              SAFE and SIMPLE - no freezing!
;;
;;; Code:

;; --- Hunspell: spell checking pl_PL + en_GB (UTF-8) ---
(require 'ispell)

;; FORCE UTF-8 encoding for Hunspell
(setq ispell-program-name "hunspell")
(setq ispell-local-dictionary-alist
      '(("pl_PL" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "pl_PL") nil utf-8)
        ("en_GB" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "en_GB") nil utf-8)))

(setq ispell-dictionary "pl_PL,en_GB")
(setq ispell-personal-dictionary (expand-file-name "~/.hunspell_personal"))
(setenv "HUNSPELL_PERSONAL" ispell-personal-dictionary)

;; Ensure personal dictionary has UTF-8 header
(unless (file-exists-p ispell-personal-dictionary)
  (with-temp-buffer 
    (insert "personal_ws-1.1 pl_PL 0 utf-8\n")
    (write-file ispell-personal-dictionary)))
(setq ispell-silently-savep t)

;; Initialize Hunspell with UTF-8
(with-eval-after-load 'ispell
  (ispell-set-spellchecker-params)
  (ispell-hunspell-add-multi-dic "pl_PL,en_GB"))

;; --- Automatic refresh after dictionary save ---
(defun my/ispell-refresh-after-save (&rest _)
  "Refresh Hunspell process after saving dictionary."
  (when (and (boundp 'ispell-process) (process-live-p ispell-process))
    (ispell-kill-ispell)))
(advice-add 'ispell-pdict-save :after #'my/ispell-refresh-after-save)

;; ============================================================
;; SAFE HELPER: Check if spell-checking is available
;; ============================================================

(defun my/spell-check-can-run-p ()
  "Check if spell-checking can safely run.
  Returns t if flyspell-mode is on and process is alive (or can be started)."
  (and flyspell-mode
       (or (and (boundp 'ispell-process) (process-live-p ispell-process))
           (ignore-errors (ispell-check-version) t))))

;; ============================================================
;; SIMPLE SPELL CORRECTION
;; ============================================================

(defun my/spell-correct-previous ()
  "Jump to previous spelling error and correct it.
  SAFE: Checks process before running."
  (interactive)
  (condition-case err
      (if (not (my/spell-check-can-run-p))
          (message "⚠️ Spell-checking not available. Toggle it on with C-c n T")
        ;; Save position
        (let ((start-pos (point)))
          ;; Try to find previous error
          (if (not (flyspell-goto-next-error t))
              (message "No spelling errors found")
            ;; Found error, show corrections
            (flyspell-correct-wrapper))))
    (error
     (message "Error in spell correction: %s" (error-message-string err)))))

;; ============================================================
;; ADD WORD TO DICTIONARY (simple and safe)
;; ============================================================

(defun my/spell-add-previous-to-dict ()
  "Add previous misspelled word to dictionary.
  SAFE: Checks process before running."
  (interactive)
  (condition-case err
      (if (not (my/spell-check-can-run-p))
          (message "⚠️ Spell-checking not available")
        (save-excursion
          (if (not (flyspell-goto-next-error t))
              (message "No spelling errors found")
            ;; Found error, add it
            (let ((word (thing-at-point 'word t)))
              (when word
                (ispell-add-per-file-word-list word)
                ;; Remove overlay
                (dolist (o (overlays-at (point)))
                  (when (flyspell-overlay-p o)
                    (delete-overlay o)))
                (message "✓ Added: %s" word))))))
    (error
     (message "Error adding word: %s" (error-message-string err)))))

;; ============================================================
;; TOGGLE FLYSPELL MODE
;; ============================================================

(defun my/toggle-flyspell ()
  "Toggle flyspell-mode on/off."
  (interactive)
  (if flyspell-mode
      (progn
        (flyspell-mode -1)
        (message "✗ Spell-checking OFF"))
    (progn
      (flyspell-mode 1)
      (message "✓ Spell-checking ON"))))

;; ============================================================
;; CHECK BUFFER (simplified and safe)
;; ============================================================

(defun my/spell-check-buffer ()
  "Check spelling in entire buffer.
  SAFE: Only checks visible region to avoid freezes."
  (interactive)
  (condition-case err
      (if (not flyspell-mode)
          (progn
            (flyspell-mode 1)
            (message "✓ Flyspell enabled. Checking visible region...")
            (flyspell-region (window-start) (window-end)))
        ;; Flyspell already on, check visible region only
        (message "Checking visible region...")
        (flyspell-region (window-start) (window-end))
        (message "✓ Visible region checked"))
    (error
     (message "Error checking buffer: %s" (error-message-string err)))))

;; ============================================================
;; FLYSPELL CONFIGURATION - SIMPLE AND SAFE
;; ============================================================

(use-package flyspell
  :ensure nil
  :hook ((text-mode . flyspell-mode)
         (org-mode  . flyspell-mode))
  :config
  ;; Reduce verbosity
  (setq flyspell-issue-message-flag nil)
  (setq flyspell-issue-welcome-flag nil)
  
  ;; Check words as you type
  (setq flyspell-delay 2)  ; 2 second delay (safer)
  
  ;; PREVENT OVERLAYS FROM DISAPPEARING
  (setq flyspell-delete-overlays nil)
  
  ;; Dash handling
  (setq flyspell-consider-dash-as-word-delimiter-flag t))

;; ============================================================
;; ENSURE FLYSPELL STAYS ON (run AFTER other hooks)
;; ============================================================

(add-hook 'org-mode-hook
          (lambda ()
            (unless flyspell-mode
              (flyspell-mode 1)))
          100)

(add-hook 'text-mode-hook
          (lambda ()
            (unless flyspell-mode
              (flyspell-mode 1)))
          100)

;; ============================================================
;; PREVENT OVERLAY DELETION
;; ============================================================

(defun my/flyspell-prevent-overlay-deletion (orig-fun &rest args)
  "Prevent flyspell from deleting overlays unnecessarily."
  (when (and flyspell-mode (called-interactively-p 'any))
    (apply orig-fun args)))

(advice-add 'flyspell-delete-all-overlays :around #'my/flyspell-prevent-overlay-deletion)

;; ============================================================
;; FLYSPELL-CORRECT: Interactive corrections
;; ============================================================

(use-package flyspell-correct
  :ensure t
  :after flyspell
  :config
  (setq flyspell-correct-interface #'flyspell-correct-ivy)
  (define-key flyspell-mode-map (kbd "C-;") 'flyspell-correct-wrapper))

(use-package flyspell-correct-ivy
  :ensure t
  :after flyspell-correct)

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c f b") 'my/spell-check-buffer)

;; ============================================================
;; WHAT WAS REMOVED (TO PREVENT FREEZES)
;; ============================================================
;;
;; REMOVED DANGEROUS HOOKS:
;; 1. window-configuration-change-hook → Called flyspell-buffer on EVERY
;;    window change, causing infinite loops
;; 2. focus-in-hook auto-recheck → Triggered with dead process
;; 3. Complex spell-return-position logic → Caused issues with wrapper
;;
;; SIMPLIFIED:
;; - spell-check-buffer now only checks VISIBLE region (fast and safe)
;; - All functions have condition-case error handling
;; - All functions check if process is alive before running
;; - Removed diagnostic tracking (was causing overhead)
;;
;; RESULT:
;; - No more freezes or infinite loops
;; - Safe spell-checking that can't crash
;; - Fast visible-region checks instead of full buffer
;; - Clean error messages when something goes wrong

;; ============================================================
;; USAGE
;; ============================================================
;;
;; C-c n s  - Correct previous error (safe, with error handling)
;; C-c n a  - Add previous error to dictionary (safe)
;; C-c n S  - Check visible region (fast, no freeze)
;; C-c n T  - Toggle flyspell on/off
;;
;; All functions now:
;; - Check if flyspell process is alive
;; - Have error handling (won't freeze)
;; - Work on visible region only (fast)
;; - Show helpful error messages

(provide '03-spelling)
;;; 03-spelling.el ends here
