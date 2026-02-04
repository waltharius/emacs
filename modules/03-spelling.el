;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) for spelling
;;              Flyspell for highlighting errors
;;              SMART correction with auto-return to original position
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

;; --- Function: add word under cursor ---
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
      (message "Added: %s -> %s" w pd))))

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
    ;; Temporarily enable, check, then disable
    (flyspell-mode 1)
    (flyspell-buffer)
    (message "Buffer checked (flyspell remains active - toggle with my/toggle-flyspell)")))

;; --- Flyspell: highlighting errors ---
(use-package flyspell
  :ensure nil
  :hook ((text-mode . flyspell-mode)
         (org-mode  . flyspell-mode))
  :config
  ;; Keep flyspell active and responsive
  (setq flyspell-issue-message-flag nil)
  (setq flyspell-issue-welcome-flag nil)
  
  ;; Don't auto-disable flyspell
  (setq flyspell-persistent t))

;; --- Flyspell-correct: correcting errors ---
(use-package flyspell-correct
  :ensure t
  :after flyspell)

(use-package flyspell-correct-ivy
  :ensure t
  :after flyspell-correct)

;; ============================================================
;; KEYBINDINGS (now mostly in transient menu)
;; ============================================================

;; Legacy keybinding for buffer check
(global-set-key (kbd "C-c f b") 'my/spell-check-buffer)

(provide '03-spelling)
;;; 03-spelling.el ends here
