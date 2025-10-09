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

;; ============================================================
;; DASHBOARD PERFORMANCE CACHE
;; ============================================================

(defvar my/dashboard-cache nil
  "Plist cache for expensive dashboard calculations.
Format: (:total-words NUM :total-files NUM :last-update TIMESTAMP)")

(defun my/dashboard-cache-valid-p ()
  "Check if dashboard cache is still valid."
  (and my/dashboard-cache
       (plist-get my/dashboard-cache :last-update)
       (< (- (float-time) (plist-get my/dashboard-cache :last-update))
          my/dashboard-cache-ttl)))

(defun my/dashboard-invalidate-cache ()
  "Invalidate dashboard cache (force recalculation)."
  (interactive)
  (setq my/dashboard-cache nil)
  (message "Dashboard cache invalidated - next open will recalculate"))

;; ============================================================
;; STATISTICS FUNCTIONS (with cache)
;; ============================================================

;; --- Statystyki: zlicz słowa we wszystkich notatkach ---
(defun my/denote-count-words-all ()
  "Zlicz słowa we wszystkich plikach Denote (with cache).
Cache valid for 5 minutes.
Use M-x my/dashboard-invalidate-cache to force refresh."
  (interactive)
  (if (my/dashboard-cache-valid-p)
      ;; Return cached value
      (plist-get my/dashboard-cache :total-words)
    ;; Cache invalid - recalculate
    (let ((total-words 0)
          (total-chars 0)
          (file-count 0))
      (dolist (file (directory-files-recursively my-notes-dir "\\.org"))
        (with-temp-buffer
          (insert-file-contents file)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq total-chars (+ total-chars (- (point-max) (point-min))))
          (setq file-count (1+ file-count))))
      ;; Update cache
      (setq my/dashboard-cache
            (plist-put my/dashboard-cache :total-words total-words))
      (setq my/dashboard-cache
            (plist-put my/dashboard-cache :total-files file-count))
      (setq my/dashboard-cache
            (plist-put my/dashboard-cache :last-update (float-time)))
      (message "Dashboard cache refreshed - %d files, %d words" file-count total-words)
      (message "Statystyki: %d plików, %d słów, %d znaków"
               file-count total-words total-chars)
      total-words)))



;; --- Statystyki dzienne: ile słów napisałem dziś? ---
(defun my/denote-count-words-today ()
  "Zlicz słowa w notatkach stworzonych DZISIAJ."
  (interactive)
  (let ((today (format-time-string "%Y-%m-%d"))
        (total-words 0)
        (file-count 0))
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (when (string-match-p today file)  ; Sprawdź czy data w nazwie == dziś
        (with-temp-buffer
          (insert-file-contents file)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count)))))
    (message "📊 Dzisiaj: %d plików | %d słów" file-count total-words)))

;; --- Cel pisarski: sprawdź postęp względem celu ---
(defvar my/daily-word-goal 3000
  "Dzienny cel słów do napisania.")

(defun my/denote-writing-goal ()
  "Sprawdź postęp względem dziennego celu."
  (interactive)
  (let ((today (format-time-string "%Y-%m-%d"))
        (total-words 0)
        (file-count 0))
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (when (string-match-p today file)
        (with-temp-buffer
          (insert-file-contents file)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count)))))
    (let* ((progress (/ (* 100.0 total-words) my/daily-word-goal))
           (remaining (- my/daily-word-goal total-words))
           (emoji (cond ((>= progress 100) "🎉")
                       ((>= progress 75) "💪")
                       ((>= progress 50) "📝")
                       ((>= progress 25) "🚀")
                       (t "⏳"))))
      (message "%s Cel: %d/%d słów (%.1f%%) | Brakuje: %d"
               emoji total-words my/daily-word-goal progress
               (max 0 remaining)))))

