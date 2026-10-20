;;; test-packages.el --- ERT tests for installing packages and the no-littering report -*- lexical-binding: t; -*-

;; Tests: 00-core

;;; Commentary:

;; 00-core.el: the package list is refreshed once, before the first
;; installation of a session (a stale list names builds MELPA has
;; deleted); when no-littering does not load, the start-up report says
;; why.  No network: the refresh is stubbed.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-packages.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules)

(ert-deftest my/packages-test-refresh-once-before-first-install ()
  "The refresh runs before the first installation, and only then."
  (should (advice-member-p #'my/package--refresh-before-first-install 'package-install))
  (let ((refreshed 0))
    (cl-letf (((symbol-function 'package-refresh-contents)
               (lambda (&rest _) (cl-incf refreshed))))
      (my/package--refresh-before-first-install 'some-package)
      (should (= refreshed 1))
      ;; Gone after the first time: a second installation does not refresh.
      (should-not (advice-member-p #'my/package--refresh-before-first-install
                                   'package-install)))))

(ert-deftest my/packages-test-report-names-the-reason ()
  "The report on no-littering carries what use-package said."
  (let ((my/var--no-littering-problems
         '("Failed to install no-littering: https://melpa.org/packages/x.tar: Not found")))
    (should (member "Failed to install no-littering: https://melpa.org/packages/x.tar: Not found"
                    (my/var--not-loaded-lines))))
  (let ((my/var--no-littering-problems nil))
    (should (string-match-p "no reason" (car (my/var--not-loaded-lines))))))

(ert-deftest my/packages-test-warnings-kept-while-loading ()
  "Warnings about no-littering while it loads are kept for the report;
others are not, and the keeping stops afterwards."
  (let ((my/var--no-littering-problems nil))
    (cl-letf (((symbol-function 'use-package-ensure-elpa) #'ignore))
      (my/var--load-no-littering))
    ;; In this sandbox no-littering is not on `load-path' unless installed.
    (unless (featurep 'no-littering)
      (should (seq-some (lambda (m) (string-match-p "no-littering" m))
                        my/var--no-littering-problems)))
    (let ((before (length my/var--no-littering-problems)))
      (display-warning 'test "a warning about no-littering after loading")
      (should (= before (length my/var--no-littering-problems))))))

(provide 'test-packages)
;;; test-packages.el ends here
