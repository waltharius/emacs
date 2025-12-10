;;; 05-denote-functions.el --- Custom Denote functions  -*- lexical-binding: t; -*-
;;; Commentary:
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
    
    ;; Szukaj istniejącego journala NA DYSKU (zapisane pliki!)
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (when (string-match-p journal-pattern (file-name-nondirectory file))
        (setq existing-journal file)))
    
    (if existing-journal
        ;; Journal już istnieje - otwórz i dodaj wpis
        (progn
          (find-file existing-journal)
          (goto-char (point-max))
          
          ;; SMART SPACING: ZAWSZE jedna linia odstępu!
          ;; 1. Usuń trailing whitespace
          (save-excursion
            (goto-char (point-max))
            (skip-chars-backward " \t\n")
            (delete-region (point) (point-max)))
          
          ;; 2. Dodaj DOKŁADNIE dwa \n (jedna pusta linia)
          (goto-char (point-max))
          (insert "\n\n")
          
          ;; 3. Dodaj nowy wpis
          (insert (format "* %s\n" time-now))
          (message "Dodano wpis do journala"))
      
      ;; Nowy journal - utwórz
      (let* ((id (format-time-string "%Y%m%dT%H%M%S"))
             (slug (replace-regexp-in-string "[^[:alnum:]]" "-" (downcase (format "%s-journal" today))))
             (filename (format "%s--%s__journal.org" id slug))
             (filepath (expand-file-name filename my-notes-dir)))
        
        ;; Utwórz plik
        (find-file filepath)
        
        ;; Frontmatter
        (insert (format "#+title:      %s Journal\n" today))
        (insert (format "#+date:       [%s]\n" (format-time-string "%Y-%m-%d %a %H:%M")))
        (insert "#+filetags:   :journal:\n")
        (insert (format "#+identifier: %s\n" id))
        
        ;; Properties
        (insert ":PROPERTIES:\n")
        (insert ":well-being:  \n")
        (insert ":END:\n\n")
        
        ;; Pierwszy wpis
        (insert (format "* Książenice (%s)\n" time-now))
        
        ;; AUTO-SAVE natychmiast (zapobiega #.# problemowi!)
        (save-buffer)
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

;;; --- FUNCJA: Journal search ---
(defun my/journal-search ()
  "Search through journal files only."
  (interactive)
  (let* ((search-term (read-string "Search journals: "))
         (journal-files (directory-files my-notes-dir t ".*journal.*\\.org$"))
         (results '()))
    (if (not journal-files)
        (message "No journal files found!")
      (dolist (file journal-files)
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (search-forward search-term nil t)
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position)
                         (line-end-position))))
              (push (cons (file-name-nondirectory file) line) results)))))
      (if results
          (with-current-buffer (get-buffer-create "*Journal Search*")
            (read-only-mode -1)
            (erase-buffer)
            (insert (format "Search results for: \"%s\"\n\n" search-term))
            (dolist (result (reverse results))
              (insert (format "- %s: %s\n" (car result) (cdr result))))
            (goto-char (point-min))
            (read-only-mode 1)
            (switch-to-buffer (current-buffer)))
        (message "No matches found for \"%s\"" search-term)))))

(defun my/denote-recent-notes (n)
  "Open one of N most recently modified notes."
  (interactive "p")
  (let* ((files (directory-files my-notes-dir t "\\.org$"))
         (sorted (sort files (lambda (a b)
                              (time-less-p (nth 5 (file-attributes b))
                                          (nth 5 (file-attributes a))))))
         (recent (seq-take sorted (or n 10)))
         (choice (completing-read "Recent note: "
                                 (mapcar #'file-name-nondirectory recent))))
    (find-file (car (seq-filter (lambda (f)
                                  (string= (file-name-nondirectory f) choice))
                                recent)))))

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
        (message "Utworzono shortcuts: %s" HEADER)))))

