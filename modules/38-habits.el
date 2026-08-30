;;; 38-habits.el --- Habits: define, log without leaving the buffer, derive -*- lexical-binding: t; -*-
;;; Commentary:
;; A habit is ticked off without leaving whatever is being written.
;;
;;   f9        log a habit as done today
;;   C-u f9    log it for an earlier day
;;   C-c n H   the menu
;;
;; WHAT A HABIT IS HERE.  org-habit's model: a TODO that never goes
;; away.  Marking it DONE does not close it -- the repeater moves its
;; SCHEDULED date forward and the completion is recorded in the LOGBOOK
;; drawer.  The agenda then draws a consistency graph from those
;; records.
;;
;; So habits are not created each time they are done.  They are defined
;; once, with `my/habit-new', and afterwards only logged.  That is what
;; `my/habit-log' does, and why it is a completion prompt rather than a
;; text entry: the answer already exists.
;;
;; BINARY ONLY.  "Did I do it today" is what this module answers.
;; Quantities -- hours slept, pages read, a wellbeing score -- belong in
;; the journal front matter (05b-journal-metrics.el), which keeps
;; numbers.  Putting a number into a habit stores a tick and loses the
;; number; putting a tick into the metrics loses the streak.  Neither
;; conversion is recoverable, so the boundary is worth keeping sharp.
;;
;; DERIVED HABITS.  `my/habit-derive' rewrites a habit's LOGBOOK from
;; something already recorded elsewhere -- for the journal, from the
;; dates in the file names of the journal silo.  The file names are the
;; truth; the LOGBOOK is a cache, rewritten whole and never edited in
;; place.  Same rule as hub membership in 33-denote-hubs.el, and for the
;; same reason: a second copy of a fact drifts from the first.
;;
;; RELATION TO OTHER MODULES
;; - 37-tasks.el is required in practice, not in code: this module adds
;;   its file to `my/tasks-extra-agenda-files' and appends to that
;;   module's menu.  Without it the habit file is not in the agenda, so
;;   no graphs are drawn, and the commands still work.
;; - 37-tasks.el also sets `org-log-done' and `org-log-into-drawer',
;;   which org-habit needs.  Set here as well, because a habit file
;;   without logging records nothing and the failure is silent.
;; - 05-notes.el supplies `my/journal-file-date' for the journal
;;   derivation.  Absent, that one command reports why and does nothing.
;; - 12-transient.el, via `my/transient-append'.
;;
;; Docs: ~/.emacs.d/function_helper.org::#habits

;;; Code:

