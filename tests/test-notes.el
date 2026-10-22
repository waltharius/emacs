;;; test-notes.el --- ERT tests for what 05-notes does to notes on disk -*- lexical-binding: t; -*-

;; Tests: 05-notes

;;; Commentary:

;; The functions of 05-notes.el that create, move or delete notes, on
;; real files in a temporary notes folder with three silos (journal,
;; pks, docu), as one git repository -- the first module of TESTING.org,
;; *Every module tested*, part 3.  What SAFETY.org promises (2.1, 2.2)
;; is tested clause by clause; the deletion question itself is in
;; test-safety.el.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-notes.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.  Needs git on PATH.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "27-denote-identifiers" "05-notes")

;; ============================================================
;; FIXTURE
;; ============================================================

(defun my/notes-test--git (dir &rest args)
  "Run git ARGS in DIR; return its output, or signal when it fails."
  (let ((default-directory (file-name-as-directory dir)))
    (with-temp-buffer
      (unless (= 0 (apply #'call-process "git" nil t nil
                          "-c" "user.name=Test" "-c" "user.email=test@example.invalid"
                          "-c" "init.defaultBranch=main" args))
        (error "git %S failed: %s" args (buffer-string)))
      (string-trim (buffer-string)))))

(defun my/notes-test--write (file text)
  "Write TEXT to FILE, creating its folder."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text)))

(defun my/notes-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro my/notes-test--with-notes (&rest body)
  "Run BODY in a fresh notes folder: silos journal, pks, docu; a git repository.
Binds `root', `journal', `pks', `docu' and `trash' (the system trash
stands in a temporary folder)."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-notes-" t)))
          (journal (file-name-as-directory (expand-file-name "journal" root)))
          (pks (file-name-as-directory (expand-file-name "pks" root)))
          (docu (file-name-as-directory (expand-file-name "docu" root)))
          (trash (file-name-as-directory (make-temp-file "mypks-trash-" t)))
          (trash-directory trash)
          (my-notes-dir root)
          (my-notes-journal journal)
          (my-notes-pks pks)
          (my-notes-docu docu)
          (my/denote-silo-alist `(("journal" . ,journal) ("pks" . ,pks) ("docu" . ,docu)))
          (my/confirm-deletion 'ask)
          (inhibit-message t))
     (dolist (d (list journal pks docu)) (make-directory d t))
     (my/notes-test--git root "init" "--quiet")
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t)
       (delete-directory trash t))))

(defun my/notes-test--note (dir id slug title &optional commit)
  "Write a Denote note ID--SLUG__test.org titled TITLE in DIR; return it.
With COMMIT, add it to git and commit."
  (let ((file (expand-file-name (format "%s--%s__test.org" id slug) dir)))
    (my/notes-test--write file (format "#+title:      %s\n#+identifier: %s\n\nBody of %s.\n"
                                       title id title))
    (when commit
      (my/notes-test--git dir "add" (file-name-nondirectory file))
      (my/notes-test--git dir "commit" "--quiet" "-m" (concat "add " title)))
    file))

(defmacro my/notes-test--answering (answers &rest body)
  "Run BODY with `completing-read' answering ANSWERS in order.
`yes-or-no-p' and `y-or-n-p' answer from the plist ANSWERS's :yes
\(default t); `read-string' from :title."
  (declare (indent 1))
  `(let ((queue (plist-get ,answers :choices))
         (yes (if (plist-member ,answers :yes) (plist-get ,answers :yes) t))
         (asked nil))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (prompt &rest _)
                  (push prompt asked)
                  (or (pop queue) (error "Unexpected question: %s" prompt))))
               ((symbol-function 'yes-or-no-p) (lambda (prompt) (push prompt asked) yes))
               ((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt asked) yes))
               ((symbol-function 'read-string)
                (lambda (prompt &rest _) (push prompt asked) (plist-get ,answers :title))))
       ,@body)))

(defun my/notes-test--move (file answers)
  "Visit FILE and run `my/denote-move-to-silo' answering ANSWERS.
Return the file the buffer visits afterwards."
  (with-current-buffer (find-file-noselect file)
    (my/notes-test--answering answers
      (my/denote-move-to-silo))
    (buffer-file-name)))

;; ============================================================
;; MOVING A NOTE TO ANOTHER SILO (SAFETY.org 2.2)
;; ============================================================

