;;; declarations.el --- Weekly: every declare-function form matches its definition -*- lexical-binding: t; -*-

;;; Commentary:

;; A `declare-function' form tells the byte compiler that a function
;; exists in another file, with a given argument list; the compiler then
;; checks calls against that list.  A declaration left behind after the
;; function moved or gained an argument silences the warning it exists
;; for: the call is checked against the wrong list (2026-10-25w: five
;; stale ones, one left by the split of 826-maintenance the same day).
;;
;; Emacs has the check built in: `check-declare-directory' (library
;; check-declare) finds each declared file, the definition in it and
;; compares the argument lists.  This runs it over modules/ and fails
;; on any problem not listed in declare-exceptions.txt -- one line per
;; function, "FUNCTION  reason", for a definition check-declare cannot
;; see (a constructor made by `cl-defstruct', a function made by a
;; macro of a package).
;;
;; Two ways to run it:
;;
;; - weekly, `my/weekly-check-declarations' (hooks/check-weekly), with
;;   every package installed: every declared file must be found,
;;   "ext:" ones too (`check-declare-ext-errors'), since a package's
;;   file missing then means the package renamed or dropped it;
;;
;; - at every push and with hooks/check-all,
;;   `my/check-declarations-installed', with the packages installed
;;   here: a package's file not found is skipped and counted (the
;;   package is not installed), everything found is checked as weekly.
;;   A module's file is never skipped: modules are always here.  Added
;;   2026-11-13c: a wrong declaration of a package's function, found by
;;   the weekly run only, had waited a week (2026-11-13a); the packages
;;   the push's tests install are the ones new code tends to use.

;;; Code:

(require 'check-declare)
(require 'seq)
(require 'subr-x)

(defconst my/weekly-declare-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "This folder, tests/weekly/.")

(defconst my/weekly-declare-exceptions-file
  (expand-file-name "declare-exceptions.txt" my/weekly-declare-directory)
  "Functions whose definition check-declare cannot see.")

(defun my/weekly-declare--exceptions ()
  "The function names listed in the exceptions file."
  (when (file-exists-p my/weekly-declare-exceptions-file)
    (with-temp-buffer
      (insert-file-contents my/weekly-declare-exceptions-file)
      (delq nil
            (mapcar (lambda (line)
                      (unless (or (string-empty-p (string-trim line))
                                  (string-prefix-p "#" line))
                        (car (split-string line))))
                    (split-string (buffer-string) "\n"))))))

(defvar my/declare-installed-only nil
  "Non-nil: a declared file that is not found and is no module is skipped.
Set by `my/check-declarations-installed'.")

(defun my/declare--module-file-p (file)
  "Non-nil when FILE, a declared file, is a module: its name starts with a digit."
  (string-match-p "\\`[0-9]" (file-name-nondirectory file)))

(defun my/check-declarations-installed ()
  "Check the declarations of modules/ against the packages installed here.
As `my/weekly-check-declarations', but a package's file that is not
found is skipped and counted instead of failing."
  (let ((my/declare-installed-only t))
    (my/weekly-check-declarations)))

(defun my/weekly-check-declarations ()
  "Check every declaration of modules/; print each problem; exit 1 on one."
  (let* ((modules (expand-file-name "../../modules" my/weekly-declare-directory))
         ;; With every package installed, an "ext:" file not found is a
         ;; package that lost the file; with some installed, it is one
         ;; not installed.
         (check-declare-ext-errors (not my/declare-installed-only))
         (exceptions (my/weekly-declare--exceptions))
         ;; check-declare also shows its findings in a *Check Declarations
         ;; Warnings* buffer; in batch that is printed to standard error,
         ;; which hooks/check-weekly does not show.
         ;; A declaration names a module by its file name, "205-notes";
         ;; check-declare looks it up with `locate-library', so the
         ;; folders of the groups go on the load path (since 2026-10-26c
         ;; a module is not in the folder of the one it declares from).
         (load-path (append (seq-filter #'file-directory-p
                                        (directory-files modules t "\\`[0-9]"))
                            load-path))
         (errors (let ((inhibit-message t)) (check-declare-directory modules)))
         (problems nil) (excused nil) (skipped nil))
    ;; ERRORS: ((DECLARED-FILE (SOURCE-FILE FUNCTION REASON) ...) ...)
    (dolist (entry errors)
      (dolist (item (cdr entry))
        (pcase-let ((`(,source ,function ,reason) item))
          (cond
           ((member function exceptions)
            (push function excused))
           ((and my/declare-installed-only
                 (equal reason "file not found")
                 (not (my/declare--module-file-p (car entry))))
            (push function skipped))
           (t
            (push (format "%s: %s declared in %s: %s"
                          (file-name-nondirectory source) function
                          (file-name-nondirectory (car entry)) reason)
                  problems))))))
    (dolist (p (sort problems #'string<))
      (princ (format "PROBLEM   %s\n" p)))
    ;; Only with every package installed: otherwise an exception is not
    ;; reported because its package is not installed.
    (unless my/declare-installed-only
      (dolist (f (seq-remove (lambda (f) (member f excused)) exceptions))
        (princ (format "gone      %s  (no longer reported: remove its line)\n" f))))
    (princ (format "declarations: %d problem(s), %d excused%s\n"
                   (length problems) (length (seq-uniq excused))
                   (if my/declare-installed-only
                       (format ", %d skipped (package not installed)" (length skipped))
                     "")))
    (kill-emacs (if problems 1 0))))

(provide 'weekly-declarations)
;;; declarations.el ends here
