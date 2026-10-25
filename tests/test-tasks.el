;;; test-tasks.el --- ERT tests for task capture, routing, agenda files and the planner of 37-tasks -*- lexical-binding: t; -*-

;; Tests: 37-tasks

;;; Commentary:

;; 37-tasks.el captures a task from any buffer into the hub of the
;; buffer's writing project or into the inbox of the task file, keeps
;; `org-agenda-files', and once offered to copy the planner out of the
;; notes folder: TESTING.org, *Every module tested*, part 3.  On real
;; files in a temporary folder; captures run through org-capture itself
;; and are finished with `org-capture-finalize'.  Not covered: the
;; refile command (Org's own `org-refile' with a narrowed target list),
;; the key and menu (weekly switch tests).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-tasks.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "28-writing-projects" "37-tasks")

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/tasks-test--with-folders (&rest body)
  "Run BODY with a notes folder `notes', its silo `pks', `projects' and
the planner folder `planner', all fresh."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-tasks-" t)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (pks (file-name-as-directory (expand-file-name "pks" notes)))
          (projects (file-name-as-directory (expand-file-name "projects" root)))
          (planner (file-name-as-directory (expand-file-name "planner" projects)))
          (my-notes-dir notes)
          (my/tasks-directory planner)
          (my/tasks-file "tasks.org")
          (my/writing-projects-directory projects)
          (my/tasks-extra-agenda-files nil)
          (my/tasks-agenda-file-functions nil)
          (my/tasks-record-source t)
          (my/tasks-date-keyword 'scheduled)
          (my/tasks--destination nil)
          (org-agenda-files nil)
          (inhibit-message t))
     (make-directory pks t)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name (or (buffer-base-buffer b) b))))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/tasks-test--write (file text)
  "Write TEXT to FILE, creating its folder; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/tasks-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/tasks-test--hub (slug)
  "Write the hub of project SLUG from 28-writing-projects' template."
  (my/tasks-test--write (my/writing-hub-file slug)
                        (my/writing--hub-template slug slug 1000 "2027-01-31")))

(defun my/tasks-test--capture (headline &optional date)
  "Capture HEADLINE dated DATE (a time value or nil) from the current
buffer, as F8 does with those answers, and file it."
  (cl-letf (((symbol-function 'read-string) (lambda (&rest _) headline))
            ((symbol-function 'my/tasks--read-date) (lambda () date)))
    (my/task-capture))
  (org-capture-finalize))

(defun my/tasks-test--under (file heading)
  "Return the text of FILE under top-level HEADING, up to the next one."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward (format "^\\* %s$" (regexp-quote heading)))
    (let ((start (line-beginning-position 2)))
      (buffer-substring-no-properties
       start (if (re-search-forward "^\\* " nil t) (line-beginning-position) (point-max))))))

;; ============================================================
;; THE TASK FILE
;; ============================================================

(ert-deftest my/tasks-test-ensure-file ()
  "The task file is made with its three headings when missing, and an
existing one is never rewritten."
  (my/tasks-test--with-folders
    (my/tasks--ensure-file)
    (let ((text (my/tasks-test--read (my/tasks--file))))
      (dolist (h (list my/tasks-heading-inbox my/tasks-heading-active my/tasks-heading-someday))
        (should (string-search (concat "\n* " h "\n") text))))
    (my/tasks-test--write (my/tasks--file) "* Mine\n")
    (my/tasks--ensure-file)
    (should (equal (my/tasks-test--read (my/tasks--file)) "* Mine\n"))))

(ert-deftest my/tasks-test-goto-heading-top-level ()
  "The target heading is the top-level one: a task with the same words
further down is not it.  A missing heading is added at the end."
  (with-temp-buffer
    (insert "#+title: Tasks\n\n* Tasks\n** TODO Inbox\n\n* Inbox\n* Someday\n")
    (org-mode)
    (my/tasks--goto-heading "Inbox")
    (should (looking-at-p "\\* Inbox$"))
    (my/tasks--goto-heading "Later")
    (should (looking-at-p "\\* Later$"))
    (should (string-suffix-p "* Someday\n* Later\n" (buffer-string)))))

;; ============================================================
;; CAPTURE AND ROUTING
;; ============================================================

(ert-deftest my/tasks-test-capture-to-inbox ()
  "A task from a note of no project goes to the inbox: a TODO with its
SCHEDULED date and its source, a link to the note."
  (my/tasks-test--with-folders
    (let ((note (my/tasks-test--write (expand-file-name "20261024T100000--a-note.org" pks)
                                      "#+title: A note\n#+identifier: 20261024T100000\n\nText.\n")))
      (with-current-buffer (find-file-noselect note)
        (my/tasks-test--capture "Check the reference" (encode-time 0 0 12 30 10 2026)))
      (let ((inbox (my/tasks-test--under (my/tasks--file) my/tasks-heading-inbox)))
        ;; The day name in the system's language, as Org writes it ("pią").
        (should (string-search (format "** TODO Check the reference\nSCHEDULED: <2026-10-30 %s>"
                                       (format-time-string "%a" (encode-time 0 0 12 30 10 2026)))
                               inbox))
        (should (string-search ":SOURCE:   [[denote:20261024T100000][A note]]" inbox))
        (should-not (string-search "Check the reference"
                                   (my/tasks-test--under (my/tasks--file) my/tasks-heading-active)))))))

(ert-deftest my/tasks-test-capture-to-project-hub ()
  "A task from a note declaring `#+project:' goes under Tasks of that
