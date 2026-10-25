;;; helper.el --- Load the configuration for a test, away from real data -*- lexical-binding: t; -*-

;;; Commentary:

;; A test that needs modules of this configuration loads this file and
;; calls `my/test-load-modules'.  That loads 00-core.el and the modules
;; named, from this repository, in a sandbox: a temporary HOME, settings
;; folder and ~/.emacs.d, removed when Emacs exits.  So a test run reads
;; and writes nothing of the real notes, settings or ~/.emacs.d -- 00-core
;; moves old files and writes reports at load, and must not do that to
;; the real ones.
;;
;; Packages are the ones installed for this user (~/.emacs.d/elpa/),
;; read only; nothing is installed.  A package that is missing makes
;; use-package warn and the module load without it, as at a real start.
;;
;; Not a test file itself: its name does not start with test-, so
;; hooks/check-all does not run it.

;;; Code:

(defconst my/test-repo
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
  "This repository: the modules loaded are its own, not ~/.emacs.d's.")

(defvar my/test-sandbox nil
  "Temporary folder standing in for HOME, or nil before the first load.")

(defvar my/test-real-home nil
  "HOME before the sandbox, or nil before the first load.
For a test that starts a child Emacs which must find the installed
packages: the child gets this HOME and makes its own sandbox.")

(defvar my/test-allow-install nil
  "Non-nil: use-package may install missing packages in the sandbox.
Only tests/weekly/install.el sets it -- the first start on a clean
machine; a test installs nothing (TESTING.org, rule 9).")

(defun my/test--enter-sandbox ()
  "Point HOME, the settings folder and ~/.emacs.d into a temporary folder."
  ;; The real package folder and current folder, taken before HOME
  ;; changes: both may be written with "~", which then means the sandbox.
  (setq default-directory (file-name-as-directory (expand-file-name default-directory)))
  (let ((elpa (expand-file-name "elpa/" user-emacs-directory)))
    (setq my/test-real-home (getenv "HOME"))
    (setq my/test-sandbox (make-temp-file "mypks-test-" t))
    (setenv "HOME" my/test-sandbox)
    (setenv "MYPKS_DIR" (expand-file-name "settings" my/test-sandbox))
    (setenv "MYPKS_HOST" "test")
    ;; `abbreviate-file-name' caches the home directory.
    (setq abbreviated-home-dir nil)
    (setq user-emacs-directory
          (file-name-as-directory (expand-file-name "emacs.d" my/test-sandbox)))
    (make-directory (expand-file-name "modules" user-emacs-directory) t)
    (setq package-user-dir elpa)
    ;; A test installs nothing.
    (unless my/test-allow-install
      (setq use-package-ensure-function #'ignore))
    (add-hook 'kill-emacs-hook
              (lambda () (ignore-errors (delete-directory my/test-sandbox t))))))

(defun my/test-load-modules (&rest modules)
  "Load 00-core.el, then MODULES (names without .el), in a sandbox.
A module loaded already is not loaded again."
  (unless my/test-sandbox
    (my/test--enter-sandbox))
  (dolist (name (cons "00-core" modules))
    (unless (featurep (intern name))
      (load (expand-file-name (concat "modules/" name ".el") my/test-repo) nil t))))

(defun my/test-date (offset)
  "The calendar date OFFSET days from today, as \"YYYY-MM-DD\".
Written apart from the date functions of 00-core.el on purpose, so
that tests of code using them compare with dates they did not compute.
Counted in calendar days, from midday: steps of 86400 seconds from
now land on the wrong date near midnight on the two days a year whose
length is not 24 hours -- in Central Europe 23:23 on the day summer
time ends, minus 86400 seconds, is 00:23 the same day (found
2026-10-25, when two tests failed in that hour).  `encode-time'
carries a day past the end of the month into the next."
  (let ((now (decode-time)))
    (format-time-string
     "%Y-%m-%d"
     (encode-time (list 0 0 12 (+ (nth 3 now) offset) (nth 4 now) (nth 5 now)
                        nil -1 nil)))))

(defconst my/test-central-europe "CET-1CEST,M3.5.0,M10.5.0/3"
  "The time zone of the owner's machines, as a POSIX TZ rule.")

(defmacro my/test-with-time-zone (zone &rest body)
  "Run BODY with the time zone ZONE, a POSIX TZ string; restore it after."
  (declare (indent 1))
  `(let ((saved (getenv "TZ")))
     (unwind-protect
         (progn (setenv "TZ" ,zone)
                (set-time-zone-rule ,zone)
                ,@body)
       (setenv "TZ" saved)
       (set-time-zone-rule saved))))

(provide 'helper)
;;; helper.el ends here
