;;; test-writing-export.el --- ERT tests for ODT and DOCX export of 729-writing-export -*- lexical-binding: t; -*-

;; Tests: 729-writing-export

;;; Commentary:

;; 729-writing-export.el exports a note to ODT through Org and converts
;; it to DOCX with LibreOffice, into the folder of its writing project
;; or a folder mirroring its silo: TESTING.org, *Every module tested*,
;; part 3.  On real files in a temporary folder.  LibreOffice is played
;; by small shell scripts on `exec-path' (one that converts by copying,
;; one that fails, one that never finishes), so the tests run where it
;; is not installed; Org's own ODT export runs for real and needs zip.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-writing-export.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "428-writing-projects" "729-writing-export")
(require 'ox-odt)

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/office-test--with-folders (&rest body)
  "Run BODY with a notes folder `notes', its silo `pks', `projects',
an export folder `out', a folder `bin' as the whole `exec-path' (zip
linked into it), and
`temporary-file-directory' in `tmp'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-office-" t)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (pks (file-name-as-directory (expand-file-name "pks" notes)))
          (projects (file-name-as-directory (expand-file-name "projects" root)))
          (out (file-name-as-directory (expand-file-name "export" notes)))
          (bin (file-name-as-directory (expand-file-name "bin" root)))
          (tmp (file-name-as-directory (expand-file-name "tmp" root)))
          (my-notes-dir notes)
          (my/office-output-dir out)
          (my/writing-projects-directory projects)
          (temporary-file-directory tmp)
          (zip (executable-find "zip"))
          ;; Only the scripts and zip: a LibreOffice installed here is
          ;; not found.
          (exec-path (list bin))
          (inhibit-message t))
     (dolist (d (list pks projects bin tmp)) (make-directory d t))
     (when zip (make-symbolic-link zip (expand-file-name "zip" bin)))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/office-test--write (file text)
  "Write TEXT to FILE, creating its folder; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/office-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents-literally file) (buffer-string)))

