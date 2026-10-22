;;; test-denote-identifiers.el --- ERT tests for finding and changing Denote identifiers -*- lexical-binding: t; -*-

;; Tests: 27-denote-identifiers

;;; Commentary:

;; 27-denote-identifiers.el renames notes and rewrites `denote:' links
;; in every note when it changes an identifier: the third module of
;; TESTING.org, *Every module tested*, part 3.  On real files in a
;; temporary notes folder with three silos and a staging inbox.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-denote-identifiers.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "27-denote-identifiers")

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/ids-test--with-notes (&rest body)
  "Run BODY in a fresh notes folder: silos journal, pks, docu, and inbox.
Binds `root', `journal', `pks', `docu', `inbox'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-ids-" t)))
          (journal (file-name-as-directory (expand-file-name "journal" root)))
          (pks (file-name-as-directory (expand-file-name "pks" root)))
          (docu (file-name-as-directory (expand-file-name "docu" root)))
          (inbox (file-name-as-directory (expand-file-name "inbox" root)))
          (my-notes-dir root)
          (my/denote-silo-directories (list journal pks docu))
          (inhibit-message t))
     (dolist (d (list journal pks docu inbox)) (make-directory d t))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/ids-test--note (dir id slug &optional body)
  "Write the note ID--SLUG.org in DIR with front matter and BODY; return it."
  (let ((file (expand-file-name (format "%s--%s.org" id slug) dir)))
    (make-directory dir t)
    (with-temp-file file
      (insert (format "#+title:      %s\n#+identifier: %s\n\n%s" slug id (or body ""))))
    file))

