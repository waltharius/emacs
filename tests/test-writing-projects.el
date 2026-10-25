;;; test-writing-projects.el --- ERT tests for writing projects of 428-writing-projects -*- lexical-binding: t; -*-

;; Tests: 428-writing-projects

;;; Commentary:

;; 428-writing-projects.el keeps a project folder with a hub file, writes
;; `#+project:' into notes and links to them into the hub, and rewrites
;; whole sections of the hub (mentions, titles, materials): TESTING.org,
;; *Every module tested*, part 3.  On real files in a temporary folder:
;; a projects folder and one silo, which is also the Denote folder.
;; Not covered: the clock options and the idle time from Mutter (they
;; only hand settings to Org), the agenda files (one `setq').
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-writing-projects.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "428-writing-projects")
(require 'denote)
(require 'org-element)

(defvar denote-directory)

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/wp-test--with-folders (&rest body)
  "Run BODY with fresh folders `projects' and `pks' under `root'.
`pks' is the only silo and the Denote folder."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-writing-" t)))
          (projects (file-name-as-directory (expand-file-name "projects" root)))
          (pks (file-name-as-directory (expand-file-name "pks" root)))
          (my-notes-dir root)
          (denote-directory pks)
          (my/writing-projects-directory projects)
          (my/writing-project-silos (list pks))
          (my/writing-project-note-directory pks)
          (my/writing-count-with-pandoc nil)
          (my/writing-project-created-hook nil)
          (org-agenda-files nil)
          (inhibit-message t))
     (make-directory projects t)
     (make-directory pks t)
     (clrhash my/writing--char-cache)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/wp-test--write (file text)
  "Write TEXT to FILE, creating its folder; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/wp-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/wp-test--hub (slug &optional title)
  "Write the hub of project SLUG from the module's template; return it."
  (my/wp-test--write (my/writing-hub-file slug)
                     (my/writing--hub-template (or title slug) slug 1000 "2027-01-31")))

(defun my/wp-test--note (dir id title &optional keywords extra body)
  "Write a Denote note ID titled TITLE in DIR; return its file.
KEYWORDS go into the file name, EXTRA after the identifier line,
BODY after the front matter."
  (my/wp-test--write
   (expand-file-name (format "%s--%s%s.org" id
                             (replace-regexp-in-string " " "-" (downcase title))
                             (if keywords (concat "__" (string-join keywords "_")) ""))
                     dir)
   (format "#+title:      %s\n#+identifier: %s\n%s\n%s" title id (or extra "") (or body ""))))

(defun my/wp-test--section (file heading)
  "Return the body of HEADING in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((bounds (my/writing--section-bounds heading)))
      (buffer-substring-no-properties (car bounds) (cdr bounds)))))

(defun my/wp-test--add (file slug section)
  "Add the note FILE to project SLUG under SECTION, as the command does."
  (with-current-buffer (find-file-noselect file)
    (my/writing-project-add-note slug section)))

(defmacro my/wp-test--messages (&rest body)
  "Run BODY; return the messages it showed, oldest first."
  `(let ((shown nil))
     (cl-letf (((symbol-function 'message)
                (lambda (format &rest args)
                  (when format (push (apply #'format format args) shown)))))
       ,@body)
     (nreverse shown)))

;; ============================================================
;; CREATING A PROJECT
;; ============================================================

(ert-deftest my/wp-test-new-project ()
  "A new project: its folder, the subfolders, a hub from the template, a
git repository, and the hook called with slug and folder."
  (my/wp-test--with-folders
    (let* ((called nil)
           (my/writing-project-created-hook
            (list (lambda (slug dir) (setq called (list slug dir))))))
      (my/writing-project-new "Moja Książka: Tom 1" 50000 "2027-03-01")
      (let* ((slug "moja-książka-tom-1")
             (dir (expand-file-name slug projects))
             (hub (my/writing-hub-file slug)))
        (should (file-directory-p (expand-file-name "email" dir)))
        (should (file-directory-p (expand-file-name ".git" dir)))
        (should (equal called (list slug (file-name-as-directory dir))))
        (should (string-prefix-p "#+title: Moja Książka: Tom 1\n" (my/wp-test--read hub)))
        (with-temp-buffer
          (insert-file-contents hub)
          (should (equal (my/writing--keyword-in-buffer "target_chars") "50000"))
          (should (equal (my/writing--keyword-in-buffer "target_date") "2027-03-01"))
          (should (my/writing--section-bounds my/writing-heading-text)))
        (should (equal (my/writing-project-slugs) (list slug)))))))

(ert-deftest my/wp-test-new-project-never-replaces-a-hub ()
  "A project whose hub exists is refused; the hub is left as it was."
  (my/wp-test--with-folders
    (let ((hub (my/wp-test--write (my/writing-hub-file "book") "#+title: mine\n")))
      (should-error (my/writing-project-new "Book" 1000 "2027-01-01") :type 'user-error)
      (should (equal (my/wp-test--read hub) "#+title: mine\n")))))

(ert-deftest my/wp-test-new-project-unusable-names ()
  "A title that leaves no usable folder name -- empty, blank, a dot, two
dots, a hidden name -- is refused before anything is made: no hub, no
git repository in the projects folder or above it."
  (my/wp-test--with-folders
    (let ((before (directory-files root)))
      (dolist (title '("" "   " "." ".." ".hidden" "///"))
        (should-error (my/writing-project-new title 1000 "2027-01-01") :type 'user-error))
      (should-not (directory-files projects nil directory-files-no-dot-files-regexp))
      (should-not (file-exists-p (expand-file-name ".git" projects)))
      (should-not (file-exists-p (expand-file-name ".git" root)))
      (should (equal (directory-files root) before)))))

(ert-deftest my/wp-test-project-slugs ()
  "Projects are the folders holding a hub named after them; a folder
without one and a hidden folder are not projects."
  (my/wp-test--with-folders
    (my/wp-test--hub "book")
    (my/wp-test--hub "talk")
    (make-directory (expand-file-name "loose" projects))
    (my/wp-test--write (expand-file-name ".trash/.trash.org" projects) "x\n")
    (should (equal (sort (my/writing-project-slugs) #'string<) '("book" "talk")))))

;; ============================================================
;; MEMBERSHIP
;; ============================================================

(ert-deftest my/wp-test-add-note-both-halves ()
  "Adding a note writes both halves: the project joins the note's own
`#+project:' line, keeping the projects it had, and the hub links it
under the section.  Added again, nothing changes."
  (my/wp-test--with-folders
    (my/wp-test--hub "book")
    (let ((note (my/wp-test--note pks "20261024T100000" "Chapter one" nil
                                  "#+project: talk" "Text of the chapter.\n")))
      (my/wp-test--add note "book" my/writing-heading-text)
      (let ((text (my/wp-test--read note))
            (hub (my/wp-test--read (my/writing-hub-file "book"))))
        (should (string-search "#+project: talk book\n" text))
        (should (equal (my/writing-file-projects note) '("talk" "book")))
        (should (string-search "[[denote:20261024T100000][Chapter one]]"
                               (my/wp-test--section (my/writing-hub-file "book")
                                                    my/writing-heading-text)))
        (my/wp-test--add note "book" my/writing-heading-text)
        (should (equal (my/wp-test--read note) text))
        (should (equal (my/wp-test--read (my/writing-hub-file "book")) hub))))))

(ert-deftest my/wp-test-project-line-in-front-matter-only ()
  "A `#+project:' line in the body -- an example in a source block -- is
not the note's membership: it is neither read nor rewritten, and the
project goes into the front matter."
  (my/wp-test--with-folders
    (my/wp-test--hub "book")
    (let* ((body "How to mark a note:\n\n#+begin_src org\n#+project: example\n#+end_src\n")
           (note (my/wp-test--note pks "20261024T100000" "Howto" nil "" body)))
      (should-not (my/writing-file-projects note))
      (my/wp-test--add note "book" my/writing-heading-text)
      (should (equal (my/wp-test--read note)
                     (concat "#+title:      Howto\n#+identifier: 20261024T100000\n"
                             "#+project: book\n\n" body)))
      (should (equal (my/writing-file-projects note) '("book"))))))

(ert-deftest my/wp-test-add-note-without-identifier ()
  "A note without `#+identifier:' is refused; neither file changes."
  (my/wp-test--with-folders
    (let* ((hub (my/wp-test--hub "book"))
           (before (my/wp-test--read hub))
           (note (my/wp-test--write (expand-file-name "plain.org" pks) "#+title: Plain\n\nText.\n")))
      (should-error (my/wp-test--add note "book" my/writing-heading-text) :type 'user-error)
      (should (equal (my/wp-test--read note) "#+title: Plain\n\nText.\n"))
      (should (equal (my/wp-test--read hub) before)))))

(ert-deftest my/wp-test-link-title-with-brackets ()
  "A title ending in `]' gives a link Org reads whole: its description is
the full title, and nothing follows the link on the line."
  (my/wp-test--with-folders
    (my/wp-test--hub "book")
    (let ((note (my/wp-test--note pks "20261024T100000" "Chapter 2 [draft]")))
      (my/wp-test--add note "book" my/writing-heading-text)
      (with-temp-buffer
        (insert (my/wp-test--section (my/writing-hub-file "book") my/writing-heading-text))
        (org-mode)
        (goto-char (point-min))
        (search-forward "[[denote:")
        (let ((link (org-element-context)))
          (should (eq (org-element-type link) 'link))
          (should (equal (org-element-property :path link) "20261024T100000"))
          (should (equal (string-trim (buffer-substring-no-properties
                                       (org-element-property :contents-begin link)
                                       (org-element-property :contents-end link))
                                      nil "​")
                         "Chapter 2 [draft]"))
          (goto-char (org-element-property :end link))
          (should (looking-at-p "[ \t]*$")))))))

(ert-deftest my/wp-test-refresh-titles ()
  "A renamed note's link description follows its title; a refresh with
nothing stale changes nothing, also for a title ending in `]'."
  (my/wp-test--with-folders
    (my/wp-test--hub "book")
    (let ((one (my/wp-test--note pks "20261024T100000" "Old title"))
          (two (my/wp-test--note pks "20261024T110000" "Chapter 2 [draft]")))
      (my/wp-test--add one "book" my/writing-heading-text)
      (my/wp-test--add two "book" my/writing-heading-text)
      (kill-buffer (find-buffer-visiting one))
      (my/wp-test--write one "#+title:      New title\n#+identifier: 20261024T100000\n#+project: book\n")
      (should (equal (my/wp-test--messages (my/writing-project-refresh-titles "book"))
                     '("1 link description(s) updated")))
      (let ((section (my/wp-test--section (my/writing-hub-file "book") my/writing-heading-text)))
        (should (string-search "[[denote:20261024T100000][New title]]" section))
        (should-not (string-search "Old title" section)))
      (should (equal (my/wp-test--messages (my/writing-project-refresh-titles "book"))
                     '("0 link description(s) updated"))))))

;; ============================================================
;; SECTIONS REWRITTEN IN FULL
;; ============================================================

(ert-deftest my/wp-test-refresh-mentions ()
  "Mentions lists the notes with the project's keyword that are not
members; the rest of the hub is left exactly as it was."
  (my/wp-test--with-folders
    (let* ((hub (my/wp-test--hub "book"))
           (member (my/wp-test--note pks "20261024T100000" "Member" '("book")))
           (_other (my/wp-test--note pks "20261024T110000" "Journal day" '("book" "diary")))
           (_unrelated (my/wp-test--note pks "20261024T120000" "Unrelated" '("bookish"))))
      (my/wp-test--add member "book" my/writing-heading-text)
      (with-current-buffer (find-buffer-visiting hub)
        (goto-char (point-max))
        (insert "Written under Mail by hand.\n")
        (save-buffer))
      (let* ((before (my/wp-test--read hub))
             (bounds (with-temp-buffer (insert before)
                                       (my/writing--section-bounds my/writing-heading-mentions))))
        (my/writing-project-refresh-mentions "book")
        (let* ((after (my/wp-test--read hub))
               (section (my/wp-test--section hub my/writing-heading-mentions))
               (tail (- (length before) (1- (cdr bounds)))))
          (should (string-search "[[denote:20261024T110000][Journal day]]" section))
          (should-not (string-search "20261024T100000" section))
          (should-not (string-search "Unrelated" section))
          (should (string-prefix-p (substring before 0 (1- (car bounds))) after))
          (should (string-suffix-p (substring before (- (length before) tail)) after)))))))

(ert-deftest my/wp-test-rebuild-materials ()
  "The scan adds under Sources every note declaring the project in its
front matter and not linked yet; a project named only in a note's body
is not added; a second scan adds nothing."
  (my/wp-test--with-folders
    (let ((hub (my/wp-test--hub "book")))
      (my/wp-test--note pks "20261024T100000" "Declared" nil "#+project: talk book")
      (my/wp-test--note pks "20261024T110000" "Example only" nil ""
                        "#+begin_example\n#+project: book\n#+end_example\n")
      (my/writing-project-rebuild-materials "book")
      (let ((sources (my/wp-test--section hub my/writing-heading-sources))
            (after (my/wp-test--read hub)))
        (should (string-search "[[denote:20261024T100000][Declared]]" sources))
        (should-not (string-search "20261024T110000" after))
        (my/writing-project-rebuild-materials "book")
        (should (equal (my/wp-test--read hub) after))))))

;; ============================================================
;; PROGRESS
;; ============================================================

(ert-deftest my/wp-test-stats-count-text-only ()
  "Progress counts the notes under Text only, without front matter or
drawers; a link to a note that is gone is counted as linked, not found."
  (my/wp-test--with-folders
    (my/wp-test--hub "book")
    (let ((text (my/wp-test--note pks "20261024T100000" "Text" nil ""
                                  ":PROPERTIES:\n:ID: x\n:END:\nabcdefghij\n"))
          (source (my/wp-test--note pks "20261024T110000" "Source" nil "" "0123456789012345\n")))
      (my/wp-test--add text "book" my/writing-heading-text)
      (my/wp-test--add source "book" my/writing-heading-sources)
      (with-current-buffer (find-file-noselect (my/writing-hub-file "book"))
        (my/writing--append-link my/writing-heading-text "20261024T999999" "Gone")
        (save-buffer))
      (let ((stats (my/writing-project-stats "book")))
        (should (equal (plist-get stats :target) 1000))
        (should (equal (plist-get stats :linked) 2))
        (should (equal (plist-get stats :files) 1))
        ;; The rough count (pandoc off): the blank line after the front
        ;; matter, the line end the drawer leaves, the body line.
        (should (equal (plist-get stats :chars) (+ 2 (length "abcdefghij\n"))))))))

(ert-deftest my/wp-test-days-until-in-calendar-days ()
  "Days until a deadline are calendar days: 0 on the day, 1 for the
next, negative after; and two, not three, at 23:30 on 2026-10-24 in
Central Europe for 2026-10-26, across the 25-hour 2026-10-25."
  (my/test-with-time-zone my/test-central-europe
    (let ((now (encode-time (list 0 30 23 24 10 2026 nil -1 nil))))
      (cl-letf (((symbol-function 'current-time) (lambda () now)))
        (should (= 0 (my/writing--days-until "2026-10-24")))
        (should (= 1 (my/writing--days-until "2026-10-25")))
        (should (= 2 (my/writing--days-until "2026-10-26")))
        (should (= -3 (my/writing--days-until "2026-10-21"))))))
  (should-not (my/writing--days-until nil)))

(ert-deftest my/wp-test-new-note ()
  "A new note for a project is a Denote note in the notes folder, with
the project's keyword in its name, the project in its front matter and
a link to it in the hub."
  (my/wp-test--with-folders
    (my/wp-test--hub "book")
    (my/writing-project-new-note "book" my/writing-heading-text "First draft")
    (let ((files (directory-files pks t "__book\\.org\\'")))
      (should (= (length files) 1))
      (should (equal (my/writing-file-projects (car files)) '("book")))
      (let ((id (with-temp-buffer (insert-file-contents (car files))
                                  (my/writing--keyword-in-buffer "identifier"))))
        (should id)
        (should (string-search (format "[[denote:%s][First draft]]" id)
                               (my/wp-test--section (my/writing-hub-file "book")
                                                    my/writing-heading-text)))))))

(provide 'test-writing-projects)
;;; test-writing-projects.el ends here
