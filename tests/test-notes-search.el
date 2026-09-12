;;; test-notes-search.el --- ERT tests for 41-notes-search -*- lexical-binding: t; -*-
;;; Commentary:
;; Everything in 41-notes-search.el that is a pure function: the
;; tokeniser, the date grammar, the glob list it produces, the
;; translation of a query into consult input, and the regexps the
;; file-name selectors build.
;;
;;   emacs -Q --batch -l ~/.emacs.d/modules/41-notes-search.el \
;;     -l ~/.emacs.d/tests/test-notes-search.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; No notes, no processes, no minibuffer: the two commands themselves
;; are covered only by the menu test at the end, which needs the full
;; configuration and skips without it.

;;; Code:

(require 'ert)

;; ============================================================
;; TOKENISER
;; ============================================================

(ert-deftest my/ns-test-tokenize-words ()
  "Bare words come back one token each."
  (should (equal (my/notes-search--tokenize "kot pies")
                 '((word . "kot") (word . "pies")))))

(ert-deftest my/ns-test-tokenize-phrase ()
  "A quoted group stays one token, and loses its quotes."
  (should (equal (my/notes-search--tokenize "\"wspolnie z innymi\" kot")
                 '((phrase . "wspolnie z innymi") (word . "kot")))))

(ert-deftest my/ns-test-tokenize-unterminated-quote ()
  "A quote with no closing quote runs to the end instead of signalling."
  (should (equal (my/notes-search--tokenize "\"kot pies")
                 '((phrase . "kot pies")))))

(ert-deftest my/ns-test-tokenize-empty-phrase ()
  "An empty pair of quotes contributes nothing."
  (should (equal (my/notes-search--tokenize "\"\" kot") '((word . "kot")))))

;; ============================================================
;; DATE GRAMMAR
;; ============================================================

(ert-deftest my/ns-test-parse-point-bare-year ()
  "A bare year means January at the start of a range and December at its end."
  (should (= (my/notes-search--parse-point "2014" 'start) 201401))
  (should (= (my/notes-search--parse-point "2014" 'end) 201412)))

(ert-deftest my/ns-test-parse-point-month-forms ()
  "YYYY-MM and YYYYMM are the same date."
  (should (= (my/notes-search--parse-point "2014-05" 'start) 201405))
  (should (= (my/notes-search--parse-point "201405" 'end) 201405)))

(ert-deftest my/ns-test-parse-point-rejects-nonsense ()
  "A month outside 1-12, or anything that is not a date, is an error."
  (should-error (my/notes-search--parse-point "2014-13" 'start))
  (should-error (my/notes-search--parse-point "wczoraj" 'start)))

(ert-deftest my/ns-test-parse-range-forms ()
  "Every accepted range spelling, including the two exclusive ones."
  (should (equal (my/notes-search--parse-range "2014") '(201401 . 201412)))
  (should (equal (my/notes-search--parse-range "2012-01..2015-05")
                 '(201201 . 201505)))
  (should (equal (my/notes-search--parse-range "<2015") '(nil . 201412)))
  (should (equal (my/notes-search--parse-range "<=2015") '(nil . 201512)))
  (should (equal (my/notes-search--parse-range ">=2012-03") '(201203 . nil)))
  (should (equal (my/notes-search--parse-range ">2012") '(201301 . nil))))

(ert-deftest my/ns-test-merge-range-intersects ()
  "Two directives narrow each other rather than replacing."
  (should (equal (my/notes-search--merge-range '(201201 . 201512)
                                               '(201301 . 201412))
                 '(201301 . 201412)))
  (should (equal (my/notes-search--merge-range nil '(201301 . nil))
                 '(201301 . nil))))

;; ============================================================
;; GLOBS
;; ============================================================

(ert-deftest my/ns-test-globs-whole-years ()
  "A range of whole years costs one glob per year."
  (should (equal (my/notes-search--date-globs '(201201 . 201412))
                 '("2012*" "2013*" "2014*"))))

(ert-deftest my/ns-test-globs-partial-years ()
  "A partial year is expanded month by month, the whole ones are not."
  (should (equal (my/notes-search--date-globs '(201211 . 201402))
                 '("201211*" "201212*" "2013*" "201401*" "201402*"))))

(ert-deftest my/ns-test-globs-single-month ()
  "One month, one glob."
  (should (equal (my/notes-search--date-globs '(201405 . 201405))
                 '("201405*"))))

(ert-deftest my/ns-test-globs-open-lower-bound ()
  "An open lower bound starts at `my/notes-search-earliest-year'."
  (let ((my/notes-search-earliest-year 2013))
    (should (equal (my/notes-search--date-globs '(nil . 201412))
                   '("2013*" "2014*")))))

(ert-deftest my/ns-test-globs-refuse-absurd-range ()
  "A range wide enough to be a typo is refused rather than run."
  (let ((my/notes-search-earliest-year 1000)
        (my/notes-search-max-globs 10))
    (should-error (my/notes-search--date-globs '(nil . 201412)))))

(ert-deftest my/ns-test-globs-reject-inverted-range ()
  "A range whose end precedes its start is an error, not an empty result."
  (should-error (my/notes-search--date-globs '(201501 . 201201))))

(ert-deftest my/ns-test-globs-nil-range ()
  "No date directive means no file filter at all."
  (should (null (my/notes-search--date-globs nil))))

;; ============================================================
;; QUERY TRANSLATION
;; ============================================================

(ert-deftest my/ns-test-parse-plain-words ()
  "Unquoted words are passed through untouched, so regexps still work."
  (let ((parsed (my/notes-search-parse "kot.*pies dom")))
    (should (equal (plist-get parsed :pattern) "kot.*pies dom"))
    (should (null (plist-get parsed :range)))))

(ert-deftest my/ns-test-parse-phrase-is-literal ()
  "A phrase keeps its spaces as one pattern and loses its regexp meaning."
  (should (equal (plist-get (my/notes-search-parse "\"a.b c\"") :pattern)
                 "a\\.b\\ c")))

(ert-deftest my/ns-test-parse-date-is-removed-from-pattern ()
  "A date directive filters files; it is not a word to search for."
  (let ((parsed (my/notes-search-parse "kot date:2012..2015")))
    (should (equal (plist-get parsed :pattern) "kot"))
    (should (equal (plist-get parsed :range) '(201201 . 201512)))))

(ert-deftest my/ns-test-parse-from-to-pair ()
  "`from:' and `to:' are the two halves of a range."
  (should (equal (plist-get (my/notes-search-parse "from:2012 to:2015-05") :range)
                 '(201201 . 201505))))

(ert-deftest my/ns-test-parse-date-only ()
  "A query that is nothing but a date leaves the pattern empty."
  (let ((parsed (my/notes-search-parse "date:2014")))
    (should (null (plist-get parsed :pattern)))
    (should (equal (plist-get parsed :range) '(201401 . 201412)))))

(ert-deftest my/ns-test-parse-protects-leading-dash ()
  "A term starting with a dash is escaped, or consult would read it as a flag."
  (should (equal (plist-get (my/notes-search-parse "-kot") :pattern) "\\-kot")))

;; ============================================================
;; BACK END ARGUMENTS
;; ============================================================

(ert-deftest my/ns-test-file-args-ripgrep ()
  "Ripgrep gets one -g per glob, and the dot-directory exclusion last."
  (should (equal (my/notes-search--file-args '("2012*" "2013*") t)
                 '("-g" "2012*" "-g" "2013*" "-g" "!.*"))))

(ert-deftest my/ns-test-file-args-grep ()
  "Grep gets --include per glob, plus the dot-directory exclusion."
  (should (equal (my/notes-search--file-args '("2012*") nil)
                 '("--include=2012*" "--exclude-dir=.*"))))

(ert-deftest my/ns-test-file-args-without-globs ()
  "With no date filter, only the exclusion is added."
  (should (equal (my/notes-search--file-args nil t) '("-g" "!.*")))
  (should (equal (my/notes-search--file-args nil nil) '("--exclude-dir=.*"))))

;; ============================================================
;; FILE-NAME SELECTORS
;; ============================================================

(ert-deftest my/ns-test-name-regexp-title ()
  "A title selector is anchored on the title separator and stops at keywords."
  (let ((regexps (my/notes-search--name-regexps "title:kant")))
    (should (= (length regexps) 1))
    (should (string-match-p (car regexps)
                            "20140101T000000--kant-i-krytyka__filozofia.org"))
    (should-not (string-match-p (car regexps)
                                "20140101T000000--krytyka__kant.org"))))

(ert-deftest my/ns-test-name-regexp-tag ()
  "A tag selector matches a whole keyword, in any position."
  (let ((regexps (my/notes-search--name-regexps "tag:praca")))
    (should (string-match-p (car regexps)
                            "20140101T000000--tytul__praca.org"))
    (should (string-match-p (car regexps)
                            "20140101T000000--tytul__bhp_praca_emacs.org"))
    (should-not (string-match-p (car regexps)
                                "20140101T000000--tytul__pracownia.org"))))

(ert-deftest my/ns-test-name-regexps-are-anded ()
  "Two selectors produce two regexps, both of which have to match."
  (should (= (length (my/notes-search--name-regexps "title:kant tag:filozofia"))
             2)))

(ert-deftest my/ns-test-name-regexp-bare-term ()
  "A term with no selector matches anywhere in the file name."
  (let ((regexps (my/notes-search--name-regexps "krytyka")))
    (should (string-match-p (car regexps)
                            "20140101T000000--kant-i-krytyka__x.org"))))

;; ============================================================
;; MENU
;; ============================================================

(ert-deftest my/ns-test-menu-entries-present ()
  "The Find menu carries the new commands after the module loads."
  (skip-unless (fboundp 'my/notes-find-menu))
  (should (equal (nth 2 (transient-get-suffix 'my/notes-find-menu "g"))
                 'my/notes-grep))
  (should (transient-get-suffix 'my/notes-find-menu "n")))

(provide 'test-notes-search)
;;; test-notes-search.el ends here
