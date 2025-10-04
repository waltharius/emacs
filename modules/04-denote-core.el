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
  (denote-known-keywords '("zettel" "osoba" "projekt" "zasób"))
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
    "Nie zmieniaj signature na lowercase - zachowaj oryginał."
    (if (and signature (not (string-empty-p signature)))
        (replace-regexp-in-string "[^A-Za-z0-9.]" "" signature)
      signature))
  
  (advice-add 'denote-sluggify :around
              (lambda (orig-fun component str &rest args)
                (if (eq component 'signature)
                    (my/denote-signature-no-lowercase str)
                  (apply orig-fun component str args)))))

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

(provide '04-denote-core)
;;; 04-denote-core.el ends here
