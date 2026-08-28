;;; 33-denote-hubs.el --- Collect notes under Denote hub notes -*- lexical-binding: t; -*-
;;; Commentary:
;; A HUB is an ordinary Denote note carrying the `hub' keyword in the
;; `__keyword' component of its file name.  Its body is a plain Org list
;; of links to the notes that belong to it, each with a one-line
;; description:
;;
;;   - [[denote:20260828T101500][Title of the note]] — why it is here
;;
;; One command, `my/denote-add-to-hub', adds the note in the current
;; buffer to a hub of one's choosing, creating the hub first when asked.
;; Entries are kept in identifier order, oldest first: a hub out of order
;; is sorted on the way, before the new entry is placed.
;; Its prompt puts the hubs that already list the note at the top, with
;; the description they give it shown beside them, so choosing one of
;; those edits that description in place instead of adding the note a
;; second time.
;;
;; Membership is DERIVED, never stored.  A note is in a hub because the
;; hub links to it, and that link is the only record.  A `#+hubs:' field
;; in the note would be a second copy of the same fact, and deleting a
;; line from a hub would silently make it wrong -- the same reason
;; Denote keeps no backlink field in front matter.
;;
;; `my/denote-hub-list-for-note' answers the same question on its own.
;;
;; Hubs are found by KEYWORD, never by file content: the scan combines
;; `denote-directory-files' with `denote-extract-keywords-from-path',
;; both of which read file names only, so no note is opened to answer
;; the question "is this a hub".  Only the hubs themselves are then read
;; to work out membership -- tens of files rather than the whole
;; collection, which is what makes it affordable on every invocation.
;; `denote-get-backlinks' would answer the membership question too, but
;; it greps the entire notes tree and returns only the file, not the
;; line, and the line is where the description lives.
;;
;; DEPENDENCIES
;; - denote 4.1 or later.  Every helper used here is public API of that
;;   release: `denote-directory-files',
;;   `denote-extract-keywords-from-path',
;;   `denote-retrieve-filename-identifier',
;;   `denote-retrieve-front-matter-title-value',
;;   `denote-filetype-heuristics' and `denote' itself, which returns the
;;   path of the note it created.
;; - 00-core.el for `my-notes-pks', the default location of new hubs.
;; - 12-transient.el is OPTIONAL: the menu entry is added through
;;   `my/transient-append', which reports and skips instead of
;;   signalling, so removing the menu module leaves this one working
;;   under M-x.
;;
;; NOT RELATED to the project hubs of 28-writing-projects.el.  Those are
;; scaffolding files under ~/projects/ and are not Denote notes at all.
;; The two namespaces are kept apart on purpose -- `my/writing--hub-*'
;; there, `my/denote-hub--*' here -- because a shared prefix is how two
;; modules end up redefining each other's helpers.
;;
;; Docs: ~/.emacs.d/function_helper.org::#fn-my-denote-add-to-hub

;;; Code:

