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

;; --- Transliteracja polskich znaków (slug-safe) ---
(defun my/transliterate-polish (str)
  "Zamień polskie znaki na ASCII."
  (when (stringp str)
    (let ((replacements '(("ą" . "a") ("ć" . "c") ("ę" . "e")
                         ("ł" . "l") ("ń" . "n") ("ó" . "o")
                         ("ś" . "s") ("ź" . "z") ("ż" . "z")
                         ("Ą" . "A") ("Ć" . "C") ("Ę" . "E")
                         ("Ł" . "L") ("Ń" . "N") ("Ó" . "O")
                         ("Ś" . "S") ("Ź" . "Z") ("Ż" . "Z"))))
      (dolist (pair replacements str)
        (setq str (replace-regexp-in-string (car pair) (cdr pair) str))))))

(with-eval-after-load 'denote
  (advice-add 'denote-sluggify-title :filter-args
              (lambda (args)
                (list (my/transliterate-polish (car args)))))
  
  (advice-add 'denote-sluggify-keyword :filter-args
              (lambda (args)
                (list (my/transliterate-polish (car args))))))

;; --- FIX: Zachowaj format signature (kropki + wielkie litery) ---
(with-eval-after-load 'denote
  (defun my/denote-signature-no-lowercase (signature)
    "Nie zmieniaj signature na lowercase - zachowaj oryginał."
    (if (and signature 
             (not (string-empty-p signature))
             (not (string-match-p "^=+$" signature)))  ; Ignoruj "=="
        (replace-regexp-in-string "[^A-Za-z0-9.]" "" signature)
      ""))  ; Zwróć pusty string jeśli signature jest pusty!
  
  (advice-add 'denote-sluggify :around
              (lambda (orig-fun component str &rest args)
                (if (and (eq component 'signature)
                         str
                         (not (string-empty-p str))
                         (not (string-match-p "^=+$" str)))  ; Ignoruj "=="
                    (my/denote-signature-no-lowercase str)
                  (apply orig-fun component str args)))))

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

(provide '04-denote-core)
;;; 04-denote-core.el ends here