project's hub, and the task file is not written to."
  (my/tasks-test--with-folders
    (my/tasks-test--hub "book")
    (my/tasks--ensure-file)
    (let ((before (my/tasks-test--read (my/tasks--file)))
          (note (my/tasks-test--write (expand-file-name "20261024T100000--ch.org" pks)
                                      "#+title: Chapter\n#+identifier: 20261024T100000\n#+project: book\n")))
      (with-current-buffer (find-file-noselect note)
        (my/tasks-test--capture "Shorten section two"))
      (should (string-search "** TODO Shorten section two"
                             (my/tasks-test--under (my/writing-hub-file "book") "Tasks")))
      (should (equal (my/tasks-test--read (my/tasks--file)) before)))))

(ert-deftest my/tasks-test-capture-project-without-hub ()
  "A note naming a project whose hub is gone: the task goes to the inbox
rather than being lost."
  (my/tasks-test--with-folders
    (let ((note (my/tasks-test--write (expand-file-name "20261024T100000--ch.org" pks)
                                      "#+title: Chapter\n#+identifier: 20261024T100000\n#+project: gone\n")))
      (with-current-buffer (find-file-noselect note)
        (my/tasks-test--capture "Still kept"))
      (should (string-search "** TODO Still kept"
                             (my/tasks-test--under (my/tasks--file) my/tasks-heading-inbox))))))

(ert-deftest my/tasks-test-capture-text-taken-literally ()
  "The task as typed and the note's title go in literally: `%(...)' is
not evaluated, `%a' and `%t' are not replaced, backslashes stay, and a
title ending in `]' gives a whole link."
  (my/tasks-test--with-folders
    (let* ((evaluated nil)
           (title "Notes %(setq evaluated t) [draft]")
           (headline "Raise to 100%a by %t, see \\%c")
           (note (my/tasks-test--write (expand-file-name "20261024T100000--n.org" pks)
                                       (format "#+title: %s\n#+identifier: 20261024T100000\n" title))))
      (ignore evaluated)
      (with-current-buffer (find-file-noselect note)
        (my/tasks-test--capture headline))
      (let ((inbox (my/tasks-test--under (my/tasks--file) my/tasks-heading-inbox)))
        (should-not evaluated)
        (should (string-search (concat "** TODO " headline "\n") inbox))
        (should (string-search (concat ":SOURCE:   "
                                       (org-link-make-string "denote:20261024T100000" title)
                                       "\n")
                               inbox))))))

(ert-deftest my/tasks-test-literal ()
  "The escape itself: every `%' gets one backslash, and backslashes
already before it are doubled, as `org-capture-escaped-%' expects."
  (should (equal (my/tasks--literal "no percent") "no percent"))
  (should (equal (my/tasks--literal "50% and %a") "50\\% and \\%a"))
  (should (equal (my/tasks--literal "a\\%b") "a\\\\\\%b"))
  (should (equal (my/tasks--literal "a\\b%") "a\\b\\%")))

(ert-deftest my/tasks-test-read-date ()
  "Date answers: none is no date; a fixed answer is that day, counted
from today, without a second question."
  (cl-letf (((symbol-function 'read-from-minibuffer) (lambda (&rest _) (error "Asked again"))))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "none")))
      (should-not (my/tasks--read-date)))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "tomorrow")))
      (should (equal (format-time-string "%F" (my/tasks--read-date)) (my/test-date 1))))
    ;; Calendar days (`my/test-date'), not 86400-second steps from now,
    ;; which miss by a day near midnight on the day summer time ends.
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "next week")))
      (should (equal (format-time-string "%F" (my/tasks--read-date)) (my/test-date 7))))))

