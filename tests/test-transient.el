;;; test-transient.el --- ERT tests for adding and removing menu entries -*- lexical-binding: t; -*-

;; Tests: 212-transient

;;; Commentary:

;; 212-transient.el: modules put their entries into the shared menus and
;; take them out when switched off (`my/transient-entries').  Taking an
;; entry out first checks that the key still runs the module's command
;; (`my/transient--layout-command'), so that another module's entry on
;; the same key is left alone.
;;
;; Until 2026-10-22 that check read only the shape of the transient
;; built into Emacs 29, (LEVEL CLASS PLIST).  Transient 0.13, which
;; comes with Magit, gives (CLASS . PLIST): the command read as nil, and
;; a module switched off kept its entries.  Found by the weekly switch
;; test (tests/weekly/test-modules.el).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-transient.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "204-denote" "205-notes" "212-transient")

(ert-deftest my/transient-test-layout-command-every-shape ()
  "The command of an entry is read in every shape transient has used."
  (should (eq (my/transient--layout-command '(1 transient-suffix (:key "u" :command foo)))
              'foo))
  (should (eq (my/transient--layout-command '(transient-suffix :key "u" :command foo))
              'foo))
  (should (eq (my/transient--layout-command [transient-suffix (:key "u" :command foo)])
              'foo))
  (should-not (my/transient--layout-command '(transient-suffix :key "u")))
  (should-not (my/transient--layout-command nil)))

(ert-deftest my/transient-test-entry-removed-when-switched-off ()
  "An entry added by a module goes when the module is switched off,
with the transient installed here -- whichever version it is."
  (skip-unless (fboundp 'my/notes-insert-menu))
  (let ((entries '((append my/notes-insert-menu "L"
                           ("Z" "Test entry" my/transient-test--command)))))
    (unwind-protect
        (progn
          (my/transient-entries t entries)
          (should (eq (my/transient--layout-command
                       (transient-get-suffix 'my/notes-insert-menu "Z"))
                      'my/transient-test--command))
          (my/transient-entries nil entries)
          (should-not (ignore-errors (transient-get-suffix 'my/notes-insert-menu "Z"))))
      (ignore-errors (transient-remove-suffix 'my/notes-insert-menu "Z")))))

(ert-deftest my/transient-test-other-modules-entry-kept ()
  "Switching a module off leaves another module's entry on the same key."
  (skip-unless (fboundp 'my/notes-insert-menu))
  (unwind-protect
      (progn
        (my/transient-entries t '((append my/notes-insert-menu "L"
                                          ("Z" "Other" my/transient-test--other))))
        (my/transient-entries nil '((append my/notes-insert-menu "L"
                                            ("Z" "Mine" my/transient-test--command))))
        (should (eq (my/transient--layout-command
                     (transient-get-suffix 'my/notes-insert-menu "Z"))
                    'my/transient-test--other)))
    (ignore-errors (transient-remove-suffix 'my/notes-insert-menu "Z"))))

(provide 'test-transient)
;;; test-transient.el ends here
