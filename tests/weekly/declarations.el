;;; declarations.el --- Weekly: every declare-function form matches its definition -*- lexical-binding: t; -*-

;;; Commentary:

;; A `declare-function' form tells the byte compiler that a function
;; exists in another file, with a given argument list; the compiler then
;; checks calls against that list.  A declaration left behind after the
;; function moved or gained an argument silences the warning it exists
;; for: the call is checked against the wrong list (2026-10-25w: five
;; stale ones, one left by the split of 26-maintenance the same day).
;;
;; Emacs has the check built in: `check-declare-directory' (library
;; check-declare) finds each declared file, the definition in it and
;; compares the argument lists.  This runs it over modules/ and fails
;; on any problem not listed in declare-exceptions.txt -- one line per
;; function, "FUNCTION  reason", for a definition check-declare cannot
;; see (a constructor made by `cl-defstruct', a function made by a
;; macro of a package).
;;
;; A weekly check: a declaration names a package's file, found only
;; with every package installed.  Run by hooks/check-weekly.

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

(defun my/weekly-check-declarations ()
  "Check every declaration of modules/; print each problem; exit 1 on one."
  (let* ((modules (expand-file-name "../../modules" my/weekly-declare-directory))
         (exceptions (my/weekly-declare--exceptions))
         ;; check-declare also shows its findings in a *Check Declarations
         ;; Warnings* buffer; in batch that is printed to standard error,
         ;; which hooks/check-weekly does not show.
         (errors (let ((inhibit-message t)) (check-declare-directory modules)))
         (problems nil) (excused nil))
    ;; ERRORS: ((DECLARED-FILE (SOURCE-FILE FUNCTION REASON) ...) ...)
    (dolist (entry errors)
      (dolist (item (cdr entry))
        (pcase-let ((`(,source ,function ,reason) item))
          (if (member function exceptions)
              (push function excused)
            (push (format "%s: %s declared in %s: %s"
                          (file-name-nondirectory source) function
                          (file-name-nondirectory (car entry)) reason)
                  problems)))))
    (dolist (p (sort problems #'string<))
      (princ (format "PROBLEM   %s\n" p)))
    (dolist (f (seq-remove (lambda (f) (member f excused)) exceptions))
      (princ (format "gone      %s  (no longer reported: remove its line)\n" f)))
    (princ (format "declarations: %d problem(s), %d excused\n"
                   (length problems) (length (seq-uniq excused))))
    (kill-emacs (if problems 1 0))))

(provide 'weekly-declarations)
;;; declarations.el ends here