;; --- Dashboard: live statystyki ---
(defun my/denote-dashboard ()
  "Pokaż live dashboard z statystykami."
  (interactive)
  (let ((buffer-name "*Denote Dashboard*"))
    (with-current-buffer (get-buffer-create buffer-name)
      (read-only-mode -1)
      (erase-buffer)
      (insert "╔════════════════════════════════════╗\n")
      (insert "║             📊 STATS 📊            ║\n")
      (insert "╚════════════════════════════════════╝\n\n")
      
      ;; Statystyki globalne
      (let ((total-words 0)
            (total-files 0))
        (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
          (with-temp-buffer
            (insert-file-contents file)
            (setq total-words (+ total-words (count-words (point-min) (point-max))))
            (setq total-files (1+ total-files))))
        (insert (format "📚 Wszystkie notatki: %d plików, %d słów\n\n"
                       total-files total-words)))
      
      ;; Statystyki dzienne
      (let ((today (format-time-string "%Y-%m-%d"))
            (today-words 0)
            (today-files 0))
        (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
          (when (string-match-p today file)
            (with-temp-buffer
              (insert-file-contents file)
              (setq today-words (+ today-words (count-words (point-min) (point-max))))
              (setq today-files (1+ today-files)))))
        (insert (format "📝 Dzisiaj: %d plików, %d słów\n\n"
                       today-files today-words))
        
        ;; Cel dzienny
        (let* ((goal my/daily-word-goal)
               (progress (/ (* 100.0 today-words) goal))
               (emoji (cond ((>= progress 100) "🎉")
                           ((>= progress 75) "💪")
                           ((>= progress 50) "📝")
                           (t "⏳"))))
          (insert (format "%s Cel dzienny: %d/%d (%.1f%%)\n\n"
                         emoji today-words goal progress))))
      
      ;; Projekty
      (insert "🎯 PROJEKTY:\n")
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
          (let* ((progress (/ (* 100.0 words) goal))
                 (emoji (cond ((>= progress 100) "✅")
                             ((>= progress 50) "🟡")
                             (t "🔴"))))
            (insert (format "  %s %s: %d/%d (%.0f%%)\n"
                           emoji tag words goal progress)))))
      
      (insert "\n────────────────────────────────────\n")
      (insert "Odśwież: r | Zamknij: q\n")
      
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "r") 'my/denote-dashboard)
      (local-set-key (kbd "q") 'quit-window))
    (switch-to-buffer buffer-name)))

;; --- Statystyki PROJEKTU (przez tag) ---
(defun my/denote-project-stats ()
  "Zlicz słowa w wybranym projekcie (przez tag)."
  (interactive)
  (let* ((project-tag (completing-read "Tag projektu: "
                                       '("arystoteles" "kant" "hume" "projekt")))
         (total-words 0)
         (file-count 0))
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward (format ":%s:" project-tag) nil t)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count)))))
    (message "📊 Projekt '%s': %d plików | %d słów"
             project-tag file-count total-words)))

;; --- Cel dzienny dla projektu ---
(defvar my/project-daily-goals
  '(("arystoteles" . 2000))
  "Dzienne cele słów dla projektów (tag . liczba_słów).")

(defun my/denote-project-goal ()
  "Sprawdź postęp względem celu dziennego PROJEKTU."
  (interactive)
  (let* ((project-tag (completing-read "Tag projektu: "
                                       (mapcar 'car my/project-daily-goals)))
         (goal (or (cdr (assoc project-tag my/project-daily-goals)) 1000))
         (today (format-time-string "%Y-%m-%d"))
         (total-words 0)
         (file-count 0))
    
    ;; Zlicz słowa w plikach z DZISIEJSZĄ datą I tagiem projektu
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (when (string-match-p today file)
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward (format ":%s:" project-tag) nil t)
            (setq total-words (+ total-words (count-words (point-min) (point-max))))
            (setq file-count (1+ file-count))))))
    
    (let* ((progress (/ (* 100.0 total-words) goal))
           (remaining (- goal total-words))
           (emoji (cond ((>= progress 100) "🎉")
                       ((>= progress 75) "💪")
                       ((>= progress 50) "📝")
                       ((>= progress 25) "🚀")
                       (t "⏳"))))
      (message "%s Projekt '%s': %d/%d słów (%.1f%%) | Brakuje: %d"
               emoji project-tag total-words goal progress
               (max 0 remaining)))))

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

