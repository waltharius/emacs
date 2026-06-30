;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) for spelling
;;              Flyspell for highlighting errors AS YOU TYPE
;;              SMART automatic checking based on buffer size
;;
;; STARTUP BEHAVIOUR
;; -----------------
;; ispell variables are set immediately at load time (flyspell needs
;; them before any hook fires).  However, the Hunspell subprocess is
;; NOT started during Emacs init or desktop-restore.  It starts on the
;; first keystroke that flyspell wants to check — typically 3 seconds
;; after you start typing in any org/text buffer.  This avoids the
;; ~18-second hang caused by Hunspell starting N times while
;; desktop-restore opens all saved .org buffers.
;;
;;; Code:

;; ============================================================
;; ISPELL CORE VARIABLES  (set immediately — flyspell reads these
;;                          before the subprocess is ever needed)
;; ============================================================

(setq ispell-program-name "hunspell")
(setq ispell-dictionary "pl_PL,en_GB")
(setq ispell-personal-dictionary (expand-file-name "~/.hunspell_personal"))
(setenv  "HUNSPELL_PERSONAL" ispell-personal-dictionary)
(setenv  "LANG"   "pl_PL.UTF-8")
(setenv  "LC_ALL" "pl_PL.UTF-8")

;; Save personal dictionary silently (no "Save buffer?" prompt for
;; ispell's internal save calls).  The remaining quit-prompt fix is
;; in E6 below.
(setq ispell-silently-savep t)

(setq ispell-hunspell-dictionary-alist
      '(("pl_PL" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "pl_PL" "-i" "utf-8") nil utf-8)
        ("en_GB" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "en_GB" "-i" "utf-8") nil utf-8)
        ("pl_PL,en_GB" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "pl_PL,en_GB" "-i" "utf-8") nil utf-8)))

;; Ensure personal dictionary exists with correct UTF-8 header
(unless (file-exists-p ispell-personal-dictionary)
  (with-temp-buffer
    (insert "personal_ws-1.1 pl_PL 0 utf-8\n")
    (write-file ispell-personal-dictionary)))

;; ============================================================
;; DEFERRED HUNSPELL SETUP  (runs after ispell.el is loaded,
;;                            NOT during Emacs startup)
;; ============================================================
;; ispell.el is loaded lazily — only when flyspell actually needs it
;; (first word checked after first keystroke).  Everything below runs
;; at that point, not during desktop-restore.

(with-eval-after-load 'ispell
  (let* ((login     (user-login-name))
         (nix-path  (format "/etc/profiles/per-user/%s/share/hunspell" login))
         (fallback  "/usr/share/hunspell")
         (dict-path (if (file-directory-p nix-path) nix-path fallback)))
    (setq ispell-hunspell-dict-paths-alist
          (list
           (list "pl_PL" (expand-file-name "pl_PL.aff" dict-path))
           (list "en_GB" (expand-file-name "en_GB.aff" dict-path)))))
  (ispell-set-spellchecker-params)
  (ispell-hunspell-add-multi-dic "pl_PL,en_GB"))

;; ============================================================
;; E6 — SUPPRESS "Save .hunspell_personal?" ON QUIT
;; ============================================================
;; ispell-pdict-save can leave the personal dictionary file open as
;; an Emacs buffer.  When Emacs quits, save-some-buffers sees the
;; modified buffer and prompts.  We suppress the prompt by telling
;; save-some-buffers to skip that specific file path.

