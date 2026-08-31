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
;; Exits non-zero on the first file that will not read.

;;; Code:

(let ((directory (expand-file-name "modules" (file-name-directory
                                              (directory-file-name
                                               (file-name-directory load-file-name)))))
      (failed nil))
  (dolist (file (directory-files directory t "\\.el\\'"))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (condition-case err
          (while (progn (skip-chars-forward " \t\n")
                        (not (eobp)))
            (read (current-buffer)))
        (error
         (setq failed t)
         (message "  FAILED   %s:%d: %s"
                  (file-name-nondirectory file)
                  (line-number-at-pos)
                  (error-message-string err))))))
  (if failed
      (kill-emacs 1)
    (message "  ok       parens")))

;;; parens.el ends here
