;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) for spelling
;;              Flyspell for highlighting errors AS YOU TYPE
;;              SMART automatic checking based on buffer size
;;
;;; Code:

;; --- Hunspell: spell checking pl_PL + en_GB (UTF-8) ---
(require 'ispell)
;; Force UTF-8 locale for the Hunspell subprocess
(setenv "LANG" "pl_PL.UTF-8")
(setenv "LC_ALL" "pl_PL.UTF-8")

;; FORCE UTF-8 encoding for Hunspell
(setq ispell-program-name "hunspell")
(setq ispell-hunspell-dictionary-alist
      '(("pl_PL" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "pl_PL" "-i" "utf-8") nil utf-8)
        ("en_GB" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "en_GB" "-i" "utf-8") nil utf-8)
        ("pl_PL,en_GB" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "pl_PL,en_GB" "-i" "utf-8") nil utf-8)))

(setq ispell-dictionary "pl_PL,en_GB")
(setq ispell-personal-dictionary (expand-file-name "~/.hunspell_personal"))
(setenv "HUNSPELL_PERSONAL" ispell-personal-dictionary)

;; Ensure personal dictionary has UTF-8 header
(unless (file-exists-p ispell-personal-dictionary)
  (with-temp-buffer
    (insert "personal_ws-1.1 pl_PL 0 utf-8\n")
    (write-file ispell-personal-dictionary)))
(setq ispell-silently-savep t)

;; Initialize Hunspell with UTF-8 - NixOS paths via per-user profile
(with-eval-after-load 'ispell
  (setq ispell-hunspell-dict-paths-alist
        '(("pl_PL" "/etc/profiles/per-user/marcin/share/hunspell/pl_PL.aff")
          ("en_GB" "/etc/profiles/per-user/marcin/share/hunspell/en_GB.aff")))
  (ispell-set-spellchecker-params)
  (ispell-hunspell-add-multi-dic "pl_PL,en_GB"))

