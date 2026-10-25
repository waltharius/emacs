;;; test-package-upgrade.el --- ERT tests for upgrading packages with a copy, 149-packages -*- lexical-binding: t; -*-

;; Tests: 149-packages

;;; Commentary:

;; 149-packages.el upgrades the installed packages after copying the
;; package folder, and puts such a copy back.  No network and no real
;; package: a package folder in a temporary directory, package.el's
;; lists filled by hand, the refresh and `package-upgrade' stood in for
;; (the stand-in changes the folder the way an upgrade does).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-package-upgrade.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "212-transient" "227-denote-identifiers" "826-maintenance" "149-packages")

;; ============================================================
;; FIXTURE
;; ============================================================

(defun my/pkg-test--write (file text)
  "Write TEXT to FILE, creating its folder."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text)))

(defun my/pkg-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/pkg-test--desc (name version &optional kind dir)
  "Return a package description of NAME at VERSION (a string)."
  (package-desc-create :name name :version (version-to-list version)
                       :kind (or kind 'tar) :dir dir))

(defmacro my/pkg-test--with-packages (&rest body)
  "Run BODY with installed packages a 1.0, b 2.0 and v 1.0 (from git).
The archives hold a 1.1, b 2.0, v 2.0 and c 1.0 (not installed).
Binds `elpa', `backups', `upgraded' (names `package-upgrade' was called
with), `failing' (names whose upgrade signals), `asked' (questions) and
`answer' (nil at first)."
  (declare (indent 0))
  `(let* ((tmp (file-name-as-directory (make-temp-file "mypks-pkg-" t)))
          (elpa (expand-file-name "elpa/" tmp))
          (backups (expand-file-name "elpa-backups/" tmp))
          (package-user-dir elpa)
          (my/packages-backup-directory backups)
          (package-alist
           (list (list 'a (my/pkg-test--desc 'a "1.0" 'tar (expand-file-name "a-1.0" elpa)))
                 (list 'b (my/pkg-test--desc 'b "2.0" 'tar (expand-file-name "b-2.0" elpa)))
                 (list 'v (my/pkg-test--desc 'v "1.0" 'vc (expand-file-name "v" elpa)))))
          (package-archive-contents
           (list (list 'a (my/pkg-test--desc 'a "1.1") (my/pkg-test--desc 'a "1.0.5"))
                 (list 'b (my/pkg-test--desc 'b "2.0"))
                 (list 'v (my/pkg-test--desc 'v "2.0"))
                 (list 'c (my/pkg-test--desc 'c "1.0"))))
          (upgraded '())
          (failing '())
          (asked '())
          (answer nil)
          (inhibit-message t))
     (my/pkg-test--write (expand-file-name "a-1.0/a.el" elpa) "a one")
     (my/pkg-test--write (expand-file-name "b-2.0/b.el" elpa) "b two")
     (unwind-protect
         (cl-letf (((symbol-function 'package-refresh-contents) #'ignore)
                   ((symbol-function 'display-buffer) #'ignore)
                   ((symbol-function 'yes-or-no-p)
                    (lambda (prompt) (push prompt asked) answer))
                   ((symbol-function 'package-upgrade)
                    (lambda (name)
                      (push name upgraded)
                      ;; As package.el does: the old version goes first.
                      (delete-directory (expand-file-name (format "%s-1.0" name) elpa) t)
                      (when (memq name failing) (error "Download of %s failed" name))
                      (my/pkg-test--write (expand-file-name (format "%s-1.1/%s.el" name name) elpa)
                                          "new"))))
           ,@body)
       (when (get-buffer my/packages-report-buffer)
         (kill-buffer my/packages-report-buffer))
       (delete-directory tmp t))))

;; ============================================================
;; WHAT CAN BE UPGRADED
;; ============================================================

(ert-deftest my/pkg-test-upgradable-only-newer-installed ()
  "Only installed packages with a newer version in an archive, the newest
one: not one at the same version, not one installed from git, not one
not installed."
  (my/pkg-test--with-packages
    (let ((todo (my/packages--upgradable)))
      (should (equal (mapcar #'car todo) '(a)))
      (should (equal (my/packages--version (nth 1 (car todo))) "1.0"))
      (should (equal (my/packages--version (nth 2 (car todo))) "1.1")))))

(ert-deftest my/pkg-test-nothing-to-upgrade ()
  "Nothing newer: no question, no copy."
  (my/pkg-test--with-packages
    (let ((package-archive-contents (list (list 'a (my/pkg-test--desc 'a "1.0")))))
      (my/packages-upgrade)
      (should-not asked)
      (should-not (file-exists-p backups)))))

;; ============================================================
;; UPGRADE
;; ============================================================

(ert-deftest my/pkg-test-asks-first ()
  "The question names each package with its versions and where the copy
goes; no copies nothing and upgrades nothing."
  (my/pkg-test--with-packages
    (my/packages-upgrade)
    (should (= 1 (length asked)))
    (should (string-match-p "a 1\\.0->1\\.1" (car asked)))
    (should (string-match-p (regexp-quote (abbreviate-file-name backups)) (car asked)))
    (should-not upgraded)
    (should-not (file-exists-p backups))))

(ert-deftest my/pkg-test-copy-before-upgrade ()
  "Yes: the package folder is copied as it was before anything changes,
then the package is upgraded; beside the copy, how to go back -- from
Emacs and from a shell; the report says where the copy is."
  (my/pkg-test--with-packages
    (setq answer t)
    (my/packages-upgrade)
    (should (equal upgraded '(a)))
    (let ((copy (car (my/packages--backups))))
      (should copy)
      (should (equal (my/pkg-test--read (expand-file-name "a-1.0/a.el" copy)) "a one"))
      (should (equal (my/pkg-test--read (expand-file-name "b-2.0/b.el" copy)) "b two"))
      (should-not (file-exists-p (expand-file-name "a-1.1" copy)))
      (should (file-exists-p (expand-file-name "a-1.1/a.el" elpa)))
      (let ((how (my/pkg-test--read (concat (directory-file-name copy) "-RESTORE.txt"))))
        (should (string-match-p "my/packages-restore" how))
        (should (string-match-p (regexp-quote (format "cp -a %s %s"
                                                      (directory-file-name copy)
                                                      (directory-file-name elpa)))
                                how)))
      (with-current-buffer my/packages-report-buffer
        (should (string-match-p (regexp-quote copy) (buffer-string)))
        (should (string-match-p "a +1\\.0 -> 1\\.1" (buffer-string)))
        (should (string-match-p "How to go back" (buffer-string)))))))

(ert-deftest my/pkg-test-copy-cut-short-not-offered ()
  "A copy that fails half way -- a full disk -- upgrades nothing and is
not among the copies offered for going back; what it left keeps a name
of its own.  (Until 2026-10-24 it was copied straight to its final name
and looked complete.)"
  (my/pkg-test--with-packages
    (setq answer t)
    (advice-add 'copy-directory :around
                (lambda (copy from to &rest args)
                  (apply copy from to args)
                  (delete-file (expand-file-name "b-2.0/b.el" to))
                  (signal 'file-error (list "No space left on device")))
                '((name . my/pkg-test-full-disk)))
    (unwind-protect
        (should-error (my/packages-upgrade))
      (advice-remove 'copy-directory 'my/pkg-test-full-disk))
    (should-not upgraded)
    (should-not (my/packages--backups))
    (should (directory-files backups nil "\\.partial\\'"))))

(ert-deftest my/pkg-test-one-failure-others-go-on ()
  "A package whose upgrade fails is reported as possibly missing; the
others are upgraded."
  (my/pkg-test--with-packages
    (setq answer t failing '(a))
    (let ((package-archive-contents
           (cons (list 'b (my/pkg-test--desc 'b "2.1")) package-archive-contents)))
      (setf (alist-get 'b package-alist) (list (my/pkg-test--desc 'b "1.0")))
      (my/pkg-test--write (expand-file-name "b-1.0/b.el" elpa) "b old")
      (my/packages-upgrade))
    (should (equal (sort (mapcar #'symbol-name upgraded) #'string<) '("a" "b")))
    (with-current-buffer my/packages-report-buffer
      (should (string-match-p "Upgraded (1)" (buffer-string)))
      (should (string-match-p "Failed (1)" (buffer-string)))
      (should (string-match-p "may be missing" (buffer-string)))
      (should (string-match-p "Download of a failed" (buffer-string))))))

;; ============================================================
;; GOING BACK
;; ============================================================

(ert-deftest my/pkg-test-restore-moves-current-aside ()
  "Going back: no changes nothing; yes moves the current package folder
aside -- not deleted -- and puts the copy in its place."
  (my/pkg-test--with-packages
    (setq answer t)
    (my/packages-upgrade)
    (let ((copy (file-name-nondirectory (directory-file-name (car (my/packages--backups))))))
      (setq answer nil)
      (my/packages-restore copy)
      (should (file-exists-p (expand-file-name "a-1.1/a.el" elpa)))
      (setq answer t)
      (my/packages-restore copy)
      (should (equal (my/pkg-test--read (expand-file-name "a-1.0/a.el" elpa)) "a one"))
      (should-not (file-exists-p (expand-file-name "a-1.1" elpa)))
      (let ((aside (directory-files tmp t "\\`elpa-replaced-")))
        (should (= 1 (length aside)))
        (should (file-exists-p (expand-file-name "a-1.1/a.el" (car aside))))))))

(ert-deftest my/pkg-test-restore-only-own-copies ()
  "A folder that is not a copy made by the module is refused, and the
package folder stays as it is."
  (my/pkg-test--with-packages
    (setq answer t)
    (make-directory (expand-file-name "other" backups) t)
    (should-error (my/packages-restore (expand-file-name "other" backups)) :type 'user-error)
    (should-error (my/packages-restore tmp) :type 'user-error)
    (should (file-exists-p (expand-file-name "a-1.0/a.el" elpa)))
    (should-not (directory-files tmp nil "\\`elpa-replaced-"))))

;; ============================================================
;; MENU
;; ============================================================

(ert-deftest my/pkg-test-menu-column-follows-switch ()
  "The Maintenance menu has the column while the switch is on, not off."
  (should (ignore-errors (transient-get-suffix 'my/notes-maintenance-menu "U")))
  (unwind-protect
      (progn
        (my/packages-mode -1)
        (should-not (ignore-errors (transient-get-suffix 'my/notes-maintenance-menu "U")))
        (should (ignore-errors (transient-get-suffix 'my/notes-maintenance-menu "q"))))
    (my/packages-mode 1))
  (should (ignore-errors (transient-get-suffix 'my/notes-maintenance-menu "U"))))

(provide 'test-package-upgrade)
;;; test-package-upgrade.el ends here