(require 'denote)
(require 'seq)
(require 'subr-x)

(defgroup my-denote-hubs nil
  "Hub notes gathering links to other Denote notes."
  :group 'convenience)

(defcustom my/denote-hub-keyword "hub"
  "Denote keyword that marks a note as a hub.
Matched against the `__keyword' component of the file name."
  :type 'string
  :group 'my-denote-hubs)

(defcustom my/denote-hub-directory my-notes-pks
  "Silo in which `my/denote-add-to-hub' creates a new hub note.
Assumption: a new hub goes to the pks silo without asking, because the
only prompt specified for hub creation is the title."
  :type 'directory
  :group 'my-denote-hubs)

(defconst my/denote-hub-new-label "[Nowy HUB]"
  "Completion candidate standing for \"create a new hub instead\".")

;; Register the keyword so it completes in `denote-rename-file-keywords'
;; and friends before the first hub exists, the same way
;; 19-philosophy-notes.el registers its own vocabulary.
(with-eval-after-load 'denote
  (add-to-list 'denote-known-keywords my/denote-hub-keyword))

;; ============================================================
;; FINDING HUBS
;; ============================================================

(defun my/denote-hub--hub-p (file)
  "Return non-nil when FILE's name carries `my/denote-hub-keyword'."
  (and (member my/denote-hub-keyword
               (denote-extract-keywords-from-path file))
       t))

(defun my/denote-hub-files ()
  "Return every Denote note whose file name carries the hub keyword.
Text files only: an attachment can hold a keyword but cannot hold a
list of links."
  (seq-filter #'my/denote-hub--hub-p
              (denote-directory-files nil nil :text-only)))

(defun my/denote-hub--title (file)
  "Return the `#+title:' value of FILE, or its file name if it has none.
Denote reads a live buffer visiting FILE in preference to the copy on
disk, so an unsaved title change is picked up."
  (or (denote-retrieve-front-matter-title-value
       file (denote-filetype-heuristics file))
      (file-name-base file)))

;; ============================================================
;; READING A HUB: which hubs already list a note, and how
;; ============================================================
;; Membership is derived, never stored.  A note is "in" a hub because
;; the hub links to it, and that link is the only record -- the same
;; reason Denote keeps no backlink field in front matter.  A `#+hubs:'
;; keyword in the note would be a second copy of the same fact, and
;; deleting a line from a hub would silently make it wrong.
;;
;; Only hub notes are read to answer the question: tens of files rather
;; than the whole collection, which is what makes it affordable on
;; every invocation of `my/denote-add-to-hub'.  `denote-get-backlinks'
;; would also answer it, but it greps the entire notes tree and returns
;; only the file, not the entry -- and the entry is where the
;; description lives.
;;
;; AN ENTRY IS ONE ORG LIST ITEM, possibly several lines long:
;;
;;   - [[denote:20230825T...][2023-08-25 Journal]] — first paragraph
;;     of the description, wrapped by hand
;;
;;     second paragraph
;;
;; Continuation lines are indented by `my/denote-hub-entry-indent'.
;; That is not cosmetic.  Org ends a list item at the first non-blank
;; line in column zero, so an unindented continuation line after a blank
;; line is a separate paragraph that merely looks attached -- it would
;; export outside the list, and this code would have no way of telling
;; where one entry stops and the next author's prose begins.  Indented,
;; the extent of an entry is unambiguous and editing one in place is
;; safe.

(defconst my/denote-hub-entry-separator " — "
  "String written between a hub entry's link and its description.")

(defconst my/denote-hub-entry-indent "  "
  "Indentation of the continuation lines of a multi-line hub entry.
Two spaces, so that the text lines up under the first line's text
rather than under its bullet.")

(defun my/denote-hub--file-contents (file)
  "Insert the contents of FILE into the current buffer.
A live buffer visiting FILE wins over the copy on disk, so a hub being
edited reports what it currently says rather than what was last saved."
  (if-let* ((buffer (find-buffer-visiting file)))
      (insert-buffer-substring buffer)
    (insert-file-contents file)))

(defun my/denote-hub--blank-line-p ()
  "Return non-nil when the current line holds nothing but whitespace."
  (looking-at-p "[ \t]*$"))

(defun my/denote-hub--entry-end ()
  "Return the end position of the hub entry whose first line holds point.

The entry runs to the last indented line that still belongs to it.  It
stops at the first non-blank line in column zero -- the next entry, a
heading, or ordinary prose -- and at a second consecutive blank line,
which is where Org ends a plain list regardless of indentation.
Trailing blank lines are left out, so replacing an entry does not eat
the space below it."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (blanks 0))
      (forward-line 1)
      (catch 'done
        (while (not (eobp))
          (cond
           ((my/denote-hub--blank-line-p)
            (setq blanks (1+ blanks))
            (when (> blanks 1) (throw 'done nil)))
           ((looking-at-p "[ \t]")
            (setq blanks 0)
            (setq end (line-end-position)))
           (t (throw 'done nil)))
          (forward-line 1)))
      end)))

(defun my/denote-hub--entry-description (entry)
  "Return the description part of hub ENTRY text, or nil when it has none.

ENTRY may span several lines; the indentation added when it was written
is removed again, so what comes back is what was typed at the prompt.

Liberal on purpose.  What is in the file is whatever was written there,
possibly edited by hand since: everything after the closing brackets of
the link counts as the description, with a leading dash of any kind
removed."
  (when entry
    (let* ((lines (split-string entry "\n"))
           (first (car lines))
           (head (when (string-match "\\]\\][ \t]*\\(.*\\)\\'" first)
                   (string-trim
                    (replace-regexp-in-string
                     "\\`[-–—][ \t]*" "" (string-trim (match-string 1 first))))))
           (rest (mapcar (lambda (line)
                           (replace-regexp-in-string "\\`[ \t]\\{1,2\\}" "" line))
                         (cdr lines)))
           (text (string-trim-right (string-join (cons (or head "") rest) "\n"))))
      (unless (string-empty-p (string-trim text)) text))))

