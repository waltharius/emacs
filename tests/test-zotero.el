;;; test-zotero.el --- ERT tests for 17c-zotero -*- lexical-binding: t; -*-

;; Tests: 17c-zotero

;;; Commentary:

;; 17c-zotero points citar at Zotero's attachments folder.  Tested: the
;; folder is citar's library path once citar loads, a new folder takes
;; effect at once, none gives no path; without the module citar has no
;; library path from this configuration (17-bibliography sets none).
;; Needs citar installed.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-zotero.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(defvar citar-library-paths)

(my/test-load-modules "04-denote" "05-notes" "17-bibliography")
(when (locate-library "citar") (require 'citar))

(defconst my/zot-test--paths-without
  (and (boundp 'citar-library-paths) citar-library-paths)
  "citar's library paths with 17-bibliography loaded and 17c-zotero not.")

(my/test-load-modules "17c-zotero")

(ert-deftest my/zot-test-only-the-module-sets-the-folder ()
  "17-bibliography alone sets no library path; 17c-zotero sets the
folder, expanded, once citar is loaded."
  (skip-unless (featurep 'citar))
  (should-not my/zot-test--paths-without)
  (should (equal citar-library-paths
                 (list (expand-file-name my/zotero-storage-directory)))))

(ert-deftest my/zot-test-a-new-folder-at-once ()
  "Setting the folder through Customize changes citar's path at once;
none leaves citar without one."
  (skip-unless (featurep 'citar))
  (let ((dir (make-temp-file "mypks-zotero-" t)))
    (unwind-protect
        (progn
          (customize-set-variable 'my/zotero-storage-directory dir)
          (should (equal citar-library-paths (list (expand-file-name dir))))
          (customize-set-variable 'my/zotero-storage-directory nil)
          (should-not citar-library-paths))
      (customize-set-variable 'my/zotero-storage-directory "~/Zotero/storage/")
      (delete-directory dir t))))

(ert-deftest my/zot-test-in-the-bibliography-settings ()
  "The folder is among the settings the bibliography menu opens."
  (should (assq 'my/zotero-storage-directory (get 'my/bibliography 'custom-group))))

(provide 'test-zotero)
;;; test-zotero.el ends here
