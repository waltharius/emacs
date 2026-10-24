;;; test-habits.el --- ERT tests for defining, logging and deriving habits of 38-habits -*- lexical-binding: t; -*-

;; Tests: 38-habits

;;; Commentary:

;; 38-habits.el defines habits once through org-capture, logs them done
;; by writing their LOGBOOK and moving the repeater, and rebuilds the
;; LOGBOOK of a derived habit from its source (the journal file names):
;; TESTING.org, *Every module tested*, part 3.  On real files in a
;; temporary planner folder.  Not covered: the agenda graph itself
;; (org-habit's drawing), the key and menu (weekly switch tests).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-habits.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "27-denote-identifiers" "05-notes" "37-tasks" "38-habits")

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/habits-test--with-planner (&rest body)
  "Run BODY with a fresh planner folder `planner' and notes folder `notes'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-habits-" t)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (planner (file-name-as-directory (expand-file-name "planner" root)))
          (my-notes-dir notes)
          (my/tasks-directory planner)
          (my/habits-file "habits.org")
          (org-agenda-files nil)
          (inhibit-message t))
     (make-directory notes t)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name (or (buffer-base-buffer b) b))))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/habits-test--write (file text)
  "Write TEXT to FILE, creating its folder; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/habits-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/habits-test--day (offset)
  "Return the date OFFSET days from today as \"YYYY-MM-DD\"."
  (format-time-string "%Y-%m-%d" (time-add nil (days-to-time offset))))

(defun my/habits-test--file-with (entries)
  "Write the habit file: its template, then ENTRIES under the heading."
  (my/habits-test--write (my/habits--file) (concat (my/habits--file-template) entries)))

(defun my/habits-test--habit (name &optional repeat logbook)
  "Return the text of habit NAME scheduled today with REPEAT and LOGBOOK."
  (format "** TODO %s\nSCHEDULED: <%s %s>\n:PROPERTIES:\n:STYLE:    habit\n:END:\n%sWhat counts.\n"
          name (format-time-string "%Y-%m-%d %a") (or repeat ".+1d")
          (if logbook (concat ":LOGBOOK:\n" (string-join logbook "\n") "\n:END:\n") "")))

(defun my/habits-test--log (name &optional date)
  "Log habit NAME as `my/habit-log' does; on DATE (\"YYYY-MM-DD\") if given."
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) name))
            ((symbol-function 'org-read-date)
             (lambda (&rest _) (org-time-string-to-time (concat "<" date ">")))))
    (my/habit-log (and date t))))

(defun my/habits-test--entry (name)
  "Return the text of habit NAME's entry in the habit file."
  (with-temp-buffer
    (insert-file-contents (my/habits--file))
    (org-mode)
    (goto-char (point-min))
    (re-search-forward (format "^\\*+ TODO %s$" (regexp-quote name)))
    (buffer-substring-no-properties (line-beginning-position)
                                    (save-excursion (outline-next-heading) (point)))))

(defun my/habits-test--scheduled (name)
  "Return the SCHEDULED timestamp of habit NAME, without brackets."
  (let ((entry (my/habits-test--entry name)))
    (string-match "SCHEDULED: <\\([^>]*\\)>" entry)
    (match-string 1 entry)))

;; ============================================================
;; THE FILE AND DEFINING
;; ============================================================

(ert-deftest my/habits-test-ensure-file ()
  "The habit file is made with its heading when missing, never rewritten."
  (my/habits-test--with-planner
    (my/habits--ensure-file)
    (should (string-search "\n* Habits\n" (my/habits-test--read (my/habits--file))))
    (my/habits-test--write (my/habits--file) "* Mine\n")
    (my/habits--ensure-file)
    (should (equal (my/habits-test--read (my/habits--file)) "* Mine\n"))))