;; --- Well-being: uzupełnij wszystkie brakujące ---
(defun my/denote-wellbeing-fill-missing ()
  "Interaktywnie uzupełnij wszystkie journale bez well-being."
  (interactive)
  (let ((missing '()))
    ;; Znajdź brakujące
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
            (push file missing)))))
    (setq missing (sort missing 'string<))
    
    (if missing
        (progn
          (message "Znaleziono %d journali bez well-being" (length missing))
          (dolist (file missing)
            (when (y-or-n-p (format "Ustaw well-being dla %s? "
                                   (file-name-nondirectory file)))
              (my/denote-set-wellbeing-for-file file))))
      (message "✅ Wszystkie journale mają well-being!"))))

;; --- Well-being: szybkie ustawienie ---
(defun my/denote-set-wellbeing ()
  "Ustaw wartość well-being dla obecnego journala (0-10)."
  (interactive)
  (let ((score (read-number "Well-being (0-10): " 7)))
    (save-excursion
      (goto-char (point-min))
      (if (re-search-forward "^:well-being:.*$" nil t)
          (progn
            (beginning-of-line)
            (kill-line)
            (insert (format ":well-being: %d" score))
            (save-buffer)
            (message "✅ Well-being ustawione: %d" score))
        (message "⚠️  To nie jest journal z własnością :well-being:")))))

