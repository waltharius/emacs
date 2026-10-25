;;; test-inbox-review.el --- ERT tests for accepting, rejecting and extracting inbox notes -*- lexical-binding: t; -*-

;; Tests: 425-inbox-review

;;; Commentary:

;; 425-inbox-review.el moves notes migrated from Obsidian out of the
;; staging inbox into a silo, rewrites [[wikilinks]] to them, settles an
;; identifier they share with a filed note, rejects notes to a folder of
;; their own, and carves text out into new notes: the fourth module of
;; TESTING.org, *Every module tested*, part 3.  On real files in a
;; temporary notes folder; the review list itself (tabs, windows) is
;; not opened.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-inbox-review.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "227-denote-identifiers" "425-inbox-review")

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/inbox-test--with-notes (&rest body)
  "Run BODY in a fresh notes folder: journal, pks, docu, inbox, rejects.
Binds `root', `journal', `pks', `docu', `inbox', `rejects'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-inbox-" t)))
          (journal (file-name-as-directory (expand-file-name "journal" root)))
          (pks (file-name-as-directory (expand-file-name "pks" root)))
          (docu (file-name-as-directory (expand-file-name "docu" root)))
          (inbox (file-name-as-directory (expand-file-name "inbox" root)))
          (rejects (file-name-as-directory (expand-file-name "inbox-odrzucone" root)))
          (my-notes-dir root)
          (my/denote-silo-directories (list journal pks docu))
          (my/inbox-directory inbox)
          (my/inbox-reject-directory rejects)
          (my/inbox-silos `(("pks" . ,pks) ("docu" . ,docu)))
          (my/inbox-journal-directory journal)
          (my/inbox-link-scan-directories (list journal pks docu inbox))
          (inhibit-message t))
     (dolist (d (list journal pks docu inbox)) (make-directory d t))
     (unwind-protect
         (cl-letf (((symbol-function 'my/inbox-review) #'ignore))
           ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/inbox-test--note (dir id slug title &optional body extra)
  "Write the note ID--SLUG.org titled TITLE in DIR; return it.
EXTRA is front matter added after the identifier line."
  (let ((file (expand-file-name (format "%s--%s.org" id slug) dir)))
    (make-directory dir t)
    (with-temp-file file
      (insert (format "#+title:      %s\n#+identifier: %s\n%s\n%s"
                      title id (or extra "") (or body ""))))
    file))

(defun my/inbox-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro my/inbox-test--at (file &rest body)
  "Run BODY with FILE's note as the entry at point of the review list."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'my/inbox--entry)
              (lambda () (my/inbox--file-meta ,file))))
     ,@body))

;; ============================================================
;; ACCEPTING A NOTE INTO A SILO
;; ============================================================

(ert-deftest my/inbox-test-accept-moves-and-repairs-wikilinks ()
  "Accepting moves the note into the silo and turns [[Title]],
[[Title|alias]] and [[Title#heading]] in the journal into denote links."
  (my/inbox-test--with-notes
    (let* ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant"))
           (day (my/inbox-test--note journal "20200302T080000" "2020-03-02" "2020-03-02"
                                     "Read [[Kant]], then [[Kant|the Prussian]] and [[Kant#Ethics]].\n")))
      (my/inbox-test--at note (my/inbox-accept "pks"))
      (should-not (file-exists-p note))
      (should (file-exists-p (expand-file-name "20200301T120000--kant.org" pks)))
      (should (string-match-p
               (regexp-quote "Read [[denote:20200301T120000][Kant]], then [[denote:20200301T120000][the Prussian]] and [[denote:20200301T120000][Kant#Ethics]].")
               (my/inbox-test--read day))))))

(ert-deftest my/inbox-test-accept-clash-moves-only-the-inbox-note ()
  "An identifier shared with a filed note: the inbox note gets the next
free one; the filed note keeps its identifier, and the links of the
collection that point at it still point at it."
  (my/inbox-test--with-notes
    (let* ((filed (my/inbox-test--note journal "20200301T000000" "2020-03-01" "2020-03-01"))
           (linker (my/inbox-test--note pks "20200401T100000" "linker" "Linker"
                                        "That day: [[denote:20200301T000000][2020-03-01]].\n"))
           (note (my/inbox-test--note inbox "20200301T000000" "kant" "Kant")))
      (my/inbox-test--at note (my/inbox-accept "pks"))
      (should (file-exists-p filed))
      (should (file-exists-p (expand-file-name "20200301T000001--kant.org" pks)))
      (should (string-match-p "denote:20200301T000000\\]\\[2020-03-01"
                              (my/inbox-test--read linker))))))

(ert-deftest my/inbox-test-accept-clash-repoints-inbox-links ()
  "Links among inbox notes to the moved note follow its new identifier."
  (my/inbox-test--with-notes
    (my/inbox-test--note journal "20200301T000000" "2020-03-01" "2020-03-01")
    (let* ((note (my/inbox-test--note inbox "20200301T000000" "kant" "Kant"))
           (other (my/inbox-test--note inbox "20200305T000000" "hegel" "Hegel"
                                       "After [[denote:20200301T000000][Kant]].\n")))
      (my/inbox-test--at note (my/inbox-accept "pks"))
      (should (string-match-p "denote:20200301T000001\\]\\[Kant" (my/inbox-test--read other))))))

(ert-deftest my/inbox-test-accept-refuses-existing-name ()
  "A note of the same file name in the silo: refused, both kept."
  (my/inbox-test--with-notes
    (let* ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant"))
           (there (my/inbox-test--note pks "20200301T120000" "kant" "Kant" "Filed text.\n")))
      ;; The same identifier is also a clash; make it free in the silos
      ;; so that the name alone is what is refused.
      (cl-letf (((symbol-function 'my/inbox--ensure-unique-identifier) #'identity))
        (my/inbox-test--at note
          (should-error (my/inbox-accept "pks") :type 'user-error)))
      (should (file-exists-p note))
      (should (string-match-p "Filed text" (my/inbox-test--read there))))))

(ert-deftest my/inbox-test-accept-clash-both-kinds-of-link ()
  "The owner's case (2026-10-22), both kinds of link at once.  A journal
note links to a note not yet imported, [[Kant]], and to another day's
journal note by its identifier, [[denote:20200301T000000]] (the week
links do that).  Kant waits in the inbox with that same identifier.
Accepted: Kant gets the next free second, the [[Kant]] link opens Kant
under its new identifier, and the link to the journal day still opens
the journal day."
  (my/inbox-test--with-notes
    (let* ((day (my/inbox-test--note journal "20200301T000000" "2020-03-01" "2020-03-01"))
           (week (my/inbox-test--note journal "20200302T000000" "2020-03-02" "2020-03-02"
                                      "Yesterday: [[denote:20200301T000000][2020-03-01]].  Read [[Kant]].\n"))
           (note (my/inbox-test--note inbox "20200301T000000" "kant" "Kant")))
      (my/inbox-test--at note (my/inbox-accept "pks"))
      (should (file-exists-p day))
      (should (file-exists-p (expand-file-name "20200301T000001--kant.org" pks)))
      (should (equal (my/inbox-test--read week)
                     (concat "#+title:      2020-03-02\n#+identifier: 20200302T000000\n\n"
                             "Yesterday: [[denote:20200301T000000][2020-03-01]].  "
                             "Read [[denote:20200301T000001][Kant]].\n"))))))

;; ============================================================
;; REJECTING
;; ============================================================

(ert-deftest my/inbox-test-accept-link-opens-at-heading ()
  "A link to a heading the accepted note has, also one with tags,
opens at it ([[denote:ID::*Heading][...]]); a link to a heading it
lacks keeps the heading in its text only, so following it opens the
note rather than failing with \"No match\"."
  (my/inbox-test--with-notes
    (let* ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant"
                                      "* Ethics\nText.\n* Logic :draft:\nMore.\n"))
           (day (my/inbox-test--note journal "20200302T080000" "2020-03-02" "2020-03-02"
                                     "[[Kant#Ethics]], [[Kant#Logic|logika]], [[Kant#Aesthetics]].\n")))
      (my/inbox-test--at note (my/inbox-accept "pks"))
      (should (string-match-p
               (regexp-quote (concat "[[denote:20200301T120000::*Ethics][Kant#Ethics]], "
                                     "[[denote:20200301T120000::*Logic][logika]], "
                                     "[[denote:20200301T120000][Kant#Aesthetics]]."))
               (my/inbox-test--read day))))))

(ert-deftest my/inbox-test-accept-repairs-links-in-sub-folders ()
  "A wikilink in a note kept in a sub-folder of a silo is repaired too,
also with that note open read only; one in a dot folder is not touched.  (The scan was flat until
2026-10-24.)"
  (my/inbox-test--with-notes
    (let* ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant"))
           (deep (my/inbox-test--note (expand-file-name "2020" journal) "20200302T080000"
                                      "2020-03-02" "2020-03-02" "Read [[Kant]].\n"))
           (hidden (my/inbox-test--note (expand-file-name ".old" journal) "20200303T080000"
                                        "2020-03-03" "2020-03-03" "Read [[Kant]].\n")))
      ;; The linking note open read only, as a preview leaves it.
      (with-current-buffer (find-file-noselect deep) (view-mode 1))
      (my/inbox-test--at note (my/inbox-accept "pks"))
      (should (string-match-p (regexp-quote "Read [[denote:20200301T120000][Kant]].")
                              (my/inbox-test--read deep)))
      (should (string-match-p (regexp-quote "Read [[Kant]].") (my/inbox-test--read hidden))))))

(ert-deftest my/inbox-test-preview-then-accept-with-clash ()
  "The note previewed (read only, `view-mode') and then accepted with an
identifier shared with a filed note: accepted without an error, and the
preview buffer follows the note to its new name in the silo."
  (my/inbox-test--with-notes
    (my/inbox-test--note journal "20200301T000000" "2020-03-01" "2020-03-01")
    (let* ((note (my/inbox-test--note inbox "20200301T000000" "kant" "Kant"))
           (buf (find-file-noselect note))
           (moved (expand-file-name "20200301T000001--kant.org" pks)))
      (with-current-buffer buf (view-mode 1))
      (my/inbox-test--at note (my/inbox-accept "pks"))
      (should (file-exists-p moved))
      (should-not (file-exists-p note))
      (should (equal (buffer-file-name buf) moved)))))