(ert-deftest my/habits-test-new-habit ()
  "A new habit is a TODO under the top-level heading, scheduled today
with the chosen repeater, marked as a habit."
  (my/habits-test--with-planner
    ;; A habit named like the heading, above it: not where habits go.
    (my/habits-test--write (my/habits--file)
                           (concat "#+title: Habits\n\n* Retired\n** TODO Habits\n"
                                   ":PROPERTIES:\n:STYLE: habit\n:END:\n\n* Habits\n"))
    ;; Both questions are completions: the repeater (this module) and
    ;; the name (org-capture's %^{Habit}).
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt &rest _)
                 (if (string-prefix-p "Repeats" prompt) "every week, 10 days grace" "Exercise"))))
      (my/habit-new))
    (org-capture-finalize)
    (let ((text (my/habits-test--read (my/habits--file))))
      (should (string-match-p
               (concat "^\\*\\* TODO Exercise\nSCHEDULED: <"
                       (format-time-string "%Y-%m-%d %a") " \\.\\+1w/10d>\n:PROPERTIES:\n:STYLE:    habit")
               text))
      ;; Not filed under the habit that is also called Habits.
      (should-not (string-search "*** TODO Exercise" text))
      (should (string-prefix-p "** TODO Exercise" (my/habits-test--entry "Exercise")))
      (should (string-match-p "\\* Habits\n\n?\\*\\* TODO Exercise" text)))))

