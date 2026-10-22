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

(provide 'helper)
;;; helper.el ends here
