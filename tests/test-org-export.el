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

(defun my/export-test--as (backend text)
  "Return TEXT, an Org body, exported by BACKEND, body only."
  (require 'denote)
  (let ((org-export-with-toc nil) (org-export-with-author nil)
        (org-export-with-title nil) (org-export-with-date nil)
        (inhibit-message t))
    (org-export-string-as text backend t)))

(ert-deftest my/export-test-denote-links-become-text ()
  "A denote: link is its description in LaTeX, ODT and plain text, the
words around it and the space after it kept; without a description it
is its target.  No link to a note reaches the document.  (Until
2026-10-24 the filter had the wrong arguments and did nothing.)"
  (skip-unless (require 'denote nil t))
  (require 'ox-latex)
  (require 'ox-ascii)
  (let ((text "See [[denote:20261024T100000][Kant on time]] now, and [[denote:20261024T110000]] too.\n"))
    (let ((latex (my/export-test--as 'latex text)))
      (should (string-match-p "See Kant on time now, and 20261024T110000 too\\." latex))
      (should-not (string-match-p "href\\|denote:" latex)))
    (let ((ascii (my/export-test--as 'ascii text)))
      (should (string-match-p "See Kant on time now, and 20261024T110000 too\\." ascii))
      (should-not (string-match-p "denote:" ascii)))
    (when (require 'ox-odt nil t)
      (let ((odt (my/export-test--as 'odt text)))
        (should (string-match-p "See Kant on time now" odt))
        (should-not (string-match-p "denote:\\|text:a " odt))))))

(ert-deftest my/export-test-other-links-untouched ()
  "A web link is left to the backend, as a link."
  (skip-unless (require 'denote nil t))
  (require 'ox-latex)
  (should (string-match-p "\\\\href{https://example.org}{Example}"
                          (my/export-test--as 'latex "[[https://example.org][Example]]\n"))))

(ert-deftest my/export-test-keywords-are-whole-keywords ()
  "The batch export by keyword compares whole Denote keywords of the file
name, never a part of the title: \"ai\" is not in \"mail\" or
\"kraina\"."
  (should (equal (my/org-export--file-keywords "/n/20261024T100000--o-ai__ai_etyka.org")
                 '("ai" "etyka")))
  (should (equal (my/org-export--file-keywords "/n/20261024T100000--mail-z-krainy__list.org")
                 '("list")))
  (should-not (my/org-export--file-keywords "/n/20261024T100000--bez-tagow.org"))
  (let ((files (list "/n/20261024T100000--o-ai__ai.org"
                     "/n/20261024T110000--mail-z-krainy__list.org"))
        (exported nil))
    (cl-letf (((symbol-function 'my/--all-notes-org-files) (lambda (&rest _) files))
              ((symbol-function 'my/ensure-pdf-dir) #'ignore)
              ((symbol-function 'my/--batch-export-and-report)
               (lambda (fs &rest _) (setq exported fs)))
              ((symbol-function 'message) #'ignore))
      (my/org-export-pdf-by-keyword "ai")
      (should (equal exported (list (car files))))
      (setq exported nil)
      (my/org-export-pdf-by-all-keywords "ai, list")
      (should-not exported))))

(provide 'test-org-export)
;;; test-org-export.el ends here