(ert-deftest my/inbox-test-accept-unsaved-linker-refused ()
  "A note linking to the accepted one, open with unsaved text and not
saved when asked: nothing moves and nothing is written; the error names
the buffer."
  (my/inbox-test--with-notes
    (let* ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant"))
           (day (my/inbox-test--note journal "20200302T080000" "2020-03-02" "2020-03-02"
                                     "Read [[Kant]].\n"))
           (before (my/inbox-test--read day))
           (buf (find-file-noselect day)))
      (with-current-buffer buf (goto-char (point-max)) (insert "Typed.\n"))
      (cl-letf (((symbol-function 'save-some-buffers) #'ignore))
        (let ((err (should-error (my/inbox-test--at note (my/inbox-accept "pks"))
                                 :type 'user-error)))
          (should (string-search (buffer-name buf) (error-message-string err)))))
      (should (file-exists-p note))
      (should (equal (my/inbox-test--read day) before))
      (should (buffer-modified-p buf)))))

(ert-deftest my/inbox-test-reject-keeps-unsaved-buffer ()
  "Rejecting a note open with unsaved text: the buffer follows it to the
reject folder and keeps the text, still unsaved."
  (my/inbox-test--with-notes
    (let* ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant" "Text.\n"))
           (buf (find-file-noselect note)))
      (with-current-buffer buf (goto-char (point-max)) (insert "Typed.\n"))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
        (my/inbox-test--at note (my/inbox-reject)))
      (should (equal (buffer-file-name buf)
                     (expand-file-name (file-name-nondirectory note) rejects)))
      (should (buffer-modified-p buf))
      (should (string-search "Typed." (with-current-buffer buf (buffer-string)))))))

(ert-deftest my/inbox-test-reject-moves-never-deletes ()
  "No leaves the note; yes moves it to the reject folder, whole."
  (my/inbox-test--with-notes
    (let* ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant" "Text.\n"))
           (text (my/inbox-test--read note)))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) nil)))
        (my/inbox-test--at note (my/inbox-reject)))
      (should (file-exists-p note))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
        (my/inbox-test--at note (my/inbox-reject)))
      (should-not (file-exists-p note))
      (should (equal (my/inbox-test--read (expand-file-name (file-name-nondirectory note) rejects))
                     text)))))

