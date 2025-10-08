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
;; ORG HTML EXPORT - DEDICATED FOLDER + AUTO-CLEANUP
;; ============================================================

;; Create html/ folder if not exists
(let ((html-dir (expand-file-name "html" my/notes-dir)))
  (unless (file-directory-p html-dir)
    (make-directory html-dir t)))

;; Advice: Intercept HTML export and move file BEFORE browser opens
(defun my/org-html-export-advice (orig-fun &rest args)
  "Przechwyt HTML export - przenieś do ~/notes/html/ + cleanup LaTeX."
  (let* ((result (apply orig-fun args))
         (html-file result)
         (base-name (file-name-sans-extension (buffer-file-name)))
         (html-dir (expand-file-name "html" my/notes-dir)))
    ;; 1. Cleanup LaTeX artifacts
    (dolist (ext '("aux" "log" "tex" "fdb_latexmk" "fls" "out" "toc" "nav" "snm"))
      (let ((artifact (concat base-name "." ext)))
        (when (file-exists-p artifact)
          (delete-file artifact))))
    ;; 2. Move HTML to dedicated folder (if exists)
    (when (and html-file (stringp html-file) (file-exists-p html-file))
      (let ((target-html (expand-file-name (file-name-nondirectory html-file) html-dir)))
        (rename-file html-file target-html t)
        (message "✅ HTML: %s" target-html)
        ;; Return new path (important for browser open!)
        target-html))))

;; Apply advice to BOTH export functions
(advice-add 'org-html-export-to-html :around #'my/org-html-export-advice)
(advice-add 'org-html-export-to-html-and-open :around #'my/org-html-export-advice)

(provide '04-denote-core)
;;; 04-denote-core.el ends here
