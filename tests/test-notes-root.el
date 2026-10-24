;;; test-notes-root.el --- ERT tests for moving the notes root and deleting the old one -*- lexical-binding: t; -*-

;; Tests: 00-core

;;; Commentary:

;; 00-core.el decides at every start which folder the notes are in: when
;; `my-notes-dir' was changed, `my/notes-check-root-move' copies, switches,
;; asks or refuses (SAFETY.org 2.9).  `my/notes-delete-old-root' moves the
;; previous root to the trash, off by default, after two questions
;; (SAFETY.org 2.3).  Neither had a test until 2026-10-24 (outside
;; audits): the sandbox of the other tests always starts with no state,
;; so only the branch "nothing changed" ever ran.
;;
;; On real folders in a temporary directory; the state file is a
;; temporary one, the report (`my/notes-report', a dialog at a real
;; start) and the questions are stood in for and recorded.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-notes-root.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules)

;; ============================================================
;; FIXTURE
;; ============================================================

(defvar my/root-test--reports nil
  "Reports made during a test, newest first: (KIND . TITLE).")

(defmacro my/root-test--with-roots (&rest body)
  "Run BODY with folders `old' and `new', a trash and a state file.
`old' holds a note in the default notes silo; `new' does not exist.
`my-notes-dir' is `new', as after the setting was changed; the state
file says `old' was used last.  Reports are recorded, not shown."
  (declare (indent 0))
  `(let* ((base (file-name-as-directory (make-temp-file "mypks-root-" t)))
          (old (file-name-as-directory (expand-file-name "notes" base)))
          (new (file-name-as-directory (expand-file-name "notes2" base)))
          (trash (file-name-as-directory (expand-file-name "trash" base)))
          (trash-directory trash)
          (my/notes-root-state-file (expand-file-name "notes-root.eld" base))
          (my-notes-dir new)
          (my/root-test--reports nil)
          (inhibit-message t))
     (my/root-test--note old "20261024T100000" "Body of the old note.\n")
     (my/notes--write-root-state old nil)
     (unwind-protect
         (cl-letf (((symbol-function 'my/notes-report)
                    (lambda (kind title &rest _) (push (cons kind title) my/root-test--reports) nil)))
           ,@body)
       (delete-directory base t))))

(defun my/root-test--silo ()
  "Return the folder of the default notes silo, relative to the root."
  (my/silo-get (car (my/silo-keys nil t)) :directory))

(defun my/root-test--note (root id text)
  "Write a Denote note ID in ROOT's default silo with TEXT; return it."
  (let ((file (expand-file-name (format "%s--note__test.org" id)
                                (expand-file-name (my/root-test--silo) root))))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))
    file))

(defun my/root-test--files (dir)
  "Return DIR's files as (RELATIVE-NAME . CONTENT), sorted, or nil."
  (when (file-directory-p dir)
    (sort (mapcar (lambda (f)
                    (cons (file-relative-name f dir)
                          (with-temp-buffer (insert-file-contents-literally f) (buffer-string))))
                  (directory-files-recursively dir "" nil))
          (lambda (a b) (string< (car a) (car b))))))

(defun my/root-test--state ()
  "Return the state file's (ROOT PREVIOUS)."
  (let ((s (my/notes--read-root-state)))
    (list (plist-get s :root) (plist-get s :previous))))

;; ============================================================
;; MOVING THE ROOT AT START (SAFETY.org 2.9)
;; ============================================================

(ert-deftest my/root-test-nothing-changed ()
  "The root used last is the setting: nothing is asked, copied or reported."
  (my/root-test--with-roots
    (let ((my-notes-dir old))
      (my/notes-check-root-move)
      (should (equal my-notes-dir old))
      (should-not (file-exists-p new))
      (should-not my/root-test--reports))))