(ert-deftest my/notes-test-move-tracked-note-keeps-history ()
  "A tracked note moves with git mv: it is in the other silo, the buffer
visits it there, and git follows its history across the move."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant" t))
           (moved (my/notes-test--move note '(:choices ("docu")))))
      (should (equal moved (expand-file-name (file-name-nondirectory note) docu)))
      (should (file-exists-p moved))
      (should-not (file-exists-p note))
      (my/notes-test--git root "commit" "--quiet" "-m" "move")
      (should (string-match-p "add Kant"
                              (my/notes-test--git root "log" "--follow" "--format=%s" "--"
                                                  (file-relative-name moved root)))))))

(ert-deftest my/notes-test-move-untracked-note ()
  "An untracked note is moved by renaming, content unchanged."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (text (my/notes-test--read note))
           (moved (my/notes-test--move note '(:choices ("journal")))))
      (should (equal (my/notes-test--read moved) text))
      (should-not (file-exists-p note)))))

(ert-deftest my/notes-test-move-refuses-existing-file ()
  "2.2: a file of the same name in the target silo is never overwritten:
the move refuses, and both files stay as they were."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (there (my/notes-test--note docu "20261022T100000" "kant" "Kant, other text")))
      ;; Different titles: no title question; the name is the same.
      (with-temp-file there (insert "#+title:      Something else\n\nKeep me.\n"))
      (should-error (my/notes-test--move note '(:choices ("docu"))) :type 'user-error)
      (should (file-exists-p note))
      (should (equal (my/notes-test--read there) "#+title:      Something else\n\nKeep me.\n")))))

(ert-deftest my/notes-test-move-same-title-cancel ()
  "A note of the same title in the target silo: cancel moves nothing."
  (my/notes-test--with-notes
    (let ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant")))
      (my/notes-test--note docu "20261022T110000" "kant" "Kant")
      (my/notes-test--move note '(:choices ("docu" "cancel")))
      (should (file-exists-p note))
      (should-not (file-exists-p (expand-file-name (file-name-nondirectory note) docu))))))

(ert-deftest my/notes-test-move-same-title-keep-both ()
  "Same title, other identifier: keep both moves the note beside it."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (other (my/notes-test--note docu "20261022T110000" "kant" "Kant"))
           (moved (my/notes-test--move note '(:choices ("docu" "keep both")))))
      (should (file-exists-p moved))
      (should (file-exists-p other))
      (should-not (equal moved other)))))

(ert-deftest my/notes-test-move-overwrite-declined ()
  "Overwrite chosen, then the deletion declined: nothing moves, nothing goes."
  (my/notes-test--with-notes
    (let ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
          (other (my/notes-test--note docu "20261022T110000" "kant" "Kant")))
      (my/notes-test--move note '(:choices ("docu" "overwrite") :yes nil))
      (should (file-exists-p note))
      (should (file-exists-p other)))))

(ert-deftest my/notes-test-move-overwrite-to-trash ()
  "Overwrite confirmed: the other note goes to the trash (it is untracked),
not deleted for good; the note takes its place in the silo."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (other (my/notes-test--note docu "20261022T110000" "kant" "Kant"))
           (moved (my/notes-test--move note '(:choices ("docu" "overwrite")))))
      (should-not (file-exists-p other))
      (should (file-exists-p (expand-file-name (file-name-nondirectory other) trash)))
      (should (file-exists-p moved)))))

(ert-deftest my/notes-test-move-same-identifier-no-title-cancels ()
  "Same title and identifier: keep both needs a new title; none given
cancels, and the note stays where it was, unchanged."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (text (my/notes-test--read note)))
      (my/notes-test--note docu "20261022T100000" "kant-copy" "Kant")
      (my/notes-test--move note '(:choices ("docu" "keep both") :title ""))
      (should (equal (my/notes-test--read note) text)))))

(ert-deftest my/notes-test-move-unsaved-declined ()
  "Unsaved changes and no to saving: nothing is moved or written."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (text (my/notes-test--read note)))
      (with-current-buffer (find-file-noselect note)
        (goto-char (point-max))
        (insert "unsaved")
        (my/notes-test--answering '(:choices ("docu") :yes nil)
          (should-error (my/denote-move-to-silo) :type 'user-error)))
      (should (equal (my/notes-test--read note) text)))))

(ert-deftest my/notes-test-relocate-outside-repository ()
  "Where git mv refuses (target outside the repository), the file is
renamed instead: it arrives, and the source is gone."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant" t))
           (outside (file-name-as-directory (make-temp-file "mypks-outside-" t)))
           (target (expand-file-name (file-name-nondirectory note) outside)))
      (unwind-protect
          (progn
            (my/denote--relocate note target)
            (should (file-exists-p target))
            (should-not (file-exists-p note)))
        (delete-directory outside t)))))

;; ============================================================
;; DELETING A NOTE WITH ITS ATTACHMENTS (SAFETY.org 2.1)
;; ============================================================

