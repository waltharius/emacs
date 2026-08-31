;;; parens.el --- Read every module, reporting the first syntax error -*- lexical-binding: t; -*-
;;; Commentary:
;; Reads each file in modules/ form by form with `read'.  That is a
;; stricter test than it looks: an unbalanced paren, an unterminated
;; string or a stray reader macro all fail here, and they fail with a
;; position rather than with a symptom three hundred lines away.
;;
;; NOT byte-compilation.  Compiling modules individually reports every
;; cross-module reference as an undefined function, because siblings are
;; not on `load-path' -- dozens of warnings that are all expected, which
;; is the fastest way to teach someone to ignore the output.  Run the
;; byte-compiler by hand when hunting a real problem.
;;
;;   emacs -Q --batch -l hooks/parens.el
;;
;; Exits non-zero if any file will not read.
;;
;; THE ONE SUBTLETY
;; ----------------
;; A truncated form and a clean end of file signal the SAME error,
;; `end-of-file' -- "End of file during parsing" either way.  The error
;; therefore cannot say which happened; only the position can.  Before
;; each `read' the point is moved past whitespace AND comments, and if
;; that lands at the end of the buffer the file is finished.  Reading is
;; attempted only when something is left, so an `end-of-file' out of
;; `read' always means a form that never closed.
;;
;; Skipping comments requires Lisp syntax: in a plain temporary buffer
;; `;' is an ordinary character and `forward-comment' would not move
;; past the `;;; ... ends here' line every module ends with.  Hence the
;; syntax table below.  Without it every file reports a failure on its
;; own last line -- a checker that cries wolf on a clean tree, which is
;; worse than no checker, because the way out is to stop reading it.

;;; Code:

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (root (directory-file-name (file-name-directory (directory-file-name here))))
       (directory (expand-file-name "modules" root))
       (failed nil)
       (count 0))
  (dolist (file (directory-files directory t "\\.el\\'"))
    (setq count (1+ count))
    (with-temp-buffer
      (insert-file-contents file)
      ;; Lisp syntax, so that `forward-comment' recognises `;'.
      (set-syntax-table emacs-lisp-mode-syntax-table)
      (goto-char (point-min))
      (condition-case err
          (while (progn (forward-comment (buffer-size))
                        (not (eobp)))
            (read (current-buffer)))
        (end-of-file
         (setq failed t)
         (message "  FAILED   %s:%d: unclosed form (reached end of file)"
                  (file-name-nondirectory file)
                  (line-number-at-pos)))
        (error
         (setq failed t)
         (message "  FAILED   %s:%d: %s"
                  (file-name-nondirectory file)
                  (line-number-at-pos)
                  (error-message-string err))))))
  (if failed
      (kill-emacs 1)
    (message "  ok       parens (%d files)" count)))

;;; parens.el ends here
