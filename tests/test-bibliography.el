;;; test-bibliography.el --- ERT tests for the PDF viewer setup of 17-bibliography -*- lexical-binding: t; -*-

;; Tests: 17-bibliography

;;; Commentary:

;; 17-bibliography.el sets up pdf-tools, the PDF viewer.  Its server,
;; epdfinfo, is a program built from source.  Until 2026-10-23 the
;; module built it whenever pdf-tools was loaded -- also by the byte
;; compilation of pdf-tools' own files during a first install -- without
;; asking.  The weekly workflow's first start failed on Emacs 29.1 and
;; 30.2 when that build failed while packages were still installing,
;; and passed on 31.1 only because Emacs had quit before the build
;; ended.  The build now waits for the first PDF opened, also in the
;; session that installed pdf-tools (the next weekly run stopped on the
;; question there, asked at once because pdf-tools was loaded).  Needs
;; pdf-tools installed (ci-packages.el installs it for the workflow);
;; nothing is built: `pdf-tools-install' is stood in for.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-bibliography.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "17-bibliography")

(defvar pdf-loader--auto-mode-alist-item)
(defvar pdf-loader--magic-mode-alist-item)

(ert-deftest my/bib-test-loading-pdf-tools-builds-nothing ()
  "Loading pdf-tools -- as compiling its files during an install does --
builds no server; the module only registered a loader for PDF files."
  (skip-unless (fboundp 'pdf-loader-install))
  (should-not (featurep 'pdf-tools))
  ;; Advice, not `cl-letf': loading pdf-tools.el defines
  ;; `pdf-tools-install' again, which keeps advice but not a stand-in.
  (let* ((builds 0)
         (count (lambda (&rest _) (setq builds (1+ builds)))))
    (advice-add 'pdf-tools-install :override count)
    (unwind-protect
        (progn
          (require 'pdf-tools)
          (require 'pdf-view)
          (should (= builds 0)))
      (advice-remove 'pdf-tools-install count)))
  (should (assoc pdf-loader--auto-mode-alist-item auto-mode-alist))
  (should (assoc pdf-loader--magic-mode-alist-item magic-mode-alist)))

(ert-deftest my/bib-test-first-pdf-asks-before-building ()
  "Opening the first PDF sets pdf-tools up, without the no-query flag:
pdf-tools asks before it builds its server."
  (skip-unless (fboundp 'pdf-loader-install))
  ;; The loader takes itself off these lists; they are restored after.
  (let ((calls '())
        (auto-mode-alist auto-mode-alist)
        (magic-mode-alist magic-mode-alist))
    (cl-letf (((symbol-function 'pdf-tools-install)
               (lambda (&rest args) (push args calls))))
      ;; The loader the module registered, as `set-auto-mode' calls it.
      (funcall (cdr (assoc pdf-loader--auto-mode-alist-item auto-mode-alist)))
      (should (= 1 (length calls)))
      (should-not (car (car calls))))))

(ert-deftest my/bib-test-setup-after-pdf-tools-loaded-asks-nothing ()
  "In the session that installed pdf-tools, pdf-tools is loaded before
the module's setup runs (the weekly first start of 2026-10-23 stopped
there, on a question nobody could answer): the setup still asks
nothing and waits for the first PDF."
  (skip-unless (fboundp 'pdf-loader-install))
  (require 'pdf-tools)
  (let* ((builds 0)
         (count (lambda (&rest _) (setq builds (1+ builds))))
         (auto-mode-alist (assoc-delete-all pdf-loader--auto-mode-alist-item
                                            (copy-alist auto-mode-alist)))
         (magic-mode-alist (assoc-delete-all pdf-loader--magic-mode-alist-item
                                             (copy-alist magic-mode-alist))))
    (advice-add 'pdf-tools-install :override count)
    (unwind-protect
        (progn
          (my/bibliography--pdf-on-demand)
          (should (= builds 0))
          (should (assoc pdf-loader--auto-mode-alist-item auto-mode-alist))
          (should (assoc pdf-loader--magic-mode-alist-item magic-mode-alist))
          ;; The features are as they were: pdf-tools still loaded.
          (should (featurep 'pdf-tools))
          (should (featurep 'pdf-loader)))
      (advice-remove 'pdf-tools-install count))))

(provide 'test-bibliography)
;;; test-bibliography.el ends here
