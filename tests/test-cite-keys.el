;;; test-cite-keys.el --- ERT tests for renaming citation keys in 417-bibliography -*- lexical-binding: t; -*-

;; Tests: 417-bibliography

;;; Commentary:

;; `my/cite-rename-key' across Org files in a temporary folder: only the
;; whole key, only inside citations, the delimiter kept; a file open with
;; unsaved changes left alone, an unmodified buffer reverted.  Needs no
;; package beyond Org.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-cite-keys.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "417-bibliography")

(defmacro my/ck-test--with-notes (&rest body)
  "Run BODY with `notes' a fresh folder and `my/cite-check-directories' on it."
  (declare (indent 0))
  `(let* ((notes (file-name-as-directory (make-temp-file "mypks-cite-" t)))
          (my/cite-check-directories (list notes))
          (inhibit-message t))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b) (string-prefix-p notes (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory notes t))))

(defun my/ck-test--write (notes name text)
  "Write TEXT to NAME in NOTES; return the file."
  (let ((file (expand-file-name name notes)))
    (with-temp-file file (insert text))
    file))

(defun my/ck-test--read (file)
  "Return the text of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest my/ck-test-rename-whole-key-only ()
  "Renaming `smith' changes @smith in every citation form -- alone, with
a locator, among several keys, with a prefix -- and leaves @smith-2020,
@smithson and the word smith in prose as they were.  Until 2026-10-28
the match ended at a word boundary and @smith-2020 became
@jones-2020."
  (my/ck-test--with-notes
    (let ((file (my/ck-test--write
                 notes "a.org"
                 (concat "Smith wrote [cite:@smith] and [cite:@smith p. 3].\n"
                         "Both: [cite:@smith-2020; @smith] and [cite:see @smithson;@smith].\n"
                         "Prose about smith and @smith outside a citation.\n"))))
      (my/cite-rename-key "smith" "jones")
      (should (equal (my/ck-test--read file)
                     (concat "Smith wrote [cite:@jones] and [cite:@jones p. 3].\n"
                             "Both: [cite:@smith-2020; @jones] and [cite:see @smithson;@jones].\n"
                             "Prose about smith and @smith outside a citation.\n"))))))

(ert-deftest my/ck-test-rename-leaves-unsaved-buffer-alone-reverts-clean-one ()
  "A file visited by a buffer with unsaved changes is not rewritten
(the buffer would write the old key back over it) and is named in the
message; a file visited by an unmodified buffer is rewritten and the
buffer shows the new key."
  (my/ck-test--with-notes
    (let* ((dirty (my/ck-test--write notes "dirty.org" "[cite:@smith]\n"))
           (clean (my/ck-test--write notes "clean.org" "[cite:@smith]\n"))
           (dirty-buffer (find-file-noselect dirty))
           (clean-buffer (find-file-noselect clean))
           (said nil))
      (with-current-buffer dirty-buffer (goto-char (point-max)) (insert "typed"))
      (cl-letf (((symbol-function 'message)
                 (lambda (f &rest a) (setq said (apply #'format f a)))))
        (my/cite-rename-key "smith" "jones"))
      (should (equal (my/ck-test--read dirty) "[cite:@smith]\n"))
      (should (string-match-p "dirty.org" said))
      (should (equal (my/ck-test--read clean) "[cite:@jones]\n"))
      (should (equal (with-current-buffer clean-buffer (buffer-string)) "[cite:@jones]\n"))
      (should (equal (with-current-buffer dirty-buffer (buffer-string)) "[cite:@smith]\ntyped")))))

(provide 'test-cite-keys)
;;; test-cite-keys.el ends here