(ert-deftest my/tasks-test-empty-task-refused ()
  "An empty task is refused before anything is captured."
  (my/tasks-test--with-folders
    (my/tasks--ensure-file)
    (let ((before (my/tasks-test--read (my/tasks--file))))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "   ")))
        (should-error (my/task-capture) :type 'user-error))
      (should-not (seq-some (lambda (b) (string-prefix-p "CAPTURE-" (buffer-name b)))
                            (buffer-list)))
      (should (equal (my/tasks-test--read (my/tasks--file)) before)))))

;; ============================================================
;; AGENDA FILES
;; ============================================================

(ert-deftest my/tasks-test-agenda-files ()
  "The agenda reads the task file, every project hub, the files other
modules add, and the extra files (relative to the notes folder);
missing files are left out."
  (my/tasks-test--with-folders
    (my/tasks--ensure-file)
    (my/tasks-test--hub "book")
    (let* ((habits (my/tasks-test--write (expand-file-name "habits.org" planner) "* Habits\n"))
           (extra (my/tasks-test--write (expand-file-name "pks/extra.org" notes) "* X\n"))
           (my/tasks-agenda-file-functions
            (list (lambda () (list habits (expand-file-name "gone.org" planner)))))
           (my/tasks-extra-agenda-files '("pks/extra.org" "pks/missing.org")))
      (should (equal (my/tasks-agenda-files)
                     (list (my/tasks--file) habits extra (my/writing-hub-file "book")))))))

;; ============================================================
;; THE PLANNER MOVE OUT OF THE NOTES FOLDER
;; ============================================================

(defmacro my/tasks-test--with-legacy (answer &rest body)
  "Run BODY with an old planner in the notes folder and ANSWER as the
choice at the question; `legacy' is bound to the old folder, `reports'
to the reports made, `saved' to the options saved."
  (declare (indent 1))
  `(my/tasks-test--with-folders
     (let* ((legacy (file-name-as-directory (expand-file-name "planner" notes)))
            (reports nil) (saved nil) (noninteractive nil))
       (my/tasks-test--write (expand-file-name "tasks.org" legacy) "* Inbox\n** TODO old task\n")
       (my/tasks-test--write (expand-file-name "habits.org" legacy) "* Habits\n")
       (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) (list ,answer)))
                 ((symbol-function 'my/tasks--report)
                  (lambda (kind title &rest _) (push (cons kind title) reports) nil))
                 ((symbol-function 'customize-save-variable)
                  (lambda (symbol value &rest _) (push (cons symbol value) saved) (set symbol value))))
         ,@body))))

