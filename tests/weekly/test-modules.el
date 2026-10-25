;;; test-modules.el --- Weekly: every module loads alone, without others, and switches cleanly -*- lexical-binding: t; -*-

;; Every module of init.el's list, with tests made from the list (below).

;;; Commentary:

;; Three kinds of test, made for each module of init.el's list, so that
;; a failure names the module (TESTING.org, "Every module tested", part
;; 2).  Each runs in its own `emacs -Q --batch' (tests/weekly/lib.el),
;; in the sandbox of tests/helper.el, with the packages installed for
;; this user:
;;
;;   my/weekly-test-alone-NAME    000-core, the modules NAME declares in
;;                                MyPKS-Requires, and NAME: nothing else.
;;                                A use of another module that is
;;                                neither declared nor guarded fails.
;;   my/weekly-test-without-NAME  (optional modules) every module but
;;                                NAME and those requiring it: all load.
;;                                None needs NAME without saying so.
;;   my/weekly-test-switch-NAME   (modules with MyPKS-Switch) NAME loaded
;;                                last, switched off and on again: off,
;;                                nothing of its own left (hooks, advice,
;;                                keys, menu entries, repeating timers,
;;                                mode lists, capture templates, global
;;                                modes) and nothing of another module
;;                                taken; on again, the same as the first
;;                                time, nothing doubled.
;;
;; The list of modules is read from init.el, the requirements and
;; switches from the modules' headers: a module renamed, merged or split
;; needs no change here.
;;
;; Known failures, each with its reason, are in expected-failures.txt;
;; they are marked as expected, reported, and fail the run when they
;; start passing (so the list stays true).
;;
;; Needs every package of the configuration (the weekly workflow
;; installs them; on the owner's machine they are installed).  Run:
;;
;;   bash hooks/check-weekly            # compilation and these tests
;;   bash hooks/check-weekly 424-readwise    # the tests of one module

;;; Code:

(require 'ert)
(require 'seq)

(load (expand-file-name "lib" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defun my/weekly--expected-failures ()
  "Alist (TEST-NAME . REASON) read from expected-failures.txt."
  (let ((file (expand-file-name "expected-failures.txt" my/weekly-directory))
        out)
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (dolist (line (split-string (buffer-string) "\n" t))
          (when (string-match "\\`\\(my/weekly-test-[^ \t]+\\)[ \t]+\\(.+\\)\\'" line)
            (push (cons (match-string 1 line) (match-string 2 line)) out)))))
    out))

(defun my/weekly--run-child (kind name)
  "Run KIND for module NAME in a child Emacs; return its PROBLEM lines.
Signals when the child did not reach its end."
  (let* ((dir (file-name-as-directory (make-temp-file "mypks-weekly-" t)))
         ;; Rule 8 of TESTING.org: the child starts in a temporary folder.
         (default-directory dir))
    (unwind-protect
        (with-temp-buffer
          (let* ((code (call-process (expand-file-name invocation-name invocation-directory)
                                     nil t nil "-Q" "--batch"
                                     "--eval" "(package-initialize)"
                                     "-l" (expand-file-name "lib.el" my/weekly-directory)
                                     "--eval" (format "(my/weekly-child %S %S)" kind name)))
                 (lines (split-string (buffer-string) "\n")))
            ;; Both: DONE printed and then an error on the way out was a
            ;; pass until 2026-10-24 (TESTING.org, rule 14).
            (unless (and (eql code 0) (member "DONE" lines))
              (error "The child Emacs %s:\n%s"
                     (if (member "DONE" lines) (format "ended with status %s" code)
                       "stopped before the end")
                     (string-join (last lines 15) "\n")))
            (seq-filter (lambda (l) (string-prefix-p "PROBLEM " l)) lines)))
      (delete-directory dir t))))

(defmacro my/weekly--deftest (kind name doc)
  "Define the test of KIND for module NAME, documented by DOC."
  (let* ((test (intern (format "my/weekly-test-%s-%s" kind name)))
         (expected (assoc (symbol-name test) (my/weekly--expected-failures))))
    `(ert-deftest ,test ()
       ,(if expected (format "%s\nExpected to fail: %s" doc (cdr expected)) doc)
       :expected-result ,(if expected :failed :passed)
       (should (equal (my/weekly--run-child ,kind ,name) nil)))))

(defun my/weekly--header (name header)
  "The value of HEADER in the header of module NAME, or nil when empty.
Read here, not through 000-core.el: loading that would put this Emacs in
the sandbox, and the children would inherit its HOME (no packages)."
  (require 'lisp-mnt)
  (with-temp-buffer
    (insert-file-contents (my/test-module-file name)
                          nil 0 4000)
    (let ((value (lm-header header)))
      (and value (not (string-empty-p (string-trim value))) value))))

(dolist (name (my/weekly-modules))
  (let ((info (list :optional (equal (my/weekly--header name "MyPKS-Optional") "yes")
                    :switch (my/weekly--header name "MyPKS-Switch"))))
    (eval `(my/weekly--deftest "alone" ,name
                               ,(format "%s loads with 000-core and what it declares, alone." name))
          t)
    (when (plist-get info :optional)
      (eval `(my/weekly--deftest "without" ,name
                                 ,(format "Every other module loads without %s." name))
            t))
    (when (plist-get info :switch)
      (eval `(my/weekly--deftest "switch" ,name
                                 ,(format "%s switched off leaves nothing; on again, nothing doubled." name))
            t))))

(provide 'test-modules)
;;; test-modules.el ends here
