;;; 05a-folgezettel.el --- Smart Folgezettel (Luhmann sequence) system  -*- lexical-binding: t; -*-
;;
;; Description: Inteligentny system Folgezettel z auto-numeracją,
;;              auto-linkowaniem parent/child, wizualizacją drzewa
;;
;;; Commentary:
;;
;; System Folgezettel (Luhmann):
;; - NX       = Top-level (root)
;; - NX.Y     = Child level 1
;; - NX.Ya    = Branch (alternative path)
;; - NX.YaZ   = Deeper level
;;
;; Funkcje:
;; - my/denote-zettel-smart     → Tworzenie z auto-numeracją
;; - my/denote-zettel-tree      → Wizualizacja drzewa
;; - my/denote-find-children    → Lista dzieci danego Zettel
;; - my/denote-find-siblings    → Siblings (rodzeństwo)
;;
;;; Code:

(require 'denote)

;; ============================================================
;; GŁÓWNA FUNKCJA: Smart Zettel Creator
;; ============================================================
(defun my/denote-zettel-smart ()
  "Utwórz Zettel z inteligentnym Folgezettel signature.
Automatycznie generuje signature, linkuje do parenta i dodaje backlink."
  (interactive)
  (let* ((parent-sig (read-string "Parent signature (Enter = nowy root): "))
         (new-sig (if (string-empty-p parent-sig)
                      ;; Nowy top-level - znajdź następny numer
                      (my/folge-next-top-level)
                    ;; Child - wybierz typ
                    (my/folge-next-child parent-sig)))
         (title (read-string "Tytuł: "))
         (keywords-string (read-string "Tagi (opcjonalnie): " "zettel"))
         (keywords (split-string keywords-string " " t))
         ;; Generuj nazwę pliku RĘCZNIE (Denote style)
         (id (format-time-string "%Y%m%dT%H%M%S"))
         (slug (denote-sluggify 'title title))
         (keyword-string (mapconcat #'identity keywords "_"))
         (filename (format "%s==%s--%s__%s.org" 
                          id new-sig slug keyword-string))
         (filepath (expand-file-name filename my-notes-dir)))
    
    ;; ✅ KLUCZOWE: Utwórz NOWY plik!
    (find-file filepath)
    
    ;; Wstaw front matter
    (insert (format "#+title:      %s\n" title))
    (insert (format "#+date:       %s\n" 
                    (format-time-string "[%Y-%m-%d %a %H:%M]")))
    (insert (format "#+filetags:   :%s:\n" keyword-string))
    (insert (format "#+identifier: %s\n" id))
    (insert (format "#+signature:  %s\n\n" new-sig))
    
    ;; Dodaj link do parenta (jeśli istnieje)
    (when (not (string-empty-p parent-sig))
      (let ((parent-file (my/folge-find-file-by-sig parent-sig)))
        (when parent-file
          (insert "\n* Parent\n")
          (insert (format "← [[denote:%s][%s]]\n\n" 
                         (my/folge-get-id-from-file parent-file)
                         parent-sig))
          
          ;; Dodaj backlink w parent
          (with-current-buffer (find-file-noselect parent-file)
            (goto-char (point-max))
            (unless (re-search-backward "^\\* Children$" nil t)
              (goto-char (point-max))
              (insert "\n* Children\n"))
            (goto-char (point-max))
            (insert (format "→ [[denote:%s][%s: %s]]\n"
                           id
                           new-sig
                           title))
            (save-buffer)))))
    
    (save-buffer)
    (message "✅ Stworzono Zettel: %s (%s)" new-sig filepath)))

;; ============================================================
;; NUMERACJA: Top-level (NX)
;; ============================================================

(defun my/folge-next-top-level ()
  "Znajdź następny wolny top-level signature (N1, N2, N3...).
UWAGA: Używa NX (nie NX.1) jako root."
  (let ((max-num 0))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        ;; Szukaj TYLKO top-level: "N[cyfra]" bez kropki/litery po
        (when (re-search-forward "^#\\+signature: *N\\([0-9]+\\)\\([^.a-z0-9]\\|$\\)" nil t)
          (let ((num (string-to-number (match-string 1))))
            (when (> num max-num)
              (setq max-num num))))))
    (format "N%d" (1+ max-num))))

;; ============================================================
;; NUMERACJA: Child signatures
;; ============================================================
(defun my/denote-zettel-smart ()
  "Utwórz Zettel z inteligentnym Folgezettel signature.
Automatycznie generuje signature, linkuje do parenta i dodaje backlink."
  (interactive)
  (let* ((parent-sig (read-string "Parent signature (Enter = nowy root): "))
         (new-sig (if (string-empty-p parent-sig)
                      ;; Nowy top-level - znajdź następny numer
                      (my/folge-next-top-level)
                    ;; Child - wybierz typ
                    (my/folge-next-child parent-sig)))
         (title (read-string "Tytuł: "))
         (keywords-string (read-string "Tagi (opcjonalnie): " "zettel"))
         (keywords (split-string keywords-string " " t))
         ;; Generuj nazwę pliku RĘCZNIE (Denote style) - BEZ slugify!
         (id (format-time-string "%Y%m%dT%H%M%S"))
         (slug (replace-regexp-in-string 
                "[^[:alnum:]ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]+" "-" 
                (downcase title)))
         (keyword-string (mapconcat #'identity keywords "_"))
         (filename (format "%s==%s--%s__%s.org" 
                          id new-sig slug keyword-string))
         (filepath (expand-file-name filename my-notes-dir)))
    
    ;; ✅ KLUCZOWE: Utwórz NOWY plik!
    (find-file filepath)
    
    ;; Wstaw front matter
    (insert (format "#+title:      %s\n" title))
    (insert (format "#+date:       %s\n" 
                    (format-time-string "[%Y-%m-%d %a %H:%M]")))
    (insert (format "#+filetags:   :%s:\n" keyword-string))
    (insert (format "#+identifier: %s\n" id))
    (insert (format "#+signature:  %s\n\n" new-sig))
    
    ;; Dodaj link do parenta (jeśli istnieje)
    (when (not (string-empty-p parent-sig))
      (let ((parent-file (my/folge-find-file-by-sig parent-sig)))
        (when parent-file
          (insert "\n* Parent\n")
          (insert (format "← [[denote:%s][%s]]\n\n" 
                         (my/folge-get-id-from-file parent-file)
                         parent-sig))
          
          ;; Dodaj backlink w parent
          (with-current-buffer (find-file-noselect parent-file)
            (goto-char (point-max))
            (unless (re-search-backward "^\\* Children$" nil t)
              (goto-char (point-max))
              (insert "\n* Children\n"))
            (goto-char (point-max))
            (insert (format "→ [[denote:%s][%s: %s]]\n"
                           id
                           new-sig
                           title))
            (save-buffer)))))
    
    (save-buffer)
    (message "✅ Stworzono Zettel: %s (%s)" new-sig filepath)))

;; ============================================================
;; POMOCNICZE: Znajdź następny numer
;; ============================================================

(defun my/folge-find-next-number (parent-sig)
  "Znajdź następny numer dla PARENT-SIG.
Przykład: N1 → szuka N1.X → zwraca max(X) + 1"
  (let ((max-num 0)
        (pattern (format "^#\\+signature: *%s\\.\\([0-9]+\\)" (regexp-quote parent-sig))))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward pattern nil t)
          (let ((num (string-to-number (match-string 1))))
            (when (> num max-num)
              (setq max-num num))))))
    (1+ max-num)))

;; ============================================================
;; POMOCNICZE: Znajdź następną literę
;; ============================================================

(defun my/folge-find-next-letter (parent-sig)
  "Znajdź następną literę dla PARENT-SIG.
Przykład: N1 → szuka N1[a-z] → zwraca max(letter) + 1"
  (let ((max-char ?`) ; Znak przed 'a'
        (pattern (format "^#\\+signature: *%s\\([a-z]\\)" (regexp-quote parent-sig))))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward pattern nil t)
          (let ((char (string-to-char (match-string 1))))
            (when (> char max-char)
              (setq max-char char))))))
    (1+ max-char)))

;; ============================================================
;; POMOCNICZE: Znajdź plik po signature
;; ============================================================

(defun my/folge-find-file-by-sig (signature)
  "Znajdź plik z danym SIGNATURE."
  (let ((result nil))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward 
               (format "^#\\+signature: *%s$" (regexp-quote signature)) 
               nil t)
          (setq result file))))
    result))

;; ============================================================
;; POMOCNICZE: Pobierz ID z pliku
;; ============================================================

(defun my/folge-get-id-from-file (file)
  "Pobierz identifier (timestamp ID) z FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+identifier: *\\([0-9T]+\\)" nil t)
      (match-string 1))))

;; ============================================================
;; WIZUALIZACJA: Drzewo Folgezettel
;; ============================================================
(defun my/denote-zettel-tree ()
  "Pokaż drzewo Folgezettel (hierarchia signatures).
Czyta signature z NAZWY PLIKU (==NX), nie z treści!"
  (interactive)
  (let ((sigs '()))
    ;; Zbierz wszystkie pliki ze signature w nazwie
    (dolist (file (directory-files my-notes-dir nil "\\.org$"))
      ;; Regex: ==NX gdzie X to cyfry, kropki, małe litery
      (when (string-match "==\\(N[0-9.a-z]+\\)--" file)
        (let* ((sig (match-string 1 file))
               (full-path (expand-file-name file my-notes-dir))
               (title (with-temp-buffer
                       (insert-file-contents full-path)
                       (goto-char (point-min))
                       (if (re-search-forward "^#\\+title: *\\(.*\\)$" nil t)
                           (match-string 1)
                         "Brak tytułu"))))
          (push (cons sig title) sigs))))
    
    ;; Usuń duplikaty (ten sam sig może być w wielu plikach - błąd!)
    (setq sigs (delete-dups sigs))
    
    ;; Sortuj alfabetycznie (Folgezettel order)
    (setq sigs (sort sigs (lambda (a b) 
                           (my/folge-sig-less-p (car a) (car b)))))
    
    ;; Wyświetl
    (with-current-buffer (get-buffer-create "*Zettel Tree*")
      (read-only-mode -1)
      (erase-buffer)kq
      (org-mode)
      (insert "#+title: Folgezettel Tree\n")
      (insert "#+startup: overview\n\n")
      (dolist (sig sigs)
        (let* ((s (car sig))
               (title (cdr sig))
               (depth (my/folge-sig-depth s))
               (indent (make-string (* 2 depth) ? )))
          (insert (format "%s- %s: %s\n" indent s title))))
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "q") 'quit-window))
    (switch-to-buffer "*Zettel Tree*")
    (message "✅ Drzewo Folgezettel: %d notatek" (length sigs))))

;; ============================================================
;; POMOCNICZE: Głębokość signature
;; ============================================================

(defun my/folge-sig-depth (sig)
  "Oblicz głębokość signature.
N1 → 0, N1.1 → 1, N1.1a → 2, N1.1a1 → 3"
  (let ((depth 0))
    (dolist (char (string-to-list sig))
      (when (or (= char ?.) (and (>= char ?a) (<= char ?z)))
        (setq depth (1+ depth))))
    depth))

;; ============================================================
;; POMOCNICZE: Sortowanie Folgezettel
;; ============================================================

(defun my/folge-sig-less-p (a b)
  "Porównaj dwa signatures według kolejności Folgezettel.
N1 < N1.1 < N1.1a < N1.1a1 < N1.1b < N1.2"
  (let ((parts-a (my/folge-parse-sig a))
        (parts-b (my/folge-parse-sig b)))
    (my/folge-parts-less-p parts-a parts-b)))

(defun my/folge-parse-sig (sig)
  "Parsuj signature na listę komponentów.
N1.1a1 → (1 1 'a' 1)"
  (let ((parts '())
        (current ""))
    (dolist (char (string-to-list sig))
      (cond
       ((= char ?N) nil)  ; Skip 'N'
       ((= char ?.)
        (when (not (string-empty-p current))
          (push (string-to-number current) parts)
          (setq current "")))
       ((and (>= char ?a) (<= char ?z))
        (when (not (string-empty-p current))
          (push (string-to-number current) parts)
          (setq current ""))
        (push char parts))
       ((and (>= char ?0) (<= char ?9))
        (setq current (concat current (char-to-string char))))))
    (when (not (string-empty-p current))
      (push (string-to-number current) parts))
    (nreverse parts)))

(defun my/folge-parts-less-p (a b)
  "Porównaj dwie listy komponentów."
  (cond
   ((null a) (not (null b)))  ; a krótsze → mniejsze
   ((null b) nil)              ; b krótsze → a większe
   (t
    (let ((part-a (car a))
          (part-b (car b)))
      (cond
       ;; Oba liczby
       ((and (numberp part-a) (numberp part-b))
        (if (= part-a part-b)
            (my/folge-parts-less-p (cdr a) (cdr b))
          (< part-a part-b)))
       ;; Liczba < litera
       ((numberp part-a) t)
       ((numberp part-b) nil)
       ;; Obie litery
       (t
        (if (= part-a part-b)
            (my/folge-parts-less-p (cdr a) (cdr b))
          (< part-a part-b))))))))

;; ============================================================
;; NAWIGACJA: Znajdź children
;; ============================================================

(defun my/denote-find-children (signature)
  "Znajdź wszystkie children danego SIGNATURE."
  (interactive "sSignature: ")
  (let ((children '())
        (pattern (format "^#\\+signature: *%s[.a-z]" (regexp-quote signature))))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward pattern nil t)
          (goto-char (match-beginning 0))
          (when (re-search-forward "^#\\+signature: *\\([^ \n]+\\)" nil t)
            (push (match-string 1) children)))))
    (message "Children of %s: %s" signature (string-join children ", "))))

(provide '05a-folgezettel)
;;; 05a-folgezettel.el ends here