(ert-deftest my/root-test-old-root-gone ()
  "The old root no longer exists: the new one is used, the state says
so, and a report says nothing was copied."
  (my/root-test--with-roots
    (delete-directory old t)
    (my/notes-check-root-move)
    (should (equal my-notes-dir new))
    (should (equal (my/root-test--state) (list new old)))
    (should (eq (caar my/root-test--reports) 'done))))

(ert-deftest my/root-test-new-already-holds-notes ()
  "The new root holds the notes and the old one does not any more (a
second machine, files moved by hand): switched, nothing copied, the old
folder left as it is."
  (my/root-test--with-roots
    (let ((old-note (car (directory-files-recursively old "\\.org\\'"))))
      (my/root-test--note new "20261024T110000" "Moved by hand.\n")
      (delete-file old-note)
      (let ((before (my/root-test--files old)))
        (my/notes-check-root-move)
        (should (equal my-notes-dir new))
        (should (equal (my/root-test--files old) before))
        (should (= 1 (length (my/root-test--files new))))))))

(ert-deftest my/root-test-both-hold-notes-kept-unless-asked ()
  "Both roots hold notes: without anyone to ask (batch) the old root is
kept for the session and nothing is written; asked and answered \"ask
me next time\", the same."
  (my/root-test--with-roots
    (my/root-test--note new "20261024T110000" "Another collection.\n")
    (let ((before (list (my/root-test--files old) (my/root-test--files new))))
      (my/notes-check-root-move)
      (should (equal my-notes-dir old))
      (setq my-notes-dir new)
      (let ((noninteractive nil))
        (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) '(?l "ask me next time"))))
          (my/notes-check-root-move)))
      (should (equal my-notes-dir old))
      (should (equal (my/root-test--state) (list old nil)))
      (should (equal (list (my/root-test--files old) (my/root-test--files new)) before)))))

(ert-deftest my/root-test-nested-roots-refused ()
  "A new root inside the old one: refused, the old root kept, the new
folder not created, the old untouched."
  (my/root-test--with-roots
    (let ((my-notes-dir (file-name-as-directory (expand-file-name "inner" old)))
          (before (my/root-test--files old)))
      (my/notes-check-root-move)
      (should (equal my-notes-dir old))
      (should (eq (caar my/root-test--reports) 'refused))
      (should (equal (my/root-test--files old) before))
      (should (equal (my/root-test--state) (list old nil))))))

(ert-deftest my/root-test-foreign-folder-refused ()
  "A new root that holds other files and no silos: refused, its files
untouched, the old root kept."
  (my/root-test--with-roots
    (make-directory new t)
    (with-temp-file (expand-file-name "thesis.docx" new) (insert "not a note"))
    (my/notes-check-root-move)
    (should (equal my-notes-dir old))
    (should (eq (caar my/root-test--reports) 'refused))
    (should (equal (my/root-test--files new) '(("thesis.docx" . "not a note"))))))

(ert-deftest my/root-test-batch-postpones ()
  "With nobody to ask (batch, a daemon), the old root is kept and the
question waits for the next start: nothing copied, the state unchanged."
  (my/root-test--with-roots
    (my/notes-check-root-move)
    (should (equal my-notes-dir old))
    (should-not (file-exists-p new))
    (should (equal (my/root-test--state) (list old nil)))))

(ert-deftest my/root-test-copy-keeps-the-old-root ()
  "Copy: the new root holds exactly the old one's files, the old root is
untouched, and the state records the new root and the old one."
  (my/root-test--with-roots
    (let ((before (my/root-test--files old))
          (noninteractive nil))
      (cl-letf (((symbol-function 'my/notes--ask-move) (lambda (&rest _) ?c)))
        (my/notes-check-root-move))
      (should (equal my-notes-dir new))
      (should (equal (my/root-test--files old) before))
      (should (equal (my/root-test--files new) before))
      (should (equal (my/root-test--state) (list new old))))))

(ert-deftest my/root-test-incomplete-copy-keeps-old-root ()
  "A copy that ends with fewer files than the old root has -- a full
disk, an interrupted copy -- is not taken for the notes: the old root
stays in use, the state unchanged, and the report says it failed."
  (my/root-test--with-roots
    (my/root-test--note old "20261024T130000" "A second note.\n")
    (let ((noninteractive nil))
      (cl-letf (((symbol-function 'my/notes--ask-move) (lambda (&rest _) ?c))
                ((symbol-function 'my/notes--copy-tree)
                 ;; Copies one note of two, and reports no error.
                 (lambda (from to)
                   (let ((one (car (directory-files-recursively from "\\.org\\'"))))
                     (make-directory (file-name-directory
                                      (expand-file-name (file-relative-name one from) to)) t)
                     (copy-file one (expand-file-name (file-relative-name one from) to))
                     nil))))
        (my/notes-check-root-move)))
    (should (equal my-notes-dir old))
    (should (equal (my/root-test--state) (list old nil)))
    (should (eq (caar my/root-test--reports) 'failed))))

(ert-deftest my/root-test-skip-copies-nothing ()
  "\"Skip, I will move my files myself\": switched, nothing copied, the
new folder left empty (no silo folders created), the old untouched."
  (my/root-test--with-roots
    (let ((before (my/root-test--files old))
          (noninteractive nil))
      (cl-letf (((symbol-function 'my/notes--ask-move) (lambda (&rest _) ?s)))
        (my/notes-check-root-move))
      (should (equal my-notes-dir new))
      (should-not (my/root-test--files new))
      (should (equal (my/root-test--files old) before))
      (should (equal (my/root-test--state) (list new old))))))

;; ============================================================
;; DELETING THE OLD ROOT (SAFETY.org 2.3)
;; ============================================================

(defmacro my/root-test--after-move (answers &rest body)
  "Run BODY after a move from `old' to `new', with ANSWERS to yes-or-no-p.
ANSWERS is a list, one per question; a question too many or an answer
left unused fails the test.  `asked' counts the questions."
  (declare (indent 1))
  `(my/root-test--with-roots
     (make-directory new t)
     (my/notes--write-root-state new old)
     (my/root-test--note new "20261024T120000" "Current note.\n")
     (let ((answers ,answers) (asked 0)
           (current (my/root-test--files new)))
       (cl-letf (((symbol-function 'yes-or-no-p)
                  (lambda (prompt)
                    (setq asked (1+ asked))
                    (if answers (pop answers) (error "Unexpected question: %s" prompt)))))
         ,@body)
       (should-not answers)
       (should (equal (my/root-test--files new) current)))))

(ert-deftest my/root-test-delete-old-root-off-by-default ()
  "Off by default: nothing is asked, nothing goes to the trash."
  (my/root-test--after-move nil
    (let ((my/notes-allow-delete-old-root nil))
      (my/notes-delete-old-root))
    (should (= asked 0))
    (should (file-directory-p old))
    (should-not (file-exists-p trash))))

(ert-deftest my/root-test-delete-old-root-two-yes ()
  "Turned on, yes to both questions: the whole old root is in the trash,
its note with it; the current root untouched; the state forgets it."
  (my/root-test--after-move '(t t)
    (let ((my/notes-allow-delete-old-root t))
      (my/notes-delete-old-root))
    (should-not (file-exists-p old))
    (should (equal (mapcar #'cdr (my/root-test--files trash))
                   (list "Body of the old note.\n")))
    (should (equal (my/root-test--state) (list new nil)))))

(ert-deftest my/root-test-delete-old-root-second-no ()
  "Yes, then no: nothing goes to the trash."
  (my/root-test--after-move '(t nil)
    (let ((my/notes-allow-delete-old-root t))
      (my/notes-delete-old-root))
    (should (file-directory-p old))
    (should-not (file-exists-p trash))))

(ert-deftest my/root-test-delete-old-root-refuses-nested ()
  "A previous root that contains the current one, or lies inside it --
a state file edited or restored by hand: refused before any question,
nothing in the trash."
  (my/root-test--after-move nil
    (let ((my/notes-allow-delete-old-root t))
      (dolist (previous (list base (expand-file-name "pks/" new) new))
        (my/notes--write-root-state new previous)
        (my/notes-delete-old-root)))
    (should (= asked 0))
    (should-not (file-exists-p trash))
    (should (file-directory-p old))))

(provide 'test-notes-root)
;;; test-notes-root.el ends here