(defun my/denote-hub--first-line (text)
  "Return the first line of TEXT, marked with an ellipsis when more follows.
Used where a description has to fit on one line: a completion annotation
or an echo-area report."
  (when text
    (let ((lines (split-string text "\n" t "[ \t]*")))
      (if (cdr lines)
          (concat (car lines) " …")
        (car lines)))))

(defun my/denote-hub--entries (hub identifier)
  "Return the full text of every entry in HUB linking to IDENTIFIER.
More than one means the note was added to that hub twice."
  (let ((needle (concat "denote:" identifier))
        (entries nil))
    (with-temp-buffer
      (my/denote-hub--file-contents hub)
      (goto-char (point-min))
      (while (search-forward needle nil t)
        (beginning-of-line)
        (let ((end (my/denote-hub--entry-end)))
          (push (buffer-substring-no-properties (point) end) entries)
          ;; Continue past the whole entry, so a second link inside it
          ;; does not report it twice.
          (goto-char end)
          (forward-line 1))))
    (nreverse entries)))

(defun my/denote-hub-membership (&optional file)
  "Return an alist of (HUB-FILE . ENTRIES) for hubs that list FILE.
FILE defaults to the file of the current buffer.  Hubs that do not
mention it are absent from the result, so a nil return means the note
belongs to no hub."
  (let* ((file (or file (buffer-file-name)
                   (user-error "This buffer is not visiting a file")))
         (identifier (or (denote-retrieve-filename-identifier file)
                         (user-error "Not a Denote note (no identifier in the file name)")))
         (result nil))
    (dolist (hub (my/denote-hub-files) (nreverse result))
      (when-let* ((entries (my/denote-hub--entries hub identifier)))
        (push (cons hub entries) result)))))

(defun my/denote-hub-list-for-note ()
  "Report in the echo area which hubs list the current note, and how.

Only the first line of each description is shown, since a multi-line one
would push the rest out of the echo area.

The same information appears beside the candidates of
`my/denote-add-to-hub'; this command exists for the times when the
question is asked on its own, without intending to add anything."
  (interactive)
  (if-let* ((membership (my/denote-hub-membership)))
      (message "%s"
               (mapconcat
                (lambda (cell)
                  (format "%s: %s"
                          (my/denote-hub--title (car cell))
                          (or (my/denote-hub--first-line
                               (my/denote-hub--entry-description (cadr cell)))
                              "(no description)")))
                membership "\n"))
    (message "This note is not listed in any hub")))

;; ============================================================
;; WRITING INTO A HUB
;; ============================================================

(defun my/denote-hub--indent-continuation (description)
  "Return DESCRIPTION with every line after the first indented.
Blank lines are left genuinely blank rather than filled with the
indentation, which is what Org wants inside a list item and what keeps
the file free of trailing whitespace."
  (let ((lines (split-string description "\n")))
    (concat
     (car lines)
     (mapconcat (lambda (line)
                  (concat "\n"
                          (if (string-empty-p (string-trim line))
                              ""
                            (concat my/denote-hub-entry-indent line))))
                (cdr lines) ""))))

(defun my/denote-hub--entry (identifier title description)
  "Return the hub list item linking to IDENTIFIER and shown as TITLE.

DESCRIPTION follows an em dash and may span several lines; its
continuation lines are indented so the whole thing stays one Org list
item.  Assumption: an empty description produces the link alone rather
than a trailing dash.

The description is inserted as typed.  Emphasis is the author\'s
business here, unlike a hub\'s own description -- see
`my/denote-hub--bold'."
  (let ((description (string-trim-right description)))
    (if (string-empty-p (string-trim description))
        (format "- [[denote:%s][%s]]" identifier title)
      (format "- [[denote:%s][%s]]%s%s"
              identifier title my/denote-hub-entry-separator
              (my/denote-hub--indent-continuation description)))))

