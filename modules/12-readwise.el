;;; 12-readwise.el --- Readwise integration for literature notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Integrates Readwise highlights into Denote literature notes
;; Handles both Books and Articles with separate note types
;;
;;; Code:

;; ============================================================
;; PACKAGE INSTALLATION
;; ============================================================

(add-to-list 'load-path
             (expand-file-name "org-readwise" user-emacs-directory))

;; Load package
(require 'org-readwise nil t)  ;; nil t = don't error if not found

;; Verify it loaded
(unless (featurep 'org-readwise)
  (message "⚠️  org-readwise not loaded! Check ~/.emacs.d/org-readwise/"))

;; ============================================================
;; FUZZY MATCHING (using built-in string-distance)
;; ============================================================

(defun my/readwise-fuzzy-match-score (str1 str2)
  "Calculate fuzzy match score between STR1 and STR2.
Returns 0-100, where 100 is perfect match.
Uses Levenshtein distance (built-in since Emacs 27)."
  (let* ((s1 (downcase (string-trim str1)))
         (s2 (downcase (string-trim str2)))
         (distance (string-distance s1 s2))
         (max-len (max (length s1) (length s2))))
    (if (= max-len 0)
        100
      (* 100 (- 1.0 (/ (float distance) max-len))))))

(defun my/readwise-contains-substring-p (haystack needle)
  "Check if HAYSTACK contain NEEDLE (case-insensitive, normalized).
Handles Polish characters and special characters."
  (let ((h (downcase (string-trim haystack)))
        (n (downcase (string-trim needle))))
    (string-match-p (regexp-quote n) h)))

;; ============================================================
;; CONFIGURATION
;; ============================================================

(setq org-readwise-output-location
      (expand-file-name "readwise-raw.org" my/notes-dir))
(setq org-readwise-debug-level 1)
(setq org-readwise-sync-highlights t)
(setq org-readwise-sync-reader t)
(setq org-readwise-last-sync-time-file
      (expand-file-name ".readwise-last-sync" user-emacs-directory))

;; ============================================================
;; ARTICLE NOTE CREATION
;; ============================================================

(defun my/denote-article ()
  "Create article note (for web content, PDFs from Readwise Reader)."
  (interactive)
  (let* ((title (read-string "Article title: "))
         (source (read-string "Source (author/website, e.g. 'Thomas Nagel' or 'studioopinii.pl'): "))
         (url (read-string "URL (optional): "))
         (type (completing-read "Type: "
                               '("artykuł" "esej" "blog" "pdf" "wywiad")
                               nil nil "artykuł"))
         (tags-input (read-string "Additional tags (space-separated): " ""))
         (tags-list (split-string tags-input " " t))
         (tags (append (list "lektura" type) tags-list))
         (id (format-time-string "%Y%m%dT%H%M%S"))
         (slug (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase title)))
         (keywords-slug (mapconcat (lambda (k)
                                    (replace-regexp-in-string
                                     "[^[:alnum:]]+" "-" (downcase k)))
                                  tags "_"))
         (filename (format "%s--%s__%s.org" id slug keywords-slug))
         (filepath (expand-file-name filename my/notes-dir)))
    
    (find-file filepath)
    
    ;; Front matter
    (insert (format "#+title:      %s\n" title))
    (insert (format "#+date:       %s\n"
                   (format-time-string "[%Y-%m-%d %a %H:%M]")))
    (insert (format "#+filetags:   :%s:\n"
                   (mapconcat 'identity tags ":")))
    (insert (format "#+identifier: %s\n" id))
    
    ;; Properties
    (insert ":PROPERTIES:\n")
    (insert (format ":SOURCE:    %s\n" source))
    (when (not (string-empty-p url))
      (insert (format ":URL:       %s\n" url)))
    (insert (format ":READ_DATE: %s\n"
                   (format-time-string "[%Y-%m-%d %a]")))
    (insert ":STATUS:    READING\n")
    (insert ":END:\n\n")
    
    ;; Structure
    (insert "* Autor/Źródło\n\n")
    (insert "* Główna teza\n\n")
    (insert "* Kluczowe punkty\n\n")
    (insert "* Moje pytania\n\n")
    (insert "* Powiązania\n\n")
    (insert "* Cytaty\n")
    (insert "#+begin_quote\n\n#+end_quote\n\n")
    (insert "* Fleeting Notes (czytanie 1)\n\n")
    (insert "* Literature Notes (refleksja)\n\n")
    (insert "* Do zbadania dalej\n")
    (insert "- [ ] \n")
    
    (save-buffer)
    (goto-char (point-min))
    (re-search-forward "^\\* Główna teza" nil t)
    (message "✅ Created article note: %s" title)))

;; ============================================================
;; PARSING READWISE RAW FILE
;; ============================================================

(defun my/readwise-parse-raw-file ()
  "Parse readwise-raw.org and return list of items.
Each item is (TYPE TITLE AUTHOR HIGHLIGHTS) where TYPE is 'book or 'article."
  (let ((raw-file (expand-file-name "readwise-raw.org" my/notes-dir))
        (items '()))
    (unless (file-exists-p raw-file)
      (error "Run M-x org-readwise-sync first!"))
    
    (with-current-buffer (find-file-noselect raw-file)
      (goto-char (point-min))
      
      ;; Each top-level heading is a document
      (while (re-search-forward "^\\* \\(.*\\)$" nil t)
        (let* ((heading (match-string 1))
               (type (my/readwise-detect-type heading))
               (title nil)
               (author nil)
               (highlights (my/readwise-collect-highlights)))
          
          ;; Parse heading based on type
          (if (eq type 'book)
              ;; Books: "Author - Title" format
              (progn
                (setq author (my/readwise-extract-field heading 'author))
                (setq title (my/readwise-extract-field heading 'title)))
            ;; Articles: just title, author/source separate
            (progn
              (setq title heading)
              (setq author (my/readwise-extract-article-source))))
          
          (push (list type title author highlights) items))))
    
    (nreverse items)))

(defun my/readwise-detect-type (heading)
  "Detect if HEADING is book or article.
Books typically have 'Author - Title' format.
Articles are usually just titles or URLs."
  (if (string-match-p " - " heading)
      'book
    'article))

(defun my/readwise-extract-field (heading field)
  "Extract FIELD from HEADING.
FIELD can be 'author or 'title.
Expects 'Author - Title' format for books."
  (cond
   ((eq field 'author)
    (if (string-match "^\\([^-]+\\) - " heading)
        (string-trim (match-string 1 heading))
      (read-string (format "Author for '%s': "
                          (substring heading 0 (min 40 (length heading))))
                  "")))
   
   ((eq field 'title)
    (if (string-match "^[^-]+ - \\(.*\\)$" heading)
        (string-trim (match-string 1 heading))
      heading))
   
   (t heading)))

(defun my/readwise-extract-article-source ()
  "Extract source/author from article properties.
Looks for URL or asks user."
  (save-excursion
    (let ((end (save-excursion (or (outline-next-heading) (point-max)))))
      ;; Try to find URL property
      (if (re-search-forward "^:URL: *\\(.*\\)$" end t)
          (let ((url (match-string 1)))
            ;; Extract domain from URL
            (if (string-match "https?://\\([^/]+\\)" url)
                (match-string 1 url)
              url))
        ;; No URL, ask user
        (read-string "Source/Author: " "")))))

(defun my/readwise-collect-highlights ()
  "Collect all highlight under current heading.
Returns list of strings."
  (let ((highlights '())
        (end (save-excursion
               (or (outline-next-heading) (point-max)))))
    (save-excursion
      ;; Highlights are typically sub-headings or list items
      (while (< (point) end)
        (cond
         ;; Sub-heading highlight
         ((looking-at "^\\*\\* \\(.*\\)$")
          (let ((hl (match-string 1)))
            (forward-line)
            ;; Collect multi-line content
            (while (and (< (point) end)
                       (not (looking-at "^\\*")))
              (let ((line (string-trim
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (line-end-position)))))
                (when (not (string-empty-p line))
                  (setq hl (concat hl "\n" line))))
              (forward-line))
            (push hl highlights)))
         
         ;; Quote block
         ((looking-at "^#\\+begin_quote")
          (forward-line)
          (let ((start (point)))
            (when (re-search-forward "^#\\+end_quote" end t)
              (let ((hl (string-trim
                        (buffer-substring-no-properties
                         start (match-beginning 0)))))
                (push hl highlights)))))
         
         ;; Move to next line
         (t (forward-line)))))
    
    (nreverse highlights)))

;; ============================================================
;; MATCHING LOGIC WITH FUZZY SEARCH
;; ============================================================

(defun my/readwise-find-literature-note (title author type)
  "Find existing literature note matching TITLE and AUTHOR.
TYPE is 'book or 'article.
Uses fuzzy matching with 30-char substring and 70% threshold.
Returns filepath or nil."
  (let* ((pattern (if (eq type 'book) "__lektura" "__lektura"))
         (notes (directory-files my/notes-dir t (concat pattern ".*\\.org$")))
         (best-match nil)
         (best-score 0)
         (threshold 70))  ;; 70% similarity required
    
    (dolist (note notes)
      (with-temp-buffer
        (insert-file-contents note)
        (goto-char (point-min))
        (when (re-search-forward "^#\\+title: *\\(.*\\)$" nil t)
          (let* ((note-title (match-string 1))
                 ;; Compare first 30 chars (or full if shorter)
                 (title-substr (substring title 0 (min 30 (length title))))
                 (note-substr (substring note-title 0
                                        (min 30 (length note-title))))
                 (score (my/readwise-fuzzy-match-score
                        title-substr note-substr)))
            
            ;; Also check author match for books
            (when (and (eq type 'book) author)
              (when (my/readwise-contains-substring-p note-title author)
                (setq score (+ score 15))))  ;; Bonus for author match
            
            (when (> score best-score)
              (setq best-score score)
              (setq best-match note))))))
    
    ;; Return match only if above threshold
    (if (>= best-score threshold)
        (progn
          (message "Found match (%.0f%% confident): %s"
                  best-score (file-name-nondirectory best-match))
          best-match)
      nil)))

;; ============================================================
;; INTEGRATION MAIN FUNCTION
;; ============================================================

(defun my/readwise-to-literature ()
  "Process Readwise highlight into Denote literature notes.
Handles both books and articles separately."
  (interactive)
  
  (let ((items (my/readwise-parse-raw-file))
        (created-count 0)
        (updated-count 0))
    
    (dolist (item items)
      (let* ((type (nth 0 item))
             (title (nth 1 item))
             (author (nth 2 item))
             (highlights (nth 3 item))
             (lit-note (my/readwise-find-literature-note title author type)))
        
        (if lit-note
            ;; Update existing note
            (progn
              (find-file lit-note)
              (my/readwise-append-highlights highlights type)
              (save-buffer)
              (setq updated-count (1+ updated-count))
              (message "✅ Updated: %s" title))
          
          ;; Create new note
          (when (yes-or-no-p
                (format "Create %s note for: %s? "
                       (symbol-name type) title))
            (if (eq type 'book)
                (my/readwise-create-book-note title author highlights)
              (my/readwise-create-article-note title author highlights))
            (setq created-count (1+ created-count))))))
    
    (message "✅ Readwise sync complete: %d created, %d updated"
            created-count updated-count)))

(defun my/readwise-append-highlights (highlights type)
  "Append HIGHLIGHTS to current note.
Adds to '* Fleeting Notes (czytanie 1)' section.
TYPE is 'book or 'article (for formatting)."
  (goto-char (point-min))
  (if (re-search-forward "^\\* Fleeting Notes (czytanie 1)" nil t)
      (progn
        (end-of-line)
        (forward-line 1)
        
        ;; Check if Readwise section already exists
        (unless (looking-at "^\\*\\* Highlights from Readwise")
          (insert "\n** Highlights from Readwise ["
                  (format-time-string "%Y-%m-%d") "]\n\n"))
        
        ;; Add highlights
        (dolist (hl highlights)
          (insert "#+begin_quote\n")
          (insert hl "\n")
          (insert "#+end_quote\n\n")))
    (error "Section '* Fleeting Notes (czytanie 1)' not found in current note!")))

(defun my/readwise-create-book-note (title author highlights)
  "Create new book literature note with TITLE, AUTHOR, and HIGHLIGHTS.
Adds 'readwise' tag automatically."
  (let* ((full-title (format "%s - %s" author title))
         (tags-input (read-string "Additional tags (space-separated): " "filozofia"))
         (tags-list (split-string tags-input " " t))
         (tags (append (list "lektura" "readwise") tags-list))
         (id (format-time-string "%Y%m%dT%H%M%S"))
         (slug (replace-regexp-in-string "[^[:alnum:]]+" "-"
                                        (downcase full-title)))
         (keywords-slug (mapconcat (lambda (k)
                                    (replace-regexp-in-string
                                     "[^[:alnum:]]+" "-" (downcase k)))
                                  tags "_"))
         (filename (format "%s--%s__%s.org" id slug keywords-slug))
         (filepath (expand-file-name filename my/notes-dir)))
    
    (find-file filepath)
    
    ;; Front matter (your exact format)
    (insert (format "#+title:      %s\n" full-title))
    (insert (format "#+date:       %s\n"
                   (format-time-string "[%Y-%m-%d %a %H:%M]")))
    (insert (format "#+filetags:   :%s:\n"
                   (mapconcat 'identity tags ":")))
    (insert (format "#+identifier: %s\n" id))
    
    ;; Properties
    (insert ":PROPERTIES:\n")
    (insert ":STATUS:   READING\n")
    (insert (format ":READ_DATE: %s\n"
                   (format-time-string "[%Y-%m-%d %a]")))
    (insert ":END:\n\n")
    
    ;; Standard structure
    (insert "* Autor\n")
    (insert (format "← [[denote:][%s]]\n\n" author))
    (insert "* Teza główna\n\n")
    (insert "* Struktura tekstu\n\n")
    (insert "* Kluczowe koncepty\n\n")
    (insert "* Argumenty\n\n")
    (insert "* Moje pytania\n\n")
    (insert "* Powiązania\n\n")
    (insert "* Cytaty\n")
    (insert "#+begin_quote\n\n#+end_quote\n\n")
    (insert "* Fleeting Notes (czytanie 1)\n\n")
    
    ;; Add Readwise highlights
    (insert "** Highlights from Readwise ["
            (format-time-string "%Y-%m-%d") "]\n\n")
    (dolist (hl highlights)
      (insert "#+begin_quote\n")
      (insert hl "\n")
      (insert "#+end_quote\n\n"))
    
    (insert "* Literature Notes (czytanie 2)\n\n")
    (insert "* Permanent Notes (refleksja)\n\n")
    (insert "* Do zbadania dalej\n")
    (insert "- [ ] \n")
    
    (save-buffer)
    (goto-char (point-min))
    (re-search-forward "^\\* Teza główna" nil t)
    (message "✅ Created book note: %s" full-title)))

(defun my/readwise-create-article-note (title source highlights)
  "Create new article note with TITLE, SOURCE, and HIGHLIGHTS.
Adds 'readwise' tag automatically."
  (let* ((tags-input (read-string "Additional tags (space-separated): " "artykuł"))
         (tags-list (split-string tags-input " " t))
         (tags (append (list "lektura" "readwise") tags-list))
         (id (format-time-string "%Y%m%dT%H%M%S"))
         (slug (replace-regexp-in-string "[^[:alnum:]]+" "-"
                                        (downcase title)))
         (keywords-slug (mapconcat (lambda (k)
                                    (replace-regexp-in-string
                                     "[^[:alnum:]]+" "-" (downcase k)))
                                  tags "_"))
         (filename (format "%s--%s__%s.org" id slug keywords-slug))
         (filepath (expand-file-name filename my/notes-dir)))
    
    (find-file filepath)
    
    ;; Front matter
    (insert (format "#+title:      %s\n" title))
    (insert (format "#+date:       %s\n"
                   (format-time-string "[%Y-%m-%d %a %H:%M]")))
    (insert (format "#+filetags:   :%s:\n"
                   (mapconcat 'identity tags ":")))
    (insert (format "#+identifier: %s\n" id))
    
    ;; Properties
    (insert ":PROPERTIES:\n")
    (insert (format ":SOURCE:    %s\n" source))
    (insert ":STATUS:    READING\n")
    (insert (format ":READ_DATE: %s\n"
                   (format-time-string "[%Y-%m-%d %a]")))
    (insert ":END:\n\n")
    
    ;; Structure
    (insert "* Autor/Źródło\n\n")
    (insert "* Główna teza\n\n")
    (insert "* Kluczowe punkty\n\n")
    (insert "* Moje pytania\n\n")
    (insert "* Powiązania\n\n")
    (insert "* Cytaty\n")
    (insert "#+begin_quote\n\n#+end_quote\n\n")
    (insert "* Fleeting Notes (czytanie 1)\n\n")
    
    ;; Add Readwise highlights
    (insert "** Highlights from Readwise ["
            (format-time-string "%Y-%m-%d") "]\n\n")
    (dolist (hl highlights)
      (insert "#+begin_quote\n")
      (insert hl "\n")
      (insert "#+end_quote\n\n"))
    
    (insert "* Literature Notes (refleksja)\n\n")
    (insert "* Do zbadania dalej\n")
    (insert "- [ ] \n")
    
    (save-buffer)
    (goto-char (point-min))
    (re-search-forward "^\\* Główna teza" nil t)
    (message "✅ Created article note: %s" title)))

(provide '12-readwise)
;;; 12-readwise.el ends here
