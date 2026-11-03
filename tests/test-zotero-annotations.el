;;; test-zotero-annotations.el --- ERT tests for 417d-zotero-annotations -*- lexical-binding: t; -*-

;; Tests: 417d-zotero-annotations

;;; Commentary:

;; 417d-zotero-annotations inserts the annotations Zotero's local API
;; returns for a reference's PDF or EPUB.  Tested without Zotero: the
;; replies of the local API are stood in for (as the API answered on
;; 2026-11-03, Zotero 10.0.2), and so is citar where a test needs the
;; files of a reference.  Tested: which file is which attachment, which
;; annotations belong to it and in which order, the Org text of one, a
;; second run inserting only what is new, the replies of the API that
;; stop the command, the menu entry, the zotero: link type and the
;; options among the bibliography's settings.  Whether the links open
;; Zotero, and the text against the real reader: TESTPLAN.org, R57.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-zotero-annotations.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "204-denote" "205-notes" "212-transient"
                      "417-bibliography" "417c-zotero" "417d-zotero-annotations")

(defun my/zotann-test--item (key parent sort &rest fields)
  "An item as the local API lists it: KEY, PARENT, SORT index, FIELDS.
FIELDS is a plist of further data fields, with symbol keys."
  (let ((data (list (cons 'key key) (cons 'itemType "annotation")
                    (cons 'parentItem parent) (cons 'annotationSortIndex sort))))
    (while fields
      (push (cons (pop fields) (pop fields)) data))
    (list (cons 'key key) (cons 'data data))))

