;;; 04-denote-core.el --- Core Denote configuration  -*- lexical-binding: t; -*-
;;
;; Description: Pakiet Denote, Consult-denote, fix signature (zachowanie kropek),
;;              auto-fill dla notatek
;;
;;; Code:


;; --- Denote: prosty system notatek ---
(use-package denote
  :ensure t
  :custom
  (denote-directory my/notes-dir)
  (denote-known-keywords my/denote-keywords)
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
             (string-match-p (expand-file-name my/notes-dir) 
                             (buffer-file-name)))
    (auto-fill-mode 1)
    (setq fill-column my/fill-column)

(add-hook 'find-file-hook 'my/denote-auto-fill-setup)
(add-hook 'org-mode-hook 'my/denote-auto-fill-setup)))

(setq org-list-allow-alphabetical t)
(setq org-list-demote-modify-bullet
      '(("+" . "-") ("-" . "+") ("*" . "-") ("1." . "a.")))

;; --- Kolumny do wyświetlenia w wyszukiwaniu po PROPERTIES ---
(setq org-columns-default-format 
      "%40ITEM(Tytuł) %10STATUS %8YEAR %6PAGES %10PROJECT")

;; ============================================================
;; ORG EXPORT - OSOBNE FOLDERY
;; ============================================================

;; HTML export → ~/notes/html/
(setq org-html-publishing-directory (expand-file-name "html" my/notes-dir))

;; LaTeX/PDF artifacts → ~/notes/.latex-tmp/
(setq org-latex-logfiles-extensions 
      '("aux" "bcf" "blg" "fdb_latexmk" "fls" "figlist" 
        "idx" "log" "nav" "out" "ptc" "run.xml" "snm" 
        "toc" "vrb" "xdv" "tex"))

;; Temporary LaTeX files → ~/notes/.latex-tmp/
(defun my/org-latex-export-cleanup ()
  "Przenieś LaTeX artifacts do .latex-tmp/."
  (let* ((base-name (file-name-sans-extension (buffer-file-name)))
         (latex-tmp-dir (expand-file-name ".latex-tmp" my/notes-dir)))
    ;; Stwórz folder jeśli nie istnieje
    (unless (file-directory-p latex-tmp-dir)
      (make-directory latex-tmp-dir t))
    ;; Przenieś LaTeX artifacts
    (dolist (ext org-latex-logfiles-extensions)
      (let ((artifact-file (concat base-name "." ext)))
        (when (file-exists-p artifact-file)
          (rename-file artifact-file 
                       (expand-file-name (file-name-nondirectory artifact-file) latex-tmp-dir)
                       t))))))

;; Auto-cleanup po eksporcie
(add-hook 'org-export-before-processing-hook 'my/org-latex-export-cleanup)

;; Ensure HTML export directory exists
(unless (file-directory-p org-html-publishing-directory)
  (make-directory org-html-publishing-directory t))

(provide '04-denote-core)
;;; 04-denote-core.el ends here
