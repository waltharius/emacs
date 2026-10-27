;;; test-editing.el --- ERT tests for 102-editing -*- lexical-binding: t; -*-

;; Tests: 102-editing

;;; Commentary:

;; 102-editing is mostly settings.  What the writing relies on is tested:
;; an apostrophe is not paired, double quotes and brackets are, in Org
;; too; M-Q joins the lines of each paragraph and
;; keeps paragraphs apart; the owner's keys (C-s save, C-f find, C-z
;; undo, C-S-z redo, M-Q); undo history kept in var/ of this machine.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-editing.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "102-editing")

(defun my/ed-test-type (text)
  "Type TEXT with self-inserting commands."
  (dolist (char (string-to-list text))
    (let ((last-command-event char))
      (call-interactively #'self-insert-command))))

(ert-deftest my/ed-test-apostrophe-not-paired ()
  "An apostrophe typed in prose is one character: \"don't\" in a text
buffer (a commit message, a Markdown note) left a stray ' after it."
  (dolist (mode '(text-mode org-mode))
    (with-temp-buffer
      (funcall mode)
      (my/ed-test-type "don't")
      (should (equal (buffer-string) "don't")))))

(ert-deftest my/ed-test-quotes-and-brackets-paired ()
  "Double quotes and brackets are paired, in Org too, and typing the
closing one steps over it -- the quoted phrase rule of 302b-bold-marker
works with what is typed."
  (dolist (mode '(text-mode org-mode))
    (with-temp-buffer
      (funcall mode)
      (my/ed-test-type "\"")
      (should (equal (buffer-string) "\"\""))
      (erase-buffer)
      (my/ed-test-type "(")
      (should (equal (buffer-string) "()"))
      (erase-buffer)
      (my/ed-test-type "\"a\" (b)")
      (should (equal (buffer-string) "\"a\" (b)")))))

(ert-deftest my/ed-test-unfill-joins-lines-keeps-paragraphs ()
  "M-Q joins the lines of each paragraph in the region and keeps the
paragraphs apart."
  (with-temp-buffer
    (text-mode)
    ;; Lines long enough that an ordinary fill would break them again.
    (let ((a (make-string 50 ?a)) (b (make-string 50 ?b)))
      (insert a "\n" b "\n\ntrzecia\nczwarta\n")
      (my/unfill-region (point-min) (point-max))
      (should (equal (buffer-string) (concat a " " b "\n\ntrzecia czwarta\n"))))))

(ert-deftest my/ed-test-keys ()
  "The owner's keys: C-s saves, C-f finds, C-z undoes, C-S-z redoes,
M-Q unfills."
  (should (eq (key-binding (kbd "C-s")) #'save-buffer))
  (should (eq (key-binding (kbd "C-f")) #'isearch-forward))
  (should (eq (key-binding (kbd "C-z")) #'undo))
  (should (eq (key-binding (kbd "C-S-z")) #'undo-redo))
  (should (eq (key-binding (kbd "M-Q")) #'my/unfill-region))
  (should (eq (lookup-key isearch-mode-map (kbd "C-f")) #'isearch-repeat-forward)))

(ert-deftest my/ed-test-yes-or-no-p-is-a-whole-word ()
  "`yes-or-no-p' is Emacs's own function and `use-short-answers' is off:
the questions before deleting, uploading and quitting with work not on
the server take a typed \"yes\", not one key.  Until 2026-10-27 an alias
to `y-or-n-p' in 102-editing made every such question one key."
  (should-not (eq (indirect-function 'yes-or-no-p) (indirect-function 'y-or-n-p)))
  (should (subrp (indirect-function 'yes-or-no-p)))
  (should-not use-short-answers))

(ert-deftest my/ed-test-undo-history-in-var ()
  "Undo history is kept in var/ of this machine, not in ~/.emacs.d."
  (skip-unless (locate-library "undo-fu-session"))
  (should (string-prefix-p (expand-file-name (my/var-file ""))
                           (expand-file-name undo-fu-session-directory))))

(provide 'test-editing)
;;; test-editing.el ends here