(ert-deftest my/habits-test-entries ()
  "Habits are the entries with STYLE habit, in the habit file and in the
agenda files; other entries are not."
  (my/habits-test--with-planner
    (my/habits-test--file-with (concat (my/habits-test--habit "Read")
                                       "** TODO Not a habit\n"))
    (let* ((other (my/habits-test--write (expand-file-name "tasks.org" planner)
                                         (concat "* Tasks\n" (my/habits-test--habit "Walk"))))
           (org-agenda-files (list other)))
      (should (equal (mapcar #'car (my/habits--entries)) '("Read" "Walk"))))))

;; ============================================================
;; LOGGING
;; ============================================================

(ert-deftest my/habits-test-log-today ()
  "Logging today: a completion line on top of the LOGBOOK, the repeater
moved to tomorrow, the habit still a TODO, the file saved.  Logged
again the same day, nothing changes."
  (my/habits-test--with-planner
    (let ((older (my/habits--logbook-line (my/habits-test--day -3))))
      (my/habits-test--file-with (my/habits-test--habit "Read" ".+1d" (list older)))
      (my/habits-test--log "Read")
      (let ((entry (my/habits-test--entry "Read")))
        (should (string-search (concat ":LOGBOOK:\n" (my/habits--logbook-line (my/habits-test--day 0))
                                       "\n" older "\n:END:\n")
                               entry))
        (should (string-prefix-p "** TODO Read" entry))
        (should (string-search "What counts." entry)))
      (should (string-prefix-p (my/habits-test--day 1) (my/habits-test--scheduled "Read")))
      (should (string-suffix-p ".+1d" (my/habits-test--scheduled "Read")))
      (should-not (buffer-modified-p (find-buffer-visiting (my/habits--file))))
      (let ((after (my/habits-test--read (my/habits--file))))
        (my/habits-test--log "Read")
        (should (equal (my/habits-test--read (my/habits--file)) after))))))

(ert-deftest my/habits-test-log-earlier-day ()
  "Logging yesterday for a daily habit records yesterday and leaves it
due today, not tomorrow."
  (my/habits-test--with-planner
    (my/habits-test--file-with (my/habits-test--habit "Read" ".+1d"))
    (my/habits-test--log "Read" (my/habits-test--day -1))
    (should (string-search (my/habits--logbook-line (my/habits-test--day -1))
                           (my/habits-test--entry "Read")))
    (should (string-prefix-p (my/habits-test--day 0) (my/habits-test--scheduled "Read")))))

(ert-deftest my/habits-test-write-logbook ()
  "The LOGBOOK is replaced whole, after the planning line and properties
and before the text; an empty list removes it."
  (with-temp-buffer
    (insert (my/habits-test--habit "Read" ".+1d" '("- old line")))
    (org-mode)
    (goto-char (point-min))
    (my/habits--write-logbook '("- a" "- b"))
    (should (string-search ":END:\n:LOGBOOK:\n- a\n- b\n:END:\nWhat counts.\n" (buffer-string)))
    (should-not (string-search "old line" (buffer-string)))
    (goto-char (point-min))
    (should (equal (my/habits--logbook-lines-at-point) '("- a" "- b")))
    (my/habits--write-logbook nil)
    (should-not (string-search ":LOGBOOK:" (buffer-string)))
    (should (string-search ":END:\nWhat counts.\n" (buffer-string)))))

;; ============================================================
;; DERIVED HABITS
;; ============================================================

(ert-deftest my/habits-test-derive ()
  "A derived habit's LOGBOOK is the source's dates, newest first, at most
`my/habits-derived-cap'; it is scheduled the day after the newest with
its repeater kept.  Derived again, the file is the same."
  (my/habits-test--with-planner
    (my/habits-test--file-with (my/habits-test--habit "journal entry" ".+1d/3d" '("- stale")))
    (let* ((dates (list "2026-10-20" "2026-10-19" "2026-10-17"))
           (my/habits-derivations `(("journal entry" . ,(lambda () dates))))
           (my/habits-derived-cap 2))
      (my/habit-derive "journal entry")
      (let ((entry (my/habits-test--entry "journal entry")))
        (should (string-search (concat ":LOGBOOK:\n"
                                       (my/habits--logbook-line "2026-10-20") "\n"
                                       (my/habits--logbook-line "2026-10-19") "\n:END:")
                               entry))
        (should-not (string-search "stale" entry))
        (should-not (string-search "2026-10-17" entry)))
      (should (string-match-p "\\`2026-10-21 .* \\.\\+1d/3d\\'" (my/habits-test--scheduled "journal entry")))
      (let ((after (my/habits-test--read (my/habits--file))))
        (my/habit-derive "journal entry")
        (should (equal (my/habits-test--read (my/habits--file)) after))))))

(defun my/habits-test--drop-repeater (&rest _)
  "Remove the repeater from the SCHEDULED line of the entry at point,
as an Org that does not keep it on `org-schedule' would."
  (save-excursion
    (org-back-to-heading t)
    (when (re-search-forward "\\(SCHEDULED: <[^>]*?\\) *[.+]?\\+[0-9]+[dwmy]\\(?:/[0-9]+[dwmy]\\)?>"
                             (org-entry-end-position) t)
      (replace-match "\\1>" t))))

(ert-deftest my/habits-test-derive-repeater-put-back ()
  "The second safeguard: when `org-schedule' drops the repeater (Org 9.6
keeps it), deriving puts it back, so the entry stays a habit."
  (my/habits-test--with-planner
    (my/habits-test--file-with (my/habits-test--habit "journal entry" ".+1d/3d"))
    (let ((my/habits-derivations '(("journal entry" . (lambda () '("2026-10-20"))))))
      (advice-add 'org-schedule :after #'my/habits-test--drop-repeater)
      (unwind-protect
          (my/habit-derive "journal entry")
        (advice-remove 'org-schedule #'my/habits-test--drop-repeater)))
    (should (string-match-p "\\`2026-10-21 .* \\.\\+1d/3d\\'" (my/habits-test--scheduled "journal entry")))))

(ert-deftest my/habits-test-derive-refuses ()
  "A source with no dates, or no habit of that name: refused, the file
unchanged."
  (my/habits-test--with-planner
    (my/habits-test--file-with (my/habits-test--habit "journal entry" ".+1d" '("- kept")))
    (let ((before (my/habits-test--read (my/habits--file)))
          (my/habits-derivations '(("journal entry" . ignore) ("missing" . ignore))))
      (should-error (my/habit-derive "journal entry") :type 'user-error)
      (should-error (my/habit-derive "missing") :type 'user-error)
      (should (equal (my/habits-test--read (my/habits--file)) before)))))

(ert-deftest my/habits-test-journal-dates ()
  "The journal dates come from the journal notes' file names, newest
first; a note in the silo without the journal keyword does not count."
  (my/habits-test--with-planner
    (let* ((journal (file-name-as-directory (expand-file-name "journal" notes)))
           (my-notes-journal journal))
      (my/habits-test--write (expand-file-name "20261019T210000--2026-10-19__journal.org" journal) "x\n")
      (my/habits-test--write (expand-file-name "20261021T080000--a-free-title__journal.org" journal) "x\n")
      (my/habits-test--write (expand-file-name "20261022T080000--2026-10-22-plan__pks.org" journal) "x\n")
      (should (equal (my/habits--journal-dates) '("2026-10-21" "2026-10-19"))))))

(provide 'test-habits)
;;; test-habits.el ends here