(defun my/denote-hub--bold (text)
  "Return TEXT wrapped in Org emphasis markers, or TEXT if it already is.
Applied to a hub\'s own description, which is a heading for everything
below it and reads as one.  Entry descriptions are left alone: marking
those up is the author\'s business."
  (let ((text (string-trim text)))
    (cond
     ((string-empty-p text) text)
     ((and (string-prefix-p "*" text) (string-suffix-p "*" text)) text)
     (t (format "*%s*" text)))))

(defmacro my/denote-hub--with-hub (file &rest body)
  "Run BODY in a buffer visiting FILE with point restored, then save it.

A buffer already visiting FILE is reused and left open; a buffer opened
here is killed again afterwards, so working through hubs does not
accumulate buffers for hubs that were not being edited.

The value of BODY is returned, which is how `my/denote-hub-add-entry\'
reports what it had to do to the hub before inserting.

The cleanup runs through `unwind-protect\', so a BODY that signals --
`my/denote-hub-sort-entries\' refuses a hub with prose between its
entries -- does not leak the buffer it opened.  The one case where the
buffer is deliberately left behind is a BODY that modified it and then
failed: killing it would discard the half-finished edit, and leaving it
visible is what lets it be inspected."
  (declare (indent 1) (debug (form body)))
  `(let* ((my-hub--file ,file)
          (my-hub--existing (find-buffer-visiting my-hub--file))
          (my-hub--buffer (or my-hub--existing
                              (find-file-noselect my-hub--file))))
     (unwind-protect
         (with-current-buffer my-hub--buffer
           (prog1 (save-excursion ,@body)
             (save-buffer)))
       (unless (or my-hub--existing
                   (buffer-modified-p my-hub--buffer))
         (kill-buffer my-hub--buffer)))))

(defun my/denote-hub--append (file text)
  "Append TEXT at the end of FILE, one blank line below its content."
  (my/denote-hub--with-hub file
    (goto-char (point-max))
    ;; Trailing whitespace is removed first so the separator is exactly
    ;; one blank line, whatever the file happened to end with.
    (skip-chars-backward " \t\n")
    (delete-region (point) (point-max))
    (insert "\n\n" text "\n")))

(defun my/denote-hub--replace-entry (file identifier entry)
  "Replace the entry of FILE linking to IDENTIFIER with ENTRY.

The whole entry goes, continuation lines included, and ENTRY is written
where it stood, so editing a description does not move the entry down
the hub or leave the tail of the old one behind."
  (my/denote-hub--with-hub file
    (goto-char (point-min))
    (if (search-forward (concat "denote:" identifier) nil t)
        (progn
          (beginning-of-line)
          (delete-region (point) (my/denote-hub--entry-end))
          (insert entry))
      (user-error "Entry for %s is no longer in %s" identifier file))))

;; ============================================================
;; ENTRY ORDER
;; ============================================================
;; Entries are kept in identifier order, oldest at the top, so a hub
;; reads as a chronology and a new entry lands where it belongs rather
;; than always at the bottom.  Adding an entry sorts the hub first when
;; it is not already sorted, since "before the first entry that is
;; newer" only means anything in a sorted list; a hub already in order
;; is left untouched.
;;
;; This costs no file access beyond the hub itself.  The identifier is
;; already written into the link -- `denote:20230825T090000' -- so
;; ordering the entries of a hub means comparing strings that are
;; already in the buffer.  None of the linked notes is opened, and the
;; hub is visited through `my/denote-hub--with-hub', which kills the
;; buffer again unless it was already open.  Sorting every hub in the
;; collection would still hold one buffer at a time.
;;
;; Identifiers are fixed-width YYYYMMDDTHHMMSS, so lexicographic order
;; is chronological order and no date parsing is needed.
;;
;; SCOPE: the entries considered are those below the last Org heading,
;; or all of them in a hub with no headings.  That is the same place
;; appending has always written to, so a hub split into sections keeps
;; its sections; only the position within the last one changes.

