;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB-large UTF-8) for spelling
;;              Flyspell for highlighting errors AS YOU TYPE
;;
;; STARTUP BEHAVIOUR
;; -----------------
;; ispell variables are set immediately at load time.
;; The Hunspell subprocess is blocked during desktop-restore via
;; `my/flyspell-desktop-restoring' flag.  After desktop-restore
;; completes, `desktop-after-read-hook' (in 15-workspace.el) clears
;; the flag and re-activates flyspell-mode-on for all open buffers.
;; Hunspell then starts once, on demand, for the first buffer checked.
;;
;;; Code:

;; ============================================================
;; ISPELL CORE VARIABLES  (set immediately — flyspell reads these
;;                          before the subprocess is ever needed)
;; ============================================================

(setq ispell-program-name "hunspell")
(setq ispell-dictionary "pl_PL,en_GB-large")
(setq ispell-personal-dictionary (expand-file-name "~/.hunspell_personal"))
(setenv  "HUNSPELL_PERSONAL" ispell-personal-dictionary)
(setenv  "LANG"   "pl_PL.UTF-8")
(setenv  "LC_ALL" "pl_PL.UTF-8")
(setq ispell-silently-savep t)

(setq ispell-hunspell-dictionary-alist
      '(("pl_PL" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "pl_PL" "-i" "utf-8") nil utf-8)
        ("en_GB-large" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "en_GB-large" "-i" "utf-8") nil utf-8)
        ("pl_PL,en_GB-large" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "pl_PL,en_GB-large" "-i" "utf-8") nil utf-8)))

;; Ensure personal dictionary exists with correct UTF-8 header
(unless (file-exists-p ispell-personal-dictionary)
  (with-temp-buffer
    (insert "personal_ws-1.1 pl_PL 0 utf-8\n")
    (write-file ispell-personal-dictionary)))

;; ============================================================
;; HUNSPELL DICT PATH REGISTRATION
;; ============================================================
;; On NixOS, hunspellDicts.pl_PL ships ISO8859-2 only.
;; A UTF-8 copy is maintained at ~/.local/share/hunspell/ by
;; home.activation.hunspellUtf8 (users/marcin/base/packages.nix).
;;
;; DICPATH alone is not enough: ispell-phaf resolves dictionary paths
;; from `ispell-hunspell-dict-paths-alist', which is built by scanning
;; known system directories — ~/.local/share/hunspell is NOT in that
;; scan.  We therefore add both dictionaries explicitly BEFORE calling
;; ispell-set-spellchecker-params, which reads the alist.

(with-eval-after-load 'ispell
  (let* ((user-dict (expand-file-name "~/.local/share/hunspell"))
         (login     (user-login-name))
         (nix-path  (format "/etc/profiles/per-user/%s/share/hunspell" login)))

    ;; DICPATH: hunspell subprocess uses this to locate .aff/.dic at runtime
    (setenv "DICPATH" (concat user-dict ":" nix-path))

    ;; pl_PL — UTF-8 copy lives in user-dict (written by home.activation)
    (when (file-exists-p (expand-file-name "pl_PL.aff" user-dict))
      (add-to-list 'ispell-hunspell-dict-paths-alist
                   (list "pl_PL"
                         (expand-file-name "pl_PL.aff" user-dict))))

    ;; en_GB-large — comes directly from the nix profile (already UTF-8)
    (when (file-exists-p (expand-file-name "en_GB.aff" nix-path))
      (add-to-list 'ispell-hunspell-dict-paths-alist
                   (list "en_GB-large"
                         (expand-file-name "en_GB.aff" nix-path)))))

  ;; Rebuild internal ispell state with the updated alist
  (ispell-set-spellchecker-params)
  (ispell-hunspell-add-multi-dic "pl_PL,en_GB-large"))

;; ============================================================
;; E6 — SUPPRESS "Save .hunspell_personal?" ON QUIT
;; ============================================================

(defun my/spell--personal-dict-buffer-p ()
  "Return t if current buffer is the hunspell personal dictionary."
  (when (buffer-file-name)
    (string= (file-truename (buffer-file-name))
             (file-truename ispell-personal-dictionary))))

(add-to-list 'save-some-buffers-action-alist
             (list #'my/spell--personal-dict-buffer-p
                   (lambda (_buf) (ignore))
                   "skip hunspell personal dictionary"))

;; ============================================================
;; DESKTOP-RESTORE GUARD
;; ============================================================
;; During desktop-restore Emacs opens all saved .org buffers.
;; Each fires org-mode-hook -> flyspell-mode -> flyspell-mode-on
;; -> Hunspell starts N times -> 17-second hang.
;;
;; Solution: while this flag is t, the flyspell-mode advice below
;; enables the mode variable but skips flyspell-mode-on (which is
;; the function that actually starts the subprocess).  After
;; desktop-restore completes, 15-workspace.el clears the flag and
;; calls flyspell-mode-on on all open buffers.

(defvar my/flyspell-desktop-restoring t
  "Non-nil during desktop-restore to prevent Hunspell from starting.
Set to nil by `my/flyspell--recheck-all-buffers' after restore.")

(defun my/flyspell--block-during-restore (orig-fun &rest args)
  "Advice around `flyspell-mode'.
When `my/flyspell-desktop-restoring' is non-nil and ARG enables
the mode (arg >= 0 or nil), enable the mode variable but skip
`flyspell-mode-on' to prevent Hunspell from starting during
desktop-restore.  Pass through normally in all other cases."
  (let ((arg (car args)))
    (if (and my/flyspell-desktop-restoring
             (or (null arg) (> arg 0)))
        ;; Enable mode flag silently, skip the subprocess start.
        (setq flyspell-mode t)
      ;; Normal path: call the real flyspell-mode.
      (apply orig-fun args))))

(advice-add 'flyspell-mode :around #'my/flyspell--block-during-restore)

(defun my/flyspell--recheck-all-buffers ()
  "Clear the desktop-restore guard and activate flyspell on all live buffers.
Called from `desktop-after-read-hook' in 15-workspace.el.
This is the first moment Hunspell is allowed to start."
  (setq my/flyspell-desktop-restoring nil)
  ;; Remove the blocking advice — no longer needed after first restore.
  (advice-remove 'flyspell-mode #'my/flyspell--block-during-restore)
  ;; Re-run flyspell-mode-on for every buffer that had flyspell enabled
  ;; during restore (mode var is t but subprocess never started).
  (dolist (buf (buffer-list))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (and flyspell-mode
                   (derived-mode-p 'text-mode 'org-mode))
          ;; flyspell-mode-on starts the process and checks the buffer.
          (flyspell-mode-on))))))

;; ============================================================
;; SAFE HELPER: Check if process is alive
;; ============================================================

(defun my/spell-check-can-run-p ()
  "Return t if flyspell-mode is on AND Hunspell process is running."
  (and flyspell-mode
       (boundp 'ispell-process)
       (process-live-p ispell-process)))

;; ============================================================
;; PROCESS STARTER: Ensure Hunspell is running and ready
;; ============================================================

(defun my/spell-ensure-process ()
  "Ensure Hunspell is running.  No-op in steady state.
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
;; SPELL CORRECTION - Returns to start position
;; ============================================================

(defun my/spell-correct-previous ()
  "Jump to previous spelling error, show correction menu, return to start."
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
  "Add previous misspelled word to personal dictionary, return to start."
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
;; ENSURE FLYSPELL STAYS ON (priority 100 — runs last)
;; ============================================================

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