;; --- Well-being: historia samopoczucia ---
(defun my/denote-wellbeing-history ()
  "Pokaż historię well-being z journali."
  (interactive)
  (let ((results '()))
    (dolist (file (directory-files my-notes-dir t "journal.*\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward ":well-being: \\([0-9]+\\)" nil t)
          (let* ((score (string-to-number (match-string 1)))
                 (date (when (string-match "\\([0-9]\\{8\\}\\)" file)
                        (match-string 1 file))))
            (when (and date (> score 0))
              (push (list date score file) results))))))
    (setq results (sort results (lambda (a b) (string< (car a) (car b)))))
    (with-current-buffer (get-buffer-create "*Well-being History*")
      (read-only-mode -1)
      (erase-buffer)
      (org-mode)
      (insert "#+title: Historia Well-being\n")
      (insert "#+startup: overview\n\n")
      (insert "* 📊 Historia Well-being\n\n")
      (insert "| Data | Score | Emoji | Journal |\n")
      (insert "|------|-------|-------|----------|\n")
      (dolist (entry results)
        (let* ((date (car entry))
               (score (cadr entry))
               (file (caddr entry))
               (date-fmt (format "%s-%s-%s"
                               (substring date 0 4)
                               (substring date 4 6)
                               (substring date 6 8)))
               (emoji (cond ((>= score 9) "😊")
                           ((>= score 7) "🙂")
                           ((>= score 5) "😐")
                           ((>= score 3) "😕")
                           (t "😔")))
               (filename (file-name-nondirectory file)))
          (insert (format "| %s | %d | %s | [[file:%s][%s]] |\n"
                         date-fmt score emoji file filename))))
      (insert "\n** 📈 Statystyki\n\n")
      (let* ((scores (mapcar 'cadr results))
             (avg (if scores (/ (apply '+ scores) (float (length scores))) 0))
             (min-score (if scores (apply 'min scores) 0))
             (max-score (if scores (apply 'max scores) 0)))
        (insert (format "- Średnia: %.1f\n" avg))
        (insert (format "- Min: %d | Max: %d\n" min-score max-score))
        (insert (format "- Liczba wpisów: %d\n" (length results))))
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "q") 'quit-window))
    (switch-to-buffer "*Well-being History*")))

;; --- Well-being: graf ASCII ---
(defun my/denote-wellbeing-graph ()
  "Pokaż graf well-being (ASCII art)."
  (interactive)
  (let ((results '()))
    (dolist (file (directory-files my-notes-dir t "journal.*\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward ":well-being: \\([0-9]+\\)" nil t)
          (let* ((score (string-to-number (match-string 1)))
                 (date (when (string-match "\\([0-9]\\{8\\}\\)" file)
                        (substring (match-string 1 file) 4 8))))  ; MMDD
            (when (and date (> score 0))
              (push (list date score) results))))))
    (setq results (sort results (lambda (a b) (string< (car a) (car b)))))
    (with-current-buffer (get-buffer-create "*Well-being Graph*")
      (read-only-mode -1)
      (erase-buffer)
      (insert "╔════════════════════════════════════╗\n")
      (insert "║   📊 Graf Well-being (0-10)        ║\n")
      (insert "╚════════════════════════════════════╝\n\n")
      (dolist (entry results)
        (let* ((date (car entry))
               (score (cadr entry))
               (bar (make-string score ?█))
               (emoji (cond ((>= score 9) "😊")
                           ((>= score 7) "🙂")
                           ((>= score 5) "😐")
                           ((>= score 3) "😕")
                           (t "😔"))))
          (insert (format "%s %s | %s %d\n"
                         date emoji bar score))))
      (insert "\n────────────────────────────────────\n")
      (insert "Zamknij: q\n")
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "q") 'quit-window))
    (switch-to-buffer "*Well-being Graph*")))

;; --- Well-being: wykres graficzny (gnuplot) ---
(defun my/denote-wellbeing-plot ()
  "Pokaż graficzny wykres well-being (wymaga gnuplot)."
  (interactive)
  (let ((results '())
        (data-file (expand-file-name "wellbeing-data.txt" temporary-file-directory)))
    ;; Zbierz dane
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
    (setq results (sort results (lambda (a b) (string< (car a) (car b)))))
    
    ;; Zapisz dane do pliku
    (with-temp-file data-file
      (dolist (entry results)
        (insert (format "%s %d\n" (car entry) (cadr entry)))))
    
    ;; Stwórz wykres w Org-mode
    (with-current-buffer (get-buffer-create "*Well-being Plot*")
      (read-only-mode -1)
      (erase-buffer)
      (org-mode)
      (insert "#+title: Well-being Wykres\n\n")
      (insert "* 📊 Wykres Well-being\n\n")
      (insert "#+PLOT: title:\"Well-being over time\" ind:1 deps:(2) type:2d with:linespoints\n")
      (insert "| Data | Score |\n")
      (insert "|------------|-------|\n")
      (dolist (entry results)
        (insert (format "| %s | %d |\n" (car entry) (cadr entry))))
      (insert "\n")
      (insert "Aby wygenerować wykres: C-c \" (org-plot)\n")
      (goto-char (point-min))
      (re-search-forward "^|" nil t)
      (org-table-align)
      (read-only-mode 1)
      (local-set-key (kbd "q") 'quit-window))
    (switch-to-buffer "*Well-being Plot*")
    (message "Naciśnij C-c \" na tabeli aby wygenerować wykres")))

;; --- Well-being: ustaw z konkretnego pliku ---
(defun my/denote-set-wellbeing-for-file (file)
  "Ustaw well-being dla konkretnego pliku journala."
  (interactive "fJournal file: ")
  (find-file file)
  (goto-char (point-min))
  (if (re-search-forward "^:well-being:.*$" nil t)
      (let ((score (read-number "Well-being (0-10): " 7)))
        (beginning-of-line)
        (kill-line)
        (insert (format ":well-being: %d" score))
        (save-buffer)
        (message "✅ Well-being ustawione: %d" score))
    (message "⚠️  To nie jest journal z własnością :well-being:")))

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
;; EXPORT TAGS LIST
;; ============================================================

(defun my/denote-export-all-tags ()
  "Zrzuć wszystkie tagi z notatek do pliku tags-list.org."
  (interactive)
  (let* ((all-files (denote-directory-files))
         (all-tags (delete-dups
                    (sort
                     (flatten-list
                      (mapcar (lambda (file)
                                (denote-extract-keywords-from-path file))
                              all-files))
                     #'string<)))
         (tag-counts (mapcar (lambda (tag)
                               (cons tag
                                     (length (seq-filter
                                              (lambda (file)
                                                (member tag (denote-extract-keywords-from-path file)))
                                              all-files))))
                             all-tags))
         (output-file (expand-file-name "tags-list.org" denote-directory)))
    ;; Write to file
    (with-temp-file output-file
      (insert "#+TITLE: Lista Wszystkich Tagów\n")
      (insert "#+DATE: " (format-time-string "%Y-%m-%d %H:%M") "\n\n")
      (insert (format "Łącznie tagów: %d\n" (length all-tags)))
      (insert (format "Łącznie notatek: %d\n\n" (length all-files)))
      (insert "* Wszystkie tagi (z liczbą notatek)\n\n")
      (insert "| Tag | Liczba notatek |\n")
      (insert "|-----+----------------|\n")
      (dolist (tag-count tag-counts)
        (insert (format "| %s | %d |\n" (car tag-count) (cdr tag-count))))
      (insert "\n* Lista alfabetyczna (tylko nazwy)\n\n")
      (dolist (tag all-tags)
        (insert (format "- %s\n" tag))))
    ;; Open file
    (find-file output-file)
    (message "✅ Tagi wyeksportowane do: %s" output-file)))

;; ============================================================
;; ORG HTML EXPORT - DEDICATED FOLDER + AUTO-CLEANUP
;; ============================================================

;; Create html/ folder if not exists
(let ((html-dir (expand-file-name "html" my/notes-dir)))
  (unless (file-directory-p html-dir)
    (make-directory html-dir t)))

;; Auto-cleanup LaTeX artifacts + move HTML AFTER export completes
(defun my/org-export-cleanup (backend)
  "Usuń LaTeX artifacts i przenieś HTML do ~/notes/html/ po eksporcie."
  (when (eq backend 'html)
    (let* ((base-name (file-name-sans-extension (buffer-file-name)))
           (html-file (concat base-name ".html"))
           (html-dir (expand-file-name "html" my/notes-dir)))
      ;; 1. Delete LaTeX artifacts
      (dolist (ext '("aux" "log" "tex" "fdb_latexmk" "fls" "out" "toc" "nav" "snm"))
        (let ((artifact (concat base-name "." ext)))
          (when (file-exists-p artifact)
            (delete-file artifact))))
      ;; 2. Move HTML to dedicated folder
      (when (file-exists-p html-file)
        (let ((target-html (expand-file-name (file-name-nondirectory html-file) html-dir)))
          (rename-file html-file target-html t)
          (message "✅ HTML: %s" target-html))))))

;; Hook: Run cleanup AFTER export finishes (note: this hook takes 3 args, but we only use 1)
(add-hook 'org-export-finished-hook 'my/org-export-cleanup)

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
;; TRANSIENT NOTES MENU
;; ============================================================

(require 'transient)

(transient-define-prefix my/notes-transient-menu ()
  "Denote notes creation and management menu"
  ["Denote Notes"
   ["Create Notes"
    ("n" "New note" denote)
    ("j" "Journal (today)" my/denote-journal)
    ("J" "Journal (date)" my/denote-journal-date)
    ("z" "Zettelkasten" my/denote-zettel)
    ("o" "Person" my/denote-osoba)
    ("p" "Project" my/denote-create-project)]
   
   ["Academic & Essays"
    ("P" "Philosopher" my/denote-philosopher)
    ("L" "Literature" my/denote-literature)
    ("E" "Essay" my/denote-essay)
    ("b" "Base note" my/denote-base)
    ("s" "Shortcut" my/denote-skroty)]
   
   ["Search & Find"
    ("f" "Find file" consult-denote-find)
    ("g" "Grep notes" consult-denote-grep)
    ("x" "Find property" my/denote-find-by-property)
    ("l" "Insert link" denote-link)
    ("r" "Rename file" denote-rename-file)]
   
   ["Well-being"
    ("w" "Set well-being" my/denote-set-wellbeing)]
   
  ["Statistics & Management"
   ["Stats"
    ("#" "Word count" count-words)
    ("%" "Note stats" my/denote-stats)
    ("@" "Dashboard" my/pkm-dashboard)]
   
   ["Export & Sync"
    ("h" "Export HTML" my/denote-export-to-html)
    ("H" "Export all HTML" my/denote-export-all-to-html)
    ("m" "Export Markdown" org-md-export-to-markdown)
    ("M" "Export PDF" org-latex-export-to-pdf)]
   
   ["Utilities"
    ("t" "Insert time" insert-current-time)
    ("d" "Insert date" org-time-stamp)
    ("i" "Insert ID" denote-link-insert-file-name-as-heading)
    ("k" "Keywords" denote-keywords-add)]]
  
  [["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]]

(provide '05-denote-functions)
;;; 05-denote-functions.el ends here
