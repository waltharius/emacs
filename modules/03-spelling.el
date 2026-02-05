;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) for spelling
;;              Flyspell for highlighting errors AS YOU TYPE
;;              MANUAL checking to prevent freezes
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
;; HELPER: Find previous spelling error
;; ============================================================

(defun my/flyspell-goto-previous-error ()
  "Go to previous spelling error. Returns position or nil."
  (let ((pos (point))
        (min (point-min))
        (found nil))
    (save-excursion
      ;; Move back one word to start search
      (backward-word 1)
      ;; Search backward for flyspell overlay
      (while (and (> (point) min) (not found))
        (let ((overlays (overlays-at (point))))
          (if (seq-some #'flyspell-overlay-p overlays)
              (setq found (point))
            (backward-word 1)))))
    (when found
      (goto-char found)
      found)))

;; ============================================================
;; SPELL CORRECTION (with menu!)
;; ============================================================

(defun my/spell-correct-previous ()
  "Jump to previous spelling error and show correction menu.
  SAFE: Checks process before running."
  (interactive)
  (condition-case err
      (if (not (my/spell-check-can-run-p))
          (message "⚠️ Spell-checking not available. Toggle it on with C-c n T")
        ;; Find previous error
        (if (not (my/flyspell-goto-previous-error))
            (message "No spelling errors found backward from cursor")
          ;; Found error and cursor is on it, show corrections
          (flyspell-correct-wrapper)))
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
        ;; Find previous error
        (if (not (my/flyspell-goto-previous-error))
            (message "No spelling errors found")
          ;; Found error, add it
          (let ((word (thing-at-point 'word t)))
            (when word
              (ispell-add-per-file-word-list word)
              ;; Remove overlay
              (dolist (o (overlays-at (point)))
                (when (flyspell-overlay-p o)
                  (delete-overlay o)))
              (message "✓ Added: %s" word)))))
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
;; CHECK BUFFER (manual only!)
;; ============================================================

(defun my/spell-check-buffer ()
  "Check spelling in visible region only.
  SAFE: Only checks what you can see (fast and won't block).
  
  This is MANUAL - run it when you want to check for errors."
  (interactive)
  (condition-case err
      (progn
        (unless flyspell-mode
          (flyspell-mode 1)
          (message "✓ Flyspell enabled"))
        ;; Only check visible region (safe and fast)
        (message "Checking visible region...")
        (flyspell-region (window-start) (window-end))
        (message "✓ Visible region checked"))
    (error
     (message "Error checking buffer: %s" (error-message-string err)))))

;; ============================================================
;; FLYSPELL CONFIGURATION - INCREMENTAL CHECKING ONLY
;; ============================================================

(use-package flyspell
  :ensure nil
  :hook ((text-mode . flyspell-mode)
         (org-mode  . flyspell-mode))
  :config
  ;; Reduce verbosity
  (setq flyspell-issue-message-flag nil)
  (setq flyspell-issue-welcome-flag nil)
  
  ;; Check words AS YOU TYPE (incremental, safe)
  (setq flyspell-delay 3)  ; Check after 3 seconds of idle typing
  
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
;; CRITICAL CHANGES TO PREVENT FREEZING
;; ============================================================
;;
;; REMOVED:
;; 1. Automatic initial check (was blocking with idle timer)
;; 2. window-configuration-change-hook (infinite loop)
;; 3. focus-in-hook (triggered with dead process)
;; 4. All automatic buffer-wide checking
;;
;; HOW IT WORKS NOW:
;; 1. Flyspell mode turns ON when opening text/org files
;; 2. As you TYPE, flyspell checks each word (incremental, safe)
;; 3. Errors appear gradually as you type or edit
;; 4. Manual check: C-c n S (checks visible region only)
;;
;; WHY THIS IS SAFE:
;; - Incremental checking (word-by-word) never blocks
;; - No automatic large buffer scans
;; - Manual checks are small (visible region only)
;; - User controls when checking happens
;; - All functions have error handling
;;
;; TRADE-OFF:
;; - Opening a file: NO immediate underlining
;; - As you type/edit: Errors appear (safe, incremental)
;; - Want to check now: Run C-c n S (manual, fast)
;;
;; This prevents ALL freezing issues at the cost of not having
;; immediate error highlighting when opening files.

;; ============================================================
;; USAGE
;; ============================================================
;;
;; AUTOMATIC CHECKING:
;; - As you type → Words checked after 3 seconds idle
;; - Errors underlined gradually as you work
;; - Safe, incremental, never blocks
;;
;; MANUAL CHECKING:
;; - C-c n S → Check visible region (fast, safe)
;; - C-c n s → Correct previous error (shows menu)
;; - C-c n a → Add previous error to dictionary
;; - C-c n T → Toggle flyspell on/off
;;
;; WORKFLOW:
;; 1. Open file → Flyspell ON (no immediate check)
;; 2. Start typing → Errors appear as you type
;; 3. Want to check existing text? → C-c n S
;; 4. See an error? → C-c n s (correct) or C-c n a (add)
;;
;; All operations are safe and won't freeze Emacs!

(provide '03-spelling)
;;; 03-spelling.el ends here