(defun my/denote-hub--entry-identifier (entry)
  "Return the Denote identifier that the first line of ENTRY links to.
Nil when the line has no `denote:' link, which is how a hand-written
list item that is not an entry gets left out of the ordering."
  (when (and entry (string-match "denote:\\([^]:[]+\\)" entry))
    (match-string 1 entry)))

(defun my/denote-hub--section-start ()
  "Return the position where the last section of the current hub begins.
The line after the last Org heading, or `point-min' when there is none."
  (save-excursion
    (goto-char (point-max))
    (if (re-search-backward "^\\*+ " nil t)
        (line-beginning-position 2)
      (point-min))))

(defun my/denote-hub--entry-positions ()
  "Return (IDENTIFIER BEG END) for each entry of the current hub's last section.
In file order.  BEG is the start of the entry's first line, END the end
of its last, as `my/denote-hub--entry-end' determines it."
  (save-excursion
    (goto-char (my/denote-hub--section-start))
    (let ((result nil))
      (while (re-search-forward "^- +\\[\\[denote:\\([^]:[]+\\)" nil t)
        (let* ((identifier (match-string-no-properties 1))
               (beg (line-beginning-position))
               (end (progn (goto-char beg) (my/denote-hub--entry-end))))
          (push (list identifier beg end) result)
          (goto-char end)))
      (nreverse result))))

(defun my/denote-hub--sorted-p (entries)
  "Return non-nil when ENTRIES are already in identifier order.
Cheap: the identifiers were collected by the same scan that produced
ENTRIES, so checking costs no reading and a hub already in order is
never rewritten."
  (let ((identifiers (mapcar #'car entries)))
    (equal identifiers (sort (copy-sequence identifiers) #'string<))))

(defun my/denote-hub--prose-between (entries)
  "Return the line number of the first non-blank text between ENTRIES, or nil.

Sorting rewrites the whole run of entries, so a paragraph written
between two of them would be swept along and end up somewhere else.
Nothing in the file says which entries it was commenting on, so the
only honest answers are to leave the hub alone or to refuse -- which of
the two is the caller's decision."
  (let ((cursor (nth 1 (car entries)))
        (found nil))
    (dolist (entry entries found)
      (unless found
        (let ((gap (buffer-substring-no-properties cursor (nth 1 entry))))
          (unless (string-match-p "\\`[ \t\n]*\\'" gap)
            (setq found (line-number-at-pos cursor))))
        (setq cursor (nth 2 entry))))))

