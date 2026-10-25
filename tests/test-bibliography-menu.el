;;; test-bibliography-menu.el --- ERT tests for the bibliography menu of 417-bibliography -*- lexical-binding: t; -*-

;; Tests: 417-bibliography

;;; Commentary:

;; The bibliography menu, C-c x and an entry in Tools, is part of
;; 417-bibliography since 2026-10-25zg (until then 18-zotero-transient).
;; A menu entry naming a command that does not exist fails only when
;; chosen, so the test checks every entry of the menu against what
;; citar, citar-denote and 417-bibliography define; and that the key,
;; the Tools entry and the old name `my/zotero-menu' all open it.
;; Needs citar and citar-denote installed (ci-packages.el).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-bibliography-menu.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "204-denote" "205-notes" "212-transient" "417-bibliography")

(defconst my/bm-menu-test-keys '("n" "o" "f" "e" "u" "i" "R" "S" "c" "C" "?" "," "q")
  "The keys of the bibliography menu.")

(ert-deftest my/bm-menu-test-every-entry-runs-a-command ()
  "Each key of the bibliography menu runs a command that exists."
  (skip-unless (and (locate-library "citar") (locate-library "citar-denote")))
  (require 'citar)
  (require 'citar-denote)
  (dolist (key my/bm-menu-test-keys)
    (let ((command (my/transient--layout-command
                    (transient-get-suffix 'my/bibliography-menu key))))
      (should (and key command))
      (should (commandp command)))))

(ert-deftest my/bm-menu-test-key-entry-and-old-name ()
  "C-c x opens the menu, Tools has it under z, and the old name of the
menu still runs it."
  (should (eq (key-binding (kbd "C-c x")) #'my/bibliography-menu))
  (should (eq (my/transient--layout-command (transient-get-suffix 'my/notes-tools-menu "z"))
              #'my/bibliography-menu))
  (should (commandp 'my/zotero-menu))
  (should (eq (indirect-function 'my/zotero-menu) (indirect-function 'my/bibliography-menu))))

(provide 'test-bibliography-menu)
;;; test-bibliography-menu.el ends here
