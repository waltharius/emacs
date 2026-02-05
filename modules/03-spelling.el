;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) for spelling
;;              Flyspell for highlighting errors AS YOU TYPE
;;              SMART automatic checking based on buffer size
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
;; CONFIGURATION: Size threshold for automatic checking
;; ============================================================

(defvar my/spell-auto-check-word-threshold 7000
  "If buffer has fewer than this many words, check entire buffer automatically.
If more, only check visible region. Set to nil to disable auto-checking.")

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
;; CHECK VISIBLE REGION (manual, fast)
;; ============================================================

(defun my/spell-check-visible ()
  "Check spelling in visible region only.
  SAFE: Fast and won't block. Use this for large buffers."
  (interactive)
  (condition-case err
      (progn
        (unless flyspell-mode
          (flyspell-mode 1)
          (message "✓ Flyspell enabled"))
        (message "Checking visible region...")
        (flyspell-region (window-start) (window-end))
        (message "✓ Visible region checked"))
    (error
     (message "Error checking visible region: %s" (error-message-string err)))))

;; ============================================================
;; CHECK ENTIRE BUFFER (manual, slower)
;; ============================================================

(defun my/spell-check-buffer-full ()
  "Check spelling in ENTIRE buffer.
  
  Use this for:
  - Small files (< 7000 words)
  - When you want to check everything
  - Before finishing a document
  
  Warning: May take a few seconds on large files."
  (interactive)
  (condition-case err
      (let ((word-count (count-words (point-min) (point-max))))
        (unless flyspell-mode
          (flyspell-mode 1)
          (message "✓ Flyspell enabled"))
        (message "Checking entire buffer (%d words)..." word-count)
        (flyspell-buffer)
        (message "✓ Buffer checked (%d words)" word-count))
    (error
     (message "Error checking buffer: %s" (error-message-string err)))))

;; ============================================================
;; SMART AUTOMATIC CHECK (based on buffer size)
;; ============================================================

(defun my/spell-auto-check-on-open ()
  "Automatically check buffer based on size.
  
  Small buffers (< 7000 words): Check entire buffer
  Large buffers (>= 7000 words): Check visible region only
  
  Runs 3 seconds after opening file (non-blocking)."
  (when (and flyspell-mode
             my/spell-auto-check-word-threshold
             (derived-mode-p 'org-mode 'text-mode))
    (let ((buffer (current-buffer)))
      ;; Run after 3 seconds idle
      (run-with-idle-timer
       3 nil
       (lambda ()
         ;; Check buffer is still alive and visible
         (when (and (buffer-live-p buffer)
                    (get-buffer-window buffer))
           (with-current-buffer buffer
             (when flyspell-mode
               (condition-case err
                   (let ((word-count (count-words (point-min) (point-max))))
                     (if (< word-count my/spell-auto-check-word-threshold)
                         ;; Small buffer: check everything
                         (progn
                           (message "Auto-checking buffer (%d words)..." word-count)
                           (flyspell-buffer)
                           (message "✓ Buffer checked"))
                       ;; Large buffer: visible region only
                       (progn
                         (message "Auto-checking visible region (buffer has %d words)..." word-count)
                         (flyspell-region (window-start) (window-end))
                         (message "✓ Visible region checked"))))
                 (error
                  (message "Auto-check failed: %s" (error-message-string err))))))))))))

;; Add to file opening hook
(add-hook 'find-file-hook 'my/spell-auto-check-on-open)

;; ============================================================
;; FLYSPELL CONFIGURATION - INCREMENTAL CHECKING
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

;; Keep old binding for compatibility (now checks visible region)
(global-set-key (kbd "C-c f b") 'my/spell-check-visible)

;; ============================================================
;; HOW IT WORKS NOW
;; ============================================================
;;
;; AUTOMATIC CHECKING (on file open):
;; - Buffer < 7000 words → Check entire buffer after 3 seconds ✓
;; - Buffer >= 7000 words → Check visible region only after 3 seconds
;; - Can disable by setting my/spell-auto-check-word-threshold to nil
;;
;; INCREMENTAL CHECKING (as you type):
;; - Flyspell checks each word after 3 seconds of idle typing
;; - Safe, never blocks
;;
;; MANUAL CHECKING:
;; - C-c n S → Check visible region (fast, always safe)
;; - C-c n B → Check entire buffer (use for small files or final review)
;; - C-c n s → Correct previous error (shows menu)
;; - C-c n a → Add previous error to dictionary
;; - C-c n T → Toggle flyspell on/off
;;
;; WORKFLOW:
;; 1. Open small file → Auto-checks everything after 3 sec ✓
;; 2. Open large file → Auto-checks visible part after 3 sec ✓
;; 3. Type/edit → Errors appear as you type ✓
;; 4. Want full check? → C-c n B (entire buffer)
;; 5. Quick check? → C-c n S (visible region)
;; 6. Fix errors → C-c n s or C-c n a
;;
;; SAFETY:
;; - All automatic checks have 3-second delay (non-blocking)
;; - Large files only check visible region automatically
;; - All functions have error handling
;; - User can disable auto-check or adjust threshold

;; ============================================================
;; CONFIGURATION OPTIONS
;; ============================================================
;;
;; Adjust auto-check threshold:
;; (setq my/spell-auto-check-word-threshold 10000)  ; Check up to 10k words
;; (setq my/spell-auto-check-word-threshold nil)    ; Disable auto-check
;;
;; Current setting: 7000 words
;; - Typical org note: 500-2000 words → Full auto-check ✓
;; - Large document: 10000+ words → Visible region only ✓

(provide '03-spelling)
;;; 03-spelling.el ends here
