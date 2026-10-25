;;; test-markdown.el --- ERT tests for Markdown notes of 440-markdown -*- lexical-binding: t; -*-

;; Tests: 440-markdown

;;; Commentary:

;; 440-markdown.el gives Markdown files the treatment of notes: a Denote
;; note in Markdown with `language:' in its front matter, the docu column
;; for docu notes, a column for Markdown outside the notes folder, and
;; buffers a restored session left in the wrong mode re-moded:
;; TESTING.org, *Every module tested*, part 3.  On real files in a
;; temporary folder; markdown-mode, visual-fill-column and Denote run.
;; Not covered: faces and typefaces (weekly tests and the eye).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-markdown.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "440-markdown")
(require 'markdown-mode)
(require 'denote)

(defvar denote-directory)
;; Options of 503b-fonts and 510-visual-fill, not loaded here: declared
;; special so that the tests' `let' binds them as the module reads them.
(defvar my/font-silo-styles)
(defvar my/fill-column-docu)

(defmacro my/md-test--with-folders (&rest body)
  "Run BODY with a notes folder `notes', its silos `pks' and `docu', and
a folder `outside' next to it."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-md-" t)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (pks (file-name-as-directory (expand-file-name "pks" notes)))
          (docu (file-name-as-directory (expand-file-name "docu" notes)))
          (outside (file-name-as-directory (expand-file-name "notes-old" root)))
          (my-notes-dir notes)
          (denote-directory notes)
          (inhibit-message t))
     (dolist (d (list pks docu outside)) (make-directory d t))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/md-test--write (file text)
  "Write TEXT to FILE; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/md-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro my/md-test--in (file &rest body)
  "Run BODY in a `markdown-mode' buffer visiting FILE, without its hooks."
  (declare (indent 1))
  `(with-current-buffer (find-file-noselect ,file)
     (delay-mode-hooks (markdown-mode))
     ,@body))

;; ============================================================
;; WHERE A FILE IS
;; ============================================================

(ert-deftest my/md-test-in-notes ()
  "A file in the notes folder is in the notes; one in a folder whose name
merely begins with it is not, also with the folder written without its
final slash."
  (my/md-test--with-folders
    (let ((inside (my/md-test--write (expand-file-name "a.md" pks) "# A\n"))
          (beside (my/md-test--write (expand-file-name "b.md" outside) "# B\n")))
      (dolist (my-notes-dir (list notes (directory-file-name notes)))
        (my/md-test--in inside
          (should (my/markdown--in-notes-p)))
        (my/md-test--in beside
          (should-not (my/markdown--in-notes-p)))))))

(ert-deftest my/md-test-siloed ()
  "A file is in a silo of `my/font-silo-styles' only inside its folder."
  (my/md-test--with-folders
    (let ((my/font-silo-styles (list (list (directory-file-name pks) :body 'proportional))))
      (my/md-test--in (my/md-test--write (expand-file-name "a.md" pks) "# A\n")
        (should (my/markdown--siloed-p)))
      (my/md-test--in (my/md-test--write (expand-file-name "pks-old/b.md" notes) "# B\n")
        (should-not (my/markdown--siloed-p))))))

(ert-deftest my/md-test-docu-note ()
  "A docu note by its file name, or by the tags of its front matter (YAML
or TOML); not by a `tags: docu' line in its text."
  (my/md-test--with-folders
    (my/md-test--in (my/md-test--write (expand-file-name "20261001T100000--x__docu.md" docu) "# X\n")
      (should (my/markdown--docu-note-p)))
    (my/md-test--in (my/md-test--write (expand-file-name "y.md" docu)
                                       "---\ntitle: y\ntags: [emacs, docu]\n---\n\nText.\n")
      (should (my/markdown--docu-note-p)))
    (my/md-test--in (my/md-test--write (expand-file-name "z.md" docu)
                                       "+++\ntitle = \"z\"\ntags = [\"docu\"]\n+++\n\nText.\n")
      (should (my/markdown--docu-note-p)))
    (my/md-test--in (my/md-test--write (expand-file-name "w.md" pks)
                                       "---\ntitle: w\ntags: [emacs]\n---\n\nAn example:\n\ntags: docu\n")
      (should-not (my/markdown--docu-note-p)))
    (my/md-test--in (my/md-test--write (expand-file-name "v.md" pks)
                                       "---\ntags: [documentation]\n---\n")
      (should-not (my/markdown--docu-note-p)))))

;; ============================================================
;; THE COLUMN
;; ============================================================

(ert-deftest my/md-test-outside-layout ()
  "Outside the notes folder a Markdown file gets a left-aligned column of
`my-fill-column', a centred one, or none, as the option says."
  (my/md-test--with-folders
    (let ((file (my/md-test--write (expand-file-name "README.md" outside) "# Readme\n"))
          (my-fill-column 70)
          (my/markdown-outside-notes-width nil))
      (let ((my/markdown-outside-notes-layout 'column))
        (my/md-test--in file
          (my/markdown--layout-adjust)
          (should visual-fill-column-mode)
          (should (= visual-fill-column-width 70))
          (should-not visual-fill-column-center-text)))
      (kill-buffer (find-buffer-visiting file))
      (let ((my/markdown-outside-notes-layout 'centered))
        (my/md-test--in file
          (my/markdown--layout-adjust)
          (should visual-fill-column-center-text)))
      (kill-buffer (find-buffer-visiting file))
      (let ((my/markdown-outside-notes-layout 'plain))
        (my/md-test--in file
          (my/markdown--layout-adjust)
          (should-not (bound-and-true-p visual-fill-column-mode)))))))

(ert-deftest my/md-test-docu-column ()
  "A docu note in the notes folder, already in a column, gets the docu
width; a pks note keeps its column."
  (my/md-test--with-folders
    (let ((my/fill-column-docu 100))
      (my/md-test--in (my/md-test--write (expand-file-name "20261001T100000--x__docu.md" docu) "# X\n")
        (my/markdown--set-column 70 t)
        (my/markdown--layout-adjust)
        (should (= visual-fill-column-width 100)))
      (my/md-test--in (my/md-test--write (expand-file-name "20261001T110000--y__emacs.md" pks) "# Y\n")
        (my/markdown--set-column 70 t)
        (my/markdown--layout-adjust)
        (should (= visual-fill-column-width 70))))))

;; ============================================================
;; A NEW NOTE AND ITS FRONT MATTER
;; ============================================================

(ert-deftest my/md-test-front-matter-language ()
  "`language:' goes at the end of the YAML front matter and is saved;
it is not added twice, not to TOML, and not when the option is nil."
  (my/md-test--with-folders
    (let ((yaml (my/md-test--write (expand-file-name "a.md" pks) "---\ntitle: a\n---\n\nText.\n"))
          (toml (my/md-test--write (expand-file-name "b.md" pks) "+++\ntitle = \"b\"\n+++\n"))
          (my/markdown-front-matter-language "pl"))
      (my/md-test--in yaml (my/markdown--add-front-matter-language))
      (should (equal (my/md-test--read yaml) "---\ntitle: a\nlanguage:   pl\n---\n\nText.\n"))
      (my/md-test--in yaml (my/markdown--add-front-matter-language))
      (should (equal (my/md-test--read yaml) "---\ntitle: a\nlanguage:   pl\n---\n\nText.\n"))
      (my/md-test--in toml (my/markdown--add-front-matter-language))
      (should (equal (my/md-test--read toml) "+++\ntitle = \"b\"\n+++\n")))
    (let ((plain (my/md-test--write (expand-file-name "c.md" pks) "---\ntitle: c\n---\n"))
          (my/markdown-front-matter-language nil))
      (my/md-test--in plain (my/markdown--add-front-matter-language))
      (should (equal (my/md-test--read plain) "---\ntitle: c\n---\n")))))

(ert-deftest my/md-test-new-note ()
  "A new Markdown note is a Denote note of the Markdown type with
`language:' in its front matter; `denote-file-type' stays Org."
  (my/md-test--with-folders
    (let ((denote-file-type nil)
          (my/markdown-front-matter-language "pl"))
      (cl-letf (((symbol-function 'my/denote-base)
                 (lambda () (interactive)
                   (let ((denote-directory pks)) (denote "Szkic" '("emacs"))))))
        (my/markdown-new-note))
      (let ((files (directory-files pks t "__emacs\\.md\\'")))
        (should (= (length files) 1))
        (let ((text (my/md-test--read (car files))))
          (should (string-prefix-p "---\ntitle:      \"Szkic\"\n" text))
          (should (string-match-p "\nlanguage:   pl\n---\n" text))))
      (should-not denote-file-type))))

;; ============================================================
;; BUFFERS A SESSION RESTORED IN THE WRONG MODE
;; ============================================================

(ert-deftest my/md-test-restore-modes ()
  "A Markdown file left in a stale mode is re-moded; one put into another
mode on purpose is left; the count says how many."
  (my/md-test--with-folders
    (let ((stale (find-file-noselect (my/md-test--write (expand-file-name "CHANGELOG.md" outside) "# C\n")))
          (chosen (find-file-noselect (my/md-test--write (expand-file-name "fixture.md" outside) "a = 1\n"))))
      (with-current-buffer stale (change-log-mode))
      (with-current-buffer chosen (conf-mode))
      (should (= (my/markdown-restore-modes) 1))
      (should (eq (buffer-local-value 'major-mode stale) 'markdown-mode))
      (should (eq (buffer-local-value 'major-mode chosen) 'conf-unix-mode)))))

(provide 'test-markdown)
;;; test-markdown.el ends here
