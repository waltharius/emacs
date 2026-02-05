;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) for spelling
;;              Flyspell for highlighting errors
;;              SMART correction with auto-return position
;;              PERSISTENT overlays (don't disappear!)
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
  (when (process-live-p ispell-process) 
    (ispell-kill-ispell)))
(advice-add 'ispell-pdict-save :after #'my/ispell-refresh-after-save)

;; --- Function: add word at point to dictionary ---
(defun my/spell-add-word-here ()
  "Add word under cursor to personal Hunspell dictionary."
  (interactive)
  (let* ((w (thing-at-point 'word t))
         (pd (expand-file-name ispell-personal-dictionary)))
    (when (and w (string-match-p "\\S-" w))
      (with-temp-buffer
        (insert (downcase w) "\n")
        (append-to-file (point-min) (point-max) pd))
      (when (process-live-p ispell-process) (ispell-kill-ispell))
      ;; Remove flyspell overlay
      (let ((overlays (overlays-at (point))))
        (dolist (o overlays)
          (when (flyspell-overlay-p o)
            (delete-overlay o))))
      (message "✓ Added: %s -> dictionary" w))))

;; --- Function: previous spelling error (jump only) ---
(defun my/flyspell-goto-previous-error (arg)
  "Go to previous spelling error (ARG times)."
  (interactive "p")
  (while (> arg 0)
    (let ((pos (point)) (min (point-min)))
      (when (and (eq (current-buffer) flyspell-old-buffer-error)
                 (eq pos flyspell-old-pos-error))
        (if (= flyspell-old-pos-error min)
            (progn (message "Restarting from end of buffer") (goto-char (point-max)))
          (backward-word 1))
        (setq pos (point)))
      (while (and (> pos min)
                  (not (seq-some #'flyspell-overlay-p (overlays-at pos))))
        (backward-word 1)
        (setq pos (point)))
      (setq flyspell-old-pos-error pos
            flyspell-old-buffer-error (current-buffer))
      (goto-char pos)
      (setq arg (1- arg))
      (when (> pos min) (forward-word)))
  (recenter)))

;; ============================================================
;; SMART SPELL CORRECTION (with auto-return position)
;; ============================================================

(defvar my/spell-return-position nil
  "Store position to return after spell correction.")

(defun my/spell-correct-previous ()
  "Jump to previous spelling error, correct it, and return to original position.
  
  Workflow:
  1. Saves current position
  2. Jumps to previous spelling error
  3. Shows correction menu (or allows adding to dictionary)
  4. After correction/adding word, returns cursor to saved position
  
  This is the main spell-checking function you'll use."
  (interactive)
  
  ;; Save current position
  (setq my/spell-return-position (point-marker))
  
  ;; Find previous error
  (let ((error-found nil)
        (start-pos (point)))
    
    ;; Search backward for spelling error
    (save-excursion
      (let ((pos (point)) (min (point-min)))
        (backward-word 1)
        (while (and (> (point) min)
                    (not (seq-some #'flyspell-overlay-p (overlays-at (point)))))
          (backward-word 1))
        (when (seq-some #'flyspell-overlay-p (overlays-at (point)))
          (setq error-found (point)))))
    
    (if error-found
        (progn
          ;; Jump to error
          (goto-char error-found)
          (recenter)
          
          ;; Show corrections and let user choose
          ;; After correction, advice will return to saved position
          (flyspell-correct-wrapper))
      
      ;; No error found
      (message "No spelling errors found backward from cursor")
      (setq my/spell-return-position nil))))

;; ============================================================
;; ADD WORD TO DICTIONARY (with auto-return)
;; ============================================================

(defun my/spell-add-previous-to-dict ()
  "Jump to previous spelling error, add it to dictionary, and return.
  
  This is faster than correction menu when you know the word is correct."
  (interactive)
  
  ;; Save current position
  (setq my/spell-return-position (point-marker))
  
  ;; Find previous error
  (let ((error-found nil))
    (save-excursion
      (let ((pos (point)) (min (point-min)))
        (backward-word 1)
        (while (and (> (point) min)
                    (not (seq-some #'flyspell-overlay-p (overlays-at (point)))))
          (backward-word 1))
        (when (seq-some #'flyspell-overlay-p (overlays-at (point)))
          (setq error-found (point)))))
    
    (if error-found
        (progn
          ;; Jump to error
          (goto-char error-found)
          ;; Add word
          (my/spell-add-word-here)
          ;; Return to original position
          (when (and my/spell-return-position
                     (marker-position my/spell-return-position))
            (goto-char my/spell-return-position)
            (setq my/spell-return-position nil)))
      
      (message "No spelling errors found backward from cursor")
      (setq my/spell-return-position nil))))

;; Advice to return to original position after correction
(defun my/spell-return-after-correction (&rest _)
  "Return to saved position after spell correction."
  (when (and my/spell-return-position
             (marker-position my/spell-return-position))
    (goto-char my/spell-return-position)
    (setq my/spell-return-position nil)
    (message "Returned to original position")))

;; Hook the return function to flyspell-correct actions
(advice-add 'flyspell-correct-wrapper :after #'my/spell-return-after-correction)

;; ============================================================
;; TOGGLE FLYSPELL MODE
;; ============================================================

(defun my/toggle-flyspell ()
  "Toggle flyspell-mode on/off.
  When enabled, it stays active until you toggle it off."
  (interactive)
  (if flyspell-mode
      (progn
        (flyspell-mode -1)
        (message "✗ Spell-checking OFF"))
    (progn
      (flyspell-mode 1)
      (message "✓ Spell-checking ON - will stay active"))))

;; ============================================================
;; FORCE CHECK BUFFER
;; ============================================================

(defun my/spell-check-buffer ()
  "Force spell-check entire buffer (even if flyspell is off)."
  (interactive)
  (if flyspell-mode
      (flyspell-buffer)
    ;; Temporarily enable, check, then keep enabled
    (flyspell-mode 1)
    (flyspell-buffer)
    (message "Buffer checked (flyspell is now active)")))

;; ============================================================
;; FLYSPELL CONFIGURATION - PREVENT OVERLAYS FROM DISAPPEARING
;; ============================================================

(use-package flyspell
  :ensure nil
  :hook ((text-mode . flyspell-mode)
         (org-mode  . flyspell-mode))
  :config
  ;; Reduce verbosity
  (setq flyspell-issue-message-flag nil)
  (setq flyspell-issue-welcome-flag nil)
  
  ;; Check words as you type (post-command)
  (setq flyspell-delay 1)  ; Check after 1 second of idle
  
  ;; PREVENT OVERLAYS FROM DISAPPEARING
  ;; Don't delete overlays when buffer loses focus
  (setq flyspell-delete-overlays nil)
  
  ;; Aggressive mode: check more frequently
  (setq flyspell-consider-dash-as-word-delimiter-flag t)
  
  ;; Keep checking in background
  (add-hook 'flyspell-mode-hook
            (lambda ()
              (when flyspell-mode
                ;; Re-check buffer when returning to window
                (add-hook 'window-configuration-change-hook
                          'flyspell-buffer nil t)))))

;; ============================================================
;; ENSURE FLYSPELL STAYS ON (run AFTER other hooks)
;; ============================================================

;; Add a late-priority hook to ensure flyspell stays enabled
;; This runs AFTER org-indent and other hooks (priority 100)
(add-hook 'org-mode-hook
          (lambda ()
            (unless flyspell-mode
              (flyspell-mode 1)))
          100)  ; Run VERY late (after indent hook at 90)

(add-hook 'text-mode-hook
          (lambda ()
            (unless flyspell-mode
              (flyspell-mode 1)))
          100)

;; ============================================================
;; PREVENT FLYSPELL FROM CLEARING ON FOCUS LOSS
;; ============================================================

;; Advice to prevent flyspell-delete-all-overlays from running
(defun my/flyspell-prevent-overlay-deletion (orig-fun &rest args)
  "Prevent flyspell from deleting overlays unnecessarily."
  ;; Only allow deletion when explicitly requested (mode disable)
  (when (and flyspell-mode (called-interactively-p 'any))
    (apply orig-fun args)))

(advice-add 'flyspell-delete-all-overlays :around #'my/flyspell-prevent-overlay-deletion)

;; Auto-recheck visible portion after focus return
(add-hook 'focus-in-hook
          (lambda ()
            (when (and flyspell-mode (eq major-mode 'org-mode))
              ;; Only check visible portion (faster!)
              (flyspell-region (window-start) (window-end)))))

;; --- Flyspell-correct: correcting errors ---
(use-package flyspell-correct
  :ensure t
  :after flyspell
  :config
  ;; Add "Save to dictionary" action
  (setq flyspell-correct-interface #'flyspell-correct-ivy)
  
  ;; Configure actions to include save option
  (define-key flyspell-mode-map (kbd "C-;") 'flyspell-correct-wrapper)
  
  ;; Add save action to corrections
  (defun my/flyspell-correct-save-word ()
    "Action to save word to dictionary from flyspell-correct."
    (my/spell-add-word-here)
    (cons 'save nil))
  
  ;; Make save action available
  (setq flyspell-correct-interface 'flyspell-correct-ivy))

(use-package flyspell-correct-ivy
  :ensure t
  :after flyspell-correct
  :config
  ;; Show save to dictionary option in ivy
  (setq flyspell-correct-ivy-map
        (let ((map (make-sparse-keymap)))
          (define-key map (kbd "C-s") 'flyspell-correct-save)
          map)))

;; ============================================================
;; KEYBINDINGS (now mostly in transient menu)
;; ============================================================

;; Legacy keybinding for buffer check
(global-set-key (kbd "C-c f b") 'my/spell-check-buffer)

;; ============================================================
;; HOW IT WORKS NOW
;; ============================================================
;;
;; PERSISTENCE STRATEGY:
;; 1. Disabled flyspell-delete-overlays (prevents auto-clearing)
;; 2. Added advice to prevent overlay deletion on focus loss
;; 3. Auto-recheck visible portion when returning to Emacs
;; 4. Check delay reduced to 1 second
;; 5. LATE HOOKS (priority 100) ensure flyspell stays on after other hooks
;;
;; RESULT: Red underlines stay visible across window switches!
;; Flyspell stays enabled even after org-indent and other hooks run.
;; Only the visible portion rechecks (fast), overlays persist.

(provide '03-spelling)
;;; 03-spelling.el ends here
