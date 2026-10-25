;;; test-denote-settings.el --- ERT tests for the settings of 04-denote -*- lexical-binding: t; -*-

;; Tests: 04-denote

;;; Commentary:

;; 04-denote sets Denote and Org up; it has one function of its own.
;; Tested is what the rest relies on: Denote's folder is the notes
;; folder; an `elisp:' link in a note asks before it runs (a note from
;; elsewhere could carry one); electric indentation is off in Org, by
;; a named function on the hook.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-denote-settings.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "04-denote")

(ert-deftest my/ds-test-denote-folder-is-the-notes-folder ()
  "Denote's folder is the notes folder."
  (skip-unless (locate-library "denote"))
  (require 'denote)
  (should (equal (file-name-as-directory (expand-file-name denote-directory))
                 (file-name-as-directory (expand-file-name my-notes-dir)))))

(ert-deftest my/ds-test-elisp-link-asks-first ()
  "Following an elisp: link asks first; answered no, nothing runs."
  (should (eq org-link-elisp-confirm-function #'y-or-n-p))
  (defvar my/ds-test--ran)
  (let ((my/ds-test--ran nil) (asked nil))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) (setq asked t) nil)))
      (with-temp-buffer
        (org-mode)
        (insert "[[elisp:(setq my/ds-test--ran t)][kliknij]]")
        (goto-char 3)
        (ignore-errors (org-open-at-point))))
    (should asked)
    (should-not my/ds-test--ran)))

(ert-deftest my/ds-test-no-electric-indent-in-org ()
  "In Org, electric indentation is off, by a named function on the hook."
  (should (memq #'my/org-no-electric-indent org-mode-hook))
  (with-temp-buffer
    (org-mode)
    (should-not electric-indent-mode)
    (should-not electric-indent-chars)))

(provide 'test-denote-settings)
;;; test-denote-settings.el ends here
