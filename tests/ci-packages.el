;;; ci-packages.el --- Install the packages the tests load, for continuous integration -*- lexical-binding: t; -*-

;;; Commentary:

;; Run once by .github/workflows/checks.yml before hooks/check-all, on a
;; machine with no packages:
;;
;;   emacs -Q --batch -l tests/ci-packages.el
;;
;; The tests install nothing themselves (tests/helper.el); they take what
;; is in ~/.emacs.d/elpa/.  These are the packages whose absence makes a
;; test file fail rather than skip: Denote (04-denote.el, loaded by
;; test-journal-metrics) and no-littering (00-core.el; compat comes with
;; it).  A module loaded by a test whose package is missing still loads,
;; with a warning, as at a real start.  Not a test file itself: its name
;; does not start with test-.

;;; Code:

(require 'package)

;; The same archives as 00-core.el: GNU ELPA and NonGNU ELPA are Emacs's
;; defaults, MELPA is added.
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

(defconst my/ci-packages '(denote no-littering)
  "Packages the test files need installed.")

(let ((missing (seq-remove #'package-installed-p my/ci-packages)))
  (when missing
    (package-refresh-contents)
    (dolist (package missing)
      (package-install package)))
  (message "Packages for the tests: %s"
           (mapconcat (lambda (p) (format "%s %s" p (if (package-installed-p p) "ok" "MISSING")))
                      my/ci-packages ", "))
  (unless (seq-every-p #'package-installed-p my/ci-packages)
    (kill-emacs 1)))

;;; ci-packages.el ends here
