;;; test-notes-files.el --- ERT tests for listing the files of the collection -*- lexical-binding: t; -*-

;; Tests: 000-core 227-denote-identifiers 417-bibliography

;;; Commentary:

;; `my/notes-files' and `my/notes-hidden-p' (000-core.el): the one rule
;; for which files belong to the collection when a folder is walked --
;; no dot folder, no dot file, judged below the folder walked so that
;; the notes folder itself may lie under a dot folder.  Then the modules
;; that used to walk the tree in their own way, through the commands
;; that showed it: identifier scans (227) under a notes folder in
;; ~/.local/share/, citation keys (417) with a .snapshots copy.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-notes-files.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "227-denote-identifiers" "417-bibliography")

(defmacro my/nf-test--with-tree (&rest body)
  "Run BODY with `root' a notes folder under a dot folder, holding notes,
a .snapshots copy, a lock file and a nested folder; `my-notes-dir' is it."
  (declare (indent 0))
  `(let* ((top (file-name-as-directory (make-temp-file "mypks-files-" t)))
          (root (file-name-as-directory (expand-file-name ".local/share/notes" top)))
          (my-notes-dir root)
          (inhibit-message t))
     (unwind-protect
         (progn
           (dolist (file '("pks/20260101T000000--a__x.org"
                           "pks/deeper/20260102T000000--b.org"
                           "pks/.snapshots/1/20260101T000000--a__x.org"
                           ".snapshots/2/pks/20260101T000000--a__x.org"
                           "pks/.stversions/20260101T000000--a__x~old.org"
                           "journal/20260103T000000--day.org"
                           "pks/notes.md"))
             (let ((path (expand-file-name file root)))
               (make-directory (file-name-directory path) t)
               (with-temp-file path
                 (insert "#+title: t\n\n[cite:@smith]\n"))))
           ;; Emacs's lock of a note being edited: a link to nowhere.
           (make-symbolic-link "user@host.1234:1" (expand-file-name "pks/.#20260101T000000--a__x.org" root))
           ,@body)
       (delete-directory top t))))

(defun my/nf-test--rel (files root)
  "Return FILES relative to ROOT, sorted."
  (sort (mapcar (lambda (f) (file-relative-name f root)) files) #'string<))

(ert-deftest my/nf-test-recursive-skips-dot-folders-and-dot-files ()
  "Walking the tree under a notes folder that itself lies in a dot folder
finds every note, in nested folders too, and nothing from .snapshots,
.stversions, or a lock file."
  (my/nf-test--with-tree
    (should (equal (my/nf-test--rel (my/notes-files root "\\.org\\'" t) root)
                   '("journal/20260103T000000--day.org"
                     "pks/20260101T000000--a__x.org"
                     "pks/deeper/20260102T000000--b.org")))
    (should (equal (my/nf-test--rel (my/notes-files (expand-file-name "pks" root) "\\.org\\'") root)
                   '("pks/20260101T000000--a__x.org")))
    (should-not (my/notes-files (expand-file-name "missing" root) "\\.org\\'" t))
    (should-not (my/notes-files nil "\\.org\\'" t))))

(ert-deftest my/nf-test-hidden-p-below-the-root-only ()
  "A file is hidden by a dot folder or dot name below the notes folder,
not by one above it."
  (my/nf-test--with-tree
    (should-not (my/notes-hidden-p (expand-file-name "pks/20260101T000000--a__x.org" root)))
    (should (my/notes-hidden-p (expand-file-name "pks/.snapshots/1/x.org" root)))
    (should (my/notes-hidden-p (expand-file-name ".snapshots/2/pks/x.org" root)))
    (should (my/notes-hidden-p (expand-file-name "pks/.#x.org" root)))
    (should-not (my/notes-hidden-p "/srv/notes/pks/x.org" "/srv/notes/"))))

(ert-deftest my/nf-test-identifier-scan-under-a-dot-folder ()
  "227's scans find the notes when the notes folder lies under a dot
folder.  Until 2026-10-28 the exclusion was matched against the whole
path: every scan came back empty, without an error."
  (my/nf-test--with-tree
    (should (equal (my/nf-test--rel (my/denote-all-files) root)
                   '("journal/20260103T000000--day.org"
                     "pks/20260101T000000--a__x.org"
                     "pks/deeper/20260102T000000--b.org")))
    (let ((my/denote-silo-directories (list (expand-file-name "pks" root))))
      (should (= 2 (length (my/denote--identifier-scope-files)))))))

(ert-deftest my/nf-test-citation-scan-leaves-snapshots-out ()
  "417 lists the notes once: a key used in a note is not counted again
for its copies in .snapshots and .stversions, and a rename does not
write into them."
  (my/nf-test--with-tree
    (let ((my/cite-check-directories (list root)))
      (should (= 3 (length (my/cite--org-files))))
      (my/cite-rename-key "smith" "jones")
      (with-temp-buffer
        (insert-file-contents (expand-file-name "pks/.snapshots/1/20260101T000000--a__x.org" root))
        (should (string-search "@smith" (buffer-string)))))))

(provide 'test-notes-files)
;;; test-notes-files.el ends here
