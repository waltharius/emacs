;;; test-note-keywords.el --- ERT tests for the note keywords of 000-core -*- lexical-binding: t; -*-

;; Tests: 000-core

;;; Commentary:
;; Reading, writing and removing `#+keyword:' front-matter lines:
;; `my/note-keyword', `my/note-keyword-number', `my/note-keyword-set'
;; with and without an alignment column, and `my/note-keyword-remove'.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-note-keywords.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.  000-core.el is loaded by
;; tests/helper.el, in a sandbox; every test works in a temp buffer and
;; touches no file at all.

;;; Code:

(require 'ert)
(require 'subr-x)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules)

(defconst my/nk-test--note
  "#+title:      2026-11-15 Journal
#+date:       [2026-11-15 nie 09:12]
#+filetags:   :journal:
#+identifier: 20261115T091200
#+language:   pl

* 09:12
Prose.
"
  "A note as Denote writes one: front matter, a blank line, a body.")

(defmacro my/nk-test--with-note (&rest body)
  "Run BODY in a temp buffer holding `my/nk-test--note'."
  (declare (indent 0))
  `(with-temp-buffer
     (insert my/nk-test--note)
     (goto-char (point-min))
     ,@body))

;; ============================================================
;; READING
;; ============================================================

(ert-deftest my/nk-test-read-value ()
  (my/nk-test--with-note
    (should (equal (my/note-keyword "language") "pl"))
    (should (equal (my/note-keyword "identifier") "20261115T091200"))
    (should-not (my/note-keyword "place"))))

(ert-deftest my/nk-test-empty-value-is-absent ()
  "A keyword with nothing after the colon is not a value."
  (my/nk-test--with-note
    (goto-char (point-min))
    (insert "#+place:\n")
    (should-not (my/note-keyword "place"))))

(ert-deftest my/nk-test-number ()
  (my/nk-test--with-note
    (my/note-keyword-set "text_width" 95)
    (should (= (my/note-keyword-number "text_width") 95))
    (my/note-keyword-set "text_width" "wide")
    (should-not (my/note-keyword-number "text_width"))))

;; ============================================================
;; WRITING
;; ============================================================

(ert-deftest my/nk-test-set-defaults-to-one-space ()
  "The old callers keep the format their notes already hold."
  (my/nk-test--with-note
    (my/note-keyword-set "text_width" 95)
    (goto-char (point-min))
    (should (re-search-forward "^#\\+text_width: 95$" nil t))))

(ert-deftest my/nk-test-set-aligns-at-column ()
  "With a column the value stands where Denote puts its own."
  (my/nk-test--with-note
    (my/note-keyword-set "place" "Kraków" my/note-front-matter-column)
    (goto-char (point-min))
    (should (re-search-forward "^#\\+place:\\( +\\)Kraków$" nil t))
    (should (= (- (match-end 1) (line-beginning-position))
               my/note-front-matter-column))))

(ert-deftest my/nk-test-set-column-never-welds ()
  "A keyword longer than the column still gets a space."
  (my/nk-test--with-note
    (my/note-keyword-set "a_very_long_keyword_name" "x" 4)
    (goto-char (point-min))
    (should (re-search-forward "^#\\+a_very_long_keyword_name: x$" nil t))))

(ert-deftest my/nk-test-set-joins-the-front-matter ()
  "A new keyword lands in the front matter, not in the prose."
  (my/nk-test--with-note
    (my/note-keyword-set "place" "Kraków" my/note-front-matter-column)
    (goto-char (point-min))
    (let ((keyword (progn (re-search-forward "^#\\+place:" nil t) (point)))
          (blank (progn (goto-char (point-min))
                        (re-search-forward "^$" nil t) (point))))
      (should (< keyword blank)))))

(ert-deftest my/nk-test-set-replaces-in-place ()
  "Setting a keyword twice leaves one line, where the first one was."
  (my/nk-test--with-note
    (my/note-keyword-set "place" "Kraków" my/note-front-matter-column)
    (let ((line (progn (goto-char (point-min))
                       (re-search-forward "^#\\+place:" nil t)
                       (line-number-at-pos))))
      (my/note-keyword-set "place" "Zakopane" my/note-front-matter-column)
      (goto-char (point-min))
      (should (re-search-forward "^#\\+place: *Zakopane$" nil t))
      (should (= (line-number-at-pos) line))
      (goto-char (point-min))
      (should (= 1 (count-matches "^#\\+place:"))))))

;; ============================================================
;; REMOVING
;; ============================================================

(ert-deftest my/nk-test-remove-takes-the-whole-line ()
  (my/nk-test--with-note
    (my/note-keyword-set "place" "Kraków" my/note-front-matter-column)
    (should (my/note-keyword-remove "place"))
    (should-not (my/note-keyword "place"))
    (goto-char (point-min))
    (should-not (re-search-forward "^#\\+place" nil t))))

(ert-deftest my/nk-test-remove-leaves-the-rest-alone ()
  "Removing one keyword is not an edit of the note."
  (let ((before my/nk-test--note))
    (my/nk-test--with-note
      (my/note-keyword-set "place" "Kraków" my/note-front-matter-column)
      (my/note-keyword-remove "place")
      (should (equal (buffer-string) before)))))

(ert-deftest my/nk-test-remove-absent-is-nil ()
  (my/nk-test--with-note
    (should-not (my/note-keyword-remove "place"))))

(provide 'test-note-keywords)
;;; test-note-keywords.el ends here
