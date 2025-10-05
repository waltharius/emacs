;;; 04-denote-core.el --- Core Denote configuration  -*- lexical-binding: t; -*-
;;
;; Description: Pakiet Denote, Consult-denote, fix signature (zachowanie kropek),
;;              auto-fill dla notatek
;;
;;; Code:

;; --- Zmienna globalna: katalog notatek ---
(defvar my-notes-dir (expand-file-name "~/notes/")
  "Katalog dla notatek Denote.")

;; --- Denote: prosty system notatek ---
(use-package denote
  :ensure t
  :custom
  (denote-directory my-notes-dir)
  (denote-known-keywords '("zettel" "osoba" "projekt"))
  (denote-infer-keywords t)
  (denote-sort-keywords t)
  (denote-file-type nil)
  (denote-prompts '(title keywords)))

;; --- Consult-Denote: wyszukiwanie z podglądem ---
(use-package consult-denote
  :ensure t
  :after denote
  :demand t
  :config
  (consult-denote-mode 1))

;; --- FIX: Zachowaj format signature (kropki + wielkie litery) ---
(with-eval-after-load 'denote
  (defun my/denote-signature-no-lowercase (signature)
    "Nie zmieniaj signature na lowercase - zachowaj oryginał.
Zachowaj litery, cyfry i kropki."
    signature)  ; Zwróć bez zmian - Denote doda == automatycznie
  
  (advice-add 'denote-sluggify-signature :override
              #'my/denote-signature-no-lowercase))

;; --- Wyłącz automatyczne wcięcia w org-mode ---
(add-hook 'org-mode-hook
          (lambda ()
            (electric-indent-local-mode -1)
            (setq-local electric-indent-chars nil)))

;; --- Auto-fill dla wszystkich notatek Denote ---
(defun my/denote-auto-fill-setup ()
  "Włącz auto-fill-mode dla notatek Denote (wrap na 80 znaków)."
  (when (and (buffer-file-name)
             (string-match-p (expand-file-name my-notes-dir) 
                             (buffer-file-name)))
    (auto-fill-mode 1)
    (setq fill-column 84)))

(add-hook 'find-file-hook 'my/denote-auto-fill-setup)
(add-hook 'org-mode-hook 'my/denote-auto-fill-setup)

;; --- Org-mode: wyłącz auto-indent, włącz lepsze listy ---
(add-hook 'org-mode-hook
          (lambda ()
            (electric-indent-local-mode -1)
            (setq-local electric-indent-chars nil)))

(setq org-list-allow-alphabetical t)
(setq org-list-demote-modify-bullet
      '(("+" . "-") ("-" . "+") ("*" . "-") ("1." . "a.")))

;; --- Kolumny do wyświetlenia w wyszukiwaniu po PROPERTIES ---
(setq org-columns-default-format 
      "%40ITEM(Tytuł) %10STATUS %8YEAR %6PAGES %10PROJECT")

(provide '04-denote-core)
;;; 04-denote-core.el ends here
