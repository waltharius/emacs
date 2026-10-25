;;; compile.el --- Weekly: byte-compile every module, fail on a new warning -*- lexical-binding: t; -*-

;;; Commentary:

;; The byte compiler reads the code more strictly than loading it: a
;; misspelt function name, a call with the wrong number of arguments, a
;; variable used but never defined, a function Emacs has made obsolete.
;; Loading finds these only when the line runs, perhaps months later.
;;
;; Every module of init.el's list is compiled, after the whole
;; configuration has loaded in the sandbox of tests/helper.el -- so that
;; a function of another module or of a package counts as known, as it
;; is at a real start.  The .elc files go to a temporary folder; nothing
;; is compiled in place (the configuration loads the .el files).
;;
;; The warnings that existed when this check began are listed in
;; compile-warnings.txt, one per line, "MODULE: message"; only a warning
;; not on the list fails the run.  A listed warning no longer seen is
;; reported, not failed: the versions of Emacs differ in what they warn
;; about.  After fixing one, remove its line.  To write the list anew
;; from the warnings of this Emacs:
;;
;;   MYPKS_COMPILE_BASELINE=write bash hooks/check-weekly compile
;;
;; Run by hooks/check-weekly; needs every package installed.

;;; Code:

(require 'bytecomp)
(require 'seq)

(load (expand-file-name "lib" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defconst my/weekly-baseline-file
  (expand-file-name "compile-warnings.txt" my/weekly-directory)
  "The warnings that do not fail the run.")

(defun my/weekly--plain-quotes (text)
  "TEXT with curved single quotes turned into a grave accent and an apostrophe.
Emacs quotes names in its messages after `text-quoting-style': curved
quotes where the display can show them, the grave form in a plain
terminal or locale.  The same warning then reads differently on two
machines, so both sides are compared in the grave form.  (2026-10-22:
every listed warning came out as NEW on the owner's machine.)"
  (replace-regexp-in-string "\u2019" "'" (replace-regexp-in-string "\u2018" "`" text)))

(defun my/weekly--read-baseline ()
  "The lines of the baseline file, comments and blank lines left out."
  (when (file-exists-p my/weekly-baseline-file)
    (with-temp-buffer
      (insert-file-contents my/weekly-baseline-file)
      (mapcar #'my/weekly--plain-quotes
              (seq-remove (lambda (l) (or (string-empty-p l) (string-prefix-p "#" l)))
                          (split-string (buffer-string) "\n"))))))

(defun my/weekly--compile (name output)
  "Compile module NAME into the folder OUTPUT.
Return (OK . WARNINGS), WARNINGS a list of \"NAME: message\" lines."
  (let* ((warnings nil)
         (byte-compile-log-warning-function
          (lambda (string _position _fill level)
            (push (my/weekly--plain-quotes
                   (format "%s: %s%s" name
                           (if (eq level :error) "ERROR " "")
                           (string-trim (replace-regexp-in-string "[ \t\n]+" " " string))))
                  warnings)))
         (byte-compile-dest-file-function
          (lambda (file) (expand-file-name (concat (file-name-base file) ".elc") output)))
         (ok (ignore-errors
               (byte-compile-file (my/test-module-file name)))))
    (cons ok (seq-uniq (nreverse warnings)))))

(defun my/weekly--report (line)
  "Print LINE, and add it to the file named by MYPKS_COMPILE_REPORT.
hooks/check-weekly reads the file: in the mixed output of Emacs a line
can lose its start to text a package wrote to standard error without a
newline, and the warning then went unshown (2026-10-24: \"1 new\" with
no NEW line on the owner's machine)."
  (princ (concat line "\n"))
  (when-let* ((file (getenv "MYPKS_COMPILE_REPORT")))
    (write-region (concat line "\n") nil file t 'silent)))

(defun my/weekly-compile-all ()
  "Compile every module; print the outcome; exit 1 on a new warning or error."
  (my/weekly-start)
  (my/weekly-load (cdr my/modules-order))
  (let* ((output (make-temp-file "mypks-elc-" t))
         (baseline (my/weekly--read-baseline))
         (write (equal (getenv "MYPKS_COMPILE_BASELINE") "write"))
         (all nil) (new nil) (failed nil))
    (dolist (name my/modules-order)
      (pcase-let ((`(,ok . ,warnings) (my/weekly--compile name output)))
        (unless ok (push name failed))
        (setq all (append all warnings))
        (dolist (w warnings)
          (unless (member w baseline) (push w new)))))
    (delete-directory output t)
    (setq new (nreverse new))
    (if write
        (with-temp-file my/weekly-baseline-file
          (insert "# Byte-compiler warnings that do not fail the weekly check\n"
                  "# (tests/weekly/compile.el).  One per line, MODULE: message.\n"
                  "# Written " (format-time-string "%Y-%m-%d") " with Emacs " emacs-version
                  "; remove a line when its warning is fixed.\n")
          (dolist (w (sort (seq-uniq (append baseline all)) #'string<))
            (insert w "\n")))
      (dolist (w (seq-remove (lambda (b) (member b all)) baseline))
        (my/weekly--report (format "gone      %s  (no longer seen: remove the line)" w))))
    (dolist (w new)
      (my/weekly--report (format "NEW       %s" w)))
    (dolist (name failed)
      (my/weekly--report (format "FAILED    %s did not compile" name)))
    (my/weekly--report (format "compiled %d modules: %d warning(s), %d new, %d failed%s"
                               (length my/modules-order) (length all) (length new) (length failed)
                               (if write "; list written" "")))
    (kill-emacs (if (or failed (and new (not write))) 1 0))))

(provide 'weekly-compile)
;;; compile.el ends here
