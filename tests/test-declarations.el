;;; test-declarations.el --- ERT test: Denote's variables bound with let are declared special -*- lexical-binding: t; -*-

;; Tests:

;;; Commentary:

;; A module that binds a variable of Denote with `let' -- most often
;; `denote-directory', to make a note in one silo -- must declare it
;; special in its own file, `(defvar denote-directory)'.  Without the
;; declaration the binding is lexical whenever Denote is not loaded yet
;; when the `let' runs: Denote, loading inside it, stops with "Defining
;; as dynamic an already lexical var", and code compiled that way never
;; sees the binding.  At a normal start 204-denote loads Denote first,
;; which hides it (found in 424-readwise, 2026-10-23t).
;;
;; This reads the code, not its behaviour (TESTING.org, rule 7): each
;; module is read form by form with `read', and every `let' or `let*'
;; -- also inside a backquoted macro body -- binding a variable Denote
;; defines (a name beginning with "denote-" that is special once Denote
;; is loaded; a module's own local `denote-params' is not) is noted; the
;; file must hold a top-level `defvar' of it.  Needs the denote package.  So the header names no module: it shows a
;; declaration, not that any module works.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert -l tests/test-declarations.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(defconst my/decl-test--modules
  (expand-file-name "../modules/" (file-name-directory (or load-file-name buffer-file-name)))
  "The modules of this repository.")

(defun my/decl-test--forms (file)
  "Return the top-level forms of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun my/decl-test--let-bound (form)
  "Return the symbols named denote-... that `let' or `let*' bind in FORM."
  (let (found)
    (cl-labels ((walk (x)
                  (when (consp x)
                    (when (and (memq (car x) '(let let*)) (consp (cdr x)) (listp (cadr x)))
                      (dolist (binding (cadr x))
                        (let ((sym (if (consp binding) (car binding) binding)))
                          (when (and (symbolp sym)
                                     (string-prefix-p "denote-" (symbol-name sym))
                                     (special-variable-p sym))
                            (cl-pushnew sym found)))))
                    ;; Walk the car and every element, also of dotted lists.
                    (while (consp x)
                      (walk (car x))
                      (setq x (cdr x))))))
      (walk form))
    found))

(defun my/decl-test--declared (forms)
  "Return the symbols FORMS declare with a top-level `defvar'."
  (cl-loop for f in forms
           when (and (consp f) (eq (car f) 'defvar) (symbolp (cadr f)))
           collect (cadr f)))

(defun my/decl-test--report ()
  "Return ((MODULE . BOUND) ...) and the undeclared ((MODULE . SYMBOLS) ...)."
  (let (bound missing)
    (dolist (file (directory-files-recursively my/decl-test--modules "\\`[0-9].*\\.el\\'"))
      (let* ((forms (my/decl-test--forms file))
             (syms (cl-remove-duplicates (cl-mapcan #'my/decl-test--let-bound forms)))
             (undeclared (cl-set-difference syms (my/decl-test--declared forms)))
             (name (file-name-base file)))
        (when syms (push (cons name syms) bound))
        (when undeclared (push (cons name undeclared) missing))))
    (list (nreverse bound) (nreverse missing))))

(ert-deftest my/decl-test-denote-variables-declared ()
  "Every module that binds a variable of Denote with `let' declares it
special in its own file.  The modules known to bind `denote-directory'
are found -- the reader reaches the code, a backquoted macro body
included (422-zettelkasten) -- and none of them leaves it undeclared."
  (skip-unless (require 'denote nil t))
  (pcase-let ((`(,bound ,missing) (my/decl-test--report)))
    (dolist (module '("205-notes" "306-capture" "419-philosophy-notes"
                      "422-zettelkasten" "424-readwise" "333-denote-hubs"))
      (should (memq 'denote-directory (cdr (assoc module bound)))))
    (should-not missing)))

(provide 'test-declarations)
;;; test-declarations.el ends here