(defun my/spell--personal-dict-buffer-p ()
  "Return t if the current buffer is the hunspell personal dictionary.
Used by `save-some-buffers-default-predicate' to skip the prompt."
  (when (buffer-file-name)
    (string= (file-truename (buffer-file-name))
             (file-truename ispell-personal-dictionary))))

;; Add to the list of buffers save-some-buffers should NOT ask about.
;; The predicate returns non-nil → buffer is skipped (not saved interactively).
;; ispell-pdict-save already wrote the file to disk, so skipping here
;; is safe — no data is lost.
(add-to-list 'save-some-buffers-action-alist
             (list #'my/spell--personal-dict-buffer-p
                   (lambda (_buf) (ignore))
                   "skip hunspell personal dictionary"))

;; ============================================================
;; SAFE HELPER: Check if process is alive (read-only, no side effects)
;; ============================================================

(defun my/spell-check-can-run-p ()
  "Return t if flyspell-mode is on AND the Hunspell process is already running.
This function ONLY checks — it never starts the process."
  (and flyspell-mode
       (boundp 'ispell-process)
       (process-live-p ispell-process)))

;; ============================================================
;; PROCESS STARTER: Ensure Hunspell is running and ready
;; ============================================================

(defun my/spell-ensure-process ()
  "Ensure the Hunspell process is running and has finished its startup handshake.
If the process is not alive, start it and wait briefly for the NixOS
wrapper iconv probe to flush through.  This is a no-op in steady state.
Returns t if process is ready, nil if it could not be started."
  (unless (and (boundp 'ispell-process) (process-live-p ispell-process))
    (message "Starting Hunspell…")
    (condition-case nil (ispell-set-spellchecker-params) (error nil))
    (condition-case nil (ispell-init-process)            (error nil))
    (sit-for 0.3))
  (and (boundp 'ispell-process)
       (process-live-p ispell-process)))

;; ============================================================
;; HELPER: Find previous spelling error
;; ============================================================

(defun my/flyspell-goto-previous-error ()
  "Go to previous spelling error.  Returns position or nil."
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
  "Jump to previous spelling error, show correction menu, then return to start."
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
  "Add previous misspelled word to personal dictionary, then return to start."
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
              (ispell-send-string (concat "*" word "\n"))
              (setq ispell-pdict-modified-p '(t))
              (ispell-pdict-save t t)
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
      (progn (flyspell-mode -1) (message "✗ Spell-checking OFF"))
    (progn (flyspell-mode 1)  (message "✓ Spell-checking ON"))))

;; ============================================================
;; CHECK VISIBLE REGION (manual, fast)
;; ============================================================

(defun my/spell-check-visible ()
  "Check spelling in visible region only."
  (interactive)
  (condition-case err
      (progn
        (unless flyspell-mode (flyspell-mode 1) (message "✓ Flyspell enabled"))
        (message "Checking visible region...")
        (flyspell-region (window-start) (window-end))
        (message "✓ Visible region checked"))
    (error (message "Error checking visible region: %s" (error-message-string err)))))

;; ============================================================
;; CHECK ENTIRE BUFFER (manual, slower)
;; ============================================================

(defun my/spell-check-buffer-full ()
  "Check spelling in ENTIRE buffer.  May take a few seconds on large files."
  (interactive)
  (condition-case err
      (let ((word-count (count-words (point-min) (point-max))))
        (unless flyspell-mode (flyspell-mode 1) (message "✓ Flyspell enabled"))
        (message "Checking entire buffer (%d words)..." word-count)
        (flyspell-buffer)
        (message "✓ Buffer checked (%d words)" word-count))
    (error (message "Error checking buffer: %s" (error-message-string err)))))

;; ============================================================
;; FLYSPELL CONFIGURATION — INCREMENTAL CHECKING
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
;; ENSURE FLYSPELL STAYS ON (run AFTER other hooks, priority 100)
;; ============================================================
;; These hooks guarantee flyspell-mode is active even if another hook
;; accidentally disabled it.  They do NOT start the Hunspell process —
;; that only happens on the first word flyspell actually needs to check.

(add-hook 'org-mode-hook
          (lambda () (unless flyspell-mode (flyspell-mode 1))) 100)

(add-hook 'text-mode-hook
          (lambda () (unless flyspell-mode (flyspell-mode 1))) 100)

;; ============================================================
;; PREVENT OVERLAY DELETION
;; ============================================================

(defun my/flyspell-prevent-overlay-deletion (orig-fun &rest args)
  "Prevent flyspell from deleting overlays unnecessarily."
  (when (and flyspell-mode (called-interactively-p 'any))
    (apply orig-fun args)))

(advice-add 'flyspell-delete-all-overlays
            :around #'my/flyspell-prevent-overlay-deletion)

;; ============================================================
;; FLYSPELL-CORRECT: Interactive corrections via Vertico
;; ============================================================

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

(provide '03-spelling)
;;; 03-spelling.el ends here
