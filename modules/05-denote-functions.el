;;; 05-denote-functions.el --- Custom Denote functions  -*- lexical-binding: t; -*-
;;
;; Description: Journal, Journal z datą, Zettelkasten, Osoba,
;;              Shortcuts, Base, pomocnicze funkcje
;;
;;; Code:

;; --- FUNKCJA: Journal (codziennie) ---
(defun my/denote-journal ()
  "Utwórz lub otwórz journal dla dzisiejszego dnia."
  (interactive)
  (let* ((today (format-time-string "%Y-%m-%d"))
         (time-now (format-time-string "%H:%M"))
         (journal-pattern (concat "--" today "-journal"))
         (existing-journal nil))
    
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (when (string-match-p journal-pattern (file-name-nondirectory file))
        (setq existing-journal file)))
    
    (if existing-journal
        (progn
          (find-file existing-journal)
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (format "\n* %s\n\n" time-now))
          (backward-char 1)
          (message "Dodano wpis do journala"))
      
      (let* ((id (format-time-string "%Y%m%dT%H%M%S"))
             (slug (replace-regexp-in-string 
                    "[^[:alnum:]]+" "-" 
                    (downcase (format "%s-journal" today))))
             (filename (format "%s--%s__journal.org" id slug))
             (filepath (expand-file-name filename my-notes-dir)))
        
        (find-file filepath)
        (insert (format "#+title:      %s Journal\n" today))
        (insert (format "#+date:       %s\n" 
                        (format-time-string "[%Y-%m-%d %a %H:%M]")))
        (insert "#+filetags:   :journal:\n")
        (insert (format "#+identifier: %s\n\n" id))
        (insert (format "* Książenice (%s)\n\n" time-now))
        (backward-char 1)
        (message "Utworzono nowy journal")))))