(require 'org)
(require 'org-capture)
(require 'cl-lib)
(require 'subr-x)
(require 'seq)

(declare-function my/journal-file-date "05-notes" (file))

;; ============================================================
;; OPTIONS
;; ============================================================

(defgroup my/habits nil
  "Binary habit tracking on top of org-habit."
  :group 'org)

(defcustom my/habits-file
  (expand-file-name "habits.org"
                    (if (boundp 'my/tasks-directory)
                        my/tasks-directory
                      (expand-file-name "~/notes/planner/")))
  "File holding every habit.

One file, not one per habit and not spread through the hubs: the point
of a habit list is that it is read in one go, and org-habit draws its
graphs from the agenda regardless of which file an entry came from."
  :type 'file
  :group 'my/habits)

(defcustom my/habits-heading "Habits"
  "Top-level heading in `my/habits-file' that habits live under."
  :type 'string
  :group 'my/habits)

(defcustom my/habits-repeaters
  '(("every day"          . ".+1d")
    ("every day, 3 days grace" . ".+1d/3d")
    ("every 2 days"       . ".+2d")
    ("every week"         . ".+1w")
    ("every week, 10 days grace" . ".+1w/10d")
    ("every month"        . ".+1m"))
  "Repeat periods offered when defining a habit.

`.+' and not `+': `.+1d' schedules the next occurrence one day after
it was actually done, `+1d' one day after it was previously due.  For
a habit the first is what is meant -- missing three days should not
leave three occurrences waiting.

The `/Nd' suffix is the grace period: the habit turns red only after
that many days, so an every-day habit with three days of grace stays
green through a normal week and only complains when the week was not
normal."
  :type '(alist :key-type string :value-type string)
  :group 'my/habits)

(defcustom my/habits-capture-key "h"
  "Key of the habit template inside `org-capture-templates'."
  :type 'string
  :group 'my/habits)

(defcustom my/habits-log-binding "<f9>"
  "Global key running `my/habit-log', or nil for none.

Unmodified, for the same reason as the task key: a habit gets logged
when it is remembered, which is rarely a moment with both hands free."
  :type '(choice string (const nil))
  :group 'my/habits)

(defcustom my/habits-derived-cap 40
  "How many completions a derived LOGBOOK keeps, newest first.

`org-habit-parse-todo' stops after `org-habit-preceding-days' plus
`org-habit-following-days' matches, 28 by default, and reads them from
the top of the drawer downwards.  Writing ten years of journal dates
into a drawer would therefore add nothing to the graph and a great deal
to the parse.  A small margin above the default is kept so that raising
`org-habit-preceding-days' a little does not silently truncate the
graph."
  :type 'integer
  :group 'my/habits)

(defcustom my/habits-derivations
  '(("journal entry" . my/habits--journal-dates))
  "Habits whose LOGBOOK is computed instead of typed.

Each entry maps a habit headline to a function of no arguments
returning a list of \"YYYY-MM-DD\" strings, newest first."
  :type '(alist :key-type string :value-type function)
  :group 'my/habits)

;; ============================================================
;; ORG-HABIT
;; ============================================================
;; `org-habit' is part of Org but not loaded by default.  Loading it
;; here rather than through `org-modules' keeps the dependency in the
;; module that needs it: `org-modules' is a single list that every
;; module would otherwise want to edit.

(with-eval-after-load 'org
  (require 'org-habit)
  ;; Far enough right that a headline of normal length is not
  ;; overwritten -- the graph is drawn over whatever is at that column.
  (setq org-habit-graph-column 50)
  (setq org-habit-preceding-days 21)
  (setq org-habit-following-days 7)
  ;; Habits on today's line only.  Repeated across a week's agenda they
  ;; are seven copies of one row, and the graph is drawn relative to
  ;; today in every copy anyway.
  (setq org-habit-show-habits-only-for-today t))

;; org-habit reads its history from state-change lines inside the
;; entry, so without logging there is nothing to read and the graph is
;; empty for reasons nothing reports.  37-tasks.el sets both as well;
;; repeated here so that this module is correct on its own.
(setq org-log-done 'time)
(setq org-log-into-drawer t)

;; ============================================================
;; THE FILE
;; ============================================================

(defun my/habits--file-template ()
  "Return the initial contents of `my/habits-file'."
  (concat
   "#+title: Habits\n"
   "#+category: habit\n"
   "#+startup: overview\n"
   "#+todo: TODO | DONE\n"
   "\n"
   "* " my/habits-heading "\n"
   "Binary habits: done or not done on a given day.\n"
   "Quantities belong in the journal front matter, not here.\n"))

(defun my/habits--ensure-file ()
  "Create `my/habits-file' with its heading when it does not exist."
  (unless (file-exists-p my/habits-file)
    (make-directory (file-name-directory my/habits-file) t)
    (with-temp-file my/habits-file
      (insert (my/habits--file-template)))
    (message "Created %s" my/habits-file)))

;;;###autoload
(defun my/habits-open ()
  "Open `my/habits-file', creating it if necessary."
  (interactive)
  (my/habits--ensure-file)
  (find-file my/habits-file))

(defun my/habits--buffer ()
  "Return a buffer visiting `my/habits-file'."
  (my/habits--ensure-file)
  (find-file-noselect my/habits-file))

;; ============================================================
;; FINDING HABITS
;; ============================================================

(defun my/habits--entries ()
  "Return an alist of (HEADLINE . MARKER) for every habit.

A habit is an entry with `:STYLE: habit', wherever it sits: entries
outside `my/habits-file' are found too, because `org-agenda-files' is
what org-habit itself reads and a habit filed elsewhere is still a
habit."
  (let (found)
    (dolist (file (delete-dups
                   (append (list my/habits-file)
                           (when (boundp 'org-agenda-files) org-agenda-files))))
      (when (file-exists-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (goto-char (point-min))
           (while (re-search-forward org-heading-regexp nil t)
             (when (equal "habit" (org-entry-get (point) "STYLE"))
               (push (cons (org-no-properties
                            (nth 4 (org-heading-components)))
                           (point-marker))
                     found)))))))
    (nreverse found)))

(defun my/habits--read (&optional prompt)
  "Prompt for a habit and return its marker."
  (let ((entries (my/habits--entries)))
    (unless entries
      (user-error "No habits defined yet -- create one with `my/habit-new'"))
    (cdr (assoc (completing-read (or prompt "Habit: ")
                                 (mapcar #'car entries) nil t)
                entries))))

;; ============================================================
;; DEFINING A HABIT
;; ============================================================

(defvar my/habits--pending-repeat nil
  "Repeater chosen for the habit currently being captured.")

(defun my/habits--capture-template ()
  "Return the capture template for a new habit."
  (concat "* TODO %^{Habit}"
          "\nSCHEDULED: "
          (format-time-string "<%Y-%m-%d %a ")
          my/habits--pending-repeat ">"
          "\n:PROPERTIES:"
          "\n:STYLE:    habit"
          "\n:CREATED:  " (format-time-string "[%Y-%m-%d %a %H:%M]")
          "\n:END:"
          "\n%?"))

(defun my/habits--capture-target ()
  "Put point on `my/habits-heading' in `my/habits-file'."
  (my/habits--ensure-file)
  (set-buffer (org-capture-target-buffer my/habits-file))
  (widen)
  (goto-char (point-min))
  (if (re-search-forward
       (format org-complex-heading-regexp-format
               (regexp-quote my/habits-heading))
       nil t)
      (goto-char (line-beginning-position))
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "* " my/habits-heading "\n")
    (forward-line -1)))

(with-eval-after-load 'org-capture
  (add-to-list
   'org-capture-templates
   (list my/habits-capture-key "Habit"
         'entry
         '(function my/habits--capture-target)
         '(function my/habits--capture-template)
         :empty-lines 1)
   t))

;;;###autoload
(defun my/habit-new ()
  "Define a new habit.

Asks how often it repeats, then opens a capture buffer for the name
and, optionally, a line about what counts as doing it -- which is worth
writing down, because \"did I exercise today\" stops being answerable
the week the answer is \"sort of\"."
  (interactive)
  (my/habits--ensure-file)
  (let* ((labels (mapcar #'car my/habits-repeaters))
         (answer (completing-read "Repeats: " labels nil t nil nil
                                  (car labels))))
    (setq my/habits--pending-repeat
          (cdr (assoc answer my/habits-repeaters)))
    (when (boundp 'my/capture--origin-window)
      (setq my/capture--origin-window (selected-window)))
    (org-capture nil my/habits-capture-key)))

;; ============================================================
;; THE LOGBOOK
;; ============================================================
;; org-habit reads a habit's history from state-change lines inside the
;; entry.  `org-habit-parse-todo' matches this shape:
;;
;;   - State "DONE"       from "TODO"       [2026-08-30 sob 00:00]
;;
;; and stops after `org-habit-preceding-days' plus
;; `org-habit-following-days' matches, reading from the top of the
;; drawer downwards while `org-log-states-order-reversed' holds its
;; default.  Newest first, therefore, in everything written here.
;;
;; The lines are written directly rather than by letting `org-todo' log
;; them.  `org-add-log-setup' defers the write to `post-command-hook',
;; which is after this command has returned -- so a `save-buffer' in the
;; command would save the file before the line existed, and the file
;; would sit modified until something else saved it.  Writing the line
;; here keeps the whole operation inside one command, at the cost of
;; owning one line format, which this module owns anyway for derived
;; habits.

(defun my/habits--logbook-line (date)
  "Return a LOGBOOK line recording DATE as a completion."
  (let ((time (org-time-string-to-time (concat "<" date ">"))))
    (format "- State \"DONE\"       from \"TODO\"       %s"
            (format-time-string "[%Y-%m-%d %a 00:00]" time))))

(defun my/habits--logbook-bounds ()
  "Return (BEG . END) of the LOGBOOK drawer of the entry at point, or nil.
Point must be on the headline."
  (save-excursion
    (let ((end (org-entry-end-position)))
      (when (re-search-forward "^[ \t]*:LOGBOOK:[ \t]*$" end t)
        (let ((beg (line-beginning-position)))
          (when (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
            (cons beg (1+ (line-end-position)))))))))

(defun my/habits--write-logbook (lines)
  "Replace the LOGBOOK of the entry at point with LINES.
Point must be on the headline.  An empty LINES removes the drawer."
  (let ((bounds (my/habits--logbook-bounds)))
    (when bounds
      (delete-region (car bounds) (cdr bounds))))
  (when lines
    (save-excursion
      (org-end-of-meta-data t)
      (insert ":LOGBOOK:\n" (string-join lines "\n") "\n:END:\n"))))

(defun my/habits--logbook-lines-at-point ()
  "Return the LOGBOOK lines of the entry at point, in order."
  (let ((bounds (my/habits--logbook-bounds)))
    (when bounds
      (seq-remove
       (lambda (line)
         (string-match-p "\\`[ \t]*:\\(LOGBOOK\\|END\\):[ \t]*\\'" line))
       (split-string (buffer-substring-no-properties (car bounds) (cdr bounds))
                     "\n" t)))))

;; ============================================================
;; LOGGING A HABIT
;; ============================================================

;;;###autoload
(defun my/habit-log (&optional arg)
  "Mark a habit done, without leaving the current buffer.

Asks which habit, records the completion at its own location, moves
the repeater forward and returns.  Nothing is closed and nothing
disappears: the habit reappears when it is next due.

With prefix ARG, asks for a day instead of using today.  Habits are
remembered in the morning about the evening before at least as often
as they are logged on the spot, and back-dating shifts the repeater
from that day rather than from today -- so logging yesterday's run for
a daily habit leaves it due today, not tomorrow."
  (interactive "P")
  (let* ((marker (my/habits--read "Log habit: "))
         (time (if arg (org-read-date nil t) (current-time)))
         (date (format-time-string "%Y-%m-%d" time))
         headline already)
    (org-with-point-at marker
      (org-back-to-heading t)
      (setq headline (org-no-properties (nth 4 (org-heading-components))))
      (let ((existing (my/habits--logbook-lines-at-point))
            (line (my/habits--logbook-line date)))
        (if (member line existing)
            (setq already t)
          ;; Logging is suppressed so that org writes nothing from
          ;; `post-command-hook'; the repeater still moves, which is the
          ;; part of `org-todo' that is wanted here.  `org-today' is
          ;; overridden because a `.+' repeater shifts from today, and
          ;; today is not necessarily the day being logged.
          (let ((org-log-done nil)
                (org-log-repeat nil))
            (cl-letf (((symbol-function 'org-today)
                       (lambda () (time-to-days time))))
              (org-todo 'done)))
          (org-back-to-heading t)
          (my/habits--write-logbook (cons line existing))
          (save-buffer))))
    (message (if already
                 "%s was already logged for %s"
               "Logged: %s (%s)")
             headline date)))

;;;###autoload
(defun my/habit-goto ()
  "Open the habit file at a chosen habit."
  (interactive)
  (let ((marker (my/habits--read "Go to habit: ")))
    (switch-to-buffer (marker-buffer marker))
    (widen)
    (goto-char marker)
    (org-fold-show-entry)))

;; ============================================================
;; DERIVED HABITS
;; ============================================================
;; The LOGBOOK is rewritten whole from a list of dates.  Never merged
;; with what is already there: a merge would have to decide what to do
;; about a date the source no longer reports, and there is no honest
;; answer -- the source is the truth, so anything else in the drawer is
;; stale by definition.

(defun my/habits--journal-dates ()
  "Return the dates of every journal note, newest first.

Read from file names through `my/journal-file-date' (05-notes.el),
which tests the `journal' keyword and then the date -- so a journal
note that was retitled still counts, and a note in another silo with a
date in its title does not."
  (unless (and (fboundp 'my/journal-file-date) (boundp 'my-notes-journal))
    (user-error "05-notes.el is not loaded, cannot read the journal silo"))
  (sort (delq nil
              (mapcar #'my/journal-file-date
                      (directory-files my-notes-journal t "\\.org\\'")))
        #'string>))

(defun my/habits--set-scheduled (date repeat)
  "Set SCHEDULED of the entry at point to the day after DATE, with REPEAT."
  (let* ((time (org-time-string-to-time (concat "<" date ">")))
         (next (time-add time (days-to-time 1)))
         (org-log-reschedule nil))
    (org-schedule nil (format-time-string "%Y-%m-%d" next))
    ;; `org-schedule' writes a plain timestamp; the repeater has to be
    ;; put back, or `org-habit-parse-todo' rejects the entry outright
    ;; and the habit stops being a habit.
    (save-excursion
      (org-back-to-heading t)
      (let ((end (org-entry-end-position)))
        (when (re-search-forward
               (concat org-scheduled-string " *<\\([^>]*\\)>") end t)
          (unless (string-match-p "[.+]\\+" (match-string 1))
            (replace-match (concat (match-string 1) " " repeat) t t nil 1)))))))

;;;###autoload
(defun my/habit-derive (&optional name)
  "Rebuild a derived habit's LOGBOOK from its source.

NAME defaults to a prompt over `my/habits-derivations'.  The habit must
already exist -- this command fills in a history, it does not invent a
habit to hang one on.

Safe to run repeatedly: the drawer is replaced, not appended to."
  (interactive)
  (let* ((names (mapcar #'car my/habits-derivations))
         (name (or name
                   (if (= (length names) 1)
                       (car names)
                     (completing-read "Derive: " names nil t))))
         (source (cdr (assoc name my/habits-derivations)))
         (marker (or (cdr (assoc name (my/habits--entries)))
                     (user-error
                      "No habit called `%s' -- create it first with `my/habit-new'"
                      name)))
         (dates (funcall source)))
    (unless dates
      (user-error "Source for `%s' reported no dates" name))
    (let ((kept (seq-take dates my/habits-derived-cap))
          (repeat nil))
      (org-with-point-at marker
        (org-back-to-heading t)
        (setq repeat
              (or (org-get-repeat (org-entry-get (point) "SCHEDULED"))
                  ".+1d"))
        (my/habits--write-logbook (mapcar #'my/habits--logbook-line kept))
        (my/habits--set-scheduled (car kept) repeat)
        (save-buffer))
      (message "%s: %d date(s) recorded of %d found"
               name (length kept) (length dates)))))

;; ============================================================
;; AGENDA
;; ============================================================
;; 37-tasks.el owns `org-agenda-files' and reads this list.  Adding the
;; file rather than setting the variable is what keeps that ownership
;; intact: this module never has to know what else is in the agenda.

(with-eval-after-load '37-tasks
  (add-to-list 'my/tasks-extra-agenda-files my/habits-file t)
  (when (fboundp 'my/tasks-update-agenda-files)
    (my/tasks-update-agenda-files)))

;; ============================================================
;; MENU
;; ============================================================

(transient-define-prefix my/habits-menu ()
  "Habits."
  [["Log"
    ("l" "Log habit done"       my/habit-log)
    ("L" "Log for another day"  (lambda () (interactive) (my/habit-log t)))]
   ["Define"
    ("n" "New habit"            my/habit-new)
    ("d" "Rebuild derived"      my/habit-derive)]
   ["View"
    ("f" "Open habits file"     my/habits-open)
    ("g" "Go to habit"          my/habit-goto)
    ("a" "Agenda"               org-agenda)]
   [("q" "Quit" transient-quit-one)]])

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    ;; Two ways in.  "H" on the main menu, anchored on "x", which
    ;; belongs to 12-transient itself; and inside the tasks menu when
    ;; that module is present, because habits and tasks are read
    ;; together.
    (my/transient-append 'my/notes-menu "x"
                         '("H" "Habits →" my/habits-menu))
    (my/transient-append 'my/tasks-menu "U"
                         '("h" "Habits →" my/habits-menu))))

;; ============================================================
;; KEYBINDING
;; ============================================================

(when my/habits-log-binding
  (global-set-key (kbd my/habits-log-binding) #'my/habit-log))

(provide '38-habits)
;;; 38-habits.el ends here