(defun my/ids-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

;; ============================================================
;; READING AND FINDING
;; ============================================================

(ert-deftest my/ids-test-identifier-from-file-name ()
  "The identifier is the timestamp at the start of the file name, or nil."
  (should (equal (my/denote-file-identifier "/n/pks/20261022T101500--kant__pks.org")
                 "20261022T101500"))
  (should-not (my/denote-file-identifier "/n/pks/kant.org"))
  (should-not (my/denote-file-identifier "/n/pks/x-20261022T101500--kant.org")))

(ert-deftest my/ids-test-duplicates-only-in-silos ()
  "A duplicate inside the silos is found; an inbox note sharing an
identifier with a filed one is not a duplicate."
  (my/ids-test--with-notes
    (let ((a (my/ids-test--note pks "20261022T000000" "a"))
          (b (my/ids-test--note journal "20261022T000000" "b")))
      (my/ids-test--note inbox "20261021T000000" "c")
      (my/ids-test--note docu "20261021T000000" "d")
      (should (equal (my/denote--duplicate-groups)
                     (list (cons "20261022T000000" (sort (list a b) #'string<))))))))

(ert-deftest my/ids-test-dot-folders-not-scanned ()
  "A copy in a dot folder (.snapshots, .git) is neither a note nor a
duplicate."
  (my/ids-test--with-notes
    (let ((a (my/ids-test--note pks "20261022T000000" "a")))
      (my/ids-test--note (expand-file-name ".snapshots/1/pks" root) "20261022T000000" "a")
      (should (equal (my/denote-all-files) (list a)))
      (should (null (my/denote--duplicate-groups))))))

(ert-deftest my/ids-test-next-free-stays-on-the-day ()
  "The next free identifier is the next free second of the same day,
also past midnight's wrap."
  (my/ids-test--with-notes
    (my/ids-test--note pks "20261022T000000" "a")
    (my/ids-test--note pks "20261022T000001" "b")
    (my/ids-test--note pks "20261022T235959" "c")
    (should (equal (my/denote-next-free-identifier "20261022T000000") "20261022T000002"))
    (should (equal (my/denote-next-free-identifier "20261022T235959") "20261022T000002"))))

;; ============================================================
;; CHANGING AN IDENTIFIER
;; ============================================================

(ert-deftest my/ids-test-change-renames-and-repoints-links ()
  "Changing an identifier rewrites the front matter, renames the file and
repoints every link to it, in the silos and in the inbox; other links
and text stay as they were."
  (my/ids-test--with-notes
    (let* ((note (my/ids-test--note pks "20261022T000000" "kant" "Body.\n"))
           (linker (my/ids-test--note docu "20261023T090000" "linker"
                                      "See [[denote:20261022T000000][Kant]] and [[denote:20261023T120000][other]].\n"))
           (draft (my/ids-test--note inbox "20261024T090000" "draft"
                                     "Draft on [[denote:20261022T000000][Kant]].\n"))
           (target (my/denote-change-identifier note "20261022T000005")))
      (should (equal target (expand-file-name "20261022T000005--kant.org" pks)))
      (should-not (file-exists-p note))
      (should (string-match-p "^#\\+identifier: 20261022T000005$" (my/ids-test--read target)))
      (should (equal (my/ids-test--read linker)
                     "#+title:      linker\n#+identifier: 20261023T090000\n\nSee [[denote:20261022T000005][Kant]] and [[denote:20261023T120000][other]].\n"))
      (should (string-match-p "denote:20261022T000005" (my/ids-test--read draft))))))

(ert-deftest my/ids-test-change-refuses-taken-identifier ()
  "An identifier already used in a silo is refused before anything is
written: the file, its name and the links are unchanged."
  (my/ids-test--with-notes
    (let* ((note (my/ids-test--note pks "20261022T000000" "kant"))
           (other (my/ids-test--note journal "20261022T000005" "other"))
           (linker (my/ids-test--note docu "20261023T090000" "linker"
                                      "[[denote:20261022T000000][Kant]]\n"))
           (before (list (my/ids-test--read note) (my/ids-test--read other)
                         (my/ids-test--read linker))))
      (should-error (my/denote-change-identifier note "20261022T000005") :type 'user-error)
      (should (file-exists-p note))
      (should (equal (list (my/ids-test--read note) (my/ids-test--read other)
                           (my/ids-test--read linker))
                     before)))))

(ert-deftest my/ids-test-change-refuses-malformed-identifier ()
  "A string that is no identifier is refused; nothing changes."
  (my/ids-test--with-notes
    (let* ((note (my/ids-test--note pks "20261022T000000" "kant"))
           (text (my/ids-test--read note)))
      (should-error (my/denote-change-identifier note "2026-10-22") :type 'user-error)
      (should (equal (my/ids-test--read note) text)))))

(ert-deftest my/ids-test-rename-never-overwrites ()
  "Renaming to a name already taken (a file outside the silos) refuses,
and leaves both files."
  (my/ids-test--with-notes
    (let* ((note (my/ids-test--note inbox "20261022T000000" "kant"))
           (taken (my/ids-test--note inbox "20261022T000005" "kant" "Keep me.\n")))
      (should-error (my/denote--rename-with-identifier note "20261022T000005") :type 'user-error)
      (should (file-exists-p note))
      (should (string-match-p "Keep me" (my/ids-test--read taken))))))

(ert-deftest my/ids-test-open-buffer-edits-kept ()
  "A linking note open with unsaved text: the link is repointed in the
buffer, and the unsaved text is saved with it, not lost."
  (my/ids-test--with-notes
    (let* ((note (my/ids-test--note pks "20261022T000000" "kant"))
           (linker (my/ids-test--note docu "20261023T090000" "linker"
                                      "[[denote:20261022T000000][Kant]]\n")))
      (with-current-buffer (find-file-noselect linker)
        (goto-char (point-max))
        (insert "Typed but not saved.\n"))
      (my/denote-change-identifier note "20261022T000005")
      (let ((text (my/ids-test--read linker)))
        (should (string-match-p "denote:20261022T000005" text))
        (should (string-match-p "Typed but not saved" text))))))

(ert-deftest my/ids-test-fix-duplicates-asks-each ()
  "Each extra note of a group is offered a new identifier: no changes
nothing; yes moves it, and the first keeps the identifier."
  (my/ids-test--with-notes
    (let ((a (my/ids-test--note journal "20261022T000000" "a"))
          (b (my/ids-test--note pks "20261022T000000" "b")))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
        (my/denote-fix-duplicates))
      (should (file-exists-p a))
      (should (file-exists-p b))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (my/denote-fix-duplicates))
      (should (null (my/denote--duplicate-groups)))
      (should (= 2 (length (my/denote--identifier-scope-files))))
      ;; Sorted by path: journal/ before pks/, so the journal note keeps it.
      (should (file-exists-p a))
      (should (file-exists-p (expand-file-name "20261022T000001--b.org" pks))))))

(ert-deftest my/ids-test-duplicate-links-stay-on-the-keeper ()
  "Fixing a duplicate does not take the links away from the note that
keeps the identifier.  Until 2026-10-22 every link to it was repointed
at the note that moved."
  (my/ids-test--with-notes
    (my/ids-test--note journal "20261022T000000" "a")
    (let ((b (my/ids-test--note pks "20261022T000000" "b"))
          (linker (my/ids-test--note docu "20261023T090000" "linker"
                                     "[[denote:20261022T000000][the day]]\n")))
      (my/denote-change-identifier b "20261022T000001")
      (should (string-match-p "denote:20261022T000000\\]" (my/ids-test--read linker))))))

(ert-deftest my/ids-test-link-files-given ()
  "With the files named, only their links follow the note."
  (my/ids-test--with-notes
    (my/ids-test--note journal "20261022T000000" "a")
    (let* ((b (my/ids-test--note inbox "20261022T000000" "b"))
           (draft (my/ids-test--note inbox "20261024T000000" "draft" "[[denote:20261022T000000][b]]\n"))
           (filed (my/ids-test--note docu "20261023T090000" "filed" "[[denote:20261022T000000][a]]\n")))
      (my/denote-change-identifier b "20261022T000001" (list draft))
      (should (string-match-p "denote:20261022T000001" (my/ids-test--read draft)))
      (should (string-match-p "denote:20261022T000000" (my/ids-test--read filed))))))

;; ============================================================
;; LINKS THAT MAY POINT AT THE WRONG NOTE (2026-10-23)
;; ============================================================

(defun my/ids-test--titled (dir id slug title &optional body)
  "Write the note ID--SLUG.org titled TITLE in DIR with BODY; return it."
  (let ((file (expand-file-name (format "%s--%s.org" id slug) dir)))
    (with-temp-file file
      (insert (format "#+title:      %s\n#+identifier: %s\n\n%s" title id (or body ""))))
    file))

(ert-deftest my/ids-test-suspect-link-found ()
  "A link labelled with one note's title that opens another note of the
same day is suspect; a matching label, a free label and a title of
another day are not."
  (my/ids-test--with-notes
    (let* ((day (my/ids-test--titled journal "20200301T000000" "2020-03-01" "2020-03-01"))
           (kant (my/ids-test--titled pks "20200301T000001" "kant" "Kant"))
           (linker (my/ids-test--titled journal "20200302T000000" "2020-03-02" "2020-03-02"
                                        (concat "[[denote:20200301T000001][2020-03-01]] "
                                                "[[denote:20200301T000001][Kant]] "
                                                "[[denote:20200301T000001][that day]] "
                                                "[[denote:20200301T000001][2020-03-02]]\n")))
           (found (my/denote-suspect-links)))
      (should (= 1 (length found)))
      (should (equal (plist-get (car found) :file) linker))
      (should (equal (plist-get (car found) :label) "2020-03-01"))
      (should (equal (plist-get (car found) :opens) kant))
      (should (equal (plist-get (car found) :meant) (list day))))))

(ert-deftest my/ids-test-suspect-link-list ()
  "The list names file and line, as grep does, so RET opens the link."
  (my/ids-test--with-notes
    (my/ids-test--titled journal "20200301T000000" "2020-03-01" "2020-03-01")
    (my/ids-test--titled pks "20200301T000001" "kant" "Kant")
    (my/ids-test--titled journal "20200302T000000" "2020-03-02" "2020-03-02"
                         "[[denote:20200301T000001][2020-03-01]]\n")
    (unwind-protect
        (progn
          (my/denote-check-suspect-links)
          (with-current-buffer "*Denote Suspect Links*"
            (should (derived-mode-p 'grep-mode))
            (should (string-match-p
                     "^journal/20200302T000000--2020-03-02\\.org:4: \\[\\[denote:20200301T000001\\]\\[2020-03-01\\]\\] opens 20200301T000001--kant\\.org; meant: 20200301T000000--2020-03-01\\.org$"
                     (buffer-string)))))
      (when (get-buffer "*Denote Suspect Links*") (kill-buffer "*Denote Suspect Links*")))))

(ert-deftest my/ids-test-suspect-link-repaired-on-yes ()
  "Yes points the link at the note its text names; no leaves it; the
rest of the note is unchanged."
  (my/ids-test--with-notes
    (my/ids-test--titled journal "20200301T000000" "2020-03-01" "2020-03-01")
    (my/ids-test--titled pks "20200301T000001" "kant" "Kant")
    (let* ((body "A [[denote:20200301T000001][2020-03-01]] B [[denote:20200301T000001][Kant]] C\n")
           (linker (my/ids-test--titled journal "20200302T000000" "2020-03-02" "2020-03-02" body))
           (text (my/ids-test--read linker)))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
        (my/denote-repair-suspect-links))
      (should (equal (my/ids-test--read linker) text))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (my/denote-repair-suspect-links))
      (should (equal (my/ids-test--read linker)
                     (replace-regexp-in-string
                      "denote:20200301T000001\\]\\[2020-03-01" "denote:20200301T000000][2020-03-01"
                      text t t)))
      (should (null (my/denote-suspect-links))))))

(ert-deftest my/ids-test-suspect-link-several-candidates-left ()
  "A label naming two notes of that day is not guessed: left, no question."
  (my/ids-test--with-notes
    (my/ids-test--titled journal "20200301T000000" "2020-03-01" "2020-03-01")
    (my/ids-test--titled docu "20200301T090000" "2020-03-01-copy" "2020-03-01")
    (my/ids-test--titled pks "20200301T000001" "kant" "Kant")
    (let* ((linker (my/ids-test--titled journal "20200302T000000" "2020-03-02" "2020-03-02"
                                        "[[denote:20200301T000001][2020-03-01]]\n"))
           (text (my/ids-test--read linker)))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) (error "Asked"))))
        (my/denote-repair-suspect-links))
      (should (equal (my/ids-test--read linker) text)))))

(ert-deftest my/ids-test-suspect-link-repaired-in-open-buffer ()
  "A note open in a buffer is repaired there and saved, unsaved text kept."
  (my/ids-test--with-notes
    (my/ids-test--titled journal "20200301T000000" "2020-03-01" "2020-03-01")
    (my/ids-test--titled pks "20200301T000001" "kant" "Kant")
    (let ((linker (my/ids-test--titled journal "20200302T000000" "2020-03-02" "2020-03-02"
                                       "[[denote:20200301T000001][2020-03-01]]\n")))
      (with-current-buffer (find-file-noselect linker)
        (goto-char (point-max))
        (insert "Typed.\n"))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (my/denote-repair-suspect-links))
      (let ((text (my/ids-test--read linker)))
        (should (string-match-p "denote:20200301T000000\\]" text))
        (should (string-match-p "Typed" text))))))

(provide 'test-denote-identifiers)
;;; test-denote-identifiers.el ends here
