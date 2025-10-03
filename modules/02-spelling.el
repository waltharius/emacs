;;; 02-spelling.el --- Spell checking and grammar checking  -*- lexical-binding: t; -*-
;;
;; Description: Hunspell (pl_PL + en_GB UTF-8) dla pisowni
;;              LanguageTool offline dla gramatyki
;;              Flyspell (LAZY, manual scan only)
;;
;;; Code:

;; --- Hunspell: sprawdzanie pisowni pl_PL + en_GB (UTF-8) ---
(require 'ispell)

;; FORCE UTF-8 encoding dla Hunspell
(setq ispell-program-name "hunspell")
(setq ispell-local-dictionary-alist
      '(("pl_PL" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "pl_PL") nil utf-8)
        ("en_GB" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
         ("-d" "en_GB") nil utf-8)))

(setq ispell-dictionary "pl_PL,en_GB")
(setq ispell-personal-dictionary (expand-file-name "~/.hunspell_personal"))
(setenv "HUNSPELL_PERSONAL" ispell-personal-dictionary)

;; Upewnij się że personal dictionary ma UTF-8 header
(unless (file-exists-p ispell-personal-dictionary)
  (with-temp-buffer 
    (insert "personal_ws-1.1 pl_PL 0 utf-8\n")
    (write-file ispell-personal-dictionary)))
(setq ispell-silently-savep t)

;; Inicjalizuj Hunspell z UTF-8
(with-eval-after-load 'ispell
  (ispell-set-spellchecker-params)
  (ispell-hunspell-add-multi-dic "pl_PL,en_GB"))

;; --- Automatyczne odświeżanie po zapisie słownika ---
(defun my/ispell-refresh-after-save (&rest _)
  "Odśwież proces Hunspell po zapisie słownika."
  (when (process-live-p ispell-process) 
    (ispell-kill-ispell)))
(advice-add 'ispell-pdict-save :after #'my/ispell-refresh-after-save)

;; --- Funkcja: dodaj słowo pod kursorem ---
(defun my/spell-add-word-here ()
  "Dodaj słowo pod kursorem do osobistego słownika Hunspell."
  (interactive)
  (let* ((w (thing-at-point 'word t))
         (pd (expand-file-name ispell-personal-dictionary)))
    (when (and w (string-match-p "\\S-" w))
      (with-temp-buffer
        (insert (downcase w) "\n")
        (append-to-file (point-min) (point-max) pd))
      (when (process-live-p ispell-process) (ispell-kill-ispell))
      (message "Dodano: %s -> %s" w pd))))

;; --- Funkcja: poprzedni błąd pisowni ---
(defun my/flyspell-goto-previous-error (arg)
  "Idź do poprzedniego błędu pisowni (ARG razy)."
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

;; --- Flyspell: podświetlanie błędów (LAZY - tylko manual!) ---
(use-package flyspell
  :ensure nil
  :hook ((text-mode . flyspell-mode)
         (org-mode  . flyspell-mode))
  :config
  ;; WYŁĄCZ automatyczne skanowanie
  (setq flyspell-issue-message-flag nil)
  (setq flyspell-issue-welcome-flag nil)
  
  ;; Manual scan
  (global-set-key (kbd "C-c f b") 'flyspell-buffer))

;; --- Flyspell-correct: poprawianie błędów ---
(use-package flyspell-correct
  :ensure t
  :after flyspell)

(use-package flyspell-correct-ivy
  :ensure t
  :after flyspell-correct)

;; --- LanguageTool: gramatyka offline ---
(use-package langtool
  :ensure t
  :config
  (setq langtool-language-tool-jar 
        (expand-file-name "~/LanguageTool/languagetool-commandline.jar"))
  (setq langtool-default-language "pl")
  (setq langtool-mother-tongue "pl"))

(provide '02-spelling)
;;; 02-spelling.el ends here