;; --- FUNKCJA: Filozof ---
(defun my/denote-philosopher ()
  "Utwórz notatkę filozofa."
  (interactive)
  (let* ((name (read-string "Pełne imię filozofa: "))
         (short (read-string "Nazwisko Inicjał (np. Nietzsche F.): "))
         (title short))
    (denote title '("filozof"))
  (save-excursion
    (goto-char (point-max))
    (insert "\n* Podstawowe informacje\n")
    (insert (format "- Pełne imię: %s\n" name))
    (insert "- Życie: \n")
    (insert "- Epoka: \n")
    (insert "- Główne dzieła: \n")
    (insert "- Tematyka: \n\n")
    (insert "* Główne koncepcje\n\n")
    (insert "* Bibliografia (moje lektury)\n\n")
    (insert "* Notatki powiązane\n\n")
    (save-buffer))
    (goto-char (point-min))
    (re-search-forward "^- Życie: " nil t)))

;; --- FUNKCJA: Lektura (literature note) ---
(defun my/denote-literature ()
  "Utwórz notatkę lektury (literature note)."
  (interactive)
  (let* ((author (read-string "Autor (Nazwisko Inicjał): "))
         (work-title (read-string "Tytuł dzieła: "))
         (title (format "%s - %s" author work-title))
         (type (completing-read "Typ lektury: "
                               '("esej" "książka" "artykuł" "rozdział"
                                 "poezja" "proza" "filozofia")
                               nil nil "filozofia"))
         (tags (list "lektura" type))
         
         ;; PROPERTIES - pyta o wszystko, domyślne wartości
         (year (read-string "Rok wydania (opcjonalnie): " ""))
         (pages (read-string "Strony/długość (opcjonalnie): " ""))
         (status (completing-read "Status: "
                                 '("TODO" "READING" "DONE" "PAUSED")
                                 nil nil "READING"))
         (project (read-string "Projekt (opcjonalnie): " ""))
         (source (read-string "Źródło/wydawnictwo (opcjonalnie): " "")))
    
    (denote title tags)
    (save-excursion
      (goto-char (point-max))
      
      ;; PROPERTIES zaraz po front matter
      (insert "\n:PROPERTIES:\n")
      (when (not (string-empty-p year))
        (insert (format ":YEAR:     %s\n" year)))
      (when (not (string-empty-p pages))
        (insert (format ":PAGES:    %s\n" pages)))
      (insert (format ":STATUS:   %s\n" status))
      (when (not (string-empty-p project))
        (insert (format ":PROJECT:  %s\n" project)))
      (when (not (string-empty-p source))
        (insert (format ":SOURCE:   %s\n" source)))
      (insert (format ":READ_DATE: %s\n" (format-time-string "[%Y-%m-%d %a]")))
      (insert ":END:\n\n")
      
      ;; Struktura notatki
      (insert "* Autor\n")
      (insert (format "← [[denote:][%s]]\n\n" author))
      (insert "* Teza główna\n\n")
      (insert "* Struktura tekstu\n\n")
      (insert "* Kluczowe koncepty\n\n")
      (insert "* Argumenty\n\n")
      (insert "* Moje pytania\n\n")
      (insert "* Powiązania\n\n")
      (insert "* Cytaty kluczowe\n")
      (insert "#+begin_quote\n\n#+end_quote\n\n")
      (insert "* Fleeting Notes (czytanie 1)\n\n")
      (insert "* Literature Notes (czytanie 2)\n\n")
      (insert "* Permanent Notes (refleksja)\n\n")
      (insert "* Do zbadania dalej\n")
      (insert "- [ ] \n"))
    
    (save-buffer)
    (goto-char (point-min))
    (re-search-forward "^\\* Teza główna" nil t)
    (message "✅ Stworzono notatkę lektury: %s" title)))

;; --- FUNKCJA: Esej (projekt pisarski) ---
(defun my/denote-essay ()
  "Utwórz esej (projekt pisarski)."
  (interactive)
  (let* ((essay-title (read-string "Tytuł eseju: "))
         (title (format "ESEJ: %s" essay-title))
         (project-tag (read-string "Tag projektu (np. kant, hume): "))
         (tags (list "esej" "projekt" project-tag)))
    (denote title tags)
  (save-excursion
    (goto-char (point-max))
    (insert "\n* Metadata\n")
    (insert "- Przedmiot: \n")
    (insert "- Termin: \n")
    (insert "- Długość: \n")
    (insert "- Status: Planowanie\n\n")
    (insert "* Plan eseju\n")
    (insert "** Wstęp\n\n")
    (insert "** Część główna\n\n")
    (insert "** Wniosek\n\n")
    (insert "* Bibliografia\n\n")
    (insert "* Notatki robocze\n\n")
    (save-buffer))
    (goto-char (point-min))
    (re-search-forward "^- Przedmiot: " nil t)))

;; ============================================================
;; PROJECT NOTE CREATION (with template system)
;; ============================================================

