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
                      (my/folge-next-top-level)
                    (my/folge-next-child parent-sig)))
         (title (read-string (format "Tytuł dla %s: " new-sig)))
         ;; Tworzymy plik z signature RĘCZNIE
         (denote-user-enforced-denote-directory denote-directory)
         (id (format-time-string denote-id-format (current-time)))
         (keywords '("zettel"))
         (slug (denote-sluggify 'title title))
         ;; === FIX: Dodaj rozszerzenie .org ===
         (extension (denote--file-extension denote-file-type))
         (filename (concat
                    (denote-format-file-name 
                     denote-directory 
                     id 
                     keywords 
                     slug 
                     nil  ;; bez extension tutaj
                     new-sig)
                    extension)))  ;; dodaj extension na końcu
    
    ;; Otwórz plik
    (find-file filename)
    
    ;; Dodaj front matter
    (insert (format "#+title: %s\n" title))
    (insert (format "#+date: %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]")))
    (insert (format "#+filetags: :%s:\n" (mapconcat 'identity keywords ":")))
    (insert (format "#+signature: %s\n" new-sig))
    (insert (format "#+identifier: %s\n\n" id))
    
    (save-buffer)
    
    ;; Link do parenta
    (unless (string-empty-p parent-sig)
      (my/folge-add-parent-link parent-sig))
    
    (message "✓ Stworzono Zettel: %s" new-sig)))

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

(defun my/folge-next-child (parent-sig)
  "Zaproponuj następny child signature dla PARENT-SIG.
Użytkownik wybiera: extend (numeric) lub branch (letter)."
  (let* ((choices '("Extend (number)" "Branch (letter)" "Manual"))
         (choice (completing-read 
                  (format "Typ child dla '%s': " parent-sig)
                  choices nil t)))
    (cond
     ;; NX → NX.1 lub NX.Y → NX.Y.1
     ((string-match "Extend" choice)
      (let ((next-num (my/folge-find-next-number parent-sig)))
        (format "%s.%d" parent-sig next-num)))
     
     ;; NX → NXa lub NX.Y → NX.Ya
     ((string-match "Branch" choice)
      (let ((next-letter (my/folge-find-next-letter parent-sig)))
        (format "%s%c" parent-sig next-letter)))
     
     ;; Manual
     (t
      (read-string (format "Child signature dla '%s': " parent-sig))))))

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
  "Wyświetl drzewo Folgezettel w nowym buforze.
Parsuje signature z NAZWY PLIKU (==sig==), nie z treści."
  (interactive)
  (let ((notes '()))
    
    ;; === KLUCZOWA ZMIANA: czytamy signature z NAZWY PLIKU ===
    (dolist (file (directory-files denote-directory t "\\.org$"))
      (when-let ((sig (denote-retrieve-filename-signature file)))
        ;; Pobierz tytuł z nazwy pliku lub z treści
        (let ((title (or (denote-retrieve-filename-title file)
                         "Bez tytułu")))
          (push (cons sig title) notes))))
    
    ;; Sortuj alfabetycznie po signature
    (setq notes (sort notes (lambda (a b) (string< (car a) (car b)))))
    
    ;; Wyświetl w nowym buforze
    (with-current-buffer (get-buffer-create "*Folgezettel Tree*")
      (erase-buffer)
      (org-mode)
      (insert "#+title: Folgezettel Tree\n")
      (insert "#+startup: overview\n\n")
      
      (dolist (note notes)
        (let* ((sig (car note))
               (title (cdr note))
               (level (my/folge-sig-depth sig)))
          (insert (make-string level ?-) " " sig ": " title "\n")))
      
      (goto-char (point-min))
      (switch-to-buffer (current-buffer)))))

;; ============================================================
;; POMOCNICZE: Głębokość signature
;; ============================================================

(defun my/folge-sig-depth (sig)
"Oblicz poziom zagnieżdżenia dla signature.
N1 = 1, N1.1 = 2, N1.1a = 3, N1.1a1 = 4, etc."
  (let ((level 1))
    ;; Usuń prefix 'N' jeśli istnieje
    (when (string-match "^[A-Za-z]+" sig)
      (setq sig (substring sig (match-end 0))))
    
    ;; Liczy kropki i litery
    (dolist (char (string-to-list sig))
      (when (or (= char ?.) (and (>= char ?a) (<= char ?z)))
        (setq level (1+ level))))
    level))

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
