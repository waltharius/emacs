;;; test-readwise.el --- ERT tests for the token, the sync and the promotion of 24-readwise -*- lexical-binding: t; -*-

;; Tests: 24-readwise

;;; Commentary:

;; 24-readwise.el reads the Readwise token through auth-source, fetches
;; the export endpoint page by page, writes one Org file per book, and
;; turns a quote into a note in the pks silo or adds it to one: the
;; eleventh module of TESTING.org, *Every module tested*, part 3, and the
;; tests of SAFETY.org 3.2 (the token read through auth-source, sent to
;; readwise.io only, written nowhere).
;;
;; No network: `url-retrieve-synchronously' is replaced, by advice
;; (TESTING.org, rule 13), with a stand-in server that records each
;; request -- its address and headers -- and answers from the test.
;; The token comes from a temporary authinfo file named in
;; `auth-sources'.  Files are real, in a temporary folder; the review
;; lists (tabs, windows) are not opened.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-readwise.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.  The promotion tests need
;; the denote package.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'url-parse)
(require 'auth-source)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "01-ui" "05-notes" "24-readwise")

;; ============================================================
;; FIXTURE
;; ============================================================

(defconst my/rw-test--token "not-a-real-readwise-token"
  "The token the temporary authinfo file holds; searched for afterwards.")

(defvar my/rw-test--requests nil
  "Requests the stand-in server received, oldest first: (URL . HEADERS).")

(defmacro my/rw-test--with-tree (&rest body)
  "Run BODY with a Readwise folder, a notes folder and an authinfo file.
Binds `root', `readwise', `notes', `pks' and `authinfo'.  Only the
category books is imported."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-rw-" t)))
          (readwise (file-name-as-directory (expand-file-name "readwise" root)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (pks (file-name-as-directory (expand-file-name "pks" notes)))
          (authinfo (expand-file-name "authinfo" root))
          (my/readwise-directory readwise)
          (my/readwise-categories '("books"))
          (my/readwise-file-keywords '("readwise"))
          (my-notes-dir notes)
          (my-notes-pks pks)
          (auth-sources (list authinfo))
          (auth-source-do-cache nil)
          (inhibit-message t))
     (make-directory pks t)
     (with-temp-file authinfo
       (insert "machine example.org login apikey password wrong-host-token\n"
               "machine readwise.io login apikey password " my/rw-test--token "\n"))
     (auth-source-forget-all-cached)
     (unwind-protect
         (progn ,@body)
       (auth-source-forget-all-cached)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/rw-test--query (url)
  "Return the query parameters of URL as an alist of (NAME . VALUE)."
  (let ((query (cdr (url-path-and-query (url-generic-parse-url url)))))
    (mapcar (lambda (pair) (cons (car pair) (cadr pair)))
            (and query (url-parse-query-string query)))))

(defmacro my/rw-test--with-server (handler &rest body)
  "Run BODY with HANDLER answering the module's requests.
HANDLER gets the query alist of a request and returns (STATUS . JSON).
Each request is recorded in `my/rw-test--requests'."
  (declare (indent 1))
  `(let ((my/rw-test--requests nil)
         (handler ,handler))
     (advice-add 'url-retrieve-synchronously :override
                 (lambda (url &rest _)
                   (setq my/rw-test--requests
                         (append my/rw-test--requests
                                 (list (cons url url-request-extra-headers))))
                   (let ((reply (funcall handler (my/rw-test--query url)))
                         (buffer (generate-new-buffer " *rw-test-reply*")))
                     (with-current-buffer buffer
                       (insert (format "HTTP/1.1 %d %s\nContent-Type: application/json\n\n"
                                       (car reply) (if (= 200 (car reply)) "OK" "Unauthorized"))
                               (cdr reply)))
                     buffer))
                 '((name . my/rw-test-server)))
     (unwind-protect
         (progn ,@body)
       (advice-remove 'url-retrieve-synchronously 'my/rw-test-server))))

(defun my/rw-test--page (books &optional next)
  "Return a successful reply holding BOOKS, with NEXT as the next cursor."
  (cons 200 (json-encode `((count . ,(length books))
                           (nextPageCursor . ,next)
                           (results . ,(vconcat books))))))

(defun my/rw-test--highlight (id text &rest extra)
  "Return a highlight alist with ID and TEXT, plus EXTRA (a plist)."
  (append `((id . ,id) (text . ,text))
          (cl-loop for (k v) on extra by #'cddr
                   collect (cons (intern (substring (symbol-name k) 1)) v))))

(defun my/rw-test--book (id category &rest highlights)
  "Return a book alist with ID in CATEGORY holding HIGHLIGHTS."
  `((user_book_id . ,id)
    (title . ,(format "Book %d" id))
    (readable_title . ,(format "Book %d" id))
    (author . "Emil Cioran")
    (category . ,category)
    (source . "kindle")
    (highlights . ,(vconcat highlights))))

(defun my/rw-test--count (regexp text)
  "Return how many times REGEXP matches in TEXT."
  (let ((n 0) (start 0))
    (while (string-match regexp text start)
      (setq n (1+ n) start (match-end 0)))
    n))

(defun my/rw-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/rw-test--book-files ()
  "Return the book files in the Readwise folder, by name."
  (and (file-directory-p my/readwise-directory)
       (directory-files my/readwise-directory nil "\\`rw[0-9]+--.*\\.org\\'")))

(defun my/rw-test--file-of (id)
  "Return the book file of book ID, or nil."
  (car (and (file-directory-p my/readwise-directory)
            (directory-files my/readwise-directory t (format "\\`rw%d--.*\\.org\\'" id)))))

;; ============================================================
;; THE TOKEN: READ THROUGH AUTH-SOURCE (SAFETY.org 3.2)
;; ============================================================

(ert-deftest my/rw-test-3.2-token-from-auth-source ()
  "The token is the password of the readwise.io entry with login apikey
in the files `auth-sources' names -- not an entry of another host."
  (my/rw-test--with-tree
    (should (equal (my/readwise--token) my/rw-test--token))))

(ert-deftest my/rw-test-3.2-no-token-says-how ()
  "Without a readwise.io entry nothing is fetched: the error says which
line to add."
  (my/rw-test--with-tree
    (with-temp-file authinfo
      (insert "machine example.org login apikey password wrong-host-token\n"))
    (auth-source-forget-all-cached)
    (my/rw-test--with-server (lambda (_q) (my/rw-test--page nil))
      (let ((err (should-error (my/readwise-sync) :type 'user-error)))
        (should (string-match-p "machine readwise.io login apikey password"
                                (error-message-string err))))
      (should-not my/rw-test--requests))))

;; ============================================================
;; THE TOKEN: SENT TO READWISE.IO ONLY (SAFETY.org 3.2)
;; ============================================================

(ert-deftest my/rw-test-3.2-token-sent-to-readwise-only ()
  "Every request of a sync goes to https://readwise.io/api/v2/export/,
with the token in its Authorization header and nowhere in the address."
  (my/rw-test--with-tree
    (my/rw-test--with-server
        (lambda (q)
          (if (assoc "pageCursor" q)
              (my/rw-test--page (list (my/rw-test--book 2 "books" (my/rw-test--highlight 20 "B"))))
            (my/rw-test--page (list (my/rw-test--book 1 "books" (my/rw-test--highlight 10 "A")))
                              "next-page")))
      (my/readwise-sync)
      (should (= 2 (length my/rw-test--requests)))
      (dolist (request my/rw-test--requests)
        (let ((url (url-generic-parse-url (car request))))
          (should (equal (url-type url) "https"))
          (should (equal (url-host url) "readwise.io"))
          (should (equal (car (url-path-and-query url)) "/api/v2/export/"))
          (should-not (string-search my/rw-test--token (car request))))
        (should (equal (cdr request)
                       (list (cons "Authorization" (concat "Token " my/rw-test--token)))))))))

(ert-deftest my/rw-test-pages-followed-to-the-end ()
  "The export is read page by page, each with the cursor the previous
one gave, until a page gives none; the books of all pages are kept."
  (my/rw-test--with-tree
    (my/rw-test--with-server
        (lambda (q)
          (pcase (cdr (assoc "pageCursor" q))
            ('nil (my/rw-test--page (list (my/rw-test--book 1 "books")) "c2"))
            ("c2" (my/rw-test--page (list (my/rw-test--book 2 "books")) "c3"))
            ("c3" (my/rw-test--page (list (my/rw-test--book 3 "books"))))))
      (should (equal (mapcar (lambda (b) (alist-get 'user_book_id b))
                             (my/readwise--fetch-all))
                     '(1 2 3)))
      (should (equal (mapcar (lambda (r) (cdr (assoc "pageCursor" (my/rw-test--query (car r)))))
                             my/rw-test--requests)
                     '(nil "c2" "c3"))))))

;; ============================================================
;; THE TOKEN: WRITTEN NOWHERE (SAFETY.org 3.2)
;; ============================================================

(defun my/rw-test--files-holding (string &rest dirs)
  "Return the files under DIRS whose contents hold STRING."
  (cl-loop for dir in dirs
           when (file-directory-p dir)
           append (cl-remove-if-not
                   (lambda (f)
                     (and (file-regular-p f)
                          (with-temp-buffer
                            (insert-file-contents-literally f)
                            (search-forward string nil t))))
                   (directory-files-recursively dir "" nil))))

(ert-deftest my/rw-test-3.2-token-written-nowhere ()
  "After a sync that succeeds and one the server refuses, the token is
in no file -- the book files, the state file, the notes, the test's
HOME with its settings and ~/.emacs.d -- and not in *Messages*; the
refusal's error does not carry it either.  (The authinfo file, which
holds it by design, lies outside the folders searched.)"
  (my/rw-test--with-tree
    (let ((authinfo-dir (file-name-as-directory (make-temp-file "mypks-rw-auth-" t))))
      (unwind-protect
          (let ((auth-sources (list (expand-file-name "authinfo" authinfo-dir))))
            (rename-file authinfo (car auth-sources))
            (auth-source-forget-all-cached)
            (with-current-buffer (messages-buffer)
              (let ((inhibit-read-only t)) (erase-buffer)))
            (my/rw-test--with-server
                (lambda (_q) (my/rw-test--page
                              (list (my/rw-test--book 1 "books" (my/rw-test--highlight 10 "A" :note "B")))))
              (my/readwise-sync))
            (my/rw-test--with-server (lambda (_q) (cons 401 "{\"detail\": \"Invalid token.\"}"))
              (let ((err (should-error (my/readwise-sync t) :type 'user-error)))
                (should-not (string-search my/rw-test--token (error-message-string err)))))
            (should (my/rw-test--book-files))
            (should-not (my/rw-test--files-holding my/rw-test--token root my/test-sandbox))
            (should-not (with-current-buffer (messages-buffer)
                          (save-excursion
                            (goto-char (point-min))
                            (search-forward my/rw-test--token nil t)))))
        (delete-directory authinfo-dir t)))))

;; ============================================================
;; SYNC: WHAT IS WRITTEN
;; ============================================================

(ert-deftest my/rw-test-full-sync-writes-wanted-books ()
  "A first sync writes one file per book of the wanted categories, in
the Readwise folder, with every highlight; a book of another category
is not written, and nothing lands in the notes folder.  The time of
the sync is recorded."
  (my/rw-test--with-tree
    (my/rw-test--with-server
        (lambda (_q)
          (my/rw-test--page
           (list (my/rw-test--book 1 "books" (my/rw-test--highlight 10 "Pierwszy.")
                                   (my/rw-test--highlight 11 "Drugi."))
                 (my/rw-test--book 2 "articles" (my/rw-test--highlight 20 "Artykuł.")))))
      (my/readwise-sync))
    (should (equal (my/rw-test--book-files) '("rw1--emil-cioran-book-1.org")))
    (should (equal (mapcar (lambda (r) (plist-get r :id))
                           (my/readwise--parse-records (my/rw-test--file-of 1)))
                   '("10" "11")))
    (should-not (directory-files-recursively notes "" nil))
    (should (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9:]\\{8\\}Z\\'"
                            (my/readwise--last-sync)))))

(ert-deftest my/rw-test-incremental-refetches-whole-book ()
  "An incremental sync asks what changed since the recorded time, then
fetches each changed book whole: its file holds every highlight, not
only the changed one."
  (my/rw-test--with-tree
    (my/readwise--save-sync-time "2026-10-01T00:00:00Z")
    (my/rw-test--with-server
        (lambda (q)
          (if (assoc "updatedAfter" q)
              (my/rw-test--page (list (my/rw-test--book 1 "books" (my/rw-test--highlight 12 "Zmieniony."))))
            (my/rw-test--page (list (my/rw-test--book 1 "books"
                                                      (my/rw-test--highlight 10 "Pierwszy.")
                                                      (my/rw-test--highlight 11 "Drugi.")
                                                      (my/rw-test--highlight 12 "Zmieniony."))))))
      (my/readwise-sync)
      (let ((queries (mapcar (lambda (r) (my/rw-test--query (car r))) my/rw-test--requests)))
        (should (equal (cdr (assoc "updatedAfter" (nth 0 queries))) "2026-10-01T00:00:00Z"))
        (should (equal (cdr (assoc "ids" (nth 1 queries))) "1"))
        (should-not (assoc "updatedAfter" (nth 1 queries)))))
    (should (equal (mapcar (lambda (r) (plist-get r :id))
                           (my/readwise--parse-records (my/rw-test--file-of 1)))
                   '("10" "11" "12")))))

(ert-deftest my/rw-test-failed-sync-keeps-state-and-files ()
  "A sync whose second request fails writes no file and leaves the
recorded time as it was, so the next sync asks again for everything it
missed; the book file of an earlier sync is unchanged."
  (my/rw-test--with-tree
    (my/rw-test--with-server
        (lambda (_q) (my/rw-test--page (list (my/rw-test--book 1 "books" (my/rw-test--highlight 10 "Stary.")))))
      (my/readwise-sync))
    (let ((file (my/rw-test--file-of 1)))
      (let ((before (my/rw-test--read file)))
        (my/readwise--save-sync-time "2026-10-01T00:00:00Z")
        (my/rw-test--with-server
            (lambda (q)
              (if (assoc "updatedAfter" q)
                  (my/rw-test--page (list (my/rw-test--book 1 "books" (my/rw-test--highlight 11 "Nowy."))))
                (cons 500 "{}")))
          (should-error (my/readwise-sync) :type 'user-error))
        (should (equal (my/readwise--last-sync) "2026-10-01T00:00:00Z"))
        (should (equal (my/rw-test--read file) before))
        (should (equal (my/rw-test--book-files) (list (file-name-nondirectory file))))))))

(ert-deftest my/rw-test-no-answer-says-offline ()
  "No reply at all (no network): the error says so, and neither the
recorded time nor any file changes."
  (my/rw-test--with-tree
    (my/readwise--save-sync-time "2026-10-01T00:00:00Z")
    (advice-add 'url-retrieve-synchronously :override #'ignore
                '((name . my/rw-test-offline)))
    (unwind-protect
        (let ((err (should-error (my/readwise-sync) :type 'user-error)))
          (should (string-match-p "no answer from readwise.io" (error-message-string err))))
      (advice-remove 'url-retrieve-synchronously 'my/rw-test-offline))
    (should (equal (my/readwise--last-sync) "2026-10-01T00:00:00Z"))
    (should-not (my/rw-test--book-files))))

(ert-deftest my/rw-test-resync-overwrites-same-file ()
  "Syncing a book again rewrites its one file, at the same path, with
what Readwise holds now -- no second copy."
  (my/rw-test--with-tree
    (dolist (text '("Pierwsza wersja." "Druga wersja."))
      (my/rw-test--with-server
          (lambda (_q) (my/rw-test--page (list (my/rw-test--book 1 "books" (my/rw-test--highlight 10 text)))))
        (my/readwise-sync t)))
    (should (= 1 (length (my/rw-test--book-files))))
    (should (equal (plist-get (car (my/readwise--parse-records (my/rw-test--file-of 1))) :quote)
                   "Druga wersja."))))

(ert-deftest my/rw-test-nothing-changed-writes-nothing ()
  "An incremental sync that finds no change writes no book file and
says so."
  (my/rw-test--with-tree
    (my/readwise--save-sync-time "2026-10-01T00:00:00Z")
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
        (my/rw-test--with-server (lambda (_q) (my/rw-test--page nil))
          (my/readwise-sync)
          (should (= 1 (length my/rw-test--requests)))))
      (should-not (my/rw-test--book-files))
      (should (string-match-p "nothing changed" (car messages))))))

;; ============================================================
;; BOOK FILES: WHAT A HIGHLIGHT CAN DO TO THEM
;; ============================================================

(ert-deftest my/rw-test-render-parse-round-trip ()
  "A book file read back gives each highlight as it came: identifier,
quote, comment, location of each kind and address, in order."
  (my/rw-test--with-tree
    (let* ((book (my/rw-test--book
                  1 "books"
                  (my/rw-test--highlight 10 "Pierwszy." :location 12 :location_type "page"
                                         :readwise_url "https://readwise.io/open/10")
                  (my/rw-test--highlight 11 "Drugi\nw dwóch liniach." :note "Mój komentarz."
                                         :location 3 :location_type "order")
                  (my/rw-test--highlight 12 "Trzeci." :location 7 :location_type "location")))
           (file (expand-file-name "rw1--x.org" readwise)))
      (make-directory readwise t)
      (with-temp-file file (insert (my/readwise--render-book book)))
      (should (equal (mapcar (lambda (r) (list (plist-get r :id) (plist-get r :quote)
                                               (plist-get r :note) (plist-get r :location)
                                               (plist-get r :url)))
                             (my/readwise--parse-records file))
                     '(("10" "Pierwszy." nil "s. 12" "https://readwise.io/open/10")
                       ("11" "Drugi\nw dwóch liniach." "Mój komentarz." "poz. 3" nil)
                       ("12" "Trzeci." nil "loc. 7" nil)))))))

(ert-deftest my/rw-test-highlight-cannot-break-file ()
  "Text from Readwise that looks like Org structure -- a heading, the
end of the quote block, the keyword that starts a record -- stays
text: the file keeps one heading, and reads back as one highlight
with all of its text."
  (my/rw-test--with-tree
    (let* ((text "Zdanie.\n* Nagłówek\n#+end_quote\n#+name: rw-999")
           (book (my/rw-test--book 1 "books" (my/rw-test--highlight 10 text :note "** Też nie nagłówek")))
           (rendered (my/readwise--render-book book))
           (file (expand-file-name "rw1--x.org" readwise)))
      (make-directory readwise t)
      (with-temp-file file (insert rendered))
      (with-temp-buffer
        (insert rendered)
        (goto-char (point-min))
        (should (equal (cl-loop while (re-search-forward "^\\*+ .*$" nil t)
                                collect (match-string 0))
                       '("* Cytaty"))))
      (let ((records (my/readwise--parse-records file)))
        (should (equal (mapcar (lambda (r) (plist-get r :id)) records) '("10")))
        (should (string-search "Nagłówek" (plist-get (car records) :quote)))
        (should (string-search "rw-999" (plist-get (car records) :quote)))))))

(ert-deftest my/rw-test-file-name-stays-in-folder ()
  "A book is written to rw<id>--<slug>.org in the Readwise folder,
whatever its title holds -- slashes and dots included."
  (my/rw-test--with-tree
    (let ((file (my/readwise--file-for '((user_book_id . 7)
                                         (title . "../../.ssh/Ciemna/strona")
                                         (author . "A/B")))))
      (should (equal (file-name-directory file) readwise))
      (should (string-match-p "\\`rw7--[[:alnum:]-]+\\.org\\'" (file-name-nondirectory file))))))

;; ============================================================
;; PROMOTED QUOTES AND PROMOTION (the pks silo)
;; ============================================================

(defun my/rw-test--book-file-with (&rest highlights)
  "Write book 1 holding HIGHLIGHTS into the Readwise folder; return its file."
  (let ((file (expand-file-name "rw1--emil-cioran-book-1.org" my/readwise-directory)))
    (make-directory my/readwise-directory t)
    (with-temp-file file
      (insert (my/readwise--render-book (apply #'my/rw-test--book 1 "books" highlights))))
    file))

(defun my/rw-test--pks-note (pks name text)
  "Write the note NAME with TEXT into PKS; return it."
  (let ((file (expand-file-name name pks)))
    (with-temp-file file (insert text))
    file))

(ert-deftest my/rw-test-promoted-own-and-cited ()
  "A note carrying :RW_ID: is that quote -- it leaves the review list;
a note citing it with #+name: leaves it on the list, marked cited; a
quote with both is used up."
  (my/rw-test--with-tree
    (my/rw-test--pks-note pks "20261001T100000--a.org" ":PROPERTIES:\n:RW_ID: rw-1\n:END:\n")
    (my/rw-test--pks-note pks "20261001T100001--b.org" "#+name: rw-2\n#+begin_quote\nx\n#+end_quote\n")
    ;; The note that is quote 3 comes first, the one citing it after:
    ;; a later citation must not turn a used quote back into a cited one.
    (my/rw-test--pks-note pks "20261001T100002--c.org" ":RW_ID: rw-3\n")
    (my/rw-test--pks-note pks "20261001T100003--d.org" "#+name: rw-3\n")
    (my/rw-test--book-file-with (my/rw-test--highlight 1 "a") (my/rw-test--highlight 2 "b")
                                (my/rw-test--highlight 3 "c") (my/rw-test--highlight 4 "d"))
    (let ((table (my/readwise--promoted-ids)))
      (should (eq (gethash "1" table) 'own))
      (should (eq (gethash "2" table) 'cited))
      (should (eq (gethash "3" table) 'own))
      (should-not (gethash "4" table)))
    (let ((entries (my/readwise--collect)))
      (should (= 1 (length entries)))
      (should (equal (mapcar (lambda (r) (plist-get r :id)) (plist-get (car entries) :pending))
                     '("2" "4"))))))

(defmacro my/rw-test--answering (title &rest body)
  "Run BODY with the questions of a promotion answered: TITLE for the
note's title, yes to carrying the comment over, keyword cytat."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'read-string)
              (lambda (prompt &rest _)
                (if (string-prefix-p "Include" prompt) "" ,title)))
             ((symbol-function 'my/notes-read-keywords) (lambda (&rest _) '("cytat"))))
     ,@body))

(defun my/rw-test--first-load-scenario ()
  "Make a note from a quote with Denote not loaded yet; signal on a failure.
Run by `my/rw-test-promote-new-note-is-the-quote' in a child Emacs, so
that Denote is surely not loaded, whatever other tests ran before."
  (should-not (featurep 'denote))
  (my/rw-test--with-tree
    (let* ((file (my/rw-test--book-file-with
                  (my/rw-test--highlight 10 "Czas jest rzeką." :note "Heraklit?")))
           (before (my/rw-test--read file))
           (book (my/readwise--file-book-meta file))
           (record (car (my/readwise--parse-records file))))
      (my/rw-test--answering "Czas jak rzeka"
        (my/readwise--promote record book 'stay))
      (let ((made (directory-files pks t "\\.org\\'")))
        (should (= 1 (length made)))
        (let ((text (my/rw-test--read (car made))))
          (should (string-match-p "^:RW_ID: rw-10$" text))
          (should (string-match-p "^:SOURCE_AUTHOR: Emil Cioran$" text))
          (should (string-match-p "#\\+begin_quote\nCzas jest rzeką\\.\n#\\+end_quote" text))
          (should (string-search "Heraklit?" text))
          (should-not (string-match-p "^#\\+name: rw-10" text))))
      (should (equal (my/rw-test--read file) before))
      (should-not (my/readwise--collect)))))

(ert-deftest my/rw-test-promote-new-note-is-the-quote ()
  "A quote made into a note gives one new note in pks: it carries the
quote's :RW_ID:, the book in its drawer, the quote and the comment; the
book file is unchanged, and the quote leaves the review list.

Before Denote is loaded -- the promotion loads it, inside the binding of
`denote-directory' (TESTING.org, rule 12).  Run in a child Emacs, with
HOME as before the sandbox so it finds the packages, started in a
temporary folder (rule 8): in this Emacs another test may have loaded
Denote already (outside audits of 2026-10-24).  Its exit status is read
(rule 14).  The order of a start where Denote is loaded first is the
next test's."
  (skip-unless (locate-library "denote"))
  (let* ((dir (file-name-as-directory (make-temp-file "mypks-rw-child-" t)))
         (default-directory dir)
         (process-environment (cons (concat "HOME=" my/test-real-home) process-environment)))
    (unwind-protect
        (with-temp-buffer
          (let ((code (call-process
                       (expand-file-name invocation-name invocation-directory) nil t nil
                       "-Q" "--batch" "--eval" "(package-initialize)"
                       "-l" (expand-file-name "tests/test-readwise.el" my/test-repo)
                       "--eval" (concat "(condition-case err"
                                        " (progn (my/rw-test--first-load-scenario) (princ \"RESULT ok\\n\"))"
                                        " (error (princ (format \"RESULT %S\\n\" err))))"))))
            (let ((result (and (re-search-backward "^RESULT \\(.*\\)$" nil t) (match-string 1))))
              (unless (and (eql code 0) (equal result "ok"))
                (ert-fail (list :exit code :result result
                                :output (buffer-substring (max (point-min) (- (point-max) 2000))
                                                          (point-max))))))))
      (delete-directory dir t))))

(ert-deftest my/rw-test-promote-with-denote-loaded ()
  "With Denote loaded first, as at a start where 04-denote runs before,
the new note is in pks too, not in Denote's own folder."
  (skip-unless (require 'denote nil t))
  (my/rw-test--with-tree
    (let* ((denote-directory notes)
           (file (my/rw-test--book-file-with (my/rw-test--highlight 10 "Cytat.")))
           (book (my/readwise--file-book-meta file)))
      (my/rw-test--answering "Cytat"
        (my/readwise--promote (car (my/readwise--parse-records file)) book 'stay))
      (should (= 1 (length (directory-files pks nil "\\.org\\'"))))
      (should-not (directory-files notes nil "\\.org\\'")))))

(ert-deftest my/rw-test-append-keeps-note ()
  "A quote added to an existing note goes at its end: every character
of the note stays in front, the quote is marked cited with #+name:,
and it stays on the review list."
  (my/rw-test--with-tree
    (let* ((old "#+title:      Cioran\n#+identifier: 20261001T100000\n\n* Notatki\nMoje myśli.\n")
           (note (my/rw-test--pks-note pks "20261001T100000--cioran.org" old))
           (file (my/rw-test--book-file-with (my/rw-test--highlight 11 "Cytat do dołączenia.")))
           (book (my/readwise--file-book-meta file))
           (record (car (my/readwise--parse-records file))))
      (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) note)))
        (my/rw-test--answering "unused"
          (my/readwise--promote record book 'append)))
      (let ((text (my/rw-test--read note)))
        (should (string-prefix-p old text))
        (should (string-match-p "^#\\+name: rw-11\n#\\+begin_quote\nCytat do dołączenia\\." text))
        (should-not (string-match-p "^:RW_ID:" text)))
      (should (equal (directory-files pks nil "\\.org\\'") '("20261001T100000--cioran.org")))
      (should (equal (mapcar (lambda (r) (plist-get r :id))
                             (plist-get (car (my/readwise--collect)) :pending))
                     '("11"))))))

(ert-deftest my/rw-test-promoted-quote-cannot-break-note ()
  "A quote whose first line looks like a heading or ends the block: the
note made from it, and the note it is added to, keep one quote block
and no heading from it.  (Reading the book file trimmed the protective
space of the first line until 2026-10-24.)"
  (skip-unless (require 'denote nil t))
  (my/rw-test--with-tree
    (let* ((file (my/rw-test--book-file-with
                  (my/rw-test--highlight 10 "* Nie nagłówek\n#+end_quote\nDalej.")))
           (book (my/readwise--file-book-meta file))
           (record (car (my/readwise--parse-records file)))
           (old (my/rw-test--pks-note pks "20261001T100000--cioran.org" "#+title: Cioran\n")))
      (my/rw-test--answering "Cytat"
        (my/readwise--promote record book 'stay))
      (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) old)))
        (my/rw-test--answering "unused"
          (my/readwise--promote record book 'append)))
      (dolist (note (directory-files pks t "\\.org\\'"))
        (let ((text (my/rw-test--read note)))
          (should-not (string-match-p "^\\* Nie" text))
          (should (= 1 (my/rw-test--count "^#\\+end_quote$" text))))))))

(ert-deftest my/rw-test-zettel-refused-without-module ()
  "Without 22-zettelkasten the zettel action is refused before anything
is asked or written."
  (should-not (fboundp 'my/zettel-adopt))
  (my/rw-test--with-tree
    (let* ((file (my/rw-test--book-file-with (my/rw-test--highlight 10 "Cytat.")))
           (asked nil))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (setq asked t) "x"))
                ((symbol-function 'my/notes-read-keywords) (lambda (&rest _) (setq asked t) nil)))
        (should-error (my/readwise--promote (car (my/readwise--parse-records file))
                                            (my/readwise--file-book-meta file) 'zettel)
                      :type 'user-error))
      (should-not asked)
      (should-not (directory-files pks nil "\\.org\\'")))))

(provide 'test-readwise)
;;; test-readwise.el ends here
