;;; test-capture.el --- ERT tests for moving a captured note of 06-capture -*- lexical-binding: t; -*-

;; Tests: 06-capture

;;; Commentary:

;; 06-capture.el moves a note made from a capture into a silo
;; (`my/--move-note-to-silo').  Until 2026-10-24 a file of the same name
;; there was replaced after Emacs's general question, for good (outside
;; audits of 2026-10-24).  The first tests of the module: the rest of it
;; follows in TESTING.org, part 3.  On real files in a temporary folder.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-capture.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "05-notes" "06-capture")

(defmacro my/capture-test--with-silos (&rest body)
  "Run BODY with folders `from' and `to' in a fresh temporary folder."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-capture-" t)))
          (from (file-name-as-directory (expand-file-name "inbox" root)))
          (to (file-name-as-directory (expand-file-name "pks" root)))
          ;; The silos lie in the notes folder, which is where a missing
          ;; silo folder is created (`my/notes-ensure-directory-of').
          (my-notes-dir root)
          (inhibit-message t))
     (make-directory from t)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/capture-test--write (file text)
  "Write TEXT to FILE, creating its folder; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/capture-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest my/capture-test-move-to-silo ()
  "The note moves into the silo, its text unchanged, and a buffer
visiting it follows it to the new name."
  (my/capture-test--with-silos
    (let* ((note (my/capture-test--write (expand-file-name "20261024T100000--a.org" from) "Text.\n"))
           (buf (find-file-noselect note))
           (moved (my/--move-note-to-silo note to)))
      (should (equal moved (expand-file-name "20261024T100000--a.org" to)))
      (should-not (file-exists-p note))
      (should (equal (my/capture-test--read moved) "Text.\n"))
      (should (equal (buffer-file-name buf) moved)))))

(ert-deftest my/capture-test-move-never-replaces ()
  "A file of the same name in the silo: refused before anything moves,
both files as they were, no question asked."
  (my/capture-test--with-silos
    (let ((note (my/capture-test--write (expand-file-name "20261024T100000--a.org" from) "New.\n"))
          (other (my/capture-test--write (expand-file-name "20261024T100000--a.org" to) "Old.\n")))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (error "Asked")))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) (error "Asked"))))
        (should-error (my/--move-note-to-silo note to) :type 'user-error))
      (should (equal (my/capture-test--read note) "New.\n"))
      (should (equal (my/capture-test--read other) "Old.\n")))))

(provide 'test-capture)
;;; test-capture.el ends here
