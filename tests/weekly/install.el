;;; install.el --- Weekly: a first start on a clean machine installs every package -*- lexical-binding: t; -*-

;;; Commentary:

;; What a new user's first start does: every module of init.el's list
;; loads, and use-package installs each package from the archives (GNU
;; ELPA, NonGNU ELPA, MELPA), as 000-core.el sets them up.  Run by the
;; weekly workflow on a machine with nothing installed, before the
;; other weekly checks, which need the packages.
;;
;; Fails when a package could not be installed (use-package's "Failed
;; to install" -- the archives change: a build deleted from MELPA, a
;; package renamed or withdrawn) or a module did not load.  On
;; 2026-10-19 a stale package list made no-littering fail exactly so.
;;
;; The sandbox of tests/helper.el, except that installing is allowed:
;; the packages go to ~/.emacs.d/elpa/ of the user running it.  Not run
;; by hooks/check-weekly: on the owner's machine everything is installed
;; already, and a test installs nothing (TESTING.org, rule 9).
;;
;;   emacs -Q --batch -l tests/weekly/install.el -f my/weekly-install-all

;;; Code:

(load (expand-file-name "lib" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defvar my/weekly-install-problems nil
  "Warnings about packages, collected while the modules load.")

(defun my/weekly--record-warning (type message &optional level &rest _)
  "Keep MESSAGE of a warning of TYPE at LEVEL that concerns a package."
  (when (or (eq type 'use-package)
            (and (memq level '(:error :emergency))
                 (string-match-p "install\\|package" (format "%s" message))))
    (push (format "%s: %s" type message) my/weekly-install-problems)))

(defun my/weekly-install-all ()
  "Load every module, installing what is missing; exit 1 on a problem."
  (package-initialize)
  (advice-add 'display-warning :before #'my/weekly--record-warning)
  (setq my/test-allow-install t)
  (my/weekly-start)
  (my/weekly-load (cdr my/modules-order))
  (let ((problems (append (mapcar (lambda (e) (my/modules--skip-line e)) my/modules--skipped)
                          (reverse my/weekly-install-problems))))
    (princ (format "installed packages: %d\n" (length package-alist)))
    (dolist (p problems)
      (princ (format "PROBLEM %s\n" p)))
    (kill-emacs (if problems 1 0))))

(provide 'weekly-install)
;;; install.el ends here
