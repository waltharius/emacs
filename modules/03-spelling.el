;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) for spelling
;;              Flyspell for highlighting errors
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

;; --- Function: previous spelling error ---
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

;; --- Flyspell: highlighting errors ---
(use-package flyspell
  :ensure nil
  :hook ((text-mode . flyspell-mode)
         (org-mode  . flyspell-mode))
  :config
  ;; Disable automatic scanning (manual only)
  (setq flyspell-issue-message-flag nil)
  (setq flyspell-issue-welcome-flag nil)
  
  ;; Manual scan
  (global-set-key (kbd "C-c f b") 'flyspell-buffer))

;; --- Flyspell-correct: correcting errors ---
(use-package flyspell-correct
  :ensure t
  :after flyspell)

(use-package flyspell-correct-ivy
  :ensure t
  :after flyspell-correct)

(provide '03-spelling)
;;; 03-spelling.el ends here