(defmacro my/notes-test--with-attachments (own shared &rest body)
  "Run BODY with `my/org-image-note-attachments' reporting OWN and SHARED.
The stand-in for 31-org-images.el, which decides what a note owns."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'my/org-image-note-attachments)
              (lambda (_file) (list :own ,own :shared ,shared :checked t))))
     ,@body))

(ert-deftest my/notes-test-delete-with-attachments-to-trash ()
  "2.1: yes to both questions: the note and its own attachments go to
the trash; an attachment other notes use stays."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (own (expand-file-name "attachments/kant.png" root))
           (shared (expand-file-name "attachments/diagram.png" root)))
      (my/notes-test--write own "png")
      (my/notes-test--write shared "png")
      (my/notes-test--with-attachments (list own) (list shared)
        (with-current-buffer (find-file-noselect note)
          (my/notes-test--answering '(:yes t)
            (my/denote-delete-note))))
      (should-not (file-exists-p note))
      (should (file-exists-p (expand-file-name (file-name-nondirectory note) trash)))
      (should-not (file-exists-p own))
      (should (file-exists-p (expand-file-name "kant.png" trash)))
      (should (file-exists-p shared)))))

(ert-deftest my/notes-test-delete-attachments-declined ()
  "Yes to the note, no to the attachments: the attachments stay."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (own (expand-file-name "attachments/kant.png" root))
           (answers (list t nil)))
      (my/notes-test--write own "png")
      (my/notes-test--with-attachments (list own) nil
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) (pop answers))))
          (with-current-buffer (find-file-noselect note)
            (my/denote-delete-note))))
      (should-not (file-exists-p note))
      (should (file-exists-p own)))))

(ert-deftest my/notes-test-delete-attachments-never ()
  "With `my/denote-delete-attachments' never: no question about them,
and they stay."
  (my/notes-test--with-notes
    (let* ((note (my/notes-test--note pks "20261022T100000" "kant" "Kant"))
           (own (expand-file-name "attachments/kant.png" root))
           (my/denote-delete-attachments 'never)
           (questions 0))
      (my/notes-test--write own "png")
      (my/notes-test--with-attachments (list own) nil
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) (cl-incf questions) t)))
          (with-current-buffer (find-file-noselect note)
            (my/denote-delete-note))))
      (should (= questions 1))
      (should (file-exists-p own)))))

;; ============================================================
;; JOURNAL NOTES
;; ============================================================

(ert-deftest my/notes-test-journal-today-created-once ()
  "The first call creates today's journal note; the second adds an entry
to it instead of creating another."
  (my/notes-test--with-notes
    (my/denote-journal)
    (let ((files (directory-files journal t "__journal\\.org\\'")))
      (should (= (length files) 1))
      (should (string-match-p "#\\+filetags:   :journal:" (my/notes-test--read (car files))))
      (my/denote-journal)
      (with-current-buffer (get-file-buffer (car files)) (save-buffer))
      (should (equal (directory-files journal t "__journal\\.org\\'") files))
      (should (= 2 (how-many "^\\* [0-9][0-9]:[0-9][0-9]$" 0 nil)))
      (with-temp-buffer
        (insert-file-contents (car files))
        (should (= 2 (how-many "^\\* [0-9][0-9]:[0-9][0-9]$" (point-min) (point-max))))))))

(ert-deftest my/notes-test-journal-found-after-retitle ()
  "Today's note renamed to a free title is still found by its date: no
second note for the day."
  (my/notes-test--with-notes
    (let* ((today (format-time-string "%Y-%m-%d"))
           (id (format-time-string "%Y%m%dT080000"))
           (file (expand-file-name (format "%s--%s-a-good-day__journal.org" id today) journal)))
      (my/notes-test--write file (format "#+title:      %s a good day\n" today))
      (my/denote-journal)
      (should (equal (directory-files journal t "__journal\\.org\\'") (list file))))))

(ert-deftest my/notes-test-backdated-journal-never-overwrites ()
  "A backdated journal note refuses to replace a file of the same name."
  (my/notes-test--with-notes
    (let* ((time (encode-time (list 0 0 12 1 3 2020 nil -1 nil)))
           (first (my/denote-journal-create-backdated "2020-03-01" time))
           (text (my/notes-test--read first)))
      (should (string-match-p ":EVENT_DATE: \\[2020-03-01\\]" text))
      (should-error (my/denote-journal-create-backdated "2020-03-01" time) :type 'user-error)
      (should (equal (my/notes-test--read first) text)))))

(provide 'test-notes)
;;; test-notes.el ends here
