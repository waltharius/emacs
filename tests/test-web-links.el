;;; test-web-links.el --- ERT tests for 332-web-links -*- lexical-binding: t; -*-

;; Tests: 332-web-links

;;; Commentary:

;; 332-web-links hands the work to org-web-tools: C-c n i u asks for an
;; address, fetches the page's title and inserts an Org link.  Tested
;; here: the command is org-web-tools' own, called interactively (an
;; advice stands in for it, so nothing reaches the network), and the
;; menu entry is in the Insert menu while the switch is on and gone
;; when it is off.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-web-links.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "205-notes" "212-transient" "332-web-links")

(ert-deftest my/wl-test-command-is-org-web-tools ()
  "The command calls org-web-tools' insert command interactively, so its
own prompt and clipboard handling apply; nothing else is fetched."
  (skip-unless (locate-library "org-web-tools"))
  (require 'org-web-tools)
  (let* ((calls nil)
         (stand-in (lambda (&rest args)
                     (interactive (list "https://example.org/"))
                     (push (list args (called-interactively-p 'any)) calls))))
    ;; Advice, not `cl-letf': loading org-web-tools would define the
    ;; function again (TESTING.org, rule 13).
    (advice-add 'org-web-tools-insert-link-for-url :override stand-in)
    (unwind-protect
        (call-interactively #'my/insert-web-link)
      (advice-remove 'org-web-tools-insert-link-for-url stand-in))
    (should (equal calls '((("https://example.org/") t))))))

(ert-deftest my/wl-test-menu-entry-follows-the-switch ()
  "Insert → u runs the command while the switch is on, and is gone when
it is off."
  (should (eq (my/transient--layout-command (transient-get-suffix 'my/notes-insert-menu "u"))
              #'my/insert-web-link))
  (unwind-protect
      (progn
        (my/web-links-mode -1)
        (should-not (ignore-errors (transient-get-suffix 'my/notes-insert-menu "u"))))
    (my/web-links-mode 1)))

(provide 'test-web-links)
;;; test-web-links.el ends here