(defconst my/zotann-test--items
  (list (my/zotann-test--item "ANN00002" "ATT00001" "00091|000263|00106"
                              'annotationType "highlight"
                              'annotationText "Second, on page 40."
                              'annotationPageLabel "40"
                              'annotationColor "#ffd400")
        (my/zotann-test--item "ANN00001" "ATT00001" "00090|000100|00050"
                              'annotationType "highlight"
                              'annotationText "First, on page 39."
                              'annotationPageLabel "39"
                              'annotationColor "#5fb236")
        (my/zotann-test--item "ANN00003" "ATT00001" "00092|000010|00010"
                              'annotationType "highlight"
                              'annotationText "A heading, marked grey."
                              'annotationPageLabel "41"
                              'annotationColor "#AAAAAA")
        (my/zotann-test--item "ANN00009" "OTHER001" "00001|000000|00000"
                              'annotationType "highlight"
                              'annotationText "Another book."))
  "Annotations of two attachments, out of reading order.")

(defmacro my/zotann-test--with-storage (var &rest body)
  "Run BODY with VAR a temporary attachments folder set as Zotero's."
  (declare (indent 1))
  `(let* ((,var (make-temp-file "mypks-zotero-storage-" t))
          (my/zotero-storage-directory ,var))
     (unwind-protect (progn ,@body)
       (delete-directory ,var t))))

(ert-deftest my/zotann-test-attachment-key-from-the-folder ()
  "A file directly in a key-named folder of the attachments folder is
that attachment; anywhere else it is none."
  (my/zotann-test--with-storage storage
    (let ((in (expand-file-name "J27DMSMH/Book - 2022.pdf" storage))
          (deeper (expand-file-name "J27DMSMH/sub/Book.pdf" storage))
          (lower (expand-file-name "j27dmsmh/Book.pdf" storage)))
      (should (equal (my/zotero-annotations--attachment-key in) "J27DMSMH"))
      (should-not (my/zotero-annotations--attachment-key deeper))
      (should-not (my/zotero-annotations--attachment-key lower))
      (should-not (my/zotero-annotations--attachment-key "/tmp/J27DMSMH/Book.pdf"))))
  (let ((my/zotero-storage-directory nil))
    (should-not (my/zotero-annotations--attachment-key "/tmp/J27DMSMH/Book.pdf"))))

(ert-deftest my/zotann-test-annotations-of-one-file-in-reading-order ()
  "Only the attachment's annotations, sorted as the reader shows them;
a colour left out is compared without regard to case."
  (let ((my/zotero-annotations-skip-colors nil))
    (should (equal (mapcar (lambda (i) (alist-get 'key i))
                           (my/zotero-annotations--of "ATT00001" my/zotann-test--items))
                   '("ANN00001" "ANN00002" "ANN00003"))))
  (let ((my/zotero-annotations-skip-colors '("#aaaaaa")))
    (should (equal (mapcar (lambda (i) (alist-get 'key i))
                           (my/zotero-annotations--of "ATT00001" my/zotann-test--items))
                   '("ANN00001" "ANN00002")))))

(ert-deftest my/zotann-test-text-on-one-line ()
  "Line breaks become spaces, words broken at a line end are joined
unless that is off, and a leading star cannot make a heading."
  (let ((my/zotero-annotations-join-hyphens t))
    (should (equal (my/zotero-annotations--clean "z indywidual- nego\npostępu")
                   "z indywidualnego postępu"))
    (should (equal (my/zotero-annotations--clean "Kraków- Warszawa") "Kraków- Warszawa"))
    (should (equal (my/zotero-annotations--clean "* not a heading") " * not a heading"))
    (should (equal (my/zotero-annotations--clean nil) "")))
  (let ((my/zotero-annotations-join-hyphens nil))
    (should (equal (my/zotero-annotations--clean "indywidual- nego") "indywidual- nego"))))

(ert-deftest my/zotann-test-org-text-of-one-annotation ()
  "A highlight: quote, link named after its page, comment.  An image:
no quote, the link says what it opens.  No page label: the link is
named Zotero."
  (let ((my/zotero-annotations-page-format "s. %s"))
    (should (equal (my/zotero-annotations--org
                    (my/zotann-test--item "ANN00001" "ATT00001" "0"
                                          'annotationType "highlight"
                                          'annotationText "Kraków"
                                          'annotationComment " Worth a note. "
                                          'annotationPageLabel "40")
                    "ATT00001")
                   (concat "#+begin_quote\nKraków\n#+end_quote\n"
                           "[[zotero://open-pdf/library/items/ATT00001?annotation=ANN00001][s. 40]]\n"
                           "\nWorth a note.\n\n")))
    (should (equal (my/zotero-annotations--org
                    (my/zotann-test--item "ANN00004" "ATT00001" "0"
                                          'annotationType "image"
                                          'annotationPageLabel "7")
                    "ATT00001")
                   "[[zotero://open-pdf/library/items/ATT00001?annotation=ANN00004][s. 7, image]]\n\n"))
    (should (string-match-p "\\]\\[Zotero\\]\\]"
                            (my/zotero-annotations--org
                             (my/zotann-test--item "ANN00005" "ATT00001" "0"
                                                   'annotationType "highlight"
                                                   'annotationText "No page.")
                             "ATT00001")))))

(defmacro my/zotann-test--with-api (items &rest body)
  "Run BODY with the local API answering ITEMS and one attachment."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'my/zotero-annotations--citekey) (lambda () "boltanski2022"))
             ((symbol-function 'my/zotero-annotations--attachments)
              (lambda (_key) '(("/s/ATT00001/b.pdf" . "ATT00001"))))
             ((symbol-function 'my/zotero-annotations--get) (lambda (_path) ,items)))
     ,@body))

(ert-deftest my/zotann-test-a-second-run-inserts-only-what-is-new ()
  "The first run inserts the file's annotations in reading order; one
already linked in the note is left out; a second run inserts nothing."
  (let ((my/zotero-annotations-skip-colors nil))
    (with-temp-buffer
      (org-mode)
      (insert "#+title: Note\n\n"
              "[[zotero://open-pdf/library/items/ATT00001?annotation=ANN00002][p. 40]]\n\n")
      (my/zotann-test--with-api my/zotann-test--items
        (my/zotero-annotations-insert)
        (let ((text (buffer-string)))
          (should (string-match-p "First, on page 39" text))
          (should-not (string-match-p "Second, on page 40" text))
          (should-not (string-match-p "Another book" text))
          (should (< (string-match "First" text) (string-match "A heading" text))))
        (let ((before (buffer-string)))
          (my/zotero-annotations-insert)
          (should (equal (buffer-string) before)))))))

(ert-deftest my/zotann-test-only-into-org ()
  "Outside an Org buffer the command stops before asking Zotero."
  (with-temp-buffer
    (fundamental-mode)
    (should-error (my/zotero-annotations-insert) :type 'user-error)))

(defun my/zotann-test--reply (text)
  "A reply buffer of url.el holding TEXT as UTF-8 bytes."
  (let ((buffer (generate-new-buffer " *zotero-reply*")))
    (with-current-buffer buffer
      (set-buffer-multibyte nil)
      (insert (encode-coding-string text 'utf-8)))
    buffer))

(ert-deftest my/zotann-test-replies-of-the-api ()
  "A 200 reply is parsed as UTF-8; a refusal names the setting; no
answer says to check whether Zotero runs."
  (cl-letf (((symbol-function 'url-retrieve-synchronously)
             (lambda (&rest _)
               (my/zotann-test--reply
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n[{\"key\":\"K\",\"data\":{\"annotationText\":\"Kraków\",\"annotationComment\":null}}]"))))
    (let ((items (my/zotero-annotations--get "users/0/items?itemType=annotation")))
      (should (equal (alist-get 'annotationText (alist-get 'data (car items))) "Kraków"))
      (should-not (alist-get 'annotationComment (alist-get 'data (car items))))))
  (cl-letf (((symbol-function 'url-retrieve-synchronously)
             (lambda (&rest _) (my/zotann-test--reply "HTTP/1.1 403 Forbidden\r\n\r\n"))))
    (should (string-match-p "Allow other applications"
                            (cadr (should-error (my/zotero-annotations--get "x")
                                                :type 'user-error)))))
  (cl-letf (((symbol-function 'url-retrieve-synchronously)
             (lambda (&rest _) (signal 'file-error '("connection refused")))))
    (should (string-match-p "is Zotero running"
                            (cadr (should-error (my/zotero-annotations--get "x")
                                                :type 'user-error))))))

(ert-deftest my/zotann-test-menu-entry ()
  "C-c x a runs the command, beside the notes of the bibliography menu."
  (skip-unless (and (featurep 'transient) (fboundp 'my/bibliography-menu)))
  (should (eq (my/transient--layout-command
               (transient-get-suffix 'my/bibliography-menu "a"))
              'my/zotero-annotations-insert)))

(ert-deftest my/zotann-test-zotero-links-open-in-zotero ()
  "zotero: links follow through `browse-url' with the scheme restored."
  (require 'ol)
  (should (eq (org-link-get-parameter "zotero" :follow) #'my/zotero-annotations--follow))
  (let (opened)
    (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (setq opened url))))
      (my/zotero-annotations--follow "//open-pdf/library/items/ATT00001?annotation=ANN00001" nil))
    (should (equal opened "zotero://open-pdf/library/items/ATT00001?annotation=ANN00001"))))

(ert-deftest my/zotann-test-in-the-bibliography-settings ()
  "The options are among the settings the bibliography menu opens."
  (dolist (option '(my/zotero-api-url my/zotero-annotations-page-format
                    my/zotero-annotations-skip-colors my/zotero-annotations-join-hyphens))
    (should (assq option (get 'my/bibliography 'custom-group)))))

(provide 'test-zotero-annotations)
;;; test-zotero-annotations.el ends here