;; --- FUNKCJA: Journal z datą (migracja) ---
(defun my/denote-journal-date ()
  "Utwórz journal z wybraną datą (dla migracji starych wpisów)."
  (interactive)
  (let* ((date-input (org-read-date nil nil nil "Data wpisu: "))
         (parsed-time (org-parse-time-string date-input))
         (date-formatted (format-time-string "%Y-%m-%d" 
                                              (apply 'encode-time parsed-time)))
         (title (read-string "Tytuł (Enter = domyślny): " 
                             (format "%s Journal" date-formatted)))
         (keywords-input (read-string "Tagi (Enter = 'journal'): " "journal"))
         (keywords (split-string keywords-input))
         (time-now (format-time-string "%H:%M")))
    
    (let* ((id (format-time-string "%Y%m%dT%H%M%S" (apply 'encode-time parsed-time)))
           (slug (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase title)))
           (keywords-slug (mapconcat (lambda (k) 
                                       (replace-regexp-in-string 
                                        "[^[:alnum:]]+" "-" (downcase k))) 
                                     keywords "_"))
           (filename (format "%s--%s__%s.org" id slug keywords-slug))
           (filepath (expand-file-name filename my-notes-dir)))
      
      (find-file filepath)
      (insert (format "#+title:      %s\n" title))
      (insert (format "#+date:       %s\n" 
                      (format-time-string "[%Y-%m-%d %a %H:%M]" 
                                          (apply 'encode-time parsed-time))))
      (insert (format "#+filetags:   :%s:\n" (mapconcat 'identity keywords ":")))
      (insert (format "#+identifier: %s\n\n" id))
      (insert (format "* Książenice (%s)\n\n" time-now))
      (insert "* Powiązane notatki\n")
      (goto-char (point-min))
      (search-forward "* Książenice")
      (end-of-line)
      (forward-line 1)
      (message "Utworzono journal z datą %s" date-formatted))))

;; --- FUNKCJA: Zettelkasten ---
(defun my/denote-zettel ()
  "Utwórz notatkę Zettelkasten z signature."
  (interactive)
  (let* ((signature (read-string "Signature (np. N1.1a): "))
         (title (read-string "Tytuł: "))
         (keywords (split-string (read-string "Tagi: " "zettel"))))
    
    (let* ((id (format-time-string "%Y%m%dT%H%M%S"))
           (slug (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase title)))
           (keywords-slug (mapconcat (lambda (k) 
                                       (replace-regexp-in-string 
                                        "[^[:alnum:]]+" "-" (downcase k))) 
                                     keywords "_"))
           (filename (format "%s==%s--%s__%s.org" id signature slug keywords-slug))
           (filepath (expand-file-name filename my-notes-dir)))
      
      (find-file filepath)
      (insert (format "#+title:      %s\n" title))
      (insert (format "#+date:       %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]")))
      (insert (format "#+filetags:   :%s:\n" (mapconcat 'identity keywords ":")))
      (insert (format "#+identifier: %s\n" id))
      (insert (format "#+signature:  %s\n\n" signature))
      (insert "* Główna teza\n\n")
      (insert "* Argumenty i dowody\n\n")
      (insert "* Powiązane idee\n\n")
      (insert "* Bibliografia\n\n")
      (goto-char (point-min))
      (search-forward "* Główna teza")
      (forward-line 1)
      (message "Utworzono Zettel: %s" signature))))

;; --- FUNKCJA: Osoba ---
(defun my/denote-osoba ()
  "Utwórz notatkę o osobie z properties."
  (interactive)
  (let* ((nazwisko (read-string "Nazwisko: "))
         (imie (read-string "Imię: "))
         (tytul (format "%s %s" imie nazwisko)))
    
    (let* ((id (format-time-string "%Y%m%dT%H%M%S"))
           (slug (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase tytul)))
           (filename (format "%s--%s__osoba.org" id slug))
           (filepath (expand-file-name filename my-notes-dir)))
      
      (find-file filepath)
      (insert (format "#+title:      %s\n" tytul))
      (insert (format "#+date:       %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]")))
      (insert "#+filetags:   :osoba:\n")
      (insert (format "#+identifier: %s\n\n" id))
      (insert ":PROPERTIES:\n")
      (insert (format ":IMIE: %s\n" imie))
      (insert (format ":NAZWISKO: %s\n" nazwisko))
      (insert (format ":PLEC: %s\n" (read-string "Płeć: ")))
      (insert (format ":WIEK: %s\n" (read-string "Wiek: ")))
      (insert (format ":URODZINY: %s\n" (read-string "Urodziny (YYYY-MM-DD): ")))
      (insert (format ":RELACJA: %s\n" (read-string "Relacja: ")))
      (insert (format ":KONTEKST_POZNANIA: %s\n" (read-string "Gdzie poznany/a: ")))
      (insert (format ":EMAIL: %s\n" (read-string "Email: ")))
      (insert (format ":TELEFON: %s\n" (read-string "Telefon: ")))
      (insert (format ":LOKALIZACJA: %s\n" (read-string "Lokalizacja: ")))
      (insert ":END:\n\n")
      (insert "* Podstawowe informacje\n\n")
      (insert "* Historia interakcji\n\n")
      (insert "* Notatki\n\n")
      (insert "* Powiązania\n\n")
      (goto-char (point-min))
      (search-forward "* Podstawowe informacje")
      (forward-line 1)
      (message "Utworzono notatkę: %s" tytul))))

;; --- FUNKCJA: Shortcuts (jeden plik) ---
(defun my/denote-skroty ()
  "Otwórz/utwórz plik shortcuts i przejdź do nagłówka."
  (interactive)
  (let* ((shortcuts-pattern "--shortcuts__skroty")
         (existing-shortcuts nil))
    
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (when (string-match-p shortcuts-pattern (file-name-nondirectory file))
        (setq existing-shortcuts file)))
    
    (if existing-shortcuts
        (progn
          (find-file existing-shortcuts)
          (let ((header (read-string "Nagłówek (np. Emacs): ")))
            (goto-char (point-min))
            (if (search-forward (format "* %s" header) nil t)
                (progn
                  (end-of-line)
                  (forward-line 1)
                  (message "Przeszedłem do: %s" header))
              (goto-char (point-max))
              (unless (bolp) (insert "\n"))
              (insert (format "\n* %s\n\n" header))
              (backward-char 1)
              (message "Dodano nagłówek: %s" header))))
      
      (let* ((id (format-time-string "%Y%m%dT%H%M%S"))
             (filename (format "%s--shortcuts__skroty.org" id))
             (filepath (expand-file-name filename my-notes-dir))
             (header (read-string "Pierwszy nagłówek: ")))
        
        (find-file filepath)
        (insert "#+title:      Skróty Klawiszowe\n")
        (insert (format "#+date:       %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]")))
        (insert "#+filetags:   :skroty:\n")
        (insert (format "#+identifier: %s\n\n" id))
        (insert (format "* %s\n\n" header))
        (backward-char 1)
        (message "Utworzono shortcuts: %s" header)))))

;; --- FUNKCJA: Base (prosta notatka) ---
(defun my/denote-base ()
  "Utwórz prostą notatkę bez struktury."
  (interactive)
  (let ((denote-prompts '(title keywords)))
    (denote nil nil nil nil nil nil)
    (goto-char (point-max))
    (insert "\n* Notatki\n\n")
    (backward-char 1)))

;; --- Pomocnicza: wstaw godzinę ---
(defun insert-current-time ()
  "Wstaw aktualną godzinę HH:MM."
  (interactive)
  (insert (format-time-string "%H:%M")))

(provide '05-denote-functions)
;;; 05-denote-functions.el ends here
