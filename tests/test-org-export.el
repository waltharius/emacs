;;; test-org-export.el --- ERT tests for the PDF export of 16-org-export -*- lexical-binding: t; -*-

;; Tests: 16-org-export

;;; Commentary:

;; `my/--export-file-to-pdf': declining to overwrite an existing PDF
;; cancels with a message and returns nil.  Until 2026-10-22 it stopped
;; with "No catch for tag: --cl-block-my/--export-file-to-pdf--" (a
;; `cl-return-from' in a plain `defun'); found by the byte compiler of
;; Emacs 31 in the weekly check.  No LaTeX is run.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-org-export.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "16-org-export")

(ert-deftest my/export-test-declined-overwrite-cancels ()
  "Declining to overwrite: nil and a message, no error, nothing built."
  (let* ((dir (make-temp-file "mypks-export-" t))
         (file (expand-file-name "note.org" dir))
         (built nil)
         (said nil))
    (unwind-protect
        (progn
          (with-temp-file file (insert "#+title: A note\n\nText.\n"))
          (cl-letf (((symbol-function 'my/org-export-resolve-destination) #'ignore)
                    ((symbol-function 'org-export-to-file)
                     (lambda (&rest _) (setq built t)))
                    ((symbol-function 'message)
                     (lambda (f &rest a) (setq said (apply #'format f a)))))
            (should (null (my/--export-file-to-pdf file))))
          (should-not built)
          (should (equal said "Export cancelled: note.org")))
      (delete-directory dir t))))

(provide 'test-org-export)
;;; test-org-export.el ends here
