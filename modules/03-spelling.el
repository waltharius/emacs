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

;; Initialize Hunspell with UTF-8.
;; Paths are resolved at runtime using (user-login-name) so this config
;; works for any user without modification.
;; NixOS per-user profile is tried first; /usr/share/hunspell is the
;; fallback for Fedora, Debian, and other distros.
(with-eval-after-load 'ispell
  (let* ((login (user-login-name))
         (nix-path (format "/etc/profiles/per-user/%s/share/hunspell" login))
         (fallback-path "/usr/share/hunspell")
         (dict-path (if (file-directory-p nix-path) nix-path fallback-path)))
    (setq ispell-hunspell-dict-paths-alist
          (list
           (list "pl_PL" (expand-file-name "pl_PL.aff" dict-path))
           (list "en_GB" (expand-file-name "en_GB.aff" dict-path)))))
  (ispell-set-spellchecker-params)
  (ispell-hunspell-add-multi-dic "pl_PL,en_GB"))

;; NOTE: No process-kill-on-save advice here.
;; ispell-send-string "*word" already tells the live Hunspell process to
;; accept a new word immediately. ispell-pdict-save only writes to disk
;; for persistence across Emacs restarts. Killing and restarting the
;; process after each dictionary save is unnecessary and causes a
;; multi-second delay on every 'a' (add to dictionary) keypress.

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
harmless \='iconv: ISO8859-2 -> UTF-8\=' banner lines on first start).

Called only when the process is dead (i.e. on very first use after
Emacs starts, or after an unexpected crash). Normal corrections and
add-to-dictionary operations never kill the process, so this function
is a no-op in steady-state use.

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
      (backward-word 1)
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
2. Ensure Hunspell process is running (starts it on first use after
   Emacs boots; instant no-op on every subsequent call).
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
4. Send '*word' to running Hunspell process (accepted immediately
   in-session, no restart needed).
5. Save word to ~/.hunspell_personal for persistence across restarts.
6. Remove error overlay.
7. Return cursor to original position.

NOT saved as LocalWords in the current file.

SAFE: No process restart; instant on all but the very first call."
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
              ;; Tell the running process to accept this word immediately
              (ispell-send-string (concat "*" word "\n"))
              ;; Mark dictionary modified and save to disk (no process restart)
              (setq ispell-pdict-modified-p '(t))
              (ispell-pdict-save t t)
              ;; Remove the flyspell overlay
              (dolist (o (overlays-at (point)))
                (when (flyspell-overlay-p o)
                  (delete-overlay o)))
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
  (setq flyspell-issue-message-flag nil)
  (setq flyspell-issue-welcome-flag nil)
  (setq flyspell-delay 3)
  (setq flyspell-delete-overlays nil)
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

;; flyspell-correct provides the correction UI via completing-read.
;; Vertico intercepts completing-read automatically, so the popup
;; looks and behaves exactly like other Vertico completions.
;; No ivy or other completion framework needed as a dependency.
(use-package flyspell-correct
  :ensure t
  :after flyspell
  :config
  (setq flyspell-correct-interface #'flyspell-correct-completing-read)
  (define-key flyspell-mode-map (kbd "C-;") 'flyspell-correct-wrapper))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c f b") 'my/spell-check-visible)

;; ============================================================
;; HOW IT WORKS
;; ============================================================
;;
;; PROCESS LIFECYCLE:
;; - Hunspell starts once on the first C-c n s or C-c n a after Emacs boots.
;; - It stays alive for the entire session.
;; - 's' and 'a' never kill or restart the process.
;; - Words added via 'a' are accepted by the running process immediately
;;   (via ispell '*word' protocol) and also written to disk for future sessions.
;;
;; INCREMENTAL CHECKING (as you type):
;; - Flyspell checks each word after 3 seconds of idle typing.
;;
;; MANUAL CHECKING:
;; - C-c n S → Check visible region (fast, always safe)
;; - C-c n b → Check entire buffer
;; - C-c n s → Correct previous error (shows menu, returns cursor home)
;; - C-c n a → Add previous error to dictionary (returns cursor home)
;; - C-c n T → Toggle flyspell on/off
;;
;; CURSOR BEHAVIOR:
;; - Both C-c n s and C-c n a return cursor to starting position.
;;
;; DICTIONARY PATHS (NixOS + fallback):
;; - NixOS: /etc/profiles/per-user/<login>/share/hunspell/
;; - Other: /usr/share/hunspell/
;; - Path resolved at runtime via (user-login-name) — no hardcoded names.

(provide '03-spelling)
;;; 03-spelling.el ends here
