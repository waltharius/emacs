;;; test-cite-preview.el --- ERT tests for 50-cite-preview -*- lexical-binding: t; -*-

;; Tests: 50-cite-preview

;;; Commentary:

;; 50-cite-preview shows the citation under point in the echo area as
;; the export will render it.  These tests put point on citations of a
;; small .bib file and check the text offered to ElDoc: a note of the
;; default style with its page, two works in one citation, a document's
;; own style, the noauthor variant, an unknown key, no bibliography;
;; that the keys alone are rendered when Org's parser of locators
;; fails; and that the switch adds the preview to Org buffers and takes
;; it away.  Needs citeproc installed (ci-packages.el installs it for
;; the workflow).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-cite-preview.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "17-bibliography" "50-cite-preview")

(defvar my/csl-bundled-styles-dir)
(defvar my/csl-bundled-locales-dir)

(defconst my/cp-test-bib
  "@book{baluk2018,
  title = {Wodecki: tak mi wyszło},
  author = {Bałuk, Kamil and Krupiński, Wacław},
  date = {2018},
  publisher = {Wydawnictwo Agora},
  langid = {polish}
}

@book{gogh1990,
  title = {Listy},
  author = {family=Gogh, given=Vincent, prefix=van, useprefix=false},
  date = {1990},
  publisher = {Penguin},
  langid = {polish}
}
"
  "A small bibliography in the shape Better BibLaTeX exports.")

(defmacro my/cp-test-with-bib (&rest body)
  "Run BODY with `my/cp-test-bib' as the only bibliography, the bundled CSL files."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "mypks-cp-" t))
          (file (expand-file-name "refs.bib" dir))
          (my/bibliography-files (list file))
          (my/csl-styles-dir (file-name-as-directory (expand-file-name "styles" dir)))
          (my/csl-locales-dir (file-name-as-directory (expand-file-name "locales" dir)))
          (my/csl-bundled-styles-dir (expand-file-name "csl/styles/" my/test-repo))
          (my/csl-bundled-locales-dir (expand-file-name "csl/locales/" my/test-repo))
          (my/csl-default-style "chicago-notes-bibliography.csl")
          (my/reference--items nil)
          (my/reference--processors nil))
     (unwind-protect
         (progn
           (with-temp-file file (insert my/cp-test-bib))
           ,@body)
       (delete-directory dir t))))

(defun my/cp-test-preview (text &optional header)
  "The preview with point on the first \"@\" of TEXT in an Org note.
HEADER is put before TEXT; by default a Polish note's #+language: line."
  (with-temp-buffer
    (insert (or header "#+language: pl\n\n") text)
    (org-mode)
    (goto-char (point-min))
    (search-forward "@")
    (my/cite-preview-at-point)))

(ert-deftest my/cp-test-note-with-page ()
  "A citation with a page: the footnote of the default note style, the
page after it, plain text without Org's objects as properties."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (let ((preview (my/cp-test-preview "Teza [cite:@baluk2018 45].")))
      (should (equal preview
                     "Kamil Bałuk i Wacław Krupiński, Wodecki: tak mi wyszło (Wydawnictwo Agora, 2018), 45."))
      (should-not (text-properties-at (- (length preview) 2) preview)))))

