;;; test-safety.el --- ERT tests for the rules of SAFETY.org -*- lexical-binding: t; -*-

;;; Commentary:

;; One test per rule or finding of SAFETY.org; the rule's number is in
;; the test's name and docstring.  Each was shown to fail with its
;; safeguard taken out (CHANGELOG.md).  This file starts with the three
;; findings decided on 2026-10-19:
;;
;;   F1  a note git does not track goes to the trash, not away for good;
;;   F2  no upload to a home folder or the root, and the question says
;;       the upload replaces what is there;
;;   F3  a theme cloned with git is checked out at its pinned commit.
;;
;; Needs git; the modules load in the sandbox of tests/helper.el, Denote
;; from the installed packages.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-safety.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "05-notes" "46-blog")

(defun my/safety-test--git (dir &rest args)
  "Run git with ARGS in DIR; return its output, or signal on failure."
  (with-temp-buffer
    (let ((default-directory (file-name-as-directory dir)))
      (unless (eq 0 (apply #'call-process "git" nil t nil
                           "-c" "user.name=test" "-c" "user.email=test@test"
                           "-c" "init.defaultBranch=main" args))
        (error "git %S failed: %s" args (buffer-string)))
      (string-trim (buffer-string)))))

;; ============================================================
;; F1 -- 2.1: DELETING A NOTE
;; ============================================================

(ert-deftest my/safety-test-2.1-untracked-note-to-trash ()
  "2.1, F1: a note git does not track goes to the trash."
  (let* ((dir (make-temp-file "mypks-notes-" t))
         (trash (make-temp-file "mypks-trash-" t))
         (trash-directory trash)
         (note (expand-file-name "20261019T120000--a-note.org" dir)))
    (with-temp-file note (insert "#+title: a note\n"))
    (should (equal (my/denote--delete-file note) "trash"))
    (should-not (file-exists-p note))
    (should (file-exists-p (expand-file-name (file-name-nondirectory note) trash)))
    (delete-directory dir t)
    (delete-directory trash t)))

(ert-deftest my/safety-test-2.1-tracked-note-kept-by-git ()
  "2.1: a tracked note is removed with git rm, and git still has it."
  (skip-unless (executable-find "git"))
  (let* ((dir (make-temp-file "mypks-notes-" t))
         (note (expand-file-name "20261019T120000--tracked.org" dir)))
    (my/safety-test--git dir "init" "--quiet")
    (with-temp-file note (insert "#+title: tracked\n"))
    (my/safety-test--git dir "add" ".")
    (my/safety-test--git dir "commit" "--quiet" "-m" "note")
    (let ((default-directory (file-name-as-directory dir)))
      (should (equal (my/denote--delete-file note) "git")))
    (should-not (file-exists-p note))
    (should (string-match-p "tracked"
                            (my/safety-test--git dir "show" "HEAD:20261019T120000--tracked.org")))
    (delete-directory dir t)))

;; ============================================================
;; F2 -- 1.5: UPLOADING A SITE
;; ============================================================

(ert-deftest my/safety-test-1.5-home-and-root-refused ()
  "1.5, F2: a home folder or the root is no upload destination."
  (dolist (remote '("user@server:" "user@server:~" "user@server:~/" "server:/"
                    "server:/root/" "user@server:/home/bob" "user@server:/home/bob/"
                    "server:/Users/bob/" "server:~bob" "~" "~/"))
    (should (my/blog--remote-problem remote)))
  (should (my/blog--remote-problem (expand-file-name "~"))))

(ert-deftest my/safety-test-1.5-site-folders-allowed ()
  "1.5: a folder of its own on the server is accepted."
  (dolist (remote '("user@server:/var/www/blog/" "server:/home/bob/www/"
                    "user@server:~/www/blog/" "/srv/site/"))
    (should-not (my/blog--remote-problem remote))))

(ert-deftest my/safety-test-1.5-upload-refused-at-the-last-moment ()
  "1.5: the build-and-upload step itself refuses, whoever calls it."
  (let ((my/blog-sites '(("s" :directory "/tmp/s/" :remote "user@server:")))
        (started nil))
    (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (setq started t))))
      (should-error (my/blog--build-and-upload "s") :type 'user-error))
    (should-not started)))

;; ============================================================
;; F3 -- 3.3: THEMES INSTALLED WITH GIT
;; ============================================================

(defun my/safety-test--theme-repo ()
  "Make a git repository with two commits; return (DIR FIRST SECOND)."
  (let ((dir (make-temp-file "mypks-theme-" t)))
    (my/safety-test--git dir "init" "--quiet")
    (with-temp-file (expand-file-name "theme.toml" dir) (insert "name = \"one\"\n"))
    (my/safety-test--git dir "add" ".")
    (my/safety-test--git dir "commit" "--quiet" "-m" "one")
    (let ((first (my/safety-test--git dir "rev-parse" "HEAD")))
      (with-temp-file (expand-file-name "theme.toml" dir) (insert "name = \"two\"\n"))
      (my/safety-test--git dir "commit" "--quiet" "-am" "two")
      (list dir first (my/safety-test--git dir "rev-parse" "HEAD")))))

(defun my/safety-test--install (theme target)
  "Install THEME into TARGET as a sync would; return the result passed on."
  (let ((result 'pending))
    (puthash target (list (lambda (ok) (setq result ok))) my/blog--theme-installs)
    (my/blog--install-theme-git '("site") theme target)
    (with-timeout (60 (error "Theme install did not finish"))
      (while (eq result 'pending)
        (accept-process-output nil 0.1)))
    result))

(ert-deftest my/safety-test-3.3-theme-at-its-pinned-commit ()
  "3.3, F3: a cloned theme is at its pinned commit, not the newest."
  (skip-unless (executable-find "git"))
  (pcase-let* ((`(,repo ,first ,_second) (my/safety-test--theme-repo))
               (target (expand-file-name "themes/t" (make-temp-file "mypks-site-" t))))
    (should (eq t (my/safety-test--install (list "t" repo first) target)))
    (should (equal (my/safety-test--git target "rev-parse" "HEAD") first))
    (should-not (my/blog--theme-pin-mismatch (list "t" repo first) target))
    (delete-directory repo t)))

(ert-deftest my/safety-test-3.3-unknown-commit-leaves-nothing ()
  "3.3: a pin the repository lacks installs nothing."
  (skip-unless (executable-find "git"))
  (pcase-let* ((`(,repo ,_first ,_second) (my/safety-test--theme-repo))
               (target (expand-file-name "themes/t" (make-temp-file "mypks-site-" t))))
    (should-not (my/safety-test--install
                 (list "t" repo "0123456789abcdef0123456789abcdef01234567") target))
    (should-not (file-exists-p target))
    (delete-directory repo t)))

(ert-deftest my/safety-test-3.3-moved-theme-is-noticed ()
  "3.3: a theme folder at another commit than its pin is noticed."
  (skip-unless (executable-find "git"))
  (pcase-let* ((`(,repo ,first ,second) (my/safety-test--theme-repo))
               (target (expand-file-name "themes/t" (make-temp-file "mypks-site-" t))))
    (my/safety-test--git repo "clone" "--quiet" repo target)
    (should (equal (my/blog--theme-pin-mismatch (list "t" repo first) target) second))
    (delete-directory repo t)))

(provide 'test-safety)
;;; test-safety.el ends here