(defun my/office-test--soffice (bin body)
  "Make BIN/soffice a shell script running BODY.
Its arguments are those of LibreOffice: --headless --convert-to FORMAT
--outdir DIR FILE, so in BODY $3 is the format, $5 the folder, $6 the file."
  (let ((script (expand-file-name "soffice" bin)))
    (my/office-test--write script (concat "#!/bin/sh\n" body "\n"))
    (set-file-modes script #o755)
    script))

(defconst my/office-test--copying
  "base=$(basename \"$6\" .odt)\ncp \"$6\" \"$5/$base.$3\""
  "A LibreOffice that converts by copying the file under the new extension.")

(defun my/office-test--note (dir name title &optional extra)
  "Write the note NAME titled TITLE in DIR; return its file."
  (my/office-test--write (expand-file-name name dir)
                         (format "#+title: %s\n%s\nThe text of the note.\n" title (or extra ""))))

(defun my/office-test--export (file format)
  "Export FILE to FORMAT as the commands do; return the destination."
  (my/office--export file format))

;; ============================================================
;; WHERE THE DOCUMENT GOES
;; ============================================================

(ert-deftest my/office-test-dest-mirrors-the-silo ()
  "A note in a silo exports to that silo's folder under the export
folder; a note directly in the notes folder or outside it, to the
export folder itself."
  (my/office-test--with-folders
    (should (equal (my/office--dest-dir (expand-file-name "a.org" pks))
                   (expand-file-name "pks/" out)))
    (should (equal (my/office--dest-dir (expand-file-name "deep/er/a.org" pks))
                   (expand-file-name "pks/" out)))
    (should (equal (my/office--dest-dir (expand-file-name "a.org" notes)) out))
    (should (equal (my/office--dest-dir (expand-file-name "elsewhere/a.org" root)) out))))

(ert-deftest my/office-test-dest-sibling-folder-not-a-silo ()
  "With the notes folder written without its final slash, a folder whose
name merely begins with it (`notes-old') is not inside it."
  (my/office-test--with-folders
    (let ((my-notes-dir (directory-file-name notes)))
      (should (equal (my/office--dest-dir (expand-file-name "notes-old/x/a.org" root)) out))
      (should-not (file-exists-p (expand-file-name "-old" out))))))

(ert-deftest my/office-test-dest-project ()
  "A note declaring `#+project:' exports into that project's folder."
  (my/office-test--with-folders
    (let ((note (my/office-test--note pks "a.org" "A" "#+project: book talk")))
      (should (equal (my/office--dest-dir note)
                     (expand-file-name "book/export/" projects))))))

;; ============================================================
;; CONVERSION
;; ============================================================

(ert-deftest my/office-test-convert-ok ()
  "A conversion that succeeds returns the new file beside the ODT."
  (my/office-test--with-folders
    (my/office-test--soffice bin my/office-test--copying)
    (let ((odt (my/office-test--write (expand-file-name "doc.odt" tmp) "odt")))
      (should (equal (my/office--convert odt "docx") (expand-file-name "doc.docx" tmp)))
      (should (equal (my/office-test--read (expand-file-name "doc.docx" tmp)) "odt")))))

(ert-deftest my/office-test-convert-fails ()
  "A conversion that exits with an error, or exits 0 without a file,
returns nil and says so."
  (my/office-test--with-folders
    (let ((odt (my/office-test--write (expand-file-name "doc.odt" tmp) "odt"))
          (shown nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (format &rest args) (push (apply #'format format args) shown))))
        (my/office-test--soffice bin "exit 3")
        (should-not (my/office--convert odt "docx"))
        (should (string-match-p "Conversion failed (exit 3)" (car shown)))
        (my/office-test--soffice bin "exit 0")
        (should-not (my/office--convert odt "docx"))
        (should (string-match-p "Conversion failed (exit 0)" (car shown)))))))

(ert-deftest my/office-test-convert-stopped-after-timeout ()
  "A LibreOffice that never finishes is stopped after
`my/office-convert-timeout' seconds; the conversion returns nil soon
after, and says it was stopped."
  (my/office-test--with-folders
    (my/office-test--soffice bin "exec sleep 30")
    (let ((odt (my/office-test--write (expand-file-name "doc.odt" tmp) "odt"))
          (my/office-convert-timeout 1)
          (shown nil)
          (start (float-time)))
      (cl-letf (((symbol-function 'message)
                 (lambda (format &rest args) (push (apply #'format format args) shown))))
        (should-not (my/office--convert odt "docx")))
      (should (< (- (float-time) start) 10))
      (should (string-match-p "did not finish within 1s" (car shown)))
      (should-not (seq-some #'process-live-p (process-list))))))

;; ============================================================
;; EXPORT
;; ============================================================

(ert-deftest my/office-test-export-odt ()
  "An ODT export writes a real ODT (a zip holding content.xml) named
after the title into the silo's folder, and leaves no build folder."
  (skip-unless (executable-find "zip"))
  (my/office-test--with-folders
    (let* ((note (my/office-test--note pks "20261024T100000--a.org" "Rozdział: pierwszy"))
           (dest (my/office-test--export note "odt")))
      (should (equal dest (expand-file-name "pks/Rozdział pierwszy.odt" out)))
      (should (string-prefix-p "PK" (my/office-test--read dest)))
      (should (string-search "content.xml" (my/office-test--read dest)))
      (should-not (directory-files tmp nil "\\`org-odt-"))
      ;; Org's own exports are as before: the output file is named after
      ;; the note again once the export is over.
      (with-current-buffer (find-file-noselect note)
        (should (equal (org-export-output-file-name ".odt")
                       "20261024T100000--a.odt"))))))

(ert-deftest my/office-test-export-docx ()
  "A DOCX export puts only the DOCX into the destination: the ODT and
LibreOffice's files stay in the build folder, which is removed."
  (skip-unless (executable-find "zip"))
  (my/office-test--with-folders
    (my/office-test--soffice bin my/office-test--copying)
    (let* ((note (my/office-test--note pks "20261024T100000--a.org" "Chapter"))
           (dest (my/office-test--export note "docx")))
      (should (equal dest (expand-file-name "pks/Chapter.docx" out)))
      (should (equal (directory-files (expand-file-name "pks/" out) nil "\\`[^.]")
                     '("Chapter.docx")))
      (should-not (directory-files tmp nil "\\`org-odt-")))))

(ert-deftest my/office-test-export-existing-kept-unless-confirmed ()
  "An existing document is replaced only after a yes; after a no nothing
is built and the old one stays."
  (skip-unless (executable-find "zip"))
  (my/office-test--with-folders
    (let* ((note (my/office-test--note pks "20261024T100000--a.org" "Chapter"))
           (old (my/office-test--write (expand-file-name "pks/Chapter.odt" out) "old")))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (should-not (my/office-test--export note "odt")))
      (should (equal (my/office-test--read old) "old"))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
        (should (equal (my/office-test--export note "odt") old)))
      (should (string-prefix-p "PK" (my/office-test--read old))))))

(ert-deftest my/office-test-docx-command-without-libreoffice ()
  "Without LibreOffice the DOCX command refuses at once and leaves the
buffer unsaved and nothing exported."
  (my/office-test--with-folders
    (let ((note (my/office-test--note pks "20261024T100000--a.org" "Chapter")))
      (with-current-buffer (find-file-noselect note)
        (goto-char (point-max))
        (insert "Unsaved.\n")
        (should-error (my/org-export-to-docx) :type 'user-error)
        (should (buffer-modified-p)))
      (should-not (file-exists-p out)))))

(provide 'test-writing-export)
;;; test-writing-export.el ends here