(ert-deftest my/cp-test-same-as-the-export ()
  "The citation, pages, prefixes and suffixes (the citation's own and the
reference's) included, is the footnote Org's own CSL export writes
(exported to ASCII, compared in Org markup)."
  (skip-unless (and (locate-library "citeproc") (require 'oc-csl nil t)))
  (require 'ox-ascii)
  (my/cp-test-with-bib
    (my/csl-apply)
    (let* ((source "#+language: pl\n\nTeza [cite:Por.;zob. @baluk2018 45-47, podkr. moje;i dalej].\n")
           (org-cite-global-bibliography (my/bibliography-file-list))
           (ours (with-temp-buffer
                   (insert source)
                   (org-mode)
                   (search-backward "@")
                   (my/reference-render-citation
                    (my/cite-preview--structure (my/cite-preview--citation-at-point))
                    (my/cite-preview--style-name) 'org)))
           (exported (with-temp-buffer
                       (insert source)
                       (org-mode)
                       (org-export-as 'ascii nil nil t '(:ascii-charset utf-8)))))
      (should (string-match-p "\\`Por\\. zob\\. .*45.*podkr\\. moje i dalej" ours))
      (should (string-match-p (regexp-quote (substring-no-properties ours))
                              (replace-regexp-in-string "[ \t\n]+" " " exported))))))

(ert-deftest my/cp-test-two-works-one-citation ()
  "Two works in one citation: one note naming both."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (let ((preview (my/cp-test-preview "Teza [cite:@baluk2018; @gogh1990].")))
      (should (string-match-p "Krupiński, Wodecki" preview))
      (should (string-match-p "Vincent van Gogh, Listy" preview)))))

(ert-deftest my/cp-test-point-on-second-key ()
  "Point on the second key of a citation shows the whole citation."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (with-temp-buffer
      (insert "#+language: pl\n\nTeza [cite:@baluk2018; @gogh1990].")
      (org-mode)
      (search-backward "gogh")
      (should (string-match-p "Krupiński.*Gogh" (my/cite-preview-at-point))))))

(ert-deftest my/cp-test-document-style ()
  "A document naming its own CSL style is previewed in that style."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (should (equal (my/cp-test-preview
                    "Teza [cite:@baluk2018]."
                    "#+language: pl\n#+cite_export: csl mypks-short-reference.csl\n\n")
                   "Kamil Bałuk i Wacław Krupiński, Wodecki: tak mi wyszło (2018)"))))

(ert-deftest my/cp-test-noauthor-variant ()
  "The noauthor variant [cite/na:...] leaves the authors out, as the
export does."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (let ((preview (my/cp-test-preview "Teza [cite/na:@baluk2018].")))
      (should (string-match-p "Wodecki: tak mi wyszło" preview))
      (should-not (string-match-p "Bałuk" preview)))))

(ert-deftest my/cp-test-unknown-key-named ()
  "A key the bibliography lacks is named, not rendered and not an error."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (should (equal (my/cp-test-preview "Teza [cite:@baluk2018; @nosuch].")
                   "Not in the bibliography: nosuch"))))

(ert-deftest my/cp-test-no-bibliography-no-error ()
  "Without a readable bibliography the preview says so instead of
signalling an error while point moves."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (delete-file (car my/bibliography-files))
    (let ((preview (my/cp-test-preview "Teza [cite:@baluk2018].")))
      (should (string-prefix-p "Citation preview: No bibliography file" preview)))))

(ert-deftest my/cp-test-nothing-off-a-citation ()
  "Off a citation, and on a nocite, nothing is offered."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (with-temp-buffer
      (insert "#+language: pl\n\nZwykły tekst [cite:@baluk2018].")
      (org-mode)
      (search-backward "tekst")
      (should-not (my/cite-preview-at-point)))
    (should-not (my/cp-test-preview "[cite/n:@baluk2018]"))))

(ert-deftest my/cp-test-keys-alone-when-org-parser-fails ()
  "Where Org's parser of locators fails, the keys alone are rendered."
  (skip-unless (locate-library "citeproc"))
  (require 'oc-csl)
  ;; Advice, not `cl-letf': a stand-in must outlive a reload of oc-csl.
  (let ((fail (lambda (&rest _) (error "Parser changed"))))
    (advice-add 'org-cite-csl--parse-reference :override fail)
    (unwind-protect
        (my/cp-test-with-bib
          (should (equal (my/cp-test-preview "Teza [cite:@baluk2018 45].")
                         "Kamil Bałuk i Wacław Krupiński, Wodecki: tak mi wyszło (Wydawnictwo Agora, 2018).")))
      (advice-remove 'org-cite-csl--parse-reference fail))))

(ert-deftest my/cp-test-eldoc-in-org-buffers ()
  "On, an Org buffer gets the preview in its ElDoc functions and ElDoc
on; the ElDoc function returns the preview."
  (skip-unless (locate-library "citeproc"))
  (my/cp-test-with-bib
    (with-temp-buffer
      (insert "#+language: pl\n\nTeza [cite:@baluk2018].")
      (org-mode)
      (should (memq #'my/cite-preview--eldoc eldoc-documentation-functions))
      (should eldoc-mode)
      (search-backward "@")
      (should (string-match-p "Wodecki" (my/cite-preview--eldoc #'ignore))))))

(ert-deftest my/cp-test-switch-off-and-on ()
  "Off: open Org buffers lose the preview, ElDoc goes off where the
module turned it on, a new Org buffer gets nothing.  On: open buffers
get it back."
  (let ((buffer (generate-new-buffer "cp-switch")))
    (unwind-protect
        (with-current-buffer buffer
          (org-mode)
          (should (memq #'my/cite-preview--eldoc eldoc-documentation-functions))
          (my/cite-preview-mode -1)
          (should-not (memq #'my/cite-preview--eldoc eldoc-documentation-functions))
          (should-not eldoc-mode)
          (with-temp-buffer
            (org-mode)
            (should-not (memq #'my/cite-preview--eldoc eldoc-documentation-functions)))
          (my/cite-preview-mode 1)
          (should (memq #'my/cite-preview--eldoc eldoc-documentation-functions))
          (should eldoc-mode))
      (my/cite-preview-mode 1)
      (kill-buffer buffer))))

(provide 'test-cite-preview)
;;; test-cite-preview.el ends here
