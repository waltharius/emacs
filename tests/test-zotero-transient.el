;;; test-zotero-transient.el --- ERT tests for the Zotero menu of 18-zotero-transient -*- lexical-binding: t; -*-

;; Tests: 18-zotero-transient

;;; Commentary:

;; 18-zotero-transient is a menu: C-c x and an entry in Tools.  A menu
;; entry naming a command that does not exist fails only when chosen,
;; so the test checks every entry of the menu against what citar,
;; citar-denote and 17-bibliography define.  The key and the entry
;; coming and going with the switch are the weekly tests' business.
;; Needs citar and citar-denote installed (ci-packages.el).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-zotero-transient.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "04-denote" "05-notes" "12-transient" "17-bibliography"
                      "18-zotero-transient")

(defconst my/zt-test-keys '("n" "o" "f" "e" "u" "i" "R" "S" "c" "C" "?" "," "q")
  "The keys of the Zotero menu.")

(ert-deftest my/zt-test-every-entry-runs-a-command ()
  "Each key of the Zotero menu runs a command that exists."
  (skip-unless (and (locate-library "citar") (locate-library "citar-denote")))
  (require 'citar)
  (require 'citar-denote)
  (dolist (key my/zt-test-keys)
    (let ((command (my/transient--layout-command (transient-get-suffix 'my/zotero-menu key))))
      (should (and key command))
      (should (commandp command)))))

(ert-deftest my/zt-test-key-and-entry ()
  "C-c x opens the menu, and Tools has it under z, while the switch is on."
  (should my/zotero-mode)
  (should (eq (key-binding (kbd "C-c x")) #'my/zotero-menu))
  (should (eq (my/transient--layout-command (transient-get-suffix 'my/notes-tools-menu "z"))
              #'my/zotero-menu)))

(provide 'test-zotero-transient)
;;; test-zotero-transient.el ends here