;; --- Automatic refresh after dictionary save ---
(defun my/ispell-refresh-after-save (&rest _)
  "Refresh Hunspell process after saving dictionary."
  (when (and (boundp 'ispell-process) (process-live-p ispell-process))
    (ispell-kill-ispell)))
(advice-add 'ispell-pdict-save :after #'my/ispell-refresh-after-save)

;; ============================================================
;; SAFE HELPER: Check if process is alive (read-only, no side effects)
;; ============================================================

(defun my/spell-check-can-run-p ()
  "Return t if flyspell-mode is on AND the Hunspell process is already running.
This function ONLY checks — it never starts the process.
Use `my/spell-ensure-process' when you need the process to be running."
  (and flyspell-mode
       (boundp 'ispell-process)
       (process-live-p ispell-process)))

;; ============================================================
;; PROCESS STARTER: Ensure Hunspell is running and ready
;; ============================================================

(defun my/spell-ensure-process ()
  "Ensure the Hunspell process is running and has finished its startup handshake.

If the process is not alive, this function starts it and waits briefly
for the NixOS wrapper to complete its iconv probe (which produces the
harmless 'iconv: ISO8859-2 -> UTF-8' banner lines on first start).

Returns t if the process is ready, nil if it could not be started."
  (unless (and (boundp 'ispell-process) (process-live-p ispell-process))
    (message "Starting Hunspell…")
    (condition-case nil
        (ispell-set-spellchecker-params)
      (error nil))
    (condition-case nil
        (ispell-init-process)
      (error nil))
    ;; Allow the process handshake and NixOS wrapper banner to flush through
    ;; before we try to send correction commands.
    (sit-for 0.3))
  (and (boundp 'ispell-process)
       (process-live-p ispell-process)))

;; ============================================================
;; HELPER: Find previous spelling error
;; ============================================================

(defun my/flyspell-goto-previous-error ()
  "Go to previous spelling error. Returns position or nil."
  (let ((min (point-min))
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
;; SPELL CORRECTION (with menu!) - Returns to start position
;; ============================================================

(defun my/spell-correct-previous ()
  "Jump to previous spelling error, show correction menu, then return to start.

Workflow:
1. Save current cursor position.
2. Ensure Hunspell process is running (starts it on first use, waits for
   its startup handshake — this is why the first press always works now).
3. Find previous spelling error.
4. Show correction menu via flyspell-correct-wrapper.
5. Return cursor to original position after correction.

SAFE: Handles process startup correctly; cursor always returns home."
  (interactive)
  (let ((start-pos (point)))
    (condition-case err
        (cond
         ((not flyspell-mode)
          (message "⚠️ Spell-checking not active. Toggle with C-c n T"))
         ((not (my/spell-ensure-process))
          (message "⚠️ Could not start Hunspell. Check dictionary configuration."))
         ((not (my/flyspell-goto-previous-error))
          (message "No spelling errors found backward from cursor"))
         (t
          (flyspell-correct-wrapper)
          (goto-char start-pos)))
      (error
       (goto-char start-pos)
       (message "Error in spell correction: %s" (error-message-string err))))))

;; ============================================================
;; ADD WORD TO PERSONAL DICTIONARY - Returns to start position
;; ============================================================

(defun my/spell-add-previous-to-dict ()
  "Add previous misspelled word to PERSONAL dictionary, then return to start.

Workflow:
1. Save current cursor position.
2. Ensure Hunspell process is running.
3. Find previous spelling error.
4. Add word to ~/.hunspell_personal (global dictionary).
5. Remove error overlay.
6. Return cursor to original position.

NOT as LocalWords in the current file!

SAFE: Handles process startup; cursor always returns home."
  (interactive)
  (let ((start-pos (point)))
    (condition-case err
        (cond
         ((not flyspell-mode)
          (message "⚠️ Spell-checking not active. Toggle with C-c n T"))
         ((not (my/spell-ensure-process))
          (message "⚠️ Could not start Hunspell. Check dictionary configuration."))
         ((not (my/flyspell-goto-previous-error))
          (message "No spelling errors found"))
         (t
          (let ((word (downcase (thing-at-point 'word t))))
            (when word
              ;; Send '*word' command to ispell process (adds to personal dict)
              (ispell-send-string (concat "*" word "\n"))
              ;; Mark dictionary as modified so it gets saved
              (setq ispell-pdict-modified-p '(t))
              ;; Save the personal dictionary immediately
              (ispell-pdict-save t t)
              ;; Remove overlay
              (dolist (o (overlays-at (point)))
                (when (flyspell-overlay-p o)
                  (delete-overlay o)))
              ;; Return to starting position
              (goto-char start-pos)
              (message "✓ Added to personal dictionary: %s" word)))))
      (error
       (goto-char start-pos)
       (message "Error adding word: %s" (error-message-string err))))))

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
;; INCREMENTAL CHECKING (as you type):
;; - Flyspell checks each word after 3 seconds of idle typing
;; - Safe, never blocks
;;
;; MANUAL CHECKING:
;; - C-c n S → Check visible region (fast, always safe)
;; - C-c n b → Check entire buffer (use for small files or final review)
;; - C-c n s → Correct previous error (shows menu, returns cursor home)
;; - C-c n a → Add previous error to dictionary (returns cursor home)
;; - C-c n T → Toggle flyspell on/off
;;
;; FIRST USE BEHAVIOUR (cold start):
;; - On the very first C-c n s / C-c n a after Emacs starts, the function
;;   will start the Hunspell process, wait 0.3s for its handshake, then
;;   immediately show the correction menu — no second press needed.
;; - The NixOS wrapper may still print "iconv: ISO8859-2 -> UTF-8" to
;;   *Messages* on that first start. This is harmless wrapper noise and
;;   does NOT mean the correction failed.
;;
;; CURSOR BEHAVIOR:
;; - Both C-c n s and C-c n a return cursor to starting position
;; - You stay where you were, error is corrected in background
;;
;; ADDING WORDS TO DICTIONARY:
;; - Words are added to ~/.hunspell_personal (global)
;; - NOT as "# LocalWords:" comments in buffer
;; - Dictionary is saved automatically
;; - Hunspell process is reloaded to pick up changes

(provide '03-spelling)
;;; 03-spelling.el ends here
