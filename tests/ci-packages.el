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
;; it); ox-hugo (with tomelr), which test-safety needs to check what a
;; page of a site says about the notes it links to (SAFETY.org 1.4);
;; pdf-tools, whose server test-bibliography checks is not built when
;; the package is loaded (nothing is built here either); Magit, whose
;; commit buffers test-auto-commit checks wrap at 72 columns (07-git.el
;; sets that once Magit loads; added 2026-10-24, when the test skipped
;; here and a strict run failed on the skip).  A module loaded by a test whose package is missing still loads,
;; with a warning, as at a real start.  Not a test file itself: its name
;; does not start with test-.

;;; Code:

(require 'package)

;; The same archives as 00-core.el: GNU ELPA and NonGNU ELPA are Emacs's
;; defaults, MELPA is added.
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

(defconst my/ci-packages
  '((denote) (no-littering) (ox-hugo) (pdf-tools) (magit)
    ;; Loaded by the module tests of 2026-10-24/25: 20-transclusion,
    ;; 22-zettelkasten, 40-markdown (the CI run of 0071/0072 stopped
    ;; with "Cannot load org-transclusion" and "denote-sequence").
    (org-transclusion) (denote-sequence) (markdown-mode) (visual-fill-column)
    ;; Not the transient built into Emacs: the one the configuration
    ;; really runs with comes from the archives with Magit (0.13 on the
    ;; owner's machine, 2026-10-20), and its menu entries have another
    ;; shape -- a test passed here with the built-in one and failed there.
    (transient (0 13)))
  "Packages the test files need installed: (NAME [MIN-VERSION]).")

;; Emacs 29 and later do not replace a built-in package unless told to.
(setq package-install-upgrade-built-in t)

(defun my/ci-package-ok (entry)
  "Non-nil when ENTRY, (NAME [MIN-VERSION]), is installed in that version."
  (package-installed-p (car entry) (cadr entry)))

(let ((missing (seq-remove #'my/ci-package-ok my/ci-packages)))
  (when missing
    (package-refresh-contents)
    (dolist (entry missing)
      (package-install (car entry))))
  (message "Packages for the tests: %s"
           (mapconcat (lambda (e) (format "%s %s" (car e) (if (my/ci-package-ok e) "ok" "MISSING")))
                      my/ci-packages ", "))
  (unless (seq-every-p #'my/ci-package-ok my/ci-packages)
    (kill-emacs 1)))

;;; ci-packages.el ends here