(ert-deftest my/tasks-test-planner-copy-only ()
  "`k': the new folder holds the same files, the old one is untouched,
and the planner is the new folder."
  (my/tasks-test--with-legacy ?k
    (my/tasks-check-planner-move)
    (should (equal (my/tasks--planner-files planner) '("habits.org" "tasks.org")))
    (should (equal (my/tasks-test--read (expand-file-name "tasks.org" planner))
                   "* Inbox\n** TODO old task\n"))
    (should (equal (my/tasks--planner-files legacy) '("habits.org" "tasks.org")))
    (should (equal my/tasks-directory planner))
    (should-not (file-exists-p (expand-file-name ".git" planner)))
    (should (eq (caar reports) 'done))))

(ert-deftest my/tasks-test-planner-copy-and-git ()
  "`c': copied, and the new folder is a git repository with one commit."
  (my/tasks-test--with-legacy ?c
    (let ((process-environment (append '("GIT_AUTHOR_NAME=t" "GIT_AUTHOR_EMAIL=t@example.org"
                                         "GIT_COMMITTER_NAME=t" "GIT_COMMITTER_EMAIL=t@example.org")
                                       process-environment)))
      (my/tasks-check-planner-move))
    (should (file-directory-p (expand-file-name ".git" planner)))
    (let ((default-directory planner))
      (should (equal (process-lines "git" "rev-list" "--count" "HEAD") '("1"))))
    (should (eq (caar reports) 'done))))

(ert-deftest my/tasks-test-planner-later-and-use-old ()
  "`l' uses the old folder for this session and saves nothing; `u'
saves the old folder as the planner.  Nothing is copied either way."
  (my/tasks-test--with-legacy ?l
    (my/tasks-check-planner-move)
    (should (equal my/tasks-directory legacy))
    (should-not saved)
    (should-not (file-exists-p planner)))
  (my/tasks-test--with-legacy ?u
    (my/tasks-check-planner-move)
    (should (equal (car saved) (cons 'my/tasks-directory (abbreviate-file-name legacy))))
    (should-not (file-exists-p planner))))

(ert-deftest my/tasks-test-planner-refused-when-new-holds-files ()
  "A new folder that already holds other files: nothing is copied, the
old folder is used, and the refusal is reported."
  (my/tasks-test--with-legacy ?k
    (my/tasks-test--write (expand-file-name "notes.txt" planner) "mine\n")
    (my/tasks-check-planner-move)
    (should (equal (my/tasks--planner-files planner) '("notes.txt")))
    (should (equal my/tasks-directory legacy))
    (should (eq (caar reports) 'refused))))

(ert-deftest my/tasks-test-planner-copy-fails ()
  "A copy that fails keeps the old folder in use and reports the failure;
the old folder is untouched."
  (my/tasks-test--with-legacy ?k
    (let* ((bin (file-name-as-directory (expand-file-name "bin" root)))
           (exec-path (list bin)))
      (my/tasks-test--write (expand-file-name "cp" bin) "#!/bin/sh\necho 'cp: no space left' >&2\nexit 1\n")
      (set-file-modes (expand-file-name "cp" bin) #o755)
      (my/tasks-check-planner-move))
    (should (equal my/tasks-directory legacy))
    (should (eq (caar reports) 'failed))
    (should (equal (my/tasks--planner-files legacy) '("habits.org" "tasks.org")))))

(ert-deftest my/tasks-test-planner-copy-incomplete ()
  "A copy that says it succeeded but left files out is a failure: the
old folder stays in use.  The second safeguard behind cp's exit status."
  (my/tasks-test--with-legacy ?k
    (let* ((bin (file-name-as-directory (expand-file-name "bin" root)))
           (exec-path (list bin)))
      (my/tasks-test--write (expand-file-name "cp" bin) "#!/bin/sh
exit 0
")
      (set-file-modes (expand-file-name "cp" bin) #o755)
      (my/tasks-check-planner-move))
    (should (equal my/tasks-directory legacy))
    (should (eq (caar reports) 'failed))))

(ert-deftest my/tasks-test-planner-nobody-to-ask ()
  "In batch the old folder is used and nothing is asked or copied."
  (my/tasks-test--with-legacy ?k
    (let ((noninteractive t))
      (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) (error "Asked"))))
        (my/tasks-check-planner-move)))
    (should (equal my/tasks-directory legacy))
    (should-not (file-exists-p planner))))

(ert-deftest my/tasks-test-planner-nothing-to-move ()
  "No old planner, or a task file already in the new folder: no question."
  (my/tasks-test--with-folders
    (let ((noninteractive nil))
      (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) (error "Asked"))))
        (my/tasks-check-planner-move)
        (should (equal my/tasks-directory planner))
        (my/tasks-test--write (expand-file-name "planner/tasks.org" notes) "* Inbox\n")
        (my/tasks--ensure-file)
        (my/tasks-check-planner-move)
        (should (equal my/tasks-directory planner))))))

(provide 'test-tasks)
;;; test-tasks.el ends here