(defun my/denote-hub--sort-region (entries)
  "Rewrite ENTRIES of the current buffer in identifier order, oldest first.
Returns how many were rewritten.  The caller has already established
that nothing but blank lines separates them."
  (let* ((beg (nth 1 (car entries)))
         (end (nth 2 (car (last entries))))
         (texts (mapcar (lambda (entry)
                          (cons (car entry)
                                (buffer-substring-no-properties
                                 (nth 1 entry) (nth 2 entry))))
                        entries))
         (sorted (sort (copy-sequence texts)
                       (lambda (a b) (string< (car a) (car b))))))
    (delete-region beg end)
    (goto-char beg)
    (insert (mapconcat #'cdr sorted "\n\n"))
    (length entries)))

(defun my/denote-hub-add-entry (file entry identifier)
  "Insert ENTRY into FILE at the position IDENTIFIER belongs to.

Puts the hub's existing entries in order first when they are not in it
already, because inserting \"before the first entry that is newer\" only
means anything in a sorted list: in a jumbled one it is whichever newer
entry happens to come first in the file, which is no position at all.
A hub already in order is not rewritten -- the check costs nothing,
since the identifiers come from the scan that has to happen anyway.

Returns what it had to do:

  `inserted' -- the hub was in order, the entry went in place
  `sorted'   -- the hub was out of order, was sorted, then the entry
                went in place
  `appended' -- the hub could not be sorted because prose sits between
                its entries, so the entry went to the end

The last case never refuses.  Adding a link is not the moment to make
someone reformat a hub, and the end is at least a predictable place;
`my/denote-hub-sort-entries' will name the offending line when asked."
  (my/denote-hub--with-hub file
    (let ((entries (my/denote-hub--entry-positions))
          (status 'inserted))
      (when (and (cdr entries) (not (my/denote-hub--sorted-p entries)))
        (if (my/denote-hub--prose-between entries)
            (setq status 'appended)
          (my/denote-hub--sort-region entries)
          ;; Positions are stale after the rewrite.
          (setq entries (my/denote-hub--entry-positions))
          (setq status 'sorted)))
      (let ((successor (unless (eq status 'appended)
                         (seq-find (lambda (e) (string< identifier (car e)))
                                   entries))))
        (if successor
            (progn
              (goto-char (nth 1 successor))
              (insert entry "\n\n"))
          (goto-char (point-max))
          ;; Trailing whitespace is removed first so the separator is
          ;; exactly one blank line, whatever the file happened to end
          ;; with.
          (skip-chars-backward " \t\n")
          (delete-region (point) (point-max))
          (insert "\n\n" entry "\n")))
      status)))

(defun my/denote-hub-sort-entries (&optional file)
  "Put the entries of a hub in identifier order, oldest first.

FILE defaults to the hub in the current buffer; called from anywhere
else, it prompts for one.  Only the entries below the last Org heading
are touched.

Rarely needed: `my/denote-add-to-hub' does this by itself before
inserting.  This command exists to sort a hub without adding anything to
it, and to report the reason when the automatic sort declines -- prose
between two entries, whose line number it names.  There it refuses,
where adding a link merely appends."
  (interactive)
  (let ((file (or file
                  (and (buffer-file-name)
                       (my/denote-hub--hub-p (buffer-file-name))
                       (buffer-file-name))
                  (let ((candidates (mapcar (lambda (f)
                                              (cons (my/denote-hub--title f) f))
                                            (my/denote-hub-files))))
                    (unless candidates (user-error "No hub notes found"))
                    (cdr (assoc (completing-read "Sort HUB: " candidates nil t)
                                candidates))))))
    (my/denote-hub--with-hub file
      (let ((entries (my/denote-hub--entry-positions)))
        (cond
         ((< (length entries) 2)
          (message "Nothing to sort in %s" (my/denote-hub--title file)))
         ((my/denote-hub--sorted-p entries)
          (message "%s is already in order (%d entries)"
                   (my/denote-hub--title file) (length entries)))
         ((my/denote-hub--prose-between entries)
          (user-error "Text between entries on line %d of %s; sort it by hand"
                      (my/denote-hub--prose-between entries)
                      (my/denote-hub--title file)))
         (t
          (message "Sorted %d entries in %s"
                   (my/denote-hub--sort-region entries)
                   (my/denote-hub--title file))))))))

;; ============================================================
;; THE HUB PROMPT
;; ============================================================

(defvar my/denote-hub-description-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-map)
    (define-key map (kbd "S-<return>") #'my/denote-hub-minibuffer-newline)
    (define-key map (kbd "M-<return>") #'my/denote-hub-minibuffer-newline)
    map)
  "Keymap for the description prompts of `my/denote-add-to-hub'.
Like `minibuffer-local-map' but with a way to break the line, since RET
has to keep meaning \"done\".  `C-q C-j' does the same thing with no
binding at all and works on a terminal, where S-RET and RET arrive as
the same key.")

(defun my/denote-hub-minibuffer-newline ()
  "Insert a newline in the minibuffer instead of accepting the input."
  (interactive)
  (insert "\n"))

(defun my/denote-hub--read-description (prompt &optional initial)
  "Read a possibly multi-line description with PROMPT and INITIAL contents.
S-RET breaks the line, RET accepts.  Trailing whitespace is dropped, so
a stray line break at the end does not become part of the entry."
  (string-trim-right
   (read-from-minibuffer prompt initial my/denote-hub-description-map)))

(defun my/denote-hub--annotation (entries)
  "Return the text shown beside a hub that already lists the note.
ENTRIES are its entry texts there, so the first line of the first
description is what the annotation reports -- an annotation has one line
to work with."
  (let ((description (my/denote-hub--first-line
                      (my/denote-hub--entry-description (car entries))))
        (count (length entries)))
    (propertize
     (concat "  already listed"
             (when description (concat ": " description))
             (when (> count 1) (format "  [%d entries]" count)))
     'face 'completions-annotations)))

(defun my/denote-hub--completion-table (candidates annotations)
  "Return a completion table over CANDIDATES with ANNOTATIONS beside them.

Two pieces of metadata do the work.  `identity' as the sort function
keeps the given order, which is what puts `my/denote-hub-new-label'
first and the hubs already listing the note next; without it the
completion frontend files them alphabetically.  The annotation
function reads ANNOTATIONS, a hash of candidate to text, and returns nil
for candidates that have none."
  (lambda (string predicate action)
    (if (eq action 'metadata)
        `(metadata
          (display-sort-function . identity)
          (cycle-sort-function . identity)
          (annotation-function
           . ,(lambda (candidate) (gethash candidate annotations))))
      (complete-with-action action candidates string predicate))))

(defun my/denote-hub--prompt-data (membership)
  "Return (CANDIDATES FILES ANNOTATIONS) for the hub prompt.

CANDIDATES are labels in display order: `my/denote-hub-new-label'
first, then the hubs that already list the note, then the rest.  FILES
maps a label to its hub file, ANNOTATIONS maps a label to the text shown
beside it.  MEMBERSHIP is the return value of
`my/denote-hub-membership'.

Creating a hub comes first because the list only grows, and scrolling
past a hundred hubs to reach it would be the one operation that gets
harder the longer the system is used.  It is also the only candidate
starting with a bracket, so typing `[' selects it."
  (let* ((hubs (my/denote-hub-files))
         (listed (seq-filter (lambda (f) (assoc f membership)) hubs))
         (rest (seq-remove (lambda (f) (assoc f membership)) hubs))
         (files (make-hash-table :test #'equal))
         (annotations (make-hash-table :test #'equal))
         (labels nil))
    (dolist (file (append listed rest))
      (let ((label (format "%s (%s)"
                           (my/denote-hub--title file)
                           (or (denote-retrieve-filename-identifier file) "?"))))
        (push label labels)
        (puthash label file files)
        (when-let* ((entry (assoc file membership)))
          (puthash label (my/denote-hub--annotation (cdr entry)) annotations))))
    (list (cons my/denote-hub-new-label (nreverse labels))
          files annotations)))

;; ============================================================
;; COMMAND
;; ============================================================

(defun my/denote-add-to-hub ()
  "Add a link to the current note to a hub note, or edit an existing one.

The prompt offers `my/denote-hub-new-label' first, then the hubs that
already link to this note, with their current description shown beside
them, then the rest.  Membership is read from the hubs themselves rather
than recorded in the note, so there is nothing to keep in step and
nothing that can go stale.

Choosing a hub that does not list the note yet asks for a description
and inserts

  - [[denote:IDENTIFIER][TITLE]] — DESCRIPTION

among its entries, before the first one with a newer identifier, so the
hub stays in chronological order with the newest at the bottom.  A hub
whose entries are out of order is sorted first, so the position means
something; a hub already in order is not rewritten.  IDENTIFIER and
TITLE belong to the current note, and TITLE is its
`#+title:' value verbatim: a note whose title already contains its
signature contributes it, and no signature is added to a note that has
none.

The description may run to several lines: S-RET breaks the line at the
prompt, RET accepts.  Continuation lines are indented on the way in and
de-indented on the way out, so the entry stays one Org list item and the
prompt still shows what was typed.  The text is inserted as written --
marking it up is the author's business.

Choosing a hub that already lists the note re-asks for the description
with the current one filled in, and rewrites the entry where it stands.
This is how a duplicate entry is avoided: adding a note twice is not
something the command can do.

Choosing `my/denote-hub-new-label' creates a note in
`my/denote-hub-directory' with the hub keyword and the title given at
the prompt.  Its own one-line description becomes the first line of the
body, in bold, since it is a heading for everything below it; the link
entry goes one blank line under it."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "This buffer is not visiting a file"))
    (let ((identifier (denote-retrieve-filename-identifier file))
          (title (my/denote-hub--title file)))
      (unless identifier
        (user-error "Not a Denote note (no identifier in the file name)"))
      (pcase-let* ((membership (my/denote-hub-membership file))
                   (`(,candidates ,files ,annotations)
                    (my/denote-hub--prompt-data membership))
                   (choice (completing-read
                            "HUB: "
                            (my/denote-hub--completion-table candidates annotations)
                            nil t))
                   (hub (gethash choice files))
                   (entries (cdr (assoc hub membership))))
        (cond
         ;; Already listed: edit the description in place.
         (entries
          (when (cdr entries)
            (user-error "%s lists this note %d times; fix it by hand first"
                        (my/denote-hub--title hub) (length entries)))
          ;; INITIAL-CONTENTS rather than a default value: the point of
          ;; this prompt is to amend existing text, and a default can
          ;; only be accepted or discarded.
          (let ((description (my/denote-hub--read-description
                              "Entry description (S-RET for a new line): "
                              (or (my/denote-hub--entry-description (car entries))
                                  ""))))
            (my/denote-hub--replace-entry
             hub identifier (my/denote-hub--entry identifier title description))
            (message "Updated entry in hub: %s" (my/denote-hub--title hub))))
         ;; An existing hub that does not list the note yet.
         (hub
          (let ((entry (my/denote-hub--entry
                        identifier title
                        (my/denote-hub--read-description
                         "Entry description (S-RET for a new line): "))))
            (pcase (my/denote-hub-add-entry hub entry identifier)
              ('sorted
               (message "Added to hub: %s (its entries were out of order and have been sorted)"
                        (my/denote-hub--title hub)))
              ('appended
               (message "Added at the end of %s: prose between its entries prevents sorting, see my/denote-hub-sort-entries"
                        (my/denote-hub--title hub)))
              (_
               (message "Added to hub: %s" (my/denote-hub--title hub))))))
         ;; New hub.  Every prompt is answered before anything is
         ;; created, so C-g leaves no half-built note behind.
         (t
          (let ((hub-title (string-trim (read-string "New HUB title: "))))
            (when (string-empty-p hub-title)
              (user-error "A hub needs a title"))
            ;; The hub's own description stays a single line on purpose:
            ;; it is wrapped in Org emphasis markers, which do not carry
            ;; across a blank line.
            (let* ((hub-description (my/denote-hub--bold
                                     (read-string "HUB description: ")))
                   (entry (my/denote-hub--entry
                           identifier title
                           (my/denote-hub--read-description
                            "Entry description (S-RET for a new line): ")))
                   ;; `denote' returns the path of the note it created
                   ;; and visits it.  Assumption: the new hub is left
                   ;; open, which is Denote's own behaviour and the
                   ;; simplest outcome.
                   (new-hub (let ((denote-directory my/denote-hub-directory))
                              (denote hub-title (list my/denote-hub-keyword)))))
              (my/denote-hub--append
               new-hub (if (string-empty-p hub-description)
                           entry
                         (concat hub-description "\n\n" entry)))
              (message "Created hub: %s" hub-title)))))))))

;; ============================================================
;; MENU INTEGRATION  (C-c n i H)
;; ============================================================
;; Anchored on "L" (Linked note), which 12-transient.el defines itself.
;; Anchoring on a key contributed by another optional module is how the
;; Insert menu lost four entries at once in August 2026.

(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-insert-menu "L"
                       '("H" "Add to HUB" my/denote-add-to-hub)))

(provide '33-denote-hubs)
;;; 33-denote-hubs.el ends here
