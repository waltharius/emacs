;;; test-org-images.el --- ERT tests for image attachments of 31-org-images -*- lexical-binding: t; -*-

;; Tests: 31-org-images

;;; Commentary:

;; 31-org-images.el copies images into the attachments folder under the
;; note's identifier, links them, recompresses them in place on request,
;; and tells 05-notes.el which attachments a note being deleted owns:
;; the sixth module of TESTING.org, *Every module tested*, part 3.  On
;; real files in a temporary notes folder.  ImageMagick is not needed:
;; the tests store images as they are, or stand in for the converter --
;; the workflow installs no ImageMagick, and a test that skipped without
;; it would fail there.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-org-images.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.  The search for other notes
;; using an attachment needs grep (or ripgrep) on PATH.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "04-denote" "31-org-images")

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/img-test--with-notes (&rest body)
  "Run BODY in a fresh notes folder with silo pks and an attachments folder.
Binds `root', `pks', `att' and `src' (a folder outside the notes)."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-img-" t)))
          (pks (file-name-as-directory (expand-file-name "pks" root)))
          (att (file-name-as-directory (expand-file-name "attachments" root)))
          (src (file-name-as-directory (make-temp-file "mypks-img-src-" t)))
          (my-notes-dir root)
          (my/org-image-attachments-directory att)
          (my/org-image-link-style 'relative)
          (my/org-image-attr-width nil)
          (inhibit-message t))
     (make-directory pks t)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t)
       (delete-directory src t))))

(defun my/img-test--write (file text)
  "Write TEXT to FILE, creating its folder; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/img-test--note (dir id title &optional body)
  "Write a Denote note ID--slug.org titled TITLE in DIR; return it."
  (my/img-test--write (expand-file-name (format "%s--note.org" id) dir)
                      (format "#+title:      %s\n#+identifier: %s\n\n%s" title id (or body ""))))

;; ============================================================
;; NAMES
;; ============================================================

(ert-deftest my/img-test-slug ()
  "Polish letters stay; anything else between words becomes one hyphen;
nothing usable gives \"image\"; long titles are cut at 60."
  (should (equal (my/org-image--slug "Środa, 25.12 -- żółw!") "środa-25-12-żółw"))
  (should (equal (my/org-image--slug "?!") "image"))
  (should (= 60 (length (my/org-image--slug (make-string 80 ?a))))))

(ert-deftest my/img-test-next-name-never-taken ()
  "The next number follows the highest in use, whatever the extension,
and a name that is somehow taken is stepped past."
  (my/img-test--with-notes
    (my/img-test--write (expand-file-name "20261023T100000--kant-0.png" att) "a")
    (my/img-test--write (expand-file-name "20261023T100000--kant-1.jpg" att) "b")
    (should (equal (my/org-image--target "20261023T100000" "kant" "png")
                   (expand-file-name "20261023T100000--kant-2.png" att)))
    ;; The count says 0, but that name is taken: a name not taken, never
    ;; the existing file.
    (cl-letf (((symbol-function 'my/org-image--next-index) (lambda (&rest _) 0)))
      (let ((target (my/org-image--target "20261023T100000" "kant" "png")))
        (should-not (file-exists-p target))
        (should (string-prefix-p (expand-file-name "20261023T100000--kant-" att) target))))))

;; ============================================================
;; INSERTING
;; ============================================================

(ert-deftest my/img-test-insert-copies-and-links ()
  "Inserting stores a copy named for the note and links it relatively;
the source stays where it was, unchanged."
  (my/img-test--with-notes
    (let* ((note (my/img-test--note pks "20261023T100000" "Kant"))
           (source (my/img-test--write (expand-file-name "photo.svg" src) "<svg/>")))
      (with-current-buffer (find-file-noselect note)
        (goto-char (point-max))
        (my/org-image-insert source "Kant" t)
        (should (string-match-p "^\\[\\[file:\\.\\./attachments/20261023T100000--kant-0\\.svg\\]\\]$"
                                (buffer-string))))
      (should (equal (with-temp-buffer
                       (insert-file-contents (expand-file-name "20261023T100000--kant-0.svg" att))
                       (buffer-string))
                     "<svg/>"))
      (should (file-exists-p source)))))

(ert-deftest my/img-test-insert-second-image-gets-next-number ()
  "A second image of the same note gets the next number; the first stays."
  (my/img-test--with-notes
    (let ((note (my/img-test--note pks "20261023T100000" "Kant"))
          (one (my/img-test--write (expand-file-name "a.svg" src) "one"))
          (two (my/img-test--write (expand-file-name "b.svg" src) "two")))
      (with-current-buffer (find-file-noselect note)
        (my/org-image-insert one "Kant" t)
        (my/org-image-insert two "Kant" t))
      (should (equal (directory-files att nil "\\.svg\\'")
                     '("20261023T100000--kant-0.svg" "20261023T100000--kant-1.svg")))
      (should (equal (with-temp-buffer
                       (insert-file-contents (expand-file-name "20261023T100000--kant-0.svg" att))
                       (buffer-string))
                     "one")))))

(ert-deftest my/img-test-without-converter-stored-as-is ()
  "Without ImageMagick an image is stored unchanged, not lost."
  (cl-letf (((symbol-function 'my/org-image--magick) #'ignore))
    (let ((file (make-temp-file "mypks-img-" nil ".png")))
      (unwind-protect
          (should (equal (my/org-image--compress file nil) (list file "png" 'no-converter)))
        (delete-file file)))))

;; ============================================================
;; RECOMPRESSING IN PLACE
;; ============================================================

(defmacro my/img-test--converter-writing (bytes &rest body)
  "Run BODY with a stand-in converter writing BYTES bytes to its output."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'my/org-image--magick) (lambda () "magick"))
             ((symbol-function 'my/org-image--run)
              (lambda (args &optional _capture)
                (with-temp-file (car (last args)) (insert (make-string ,bytes ?x)))
                t)))
     ,@body))

(ert-deftest my/img-test-recompress-asks-first ()
  "No to the question: nothing is rewritten."
  (my/img-test--with-notes
    (let ((big (my/img-test--write (expand-file-name "20261023T100000--kant-0.png" att)
                                   (make-string 2000 ?o)))
          (my/org-image-max-bytes 1000))
      (my/img-test--converter-writing 10
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) nil)))
          (my/org-image-recompress-attachments)))
      (should (= 2000 (my/org-image--size big))))))

(ert-deftest my/img-test-recompress-only-when-smaller ()
  "Yes: a file is replaced only by a smaller result; a larger result
leaves it as it was."
  (my/img-test--with-notes
    (let ((big (my/img-test--write (expand-file-name "20261023T100000--kant-0.png" att)
                                   (make-string 2000 ?o)))
          (my/org-image-max-bytes 1000))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
        (my/img-test--converter-writing 3000
          (my/org-image-recompress-attachments))
        (should (= 2000 (my/org-image--size big)))
        (my/img-test--converter-writing 10
          (my/org-image-recompress-attachments))
        (should (= 10 (my/org-image--size big)))))))

;; ============================================================
;; WHICH ATTACHMENTS A NOTE OWNS (for deleting it)
;; ============================================================

(ert-deftest my/img-test-note-attachments-own-and-shared ()
  "Named for the note or linked from it, and used by no other note: own.
Linked from another note too: shared, kept.  A link with a scheme names
no file."
  (skip-unless (or (executable-find "rg") (executable-find "grep")))
  (my/img-test--with-notes
    (let* ((named (my/img-test--write (expand-file-name "20261023T100000--kant-0.png" att) "a"))
           (linked (my/img-test--write (expand-file-name "diagram.png" att) "b"))
           (both (my/img-test--write (expand-file-name "20261023T100000--kant-1.png" att) "c"))
           (note (my/img-test--note pks "20261023T100000" "Kant"
                                    (concat "[[file:../attachments/diagram.png]]\n"
                                            "[[file:../attachments/20261023T100000--kant-1.png]]\n"
                                            "[[https://example.org/x.png]]\n"))))
      (my/img-test--note pks "20261024T100000" "Hegel"
                         "[[file:../attachments/20261023T100000--kant-1.png]]\n")
      (let ((report (my/org-image-note-attachments note)))
        (should (equal (sort (plist-get report :own) #'string<) (sort (list named linked) #'string<)))
        (should (equal (plist-get report :shared) (list both)))
        (should (plist-get report :checked))))))

(ert-deftest my/img-test-note-attachments-without-search ()
  "Without a search program nothing can be called the note's own: all
is shared, and the report says it was not checked."
  (my/img-test--with-notes
    (let ((named (my/img-test--write (expand-file-name "20261023T100000--kant-0.png" att) "a"))
          (note (my/img-test--note pks "20261023T100000" "Kant")))
      (cl-letf (((symbol-function 'my/org-image--search-command) #'ignore))
        (let ((report (my/org-image-note-attachments note)))
          (should (null (plist-get report :own)))
          (should (equal (plist-get report :shared) (list named)))
          (should-not (plist-get report :checked)))))))

(ert-deftest my/img-test-search-skips-dot-folders ()
  "A copy in .snapshots that names the attachment is not another user."
  (skip-unless (or (executable-find "rg") (executable-find "grep")))
  (my/img-test--with-notes
    (let ((named (my/img-test--write (expand-file-name "20261023T100000--kant-0.png" att) "a"))
          (note (my/img-test--note pks "20261023T100000" "Kant"
                                   "[[file:../attachments/20261023T100000--kant-0.png]]\n")))
      (my/img-test--write (expand-file-name ".snapshots/1/pks/old.org" root)
                          "[[file:../attachments/20261023T100000--kant-0.png]]\n")
      (should (equal (plist-get (my/org-image-note-attachments note) :own) (list named))))))

(ert-deftest my/img-test-search-with-grep-only ()
  "Without ripgrep, plain grep gives the same answer, .snapshots skipped
too (the workflow's machines may have no ripgrep)."
  (skip-unless (executable-find "grep"))
  (let ((real (symbol-function 'executable-find)))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest args) (unless (equal name "rg") (apply real name args)))))
      (my/img-test--with-notes
        (let ((named (my/img-test--write (expand-file-name "20261023T100000--kant-0.png" att) "a"))
              (shared (my/img-test--write (expand-file-name "20261023T100000--kant-1.png" att) "b"))
              (note (my/img-test--note pks "20261023T100000" "Kant")))
          (my/img-test--note pks "20261024T100000" "Hegel"
                             "[[file:../attachments/20261023T100000--kant-1.png]]\n")
          (my/img-test--write (expand-file-name ".snapshots/1/pks/old.org" root)
                              "[[file:../attachments/20261023T100000--kant-0.png]]\n")
          (should (equal (car (my/org-image--search-command "x")) "grep"))
          (let ((report (my/org-image-note-attachments note)))
            (should (equal (plist-get report :own) (list named)))
            (should (equal (plist-get report :shared) (list shared)))))))))

(provide 'test-org-images)
;;; test-org-images.el ends here