(defun my/denote-create-project ()
  "Create new project note using template from ~/.emacs.d/templates/project.org.
Template contains project standards and conventions as reference."
  (interactive)
  
  ;; Check if template exists
  (unless (my/template-available-p "project")
    (error "Project template not found.  Please create ~/.emacs.d/templates/project.org"))
  
  (let* ((project-name (read-string "Project name: "))
         (title project-name)
         (tags-input (read-string "Tags (space-separated, 'project' will be added): "))
         ;; Parse tags and ensure 'project' tag is included
         (tags-list (split-string tags-input " " t))
         (tags-list (if (member "project" tags-list)
                        tags-list
                      (cons "project" tags-list)))
         (keywords tags-list)
         ;; Prepare placeholders
         (category (replace-regexp-in-string " " "-"
                     (replace-regexp-in-string "[^a-zA-Z0-9 -]" "" project-name)))
         (deadline-date (format-time-string "%Y-%m-%d %a"
                                           (time-add (current-time) (* 7 24 60 60))))
         (placeholders `(("{{TITLE}}" . ,project-name)
                        ("{{DATE}}" . ,(format-time-string "%Y-%m-%d"))
                        ("{{DATETIME}}" . ,(format-time-string "[%Y-%m-%d %a %H:%M]"))
                        ("{{CATEGORY}}" . ,category)
                        ("{{DEADLINE}}" . ,deadline-date))))
    
    ;; Create note using standard Denote
    (denote title keywords)
    
    ;; Load and insert template
    (save-excursion
      (goto-char (point-max))
      (insert "\n")
      (insert (my/load-template "project" placeholders))
      (save-buffer))
    
    ;; Position cursor at purpose description
    (goto-char (point-min))
    (when (search-forward "Describe the purpose" nil t)
      (beginning-of-line))
    
    (message "✅ Created project: %s (from template)" project-name)))

;; --- POPRAWKA: Base note z pytaniem o tytuł i tagi ---
(defun my/denote-base ()
  "Utwórz prostą notatkę (z pytaniem o tytuł i tagi)."
  (interactive)
  (let* ((title (read-string "Tytuł: "))
         (keywords-string (read-string "Tagi (rozdziel spacjami): "))
         (keywords (if (string-empty-p keywords-string)
                       nil
                     (split-string keywords-string " " t))))
    (if (string-empty-p title)
        (denote nil keywords)  ; Pusty tytuł = tylko ID
      (denote title keywords))))

;; --- Pomocnicza: wstaw godzinę ---
(defun insert-current-time ()
  "Wstaw aktualną godzinę HH:MM."
  (interactive)
  (insert (format-time-string "%H:%M")))

;; --- Menu zarządzania projektami ---
(defun my/denote-projects-menu ()
  "Interaktywne menu zarządzania projektami."
  (interactive)
  (let ((choice (completing-read
                 "Projekty - wybierz akcję: "
                 '("📊 Pokaż wszystkie projekty"
                   "➕ Dodaj nowy projekt"
                   "✏️  Edytuj cel projektu"
                   "🗑️  Usuń projekt"
                   "📈 Statystyki projektu"
                   "🎯 Cel dzienny projektu")
                 nil t)))
    (cond
     ((string-match "Pokaż wszystkie" choice)
      (my/denote-projects-list))
     ((string-match "Dodaj nowy" choice)
      (my/denote-project-add))
     ((string-match "Edytuj cel" choice)
      (my/denote-project-edit))
     ((string-match "Usuń projekt" choice)
      (my/denote-project-delete))
     ((string-match "Statystyki" choice)
      (my/denote-project-stats))
     ((string-match "Cel dzienny" choice)
      (my/denote-project-goal)))))

;; --- Lista projektów ---
(defun my/denote-projects-list ()
  "Pokaż listę projektów w ładnym buforze."
  (interactive)
  (let ((buffer-name "*Projekty*"))
    (with-current-buffer (get-buffer-create buffer-name)
      (read-only-mode -1)
      (erase-buffer)
      (insert "╔════════════════════════════════════╗\n")
      (insert "║   🎯 MOJE PROJEKTY 🎯              ║\n")
      (insert "╚════════════════════════════════════╝\n\n")
      
      (insert (format "%-20s | %s\n" "Projekt" "Cel dzienny"))
      (insert "────────────────────────────────────\n")
      
      (dolist (project my/project-daily-goals)
        (let ((name (car project))
              (goal (cdr project)))
          (insert (format "%-20s | %d słów\n" name goal))))
      
      (insert "\n────────────────────────────────────\n")
      (insert "Edytuj: e | Dodaj: a | Usuń: d | Zamknij: q\n")
      
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "e") 'my/denote-project-edit)
      (local-set-key (kbd "a") 'my/denote-project-add)
      (local-set-key (kbd "d") 'my/denote-project-delete)
      (local-set-key (kbd "q") 'quit-window))
    (switch-to-buffer buffer-name)))

;; --- Dodaj projekt ---
(defun my/denote-project-add ()
  "Dodaj nowy projekt przez menu."
  (interactive)
  (let* ((name (read-string "Nazwa projektu (tag): "))
         (goal (read-number "Cel dzienny (słowa): " 1000)))
    (when (and name (not (string-empty-p name)))
      ;; Dodaj do zmiennej
      (add-to-list 'my/project-daily-goals (cons name goal))
      ;; Zapisz do pliku
      (my/denote-projects-save)
      (message "✅ Projekt '%s' dodany (cel: %d słów)" name goal)
      ;; Odśwież listę jeśli jest otwarta
      (when (get-buffer "*Projekty*")
        (my/denote-projects-list)))))

;; --- Edytuj projekt ---
(defun my/denote-project-edit ()
  "Edytuj cel projektu."
  (interactive)
  (let* ((project-name (completing-read "Projekt do edycji: "
                                        (mapcar 'car my/project-daily-goals)))
         (old-goal (cdr (assoc project-name my/project-daily-goals)))
         (new-goal (read-number (format "Nowy cel dla '%s' (było: %d): "
                                       project-name old-goal)
                               old-goal)))
    (setf (cdr (assoc project-name my/project-daily-goals)) new-goal)
    (my/denote-projects-save)
    (message "✅ Projekt '%s': cel zmieniony na %d słów" project-name new-goal)
    (when (get-buffer "*Projekty*")
      (my/denote-projects-list))))

;; --- Usuń projekt ---
(defun my/denote-project-delete ()
  "Usuń projekt."
  (interactive)
  (let ((project-name (completing-read "Projekt do usunięcia: "
                                       (mapcar 'car my/project-daily-goals))))
    (when (yes-or-no-p (format "Usunąć projekt '%s'? " project-name))
      (setq my/project-daily-goals
            (assoc-delete-all project-name my/project-daily-goals))
      (my/denote-projects-save)
      (message "🗑️  Projekt '%s' usunięty" project-name)
      (when (get-buffer "*Projekty*")
        (my/denote-projects-list)))))

;; --- Zapisz projekty do pliku ---
(defvar my/projects-file (expand-file-name "denote-projects.el" user-emacs-directory)
  "Plik z listą projektów.")

(defun my/denote-projects-save ()
  "Zapisz projekty do pliku."
  (with-temp-file my/projects-file
    (insert ";;; denote-projects.el --- Auto-generated projects list\n\n")
    (insert "(setq my/project-daily-goals\n")
    (insert "  '(")
    (dolist (project my/project-daily-goals)
      (insert (format "\n    (\"%s\" . %d)" (car project) (cdr project))))
    (insert "))\n")))

(defun my/denote-projects-load ()
  "Załaduj projekty z pliku."
  (when (file-exists-p my/projects-file)
    (load my/projects-file)))

;; Załaduj przy starcie
(my/denote-projects-load)

;; --- Cockpit: interaktywny dashboard ---
(defun my/denote-cockpit ()
  "Interaktywny cockpit do zarządzania notatkami."
  (interactive)
  (let ((buffer-name "*Denote Cockpit*"))
    (with-current-buffer (get-buffer-create buffer-name)
      (read-only-mode -1)
      (erase-buffer)
      (org-mode)
      
      (insert "#+title: Denote Cockpit\n")
      (insert "#+startup: overview\n\n")
      
      ;; Sekcja Statystyki
      (insert "* 📊 Statystyki\n\n")
      (let ((total-files 0)
            (total-words 0)
            (today-files 0)
            (today-words 0)
            (today (format-time-string "%Y-%m-%d")))
        (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
          (with-temp-buffer
            (insert-file-contents file)
            (let ((words (count-words (point-min) (point-max))))
              (setq total-words (+ total-words words))
              (setq total-files (1+ total-files))
              (when (string-match-p today file)
                (setq today-words (+ today-words words))
                (setq today-files (1+ today-files))))))
        (insert (format "- Wszystkie notatki: *%d plików* | *%d słów*\n"
                       total-files total-words))
        (insert (format "- Dzisiaj: *%d plików* | *%d słów*\n\n"
                       today-files today-words)))
      
      ;; Sekcja Projekty
      (insert "* 🎯 Projekty\n\n")
      (insert "| Projekt | Cel | Dzisiaj | Postęp |\n")
      (insert "|---------|-----|---------|--------|\n")
      (dolist (project my/project-daily-goals)
        (let* ((tag (car project))
               (goal (cdr project))
               (today (format-time-string "%Y-%m-%d"))
               (words 0))
          (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
            (when (string-match-p today file)
              (with-temp-buffer
                (insert-file-contents file)
                (goto-char (point-min))
                (when (re-search-forward (format ":%s:" tag) nil t)
                  (setq words (+ words (count-words (point-min) (point-max))))))))
          (let ((progress (/ (* 100.0 words) goal)))
            (insert (format "| %s | %d | %d | %.0f%% |\n"
                           tag goal words progress)))))
      (insert "\n")
      
      ;; Sekcja Tagi (TOP 10)
      (insert "* 🏷️  Najczęstsze tagi\n\n")
      (let ((tags-count (make-hash-table :test 'equal)))
        (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (when (re-search-forward "^#\\+filetags: *\\(.*\\)$" nil t)
              (let ((tags-string (match-string 1)))
                (dolist (tag (split-string tags-string ":" t))
                  (puthash tag (1+ (gethash tag tags-count 0)) tags-count))))))
        (let ((sorted-tags (sort (hash-table-keys tags-count)
                                (lambda (a b)
                                  (> (gethash a tags-count)
                                     (gethash b tags-count))))))
          (dotimes (i (min 10 (length sorted-tags)))
            (let ((tag (nth i sorted-tags)))
              (insert (format "%d. *%s* (%d)\n"
                             (1+ i) tag (gethash tag tags-count)))))))
      (insert "\n")

      ;;Sekcja Well-being (ostatnie 7 dni)
      (insert "\n💚 WELL-BEING (ostatnie 7 dni):\n\n")
      (let ((results '())
	    (days-back 7))
	(dolist (file (directory-files my-notes-dir t "journal.*\\.org$"))
	  (with-temp-buffer
	    (insert-file-contents file)
	    (goto-char (point-min))
	    (when (re-search-forward ":well-being: \\([0-9]+\\)" nil t)
              (let* ((score (string-to-number (match-string 1)))
		     (date (when (string-match "\\([0-9]\\{8\\}\\)" file)
			     (match-string 1 file))))
		(when (and date (> score 0))
		  (push (list date score) results))))))
	(setq results (sort results (lambda (a b) (string> (car a) (car b)))))
	(setq results (seq-take results days-back))
	(dolist (entry results)
	  (let* ((date (car entry))
		 (score (cadr entry))
		 (emoji (cond ((>= score 9) "😊")
			      ((>= score 7) "🙂")
			      ((>= score 5) "😐")
			      (t "😕"))))
	    (insert (format "  %s %s: %d\n"
			    (substring date 4 8) emoji score)))))

      ;; Sekcja Missing Well-being
      (insert "* ⚠️  Brakujące Well-being\n\n")
      (let ((missing '()))
	(dolist (file (directory-files my-notes-dir t "journal.*\\.org$"))
	  (with-temp-buffer
	    (insert-file-contents file)
	    (goto-char (point-min))
	    (let ((has-property (re-search-forward "^:well-being:" nil t))
		  (has-value nil))
              (when has-property
		(beginning-of-line)
		(when (re-search-forward ":well-being: *\\([0-9]+\\)" (line-end-position) t)
		  (setq has-value t)))
              (when (not has-value)
		(let ((date (when (string-match "\\([0-9]\\{8\\}\\)" file)
			      (match-string 1 file))))
		  (when date
		    (push (list date file) missing)))))))
	(setq missing (sort missing (lambda (a b) (string> (car a) (car b)))))
	(if missing
	    (progn
              (insert "Journale bez ustawionego well-being:\n\n")
              (dolist (entry missing)
		(let* ((date (car entry))
                       (file (cadr entry))
                       (filename (file-name-nondirectory file))
                       (date-fmt (format "%s-%s-%s"
					 (substring date 0 4)
					 (substring date 4 6)
					 (substring date 6 8))))
		  (insert (format "- %s [[file:%s][%s]] [[elisp:(progn (find-file \"%s\") (my/denote-set-wellbeing))][⚙️ Ustaw]]\n"
				  date-fmt file filename file)))))
	  (insert "✅ Wszystkie journale mają ustawione well-being!\n"))
	(insert "\n"))
 
      ;; Sekcja Akcje
      (insert "* 🎛️  Akcje\n\n")
      (insert "- [[elisp:(my/denote-projects-menu)][Zarządzaj projektami]]\n")
      (insert "- [[elisp:(my/denote-dashboard)][Dashboard statystyk]]\n")
      (insert "- [[elisp:(my/denote-wellbeing-history)][Historia well-being]]\n")
      (insert "- [[elisp:(my/denote-wellbeing-graph)][Graf well-being ASCII]]\n")
      (insert "- [[elisp:(my/denote-wellbeing-plot)][Wykres well-being (gnuplot)]]\n")
      (insert "- [[elisp:(consult-denote-find)][Szukaj notatki]]\n")
      (insert "- [[elisp:(my/denote-wellbeing-fill-missing)][⚠️ Uzupełnij brakujące well-being]]\n")
      (insert "- [[elisp:(my/denote-cockpit)][Odśwież cockpit]]\n")
            
      (goto-char (point-min))
      (read-only-mode 1))
    (switch-to-buffer buffer-name)))

;; ============================================================
;; USUWANIE: Smart delete z Git-aware
;; ============================================================

(defun my/denote-delete-note ()
  "Usuń obecną notatkę (plik + bufor).
Jeśli w Git repo - używa 'git rm', inaczej zwykłe delete.
ZAWSZE pyta o potwierdzenie!"
  (interactive)
  (let* ((file (buffer-file-name))
         (name (file-name-nondirectory file)))
    (if (not file)
        (message "To nie jest plik!")
      (when (yes-or-no-p (format "🗑️  Usunąć notatkę: %s? " name))
        ;; Sprawdź czy w Git repo
        (if (and (executable-find "git")
                 (= 0 (call-process "git" nil nil nil
                                   "ls-files" "--error-unmatch" file)))
            ;; W Git - użyj git rm
            (progn
              (shell-command (format "git rm -f '%s'" file))
              (message "✅ Usunięto z Git: %s" name))
          ;; Nie w Git - zwykłe delete
          (progn
            (delete-file file)
            (message "✅ Usunięto plik: %s" name)))
        ;; Zamknij bufor
        (kill-buffer (current-buffer))))))

(defun my/denote-delete-from-list ()
  "Znajdź notatkę i usuń ją (bez otwierania)."
  (interactive)
  (let* ((files (directory-files my-notes-dir t "\\.org$"))
         (file-names (mapcar #'file-name-nondirectory files))
         (choice (completing-read "Usuń notatkę: " file-names))
         (file (expand-file-name choice my-notes-dir)))
    (when (yes-or-no-p (format "🗑️  Na pewno usunąć: %s? " choice))
      ;; Git-aware delete
      (if (and (executable-find "git")
               (= 0 (call-process "git" nil nil nil
                                 "ls-files" "--error-unmatch" file)))
          (progn
            (shell-command (format "git rm -f '%s'" file))
            (message "✅ Usunięto z Git: %s" choice))
        (progn
          (delete-file file)
          (message "✅ Usunięto: %s" choice)))
      ;; Zamknij bufor jeśli otwarty
      (let ((buf (get-file-buffer file)))
        (when buf (kill-buffer buf))))))

(defun my/denote-find-by-property (property value)
  "Znajdź notatki gdzie PROPERTY = VALUE."
  (interactive
   (list (read-string "Property: " "CATEGORY")
         (read-string "Value: ")))
  (let ((results '()))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward
               (format "^:%s: +%s" property (regexp-quote value))
               nil t)
          (let ((title (progn
                        (goto-char (point-min))
                        (when (re-search-forward "^#\\+title: *\\(.*\\)$" nil t)
                          (match-string 1)))))
            (push (cons title file) results)))))
    (if results
        (let* ((titles (mapcar #'car results))
               (choice (completing-read "Wybierz notatkę: " titles))
               (file (cdr (assoc choice results))))
          (find-file file))
      (message "Nie znaleziono notatek z %s=%s" property value))))
;; ============================================================
;; WELL-BEING: Auto-create tracker file
;; ============================================================

(defun my/ensure-wellbeing-file ()
  "Create well-being.org if it doesn't exist."
  (let ((wellbeing-file (expand-file-name "~/notes/well-being.org")))
    (unless (file-exists-p wellbeing-file)
      (with-temp-file wellbeing-file
        (insert "#+title: Well-Being Tracker\n")
        (insert "#+filetags: :wellbeing:\n\n")
        (insert "* Daily Check-ins\n\n")
        (insert "Track your well-being daily. Rate each category from 1-10.\n\n")
        (insert "** " (format-time-string "%Y-%m-%d") " [0/10]\n\n")
        (insert "- Mood: \n")
        (insert "- Energy: \n")
        (insert "- Focus: \n")
        (insert "- Sleep Quality: \n")
        (insert "- Physical Health: \n")
        (insert "- Social Connection: \n")
        (insert "- Stress Level (1=low, 10=high): \n")
        (insert "- Notes: \n\n"))
      (message "✅ Created well-being.org tracker!"))))

;; Create well-being file on Dashboard load
(add-hook 'dashboard-mode-hook 'my/ensure-wellbeing-file)

;; ============================================================
;; DASHBOARD-AWARE NOTE CREATION
;; ============================================================

(defun my/denote-journal-split ()
  "Create journal in right split if in dashboard, else fullscreen."
  (interactive)
  (when (and (equal major-mode 'dashboard-mode)
             (= (length (window-list)) 1))  ; Only 1 window = dashboard fullscreen
    (split-window-right)
    (other-window 1))
  (call-interactively 'my/denote-journal))

(defun my/denote-zettel-split ()
  "Create zettel in right split if in dashboard, else fullscreen."
  (interactive)
  (when (and (equal major-mode 'dashboard-mode)
             (= (length (window-list)) 1))
    (split-window-right)
    (other-window 1))
  (call-interactively 'my/denote-zettel))

(defun my/denote-base-split ()
  "Create quick note in right split if in dashboard, else fullscreen."
  (interactive)
  (when (and (equal major-mode 'dashboard-mode)
             (= (length (window-list)) 1))
    (split-window-right)
    (other-window 1))
  (call-interactively 'my/denote-base))

(defun my/denote-lektura-split ()
  "Create literature note in right split if in dashboard, else fullscreen."
  (interactive)
  (when (and (equal major-mode 'dashboard-mode)
             (= (length (window-list)) 1))
    (split-window-right)
    (other-window 1))
  (call-interactively 'my/denote-lektura))

(defun my/denote-filozof-split ()
  "Create philosophy note in right split if in dashboard, else fullscreen."
  (interactive)
  (when (and (equal major-mode 'dashboard-mode)
             (= (length (window-list)) 1))
    (split-window-right)
    (other-window 1))
  (call-interactively 'my/denote-filozof))

;; ============================================================
;; TEMPLATE ENGINE
;; ============================================================

(defun my/load-template (template-name placeholders)
  "Load template from TEMPLATE-NAME and replace PLACEHOLDERS.
TEMPLATE-NAME is filename without extension (e.g., 'project').
PLACEHOLDERS is alist: ((\"{{TITLE}}\" . \"My Project\") ...)
Returns template content as string."
  (let* ((template-file (expand-file-name
                         (concat template-name ".org")
                         my/templates-dir))
         (content (if (file-exists-p template-file)
                      (with-temp-buffer
                        (insert-file-contents template-file)
                        (buffer-string))
                    (error "Template not found: %s" template-file))))
    
    ;; Replace all placeholders
    (dolist (placeholder placeholders)
      (setq content (replace-regexp-in-string
                     (regexp-quote (car placeholder))
                     (cdr placeholder)
                     content
                     t t)))
    
    content))

(defun my/template-available-p (template-name)
  "Check if TEMPLATE-NAME exists in templates directory."
  (file-exists-p (expand-file-name
                  (concat template-name ".org")
                  my/templates-dir)))

;; ============================================================
;; READWISE PROCESSING
;; ============================================================

(defun my/readwise-to-literature ()
  "Process readwise-raw.org into individual literature notes.
Uses 2-second delays to maintain standard Denote ID format."
  (interactive)
  (let* ((raw-file (expand-file-name "readwise-raw.org" my/notes-dir))
         (processed-count 0)
         (skipped-count 0))
    
    (unless (file-exists-p raw-file)
      (error "A readwise-raw.org not found! Run sync first (C-c n w s)"))
    
    (message "🔄 Przetwarzam readwise-raw.org...")
    
    (with-temp-buffer
      (insert-file-contents raw-file)
      (goto-char (point-min))
      
      (while (re-search-forward "^\\* \\([^*].*\\)$" nil t)
        (let* ((title (match-string 1))
               (title-clean (string-trim title))
               (entry-start (point))
               entry-end author category url book-id highlights-list)
          
          (save-excursion
            ;; Find end of this book
            (if (re-search-forward "^\\* [^*]" nil t)
                (setq entry-end (match-beginning 0))
              (setq entry-end (point-max)))
            
            ;; Look for PROPERTIES drawer (may have leading whitespace)
            (goto-char entry-start)
            (when (re-search-forward "^ *:PROPERTIES:$" entry-end t)
              (let ((props-start (point))
                    (props-end (when (re-search-forward "^ *:END:$" entry-end t)
                                 (point))))
                
                (when props-end
                  ;; Extract ID (may have leading whitespace)
                  (goto-char props-start)
                  (when (re-search-forward "^ *:ID: *\\([0-9]+\\)" props-end t)
                    (setq book-id (match-string 1)))
                  
                  ;; Extract AUTHOR
                  (goto-char props-start)
                  (when (re-search-forward "^ *:AUTHOR: *\\(.+\\)$" props-end t)
                    (setq author (string-trim (match-string 1))))
                  
                  ;; Extract CATEGORY
                  (goto-char props-start)
                  (when (re-search-forward "^ *:CATEGORY: *\\(.+\\)$" props-end t)
                    (setq category (string-trim (match-string 1))))
                  
                  ;; Extract URL
                  (goto-char props-start)
                  (when (re-search-forward "^ *:URL: *\\(.+\\)$" props-end t)
                    (setq url (string-trim (match-string 1)))))))
            
            ;; Extract highlights (** Highlight)
            (goto-char entry-start)
            (while (re-search-forward "^\\*\\* Highlight$" entry-end t)
              (let ((highlight-start (point)))
                ;; Skip highlight's properties drawer
                (when (looking-at "[\n\r]* *:PROPERTIES:")
                  (re-search-forward "^ *:END:$" entry-end t)
                  (forward-line 1)
                  (setq highlight-start (point)))
                
                ;; Get text until next highlight or end
                (let ((highlight-end (if (re-search-forward "^\\*\\* Highlight$" entry-end t)
                                         (match-beginning 0)
                                       entry-end)))
                  (let ((highlight-text (buffer-substring-no-properties
                                        highlight-start highlight-end)))
                    (setq highlight-text (string-trim highlight-text))
                    (when (not (string-empty-p highlight-text))
                      (push highlight-text highlights-list)))
                  (goto-char highlight-end)))))
          
          ;; Process book
          (cond
           ((not book-id)
            (message "⚠️  Pomijam '%s' (brak ID)" title-clean)
            (setq skipped-count (1+ skipped-count)))
           
           ((not highlights-list)
            (message "⚠️  Pomijam '%s' (brak podświetleń)" title-clean)
            (setq skipped-count (1+ skipped-count)))
           
           (t
            ;; Check if already processed
            (let ((already-exists nil))
              (dolist (file (directory-files my/notes-dir t "\\.org$"))
                (ignore-errors
                  (with-temp-buffer
                    (insert-file-contents file)
                    (when (search-forward (format ":READWISE_ID: %s" book-id) nil t)
                      (setq already-exists t)))))
              
              (if already-exists
                  (progn
                    (message "⏭️  Pomijam '%s' (już przetworzono)" title-clean)
                    (setq skipped-count (1+ skipped-count)))
                
                ;; Create literature note
                (condition-case err
                    (let* ((author-final (or author "Nieznany Autor"))
                           (note-title (format "%s - %s" author-final title-clean))
                           (tags (list "literatura" "readwise" (or category "książka")))
                           ;; STANDARD DENOTE ID FORMAT - clean!
                           (id (format-time-string "%Y%m%dT%H%M%S"))
                           (slug (denote-sluggify 'title note-title))
                           (filename (format "%s--%s__literatura_readwise.org" id slug))
                           (filepath (expand-file-name filename my/notes-dir)))
                      
                      ;; Wait 2 seconds before next file (ensures unique IDs)
                      (sleep-for 2)
                      
                      (with-temp-file filepath
                        (insert (format "#+title:      %s\n" note-title))
                        (insert (format "#+date:       %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]")))
                        (insert (format "#+filetags:   :%s:\n" (mapconcat 'identity tags ":")))
                        (insert (format "#+identifier: %s\n" id))
                        (when (and url (not (string-empty-p url)))
                          (insert (format "#+source_url: %s\n" url)))
                        (insert "\n:PROPERTIES:\n")
                        (insert (format ":AUTHOR: %s\n" author-final))
                        (insert (format ":CATEGORY: %s\n" (or category "książka")))
                        (insert (format ":READWISE_ID: %s\n" book-id))
                        (insert (format ":IMPORT_DATE: %s\n" (format-time-string "[%Y-%m-%d %a]")))
                        (insert ":END:\n\n")
                        
                        (insert "* O książce\n\n")
                        (when (and url (not (string-empty-p url)))
                          (insert (format "Źródło: [[%s][Zobacz na Readwise]]\n\n" url)))
                        
                        (insert "* Cytaty\n\n")
                        (dolist (highlight (reverse highlights-list))
                          (insert (format "#+begin_quote\n%s\n#+end_quote\n\n" highlight)))
                        
                        (insert "* Główna teza\n\n")
                        (insert "* Kluczowe koncepty\n\n")
                        (insert "* Argumenty\n\n")
                        (insert "* Moje pytania\n\n")
                        (insert "* Powiązane notatki\n\n"))
                      
                      (setq processed-count (1+ processed-count))
                      (message "✅ Utworzono: %s (%d cytatów)" note-title (length highlights-list)))
                  
                  (error
                   (message "❌ BŁĄD przy '%s': %s" title-clean (error-message-string err))
                   (setq skipped-count (1+ skipped-count))))))))))
    
    (message "✅ Przetworzono: %d książek | ⏭️  Pominięto: %d"
             processed-count skipped-count)))

(defun my/readwise-update-existing-notes ()
  "Update existing literature notes with new highlights from readwise-raw.org.
Only adds NEW highlights that don't already exist in the note.
Preserves all your existing manual notes and edits."
  (interactive)
  (let* ((raw-file (expand-file-name "readwise-raw.org" my/notes-dir))
         (updated-count 0)
         (total-new-highlights 0))
    
    (unless (file-exists-p raw-file)
      (error "A readwise-raw.org not found! Run sync first (C-c n w s)"))
    
    (message "🔄 Sprawdzam nowe podświetlenia...")
    
    ;; Parse readwise-raw.org
    (with-temp-buffer
      (insert-file-contents raw-file)
      (goto-char (point-min))
      
      (while (re-search-forward "^\\* \\([^*].*\\)$" nil t)
        (let* ((title (string-trim (match-string 1)))
               (entry-start (point))
               entry-end book-id new-highlights)
          
          (save-excursion
            (if (re-search-forward "^\\* [^*]" nil t)
                (setq entry-end (match-beginning 0))
              (setq entry-end (point-max)))
            
            ;; Get book ID
            (goto-char entry-start)
            (when (re-search-forward "^ *:PROPERTIES:$" entry-end t)
              (let ((props-start (point))
                    (props-end (when (re-search-forward "^ *:END:$" entry-end t)
                                 (point))))
                (when props-end
                  (goto-char props-start)
                  (when (re-search-forward "^ *:ID: *\\([0-9]+\\)" props-end t)
                    (setq book-id (match-string 1))))))
            
            ;; Get all highlights from readwise
            (goto-char entry-start)
            (while (re-search-forward "^\\*\\* Highlight$" entry-end t)
              (let ((highlight-start (point)))
                (when (looking-at "[\n\r]* *:PROPERTIES:")
                  (re-search-forward "^ *:END:$" entry-end t)
                  (forward-line 1)
                  (setq highlight-start (point)))
                
                (let ((highlight-end (if (re-search-forward "^\\*\\* Highlight$" entry-end t)
                                         (match-beginning 0)
                                       entry-end)))
                  (let ((highlight-text (string-trim
                                        (buffer-substring-no-properties
                                         highlight-start highlight-end))))
                    (when (not (string-empty-p highlight-text))
                      (push highlight-text new-highlights)))
                  (goto-char highlight-end)))))
          
          ;; Find existing note for this book
          (when book-id
            (let ((existing-file nil))
              (dolist (file (directory-files my/notes-dir t "\\.org$"))
                (ignore-errors
                  (with-temp-buffer
                    (insert-file-contents file)
                    (when (search-forward (format ":READWISE_ID: %s" book-id) nil t)
                      (setq existing-file file)))))
              
              ;; Update file if found
              (when existing-file
                (with-current-buffer (find-file-noselect existing-file)
                  (save-excursion
                    (goto-char (point-min))
                    
                    ;; Find "* Cytaty" section
                    (if (re-search-forward "^\\* Cytaty$" nil t)
                        (let ((citations-start (point))
                              (citations-end (if (re-search-forward "^\\* " nil t)
                                               (match-beginning 0)
                                             (point-max)))
                              (added-count 0))
                          
                          ;; Check each new highlight
                          (dolist (highlight new-highlights)
                            (goto-char citations-start)
                            ;; If highlight not already in the note
                            (unless (search-forward highlight citations-end t)
                              ;; Add it at the end of Cytaty section
                              (goto-char citations-end)
                              ;; Go back before next section header
                              (when (looking-at "^\\* ")
                                (forward-line -1)
                                (end-of-line))
                              (insert (format "\n#+begin_quote\n%s\n#+end_quote\n" highlight))
                              (setq added-count (1+ added-count))
                              (setq total-new-highlights (1+ total-new-highlights))))
                          
                          (when (> added-count 0)
                            (save-buffer)
                            (setq updated-count (1+ updated-count))
                            (message "✅ Dodano %d nowych cytatów do: %s"
                                    added-count (file-name-nondirectory existing-file))))
                      
                      (message "⚠️  Brak sekcji '* Cytaty' w: %s"
                              (file-name-nondirectory existing-file))))))))))))
    
    (if (> updated-count 0)
        (message "✅ Zaktualizowano %d notatek! Dodano łącznie %d nowych cytatów."
                 updated-count total-new-highlights)
      (message "ℹ️  Brak nowych cytatów do dodania"))))

(defun my/denote-article ()
  "Create article note (web article, not from Readwise)."
  (interactive)
  (let* ((title (read-string "Article title: "))
         (author (read-string "Author: "))
         (url (read-string "URL: "))
         (note-title (if (string-empty-p author)
                         title
                       (format "%s - %s" author title)))
         (tags (list "article" "literature")))
    (denote note-title tags)
    (save-excursion
      (goto-char (point-max))
      (insert "\n:PROPERTIES:\n")
      (when (not (string-empty-p author))
        (insert (format ":AUTHOR: %s\n" author)))
      (when (not (string-empty-p url))
        (insert (format ":URL: %s\n" url)))
      (insert (format ":READ_DATE: %s\n" (format-time-string "[%Y-%m-%d %a]")))
      (insert ":END:\n\n")
      (when (not (string-empty-p url))
        (insert (format "Source: [[%s][Original article]]\n\n" url)))
      (insert "* Summary\n\n")
      (insert "* Key Points\n\n")
      (insert "* My Notes\n\n")
      (save-buffer))
    (goto-char (point-min))
    (re-search-forward "^\\* Summary" nil t)
    (message "✅ Created article note: %s" title)))

;; ALWAYS AT THE END OF THE FILE
;; ============================================================
;; TRANSIENT NOTES MENU (replaces all C-c n X keybindings)
;; ============================================================

(require 'transient)

(transient-define-prefix my/notes-transient-menu ()
  "Denote notes - all functions (verified from keybindings)"
  ["Denote Notes"
   ["Create Basic"
    ("n" "New note" denote)
    ("j" "Journal today" my/denote-journal)
    ("J" "Journal date" my/denote-journal-date)
    ("z" "Zettelkasten" my/denote-zettel)
    ("o" "Person" my/denote-osoba)
    ("b" "Base note" my/denote-base)
    ("p" "Project" my/denote-create-project)
    ("s" "Shortcut" my/denote-skroty)
    ("q" "Fleeting quote" my/fleeting-quote)
    ("Q" "Smart fleeting quote" my/fleeting-quote-smart)]
   
   ["Create Advanced"
    ("P" "Philosopher" my/denote-philosopher)
    ("L" "Literature" my/denote-literature)
    ("E" "Essay" my/denote-essay)
    ("Z" "Smart Zettel" my/denote-zettel-smart)]
   
   ["Search & Find"
    ("f" "Open/create" denote-open-or-create)
    ("g" "Grep notes" consult-denote-grep)
    ("F" "Find file" consult-denote-find)
    ("x" "Find property" my/denote-find-by-property)
    ("/" "Journal search" my/journal-search)]
   
   ["Linking"
    ("i" "Insert link" denote-link)
    ("I" "Link or create" denote-link-or-create)
    ("B" "Backlinks" denote-backlinks)
    ("l" "Add links" denote-add-links)
    ("A" "Link after create" denote-link-after-creating)]]

    ["Readwise"
   ("w s" "Sync highlights" org-readwise-sync)
   ("w p" "Process to notes" my/readwise-to-literature)
   ("w u" "Update existing" my/readwise-update-existing-notes)
   ("w a" "New article" my/denote-article)
   ("w o" "Open raw file"
    (lambda ()
      (interactive)
      (find-file (expand-file-name "readwise-raw.org" my/notes-dir))))]
  
  ["Management"
   ["Rename & Tags"
    ("r" "Rename file" denote-rename-file)
    ("R" "Rename frontm." denote-rename-file-using-front-matter)
    ("t" "Add keywords" denote-keywords-add)
    ("T" "Remove keywords" denote-keywords-remove)]
   
   ["Folgezettel"
    (">" "Zettel tree" my/denote-zettel-tree)
    ("<" "Find children" my/denote-find-children)]
   
   ["Delete"
    ("d" "Delete note" my/denote-delete-note)
    ("D" "Delete from list" my/denote-delete-from-list)]
   
   ["UI & Tools"
    ("e" "Edit init.el" open-init-el-bottom-split)
    ("h" "Insert time" insert-current-time)
    ("c" "Journal calendar" my/open-journal-calendar)
    ("u" "Roam UI graph" org-roam-ui-mode)]]
  
  [["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]])



(provide '05-denote-functions)
;;; 05-denote-functions.el ends here