;; ============================================================
;; EXTRACTING TEXT INTO A NEW NOTE
;; ============================================================

(defmacro my/inbox-test--extracting (title silo &rest body)
  "Run BODY answering TITLE, no keywords and SILO to the extract questions."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'read-string) (lambda (&rest _) ,title))
             ((symbol-function 'denote-keywords-prompt) (lambda (&rest _) nil))
             ((symbol-function 'completing-read) (lambda (&rest _) ,silo)))
     ,@body))

(ert-deftest my/inbox-test-extract-paragraph ()
  "A paragraph becomes a new note in the silo, recording its source; in
the source a link to the new note takes its place."
  (my/inbox-test--with-notes
    (let ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant"
                                     "First paragraph.\n\nThe part to keep apart.\n\nLast.\n")))
      (with-current-buffer (find-file-noselect note)
        (goto-char (point-min))
        (search-forward "part to keep")
        (my/inbox-test--extracting "Apart" "docu"
          (my/inbox-extract))
        (save-buffer))
      (let* ((new (car (directory-files docu t "--apart\\.org\\'")))
             (text (my/inbox-test--read new))
             (id (my/denote-file-identifier new)))
        (should (string-match-p "The part to keep apart\\." text))
        (should (string-match-p ":extracted_from: 20200301T120000--kant.org" text))
        (let ((source (my/inbox-test--read note)))
          (should-not (string-match-p "part to keep" source))
          (should (string-match-p (regexp-quote (format "[[denote:%s][Apart]]" id)) source))
          (should (string-match-p "First paragraph\\." source))
          (should (string-match-p "Last\\." source)))))))

(ert-deftest my/inbox-test-extract-refuses-front-matter ()
  "Point in the front matter: nothing is extracted, nothing changes."
  (my/inbox-test--with-notes
    (let* ((note (my/inbox-test--note inbox "20200301T120000" "kant" "Kant" "Body.\n"))
           (text (my/inbox-test--read note)))
      (with-current-buffer (find-file-noselect note)
        (goto-char (point-min))
        (my/inbox-test--extracting "X" "docu"
          (should-error (my/inbox-extract) :type 'user-error))
        (should (equal (buffer-string) text)))
      (should (null (directory-files docu nil "\\.org\\'"))))))

(provide 'test-inbox-review)
;;; test-inbox-review.el ends here
