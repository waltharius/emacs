;;; 37-tasks.el --- Tasks: background capture, project routing, agenda files -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes

;;; Commentary:
;; A task is written without leaving whatever is being written.  One key
;; asks three questions -- what, when, and why -- and puts the answer
;; where it belongs, then gives the window back.
;;
;;   f8            capture a task, routed automatically
;;   C-u f8        capture a task, choosing the destination by hand
;;   C-c n A       the menu
;;
;; ROUTING.  The destination is decided from the buffer the capture was
;; started in, not asked for:
;;
;;   note declares `#+project: slug'  ->  the `Tasks' heading of that
;;                                        project's hub file
;;   anything else                    ->  the `Inbox' heading of
;;                                        `my/tasks-file'
;;
;; Nothing has to be remembered at capture time, which is the point: a
;; task thought of mid-paragraph is worth writing down only if writing
;; it down costs nothing.  A prefix argument overrides the routing for
;; the case where the thought is unrelated to the text on screen.
;;
;; The echo area always says where the task landed.  Automatic routing
;; that stays silent is routing nobody trusts after the first week.
;;
;; WHY THE PROMPTS ARE HERE AND NOT IN THE TEMPLATE.  org-capture can
;; ask for a date with `%^t', but an empty answer there means today
;; rather than no date, and most tasks have no date at all.  Asking in
;; the command instead makes "no date" the default answer and turns the
;; common dates into single keystrokes.  It also fixes the order the
;; questions arrive in, which `%^' does not.
;;
;; SCHEDULED, NOT DEADLINE, by default.  "Check X in a few days" is a
;; date to start on, and SCHEDULED hides the task until then; DEADLINE
;; is a date to be finished by and starts warning in advance.  Most
;; captures are the former.  `C-c C-d' in the capture buffer sets a
;; deadline when it is really one, and `my/tasks-date-keyword' changes
;; the default.
;;
;; RELATION TO OTHER MODULES
;; - Requires nothing.  Works with 28-writing-projects absent: routing
;;   then always lands in the inbox, and the agenda holds this module's
;;   files only.
;; - Owns `org-agenda-files' for the whole configuration.  When
;;   28-writing-projects is present its hub files are included; that
;;   module's own setter defers to this one, so the two cannot fight
;;   whichever loads first.
;; - Sets `my/capture-origin-window' (06-capture.el) when it exists, so
;;   the capture buffer opens beside the note instead of over it.  Only
;;   when bound; without 06-capture, org-capture places its own window.
;; - Appends to the menus of 12-transient via `my/transient-append', so
;;   a missing 12-transient leaves the entry out instead of breaking
;;   init.
;; - 38-habits.el adds its file through `my/tasks-agenda-file-functions'.
;;   Nothing here knows about habits.
;; - 07-git.el, when present, commits the planner folder like the notes
;;   when it is a git repository (`my/tasks--repository-directories').
;;
;; THE PLANNER FOLDER is its own place, `~/projects/planner/' by default,
;; independent of the notes folder and of the silos: tasks span every
;; collection, and moving or switching the notes folder must not move
;; the task list or start an empty one.  Until 2026-10 it was
;; `planner/' inside the notes folder; the first start after the change
;; offers to copy it (`my/tasks-check-planner-move').
;;
;; Docs: ~/.emacs.d/function_helper.org::#tasks

;;; Code:

(require 'org)
(require 'org-capture)
(require 'subr-x)
(require 'seq)

;; ============================================================
;; OPTIONS
;; ============================================================

(defgroup my/tasks nil
  "Capturing and routing tasks without leaving the current buffer."
  :tag "Tasks and planner"
  :group 'mypks-tasks)

(defcustom my/tasks-directory (expand-file-name "~/projects/planner/")
  "The planner folder: the task and habit files.

Outside the notes folder and independent of it: tasks span every
collection of notes, and switching the notes folder must not switch
the task list.  Next to the writing projects, and like them its own
git repository, committed automatically when 07-git.el is loaded.  Not
a Denote silo: nothing here has an identifier and nothing here is a
note.  Not under `user-emacs-directory' either, which is configuration
rather than content and whose history should not fill with daily task
churn.

Takes effect at once; nothing is moved.  The first start after the
default moved here from the notes folder offers to copy the old
planner (`my/tasks-check-planner-move')."
  :type 'directory
  :tag "Planner folder"
  :set (my/settings-apply-on-set #'my/tasks-update-agenda-files)
  :group 'my/tasks)

(defcustom my/tasks-file "tasks.org"
  "File holding tasks that belong to no writing project.
Relative to `my/tasks-directory', or absolute.  See `my/tasks--file'."
  :type 'file
  :group 'my/tasks)

(defun my/tasks--file ()
  "Return the absolute name of `my/tasks-file'."
  (expand-file-name my/tasks-file my/tasks-directory))

(defcustom my/tasks-category "general"
  "Value written as `#+category:' into a newly created `my/tasks-file'.

Shown in the agenda's left column, where it is what distinguishes a
general task from one belonging to a project: project hubs set their
own category to the project slug."
  :type 'string
  :group 'my/tasks)

(defcustom my/tasks-heading-inbox "Inbox"
  "Heading in `my/tasks-file' receiving captures with no project.

Not the same thing as the task list: the inbox is where something
waits until it is decided what it is.  Emptying it is the weekly
review."
  :type 'string
  :group 'my/tasks)

(defcustom my/tasks-heading-active "Tasks"
  "Heading in `my/tasks-file' for filed tasks belonging to no project."
  :type 'string
  :group 'my/tasks)

(defcustom my/tasks-heading-someday "Someday"
  "Heading in `my/tasks-file' for tasks deliberately not being worked on.

Separate from the inbox so that the inbox can be emptied.  A list that
never reaches zero stops being read."
  :type 'string
  :group 'my/tasks)

(defcustom my/tasks-extra-agenda-files nil
  "Additional files `org-agenda' should read, chosen by hand.

A relative name is relative to the notes folder (`my-notes-dir'), so
it follows that folder: the agenda of another collection reads that
collection's file of the same name.  An absolute name stays where it
is.  Non-existent files are dropped rather than signalling.

For the user only.  Modules join the agenda through
`my/tasks-agenda-file-functions' instead: a module that added its file
here had it saved with the option the next time the option was saved,
as an absolute path that then outlived a move of the folder."
  :type '(repeat file)
  :group 'my/tasks)

(defvar my/tasks-agenda-file-functions nil
  "Functions of no arguments returning files `org-agenda' should read.
How other modules join the agenda without this one knowing about them.")

(defcustom my/tasks-capture-key "t"
  "Key of the task template inside `org-capture-templates'.

Only relevant when reaching the template through the generic
`org-capture' menu.  `my/task-capture' fires it directly.  Takes
effect at once."
  :type 'string
  :set (my/settings-apply-on-set #'my/tasks--register-template)
  :group 'my/tasks)

(defcustom my/tasks-capture-binding "<f8>"
  "Global key running `my/task-capture', or nil for none.

A single unmodified key on purpose.  This command is meant to be
pressed mid-sentence; anything needing two hands gets skipped and the
task gets forgotten instead.  Takes effect at once."
  :type '(choice string (const nil))
  :set (my/settings-apply-on-set #'my/tasks--apply-binding)
  :group 'my/tasks)

(defcustom my/tasks-date-keyword 'scheduled
  "Which planning line a captured date becomes.

`scheduled' hides the task until the day and is right for a reminder.
`deadline' shows it in advance with warnings and is right for
something genuinely due."
  :type '(choice (const scheduled) (const deadline))
  :group 'my/tasks)

(defcustom my/tasks-date-choices
  '(("other date" . ask)
    ("none"       . nil)
    ("today"      . "+0d")
    ("tomorrow"   . "+1d")
    ("in 3 days"  . "+3d")
    ("next week"  . "+1w")
    ("in a month" . "+1m"))
  "Answers offered for the date prompt, in order.

The order is the display order, and the first entry is also what RET
answers.  Both follow from Vertico: it always moves the default
candidate to the top, so \"first in the list\" and \"the RET answer\"
cannot be two different entries.

Each cdr is nil for no date, the symbol `ask' to open the date reader,
or a string `org-read-date' understands.  Fixed answers matter more
than they look: typing a date is slow enough that the prompt starts
getting dismissed."
  :type '(alist :key-type string :value-type sexp)
  :group 'my/tasks)

(defcustom my/tasks-record-source t
  "When non-nil, record where a capture came from as a `SOURCE' property.

A property rather than a line of body text, because a task always has
a heading of its own to hang one on.  Body text is what 06-capture.el
has to use for fragments filed under a shared heading, and that is
where the repetition comes from."
  :type 'boolean
  :group 'my/tasks)

;; ============================================================
;; STATE CARRIED FROM THE COMMAND TO THE TEMPLATE
;; ============================================================
;; org-capture decides the destination and expands the template after
;; the command has returned, so everything asked for up front has to be
;; parked somewhere both can see.  All of it is set by `my/task-capture'
;; and read once; nothing here survives a finished capture.

(defvar my/tasks--slug nil
  "Project slug the pending capture is routed to, or nil for the inbox.")

(defvar my/tasks--headline nil
  "Headline text of the pending capture.")

(defvar my/tasks--date nil
  "Planning date of the pending capture as a time value, or nil.")

(defvar my/tasks--origin nil
  "Cons of (LINK . TITLE) describing where the pending capture came from.")

(defvar my/tasks--destination nil
  "Human-readable destination of the pending capture, for the report.")

;; ============================================================
;; THE FILE
;; ============================================================

(defun my/tasks--file-template ()
  "Return the initial contents of `my/tasks-file'."
  (concat
   "#+title: Tasks\n"
   "#+category: " my/tasks-category "\n"
   "#+startup: overview\n"
   ;; The same keyword set as a project hub, so that a task refiled
   ;; from one to the other keeps its state instead of becoming plain
   ;; text that no agenda view will show.
   "#+todo: TODO NEXT INPROGRESS WAITING | DONE CANCELLED\n"
   "#+property: Effort_ALL 0:15 0:30 1:00 2:00 4:00 8:00 16:00\n"
   "#+columns: %48ITEM(Task) %TODO %3PRIORITY %8Effort(Est){:} %8CLOCKSUM(Clocked)\n"
   "\n"
   "* " my/tasks-heading-inbox "\n"
   "Captured with no project and not yet filed.\n"
   "\n"
   "* " my/tasks-heading-active "\n"
   "Tasks belonging to no writing project.\n"
   "\n"
   "* " my/tasks-heading-someday "\n"
   "Not being worked on, kept so it stops occupying attention.\n"))

(defun my/tasks--ensure-file ()
  "Create `my/tasks-file' with its headings when it does not exist."
  (let ((file (my/tasks--file)))
    (unless (file-exists-p file)
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert (my/tasks--file-template)))
      (message "Created %s" file))))

;;;###autoload
(defun my/tasks-open ()
  "Open `my/tasks-file', creating it if necessary."
  (interactive)
  (my/tasks--ensure-file)
  (find-file (my/tasks--file)))

;; ============================================================
;; ROUTING
;; ============================================================
;; Every reference to 28-writing-projects goes through these three, so
;; that the module is optional in one place rather than in ten.

(defun my/tasks--project-slugs ()
  "Return the known project slugs, or nil when there are no projects."
  (when (fboundp 'my/writing-project-slugs)
    (ignore-errors (my/writing-project-slugs))))

(defun my/tasks--current-project ()
  "Return the project slug of the current buffer, or nil."
  (when (fboundp 'my/writing-current-project)
    (ignore-errors (my/writing-current-project))))

(defun my/tasks--hub-file (slug)
  "Return the hub file of SLUG when it exists, or nil."
  (when (and slug (fboundp 'my/writing-hub-file))
    (let ((hub (ignore-errors (my/writing-hub-file slug))))
      (when (and hub (file-exists-p hub)) hub))))

(defun my/tasks--project-tasks-heading ()
  "Return the heading tasks go under inside a project hub."
  (if (boundp 'my/writing-heading-tasks)
      my/writing-heading-tasks
    "Tasks"))

(defconst my/tasks--inbox-label "— inbox (no project) —"
  "Completion candidate standing for \"no project\".")

(defun my/tasks--read-destination ()
  "Prompt for a project slug, or nil for the inbox."
  (let* ((slugs (my/tasks--project-slugs))
         (choices (cons my/tasks--inbox-label slugs))
         (answer (completing-read "Task goes to: " choices nil t nil nil
                                  (or (my/tasks--current-project)
                                      my/tasks--inbox-label))))
    (unless (equal answer my/tasks--inbox-label) answer)))

;; ============================================================
;; THE PROMPTS
;; ============================================================

(defun my/tasks--read-date ()
  "Ask when the task is for.  Return a time value, or nil for no date."
  (let* ((labels (mapcar #'car my/tasks-date-choices))
         ;; Identity sorting keeps `my/tasks-date-choices' in its own
         ;; order.  Without it Vertico sorts by history, then length,
         ;; then alphabet, which is what pushed "other date" to the
         ;; bottom.
         (table (lambda (string predicate action)
                  (if (eq action 'metadata)
                      '(metadata (display-sort-function . identity)
                                 (cycle-sort-function . identity))
                    (complete-with-action action labels string predicate))))
         (answer (completing-read
                  (format "%s (RET = %s): "
                          (capitalize (symbol-name my/tasks-date-keyword))
                          (car labels))
                  table nil t nil nil (car labels)))
         (spec (cdr (assoc answer my/tasks-date-choices))))
    (cond
     ((null spec) nil)
     ((eq spec 'ask) (org-read-date nil t))
     ;; FROM-STRING makes `org-read-date' parse without prompting.
     (t (org-read-date nil t nil nil nil spec)))))

(defun my/tasks--origin-of-buffer ()
  "Return (LINK . TITLE) for the current buffer, or nil.

A denote link when the file has an identifier, a file link otherwise,
and nothing at all for a buffer with no file -- a link to nowhere is
worse than no link, because it looks like it should work."
  (let ((file (buffer-file-name)))
    (when (and file my/tasks-record-source)
      (let* ((id (when (fboundp 'denote-retrieve-filename-identifier)
                   (ignore-errors (denote-retrieve-filename-identifier file))))
             (title (or (when (derived-mode-p 'org-mode)
                          (ignore-errors
                            (cadar (org-collect-keywords '("title")))))
                        (file-name-base file))))
        (cons (if id (format "denote:%s" id) (format "file:%s" file))
              title)))))

;; ============================================================
;; THE TEMPLATE
;; ============================================================
;; Built as a function rather than assembled from `%(...)' fragments.
;; Both forms are expanded for `%' escapes afterwards, but one string
;; built in one place is far easier to reason about than five sexps
;; whose results are concatenated by org-capture.
;;
;; CAVEAT: a literal `%' followed by an org-capture escape letter in a
;; note title (`100%TODO', say) would still be expanded.  A percent
;; sign followed by a space or a digit -- which is every real case --
;; passes through untouched.

(defun my/tasks--timestamp ()
  "Return an inactive Org timestamp for now."
  (format-time-string "[%Y-%m-%d %a %H:%M]"))

(defun my/tasks--date-line ()
  "Return the planning line for the pending capture, or an empty string."
  (if (null my/tasks--date)
      ""
    (format "\n%s: %s"
            (if (eq my/tasks-date-keyword 'deadline) "DEADLINE" "SCHEDULED")
            (format-time-string "<%Y-%m-%d %a>" my/tasks--date))))

(defun my/tasks--properties ()
  "Return the property drawer for the pending capture."
  (concat "\n:PROPERTIES:"
          "\n:CREATED:  " (my/tasks--timestamp)
          (when my/tasks--origin
            (format "\n:SOURCE:   [[%s][%s]]"
                    (car my/tasks--origin) (cdr my/tasks--origin)))
          "\n:END:\n"))

(defun my/tasks--capture-template ()
  "Return the capture template for the pending task."
  (concat "* TODO " (or my/tasks--headline "")
          (my/tasks--date-line)
          (my/tasks--properties)
          "\n%?"))

;; ============================================================
;; THE TARGET
;; ============================================================

(defun my/tasks--goto-heading (heading)
  "Move point to the start of top-level HEADING, creating it if absent.

Creating it rather than failing matters because the headings are
customisable: renaming one should not turn every capture into an
error, and an unexpected heading at the end of the file is visible and
trivially fixed."
  (widen)
  (goto-char (point-min))
  (if (re-search-forward
       (format org-complex-heading-regexp-format (regexp-quote heading))
       nil t)
      (goto-char (line-beginning-position))
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "* " heading "\n")
    (forward-line -1)))

(defun my/tasks--capture-target ()
  "Find the file and heading the pending capture belongs in.

Sets the current buffer and point, as an org-capture target function
must.  Falls back to the inbox when the routed project turns out to
have no hub file -- a project directory can be deleted while a note
still declares it, and losing the capture over that would be absurd."
  (let* ((hub (my/tasks--hub-file my/tasks--slug))
         (file (or hub (my/tasks--file)))
         (heading (if hub
                      (my/tasks--project-tasks-heading)
                    my/tasks-heading-inbox)))
    (when (and my/tasks--slug (null hub))
      (message "No hub file for `%s', filing to the inbox" my/tasks--slug)
      (setq my/tasks--slug nil))
    (unless hub (my/tasks--ensure-file))
    (setq my/tasks--destination
          (format "%s / %s"
                  (or my/tasks--slug (file-name-nondirectory (my/tasks--file)))
                  heading))
    (set-buffer (org-capture-target-buffer file))
    (my/tasks--goto-heading heading)))

(defun my/tasks--report-destination ()
  "Say in the echo area where the finished capture went.

Runs from `org-capture-after-finalize-hook'.  Silent for captures from
other templates and for aborts."
  (let ((destination my/tasks--destination))
    (setq my/tasks--destination nil
          my/tasks--slug nil
          my/tasks--headline nil
          my/tasks--date nil
          my/tasks--origin nil)
    (when (and destination (not (bound-and-true-p org-note-abort)))
      (message "Task filed under %s" destination))))

(add-hook 'org-capture-after-finalize-hook #'my/tasks--report-destination)

(defun my/tasks--register-template ()
  "Register the task template under `my/tasks-capture-key'."
  (my/settings-capture-template
   (list my/tasks-capture-key "Task"
         'entry
         '(function my/tasks--capture-target)
         '(function my/tasks--capture-template)
         :empty-lines 1
         ;; Newest first, matching every other list in this
         ;; configuration, and so that a task just written is on screen
         ;; rather than below a screenful of older ones.
         :prepend t)))

(my/tasks--register-template)

;; ============================================================
;; THE COMMAND
;; ============================================================

;;;###autoload
(defun my/task-capture (&optional arg)
  "Capture a task without leaving the current buffer.

Asks what the task is and when it is for, then opens a capture buffer
for the reason -- what X is and why it is worth checking -- which is
the part worth writing while it is still in mind.  `C-c C-c' files it
and gives the window back.

With prefix ARG, asks where it goes instead of deciding from the
buffer's `#+project:' line."
  (interactive "P")
  (my/tasks--ensure-file)
  ;; Prompt phase.  Nothing below this line is set until every question
  ;; has an answer, so C-g at any prompt leaves no partial state behind.
  (let* ((origin (my/tasks--origin-of-buffer))
         (slug (if arg
                   (my/tasks--read-destination)
                 (my/tasks--current-project)))
         (headline (string-trim (read-string "Task: ")))
         (date (progn
                 (when (string-empty-p headline)
                   (user-error "Empty task, nothing captured"))
                 (my/tasks--read-date))))
    (setq my/tasks--slug slug
          my/tasks--headline headline
          my/tasks--date date
          my/tasks--origin origin
          my/tasks--destination nil)
    ;; 06-capture.el reads this in `org-capture-mode-hook' to put the
    ;; capture buffer beside the note rather than over it.  Optional:
    ;; without that module org-capture places its own window.
    (when (boundp 'my/capture-origin-window)
      (setq my/capture-origin-window (selected-window)))
    (org-capture nil my/tasks-capture-key)))

;;;###autoload
(defun my/task-capture-here ()
  "Capture a task, choosing the destination by hand."
  (interactive)
  (my/task-capture t))

;; ============================================================
;; MOVING TASKS BETWEEN PROJECTS
;; ============================================================
;; `org-refile' already does this, including completion over
;; destinations, so nothing is reimplemented.  All that is added is a
;; narrowed target list: without it the completion offers every heading
;; in every agenda file, including the clocktable and materials
;; sections of every hub, and a list that long is not chosen from, it
;; is escaped from.

(defun my/tasks--refile-headings ()
  "Return the headings a task may be refiled to."
  (delete-dups
   (list my/tasks-heading-inbox
         my/tasks-heading-active
         my/tasks-heading-someday
         (my/tasks--project-tasks-heading))))

;;;###autoload
(defun my/task-refile ()
  "Move the task at point to another project, or out of all projects.

Offers only the task headings of the agenda files: the `Tasks' heading
of every project hub, and the three headings of `my/tasks-file'.
Works in an Org buffer and in the agenda."
  (interactive)
  (let* ((headings (my/tasks--refile-headings))
         (regexp (concat "\\`" (regexp-opt headings) "\\'"))
         (org-refile-targets `((,(my/tasks-agenda-files) :regexp . ,regexp)))
         ;; The file name is the project name, so showing it is what
         ;; makes the destinations distinguishable at all: every
         ;; candidate is called "Tasks".
         (org-refile-use-outline-path 'file)
         (org-outline-path-complete-in-steps nil))
    (if (derived-mode-p 'org-agenda-mode)
        (org-agenda-refile)
      (org-refile))))

;; ============================================================
;; AGENDA FILES
;; ============================================================
;; Owned here for the whole configuration.  28-writing-projects.el used
;; to set this variable itself and now defers; see the Agenda section of
;; that module for why the silos are deliberately not in the list.
;;
;; Non-existent files are filtered out rather than left in.  The old
;; laptop has the notes tree but not necessarily the project
;; directories, and `org-agenda' signals on a missing file rather than
;; skipping it, which would make the agenda unusable there instead of
;; merely shorter.

(defun my/tasks-agenda-files ()
  "Return every existing file `org-agenda' should read."
  (seq-filter
   #'file-exists-p
   (delete-dups
    (append (list (my/tasks--file))
            (seq-mapcat (lambda (fn) (ignore-errors (funcall fn)))
                        my/tasks-agenda-file-functions)
            (mapcar (lambda (file) (expand-file-name file my-notes-dir))
                    my/tasks-extra-agenda-files)
            (when (fboundp 'my/writing-hub-file)
              (mapcar #'my/writing-hub-file (my/tasks--project-slugs)))))))

;;;###autoload
(defun my/tasks-update-agenda-files ()
  "Set `org-agenda-files' from the task files and the project hubs."
  (interactive)
  (setq org-agenda-files (my/tasks-agenda-files))
  (when (called-interactively-p 'interactive)
    (message "org-agenda-files: %d file(s)" (length org-agenda-files))))

(defun my/tasks--refresh-agenda-files (&rest _)
  "Refresh `org-agenda-files' before the agenda is built.

A new project created during the session would otherwise stay out of
the agenda until Emacs restarted, which is exactly the sort of stale
state that gets diagnosed as \"the agenda is broken\".  The cost is one
`directory-files' call on a directory holding a handful of entries."
  (my/tasks-update-agenda-files))

(advice-add 'org-agenda :before #'my/tasks--refresh-agenda-files)

(with-eval-after-load 'org
  (my/tasks-update-agenda-files))

;; ============================================================
;; THE PLANNER FOLDER: GIT, AND THE MOVE OUT OF THE NOTES FOLDER
;; ============================================================
;; Committed like the notes: 07-git.el commits and pushes every
;; directory its sources return that is a git repository, and skips the
;; rest, so the planner joins when it has a repository and costs
;; nothing when it does not.  Inside the notes folder (the old place,
;; or a folder chosen there) it has no repository of its own and the
;; notes repository already holds it.

(defun my/tasks--repository-directories ()
  "Return the planner folder, for 07-git.el's automatic commits."
  (list my/tasks-directory))

(with-eval-after-load '07-git
  ;; `add-hook' works on any list of functions, and with a quoted
  ;; symbol needs no declaration of 07-git.el's variable here.
  (add-hook 'my/auto-commit-repository-sources
            #'my/tasks--repository-directories t))

;; The default moved from <notes>/planner/ to ~/projects/planner/ in
;; 2026-10.  At the first start that finds the old folder with task or
;; habit files and no task file in the new one, the user is asked --
;; before anything is created in the new folder, which a capture would
;; otherwise do, starting an empty task list next to the real one:
;;
;;   c  copy the old folder and start a git repository there (local; a
;;      remote is added by hand)
;;   k  copy only
;;   u  keep using the old folder (saved as `my/tasks-directory')
;;   l  ask at the next start; the old folder is used for this session
;;
;; The old folder is never changed: it stays in the notes repository
;; until deleted by hand.  The result is a report from 00-core.el
;; (`my/notes-report') when that module is loaded.

(defun my/tasks--legacy-directory ()
  "Return the planner folder of the old default, inside the notes folder."
  (file-name-as-directory (expand-file-name "planner/" my-notes-dir)))

(defun my/tasks--planner-files (dir)
  "Return the files under DIR, relative to it, without .git; nil if none."
  (when (file-directory-p dir)
    (sort (seq-remove (lambda (f) (string-match-p "\\`\\.git/" f))
                      (mapcar (lambda (f) (file-relative-name f dir))
                              (directory-files-recursively dir "" nil)))
          #'string<)))

(defun my/tasks--report (kind title lines &optional choices)
  "Report through 00-core.el's `my/notes-report', or as a message."
  (if (fboundp 'my/notes-report)
      (my/notes-report kind title lines choices)
    (message "%s: %s" title (string-join lines " "))
    nil))

(defun my/tasks--git-init (dir)
  "Make DIR a git repository with one commit.  Return nil, or a failure."
  (let ((default-directory (file-name-as-directory dir)))
    (with-temp-buffer
      (if (and (eq 0 (call-process "git" nil t nil "init" "--quiet"))
               (eq 0 (call-process "git" nil t nil "add" "-A"))
               (eq 0 (call-process "git" nil t nil "commit" "--quiet" "-m"
                                   "Planner: copied from the notes folder")))
          nil
        (format "git failed: %s" (string-trim (buffer-string)))))))

(defun my/tasks--stale-agenda-entries (legacy)
  "Return entries of `my/tasks-extra-agenda-files' inside LEGACY."
  (seq-filter (lambda (file)
                (string-prefix-p legacy (expand-file-name file my-notes-dir)))
              my/tasks-extra-agenda-files))

(defun my/tasks--copy-planner (legacy new)
  "Copy the folder LEGACY into NEW.  Return nil, or a failure message.
The copy must hold the same files as the original, .git aside."
  (make-directory new t)
  (let ((failure (with-temp-buffer
                   (unless (eq 0 (call-process "cp" nil t nil "-a" "--reflink=auto"
                                               (concat legacy ".") new))
                     (string-trim (buffer-string))))))
    (or failure
        (let ((old (my/tasks--planner-files legacy))
              (copy (my/tasks--planner-files new)))
          (unless (equal old copy)
            (format "Old: %d files.  Copy: %d files." (length old) (length copy)))))))

(defun my/tasks-check-planner-move ()
  "Offer to copy the planner from the notes folder to `my/tasks-directory'.
See the commentary above.  Runs when this module loads."
  (let* ((legacy (my/tasks--legacy-directory))
         (new (file-name-as-directory (expand-file-name my/tasks-directory)))
         (short-old (abbreviate-file-name legacy))
         (short-new (abbreviate-file-name new)))
    (cond
     ;; Nothing to move, or the new folder is already the planner.
     ((or (equal legacy new)
          (null (my/tasks--planner-files legacy))
          (file-exists-p (my/tasks--file))))
     ;; Nobody to ask: use the old folder, ask at the next start.
     ((or noninteractive (and (daemonp) (eq (selected-frame) terminal-frame)))
      (setq my/tasks-directory legacy)
      (message "Planner: still in %s this session; the move to %s waits for a frame"
               short-old short-new))
     ;; Something else is already in the new folder.
     ((my/tasks--planner-files new)
      (setq my/tasks-directory legacy)
      (my/tasks--report
       'refused (format "Planner NOT copied to %s" short-new)
       (list (format "%s already holds files, but no %s." short-new my/tasks-file)
             (format "Still using %s for this session." short-old)
             "Empty it, move the files yourself, or choose another planner folder in C-c n ,")))
     (t
      (let ((answer (car (read-multiple-choice
                          (format "Planner moves out of the notes folder: %s -> %s"
                                  short-old short-new)
                          '((?c "copy + git" "Copy, then start a local git repository there")
                            (?k "copy only" "Copy; no repository")
                            (?u "use the old folder" "Keep the planner in the notes folder (saved)")
                            (?l "ask me next time" "Use the old folder for this session"))))))
        (pcase answer
          (?u (customize-save-variable 'my/tasks-directory short-old)
              (my/tasks--report 'done "Planner stays in the notes folder"
                                (list (format "%s saved as the planner folder (C-c n ,)."
                                              short-old))))
          ((or ?c ?k)
           (let ((failure (my/tasks--copy-planner legacy new)))
             (if failure
                 (progn
                   (setq my/tasks-directory legacy)
                   (my/tasks--report
                    'failed (format "Copying the planner to %s failed" short-new)
                    (list failure
                          (format "Still using %s for this session." short-old)
                          (format "Nothing was removed.  The partial copy is in %s." short-new))))
               (let ((git-failure (and (eq answer ?c) (my/tasks--git-init new)))
                     (stale (my/tasks--stale-agenda-entries legacy)))
                 (when (eq (my/tasks--report
                            (if git-failure 'failed 'done)
                            (format "Planner copied to %s" short-new)
                            (append
                             (list (format "%d files copied; the old folder %s is untouched"
                                           (length (my/tasks--planner-files legacy)) short-old)
                                   "and still in the notes repository: delete it by hand when satisfied.")
                             (cond (git-failure (list "" git-failure
                                                      "The copy is complete; the repository was not made."))
                                   ((eq answer ?c)
                                    (list "" "A local git repository was started there, committed"
                                          "automatically like the notes.  Add a remote to push it:"
                                          (format "  git -C %s remote add origin <url>" short-new))))
                             (when stale
                               (append (list "" "Saved agenda entries pointing into the old folder:")
                                       (mapcar (lambda (f) (concat "  " f)) stale)
                                       (list "The planner's own files are read anyway; keeping these"
                                             "shows every habit and task twice."))))
                            (if stale
                                '((?r "remove them" "Remove those entries from my/tasks-extra-agenda-files (saved)")
                                  (?k "keep them" "Leave the saved agenda entries as they are"))
                              '((?o "ok" "Close the report"))))
                           ?r)
                   (customize-save-variable
                    'my/tasks-extra-agenda-files
                    (seq-remove (lambda (f) (member f stale)) my/tasks-extra-agenda-files)))))))
          (_ (setq my/tasks-directory legacy)
             (message "Planner: still in %s this session; asking again next time"
                      short-old))))))))

(defun my/tasks--check-planner-move-safely ()
  "Run `my/tasks-check-planner-move'; on an error keep the old folder.
Start-up must not stop over the planner."
  (condition-case err
      (my/tasks-check-planner-move)
    (error
     (when (my/tasks--planner-files (my/tasks--legacy-directory))
       (setq my/tasks-directory (my/tasks--legacy-directory)))
     (message "Planner: the move check failed (%s); using %s"
              (error-message-string err) my/tasks-directory))))

(my/tasks--check-planner-move-safely)

;; ============================================================
;; LOGGING
;; ============================================================
;; Closing time is recorded, and log entries go into a drawer rather
;; than into the body, where they push the text of a task down the
;; screen one line at a time.
;;
;; 38-habits.el depends on both: a habit's consistency graph is built
;; from the state-change entries in its LOGBOOK, and without logging
;; there is nothing to build it from.

(setq org-log-done 'time)
(setq org-log-into-drawer t)

;; ============================================================
;; MENU
;; ============================================================

(transient-define-prefix my/tasks-menu ()
  "Tasks and agenda."
  [["Capture"
    ("t" "New task"              my/task-capture)
    ("T" "New task (choose)"     my/task-capture-here)]
   ["Move"
    ("r" "Refile / move project" my/task-refile)]
   ["View"
    ("a" "Agenda"                org-agenda)
    ("f" "Open tasks file"       my/tasks-open)
    ("U" "Update agenda files"   my/tasks-update-agenda-files)]
   ["Clock"
    ("i" "Clock in"              org-clock-in)
    ("o" "Clock out"             org-clock-out)
    ("g" "Goto clock"            org-clock-goto)]
   [("q" "Quit" transient-quit-one)]])

;; Anchored on "x", which belongs to 12-transient itself.  Anchoring on
;; an entry contributed by another feature module would couple this one
;; to that module's presence.
(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-menu "x"
                       '("A" "Agenda & tasks →" my/tasks-menu)))

;; ============================================================
;; KEYBINDING
;; ============================================================

(defun my/tasks--apply-binding ()
  "Bind `my/tasks-capture-binding' to `my/task-capture'."
  (my/settings-bind-key #'my/task-capture my/tasks-capture-binding))

(my/tasks--apply-binding)

;; "C-c a" is the agenda key in every piece of Org documentation, every
;; tutorial and every answer on the subject.  It was a prefix for
;; typing-analytics until 2026-08; those four commands moved to "C-c y"
;; (14-typing-analytics.el), which is the right way round -- the agenda
;; is opened every morning and keyfreq a few times a year.
(global-set-key (kbd "C-c a") #'org-agenda)

(provide '37-tasks)
;;; 37-tasks.el ends here
