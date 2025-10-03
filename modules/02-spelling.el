;;; 02-spelling.el --- Spell checking and grammar checking
;;
;; Description: Hunspell (pl_PL + en_GB) dla pisowni
;;              LanguageTool offline dla gramatyki
;;              Flyspell + custom funkcje
;;
;;; Code:

;; --- Hunspell: sprawdzanie pisowni pl_PL + en_GB ---
(require 'ispell)
(setq ispell-program-name "hunspell")
(setq ispell-personal-dictionary (expand-file-name "~/.hunspell_personal"))
(setenv "HUNSPELL_PERSONAL" (expand-file-name "~/.hunspell_personal"))
(setq ispell-dictionary "pl_PL,en_GB")
(ispell-set-spellchecker-params)
(ispell-hunspell-add-multi-dic "pl_PL,en_GB")

;; Utwórz słownik jeśli nie istnieje
(unless (file-exists-p ispell-personal-dictionary)
  (with-temp-buffer (write-file ispell-personal-dictionary)))
(setq ispell-silently-savep t)

;; --- Automatyczne odświeżanie po zapisie słownika ---
(defun my/ispell-refresh-after-save (&rest _)
  "Odśwież proces Hunspell po zapisie słownika."
  (when (process-live-p ispell-process) (ispell-kill-ispell))
  (when (bound-and-true-p flyspell-mode) (flyspell-buffer)))
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
      (when (bound-and-true-p flyspell-mode) (flyspell-buffer))
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
      (when (> pos min) (forward-word))))
  (recenter))

;; --- Flyspell: podświetlanie błędów (LAZY, BEZ TIMERÓW! Bez AUTO-SCAN!) ---
(use-package flyspell
  :ensure nil
  :hook ((text-mode . flyspell-mode)
         (org-mode  . flyspell-mode))
  :config
  ;; WYŁĄCZ automatyczne skanowanie przy starcie!
  ;; (brak flyspell-buffer w hookach)
  
  ;; Manual scan dla dużych plików (C-c f b)
  (global-set-key (kbd "C-c f b") 'flyspell-buffer)
  
  ;; Opcjonalnie: lazy check TYLKO przy zapisie pliku
  (defun my/flyspell-buffer-on-save ()
    "Skanuj bufor przy zapisie (tylko dla małych plików <20k)."
    (when (and (derived-mode-p 'text-mode 'org-mode)
               (< (buffer-size) 20000))
      (flyspell-buffer)))
  
  ;; Włącz tylko dla małych plików przy zapisie
  ;; (add-hook 'after-save-hook 'my/flyspell-buffer-on-save)
  )

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
