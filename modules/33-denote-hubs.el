;;; 33-denote-hubs.el --- Collect notes under Denote hub notes -*- lexical-binding: t; -*-
;;; Commentary:
;; A HUB is an ordinary Denote note carrying the `hub' keyword in the
;; `__keyword' component of its file name.  Its body is a plain Org list
;; of links to the notes that belong to it, each with a one-line
;; description:
;;
;;   - [[denote:20260828T101500][Title of the note]] — why it is here
;;
;; One command, `my/denote-add-to-hub', appends the note in the current
;; buffer to a hub of one's choosing, creating the hub first when asked.
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
here is killed again afterwards, so browsing hubs from a prompt does not
accumulate buffers for hubs that were not being edited."
  (declare (indent 1) (debug (form body)))
  `(let* ((my-hub--file ,file)
          (my-hub--existing (find-buffer-visiting my-hub--file))
          (my-hub--buffer (or my-hub--existing
                              (find-file-noselect my-hub--file))))
     (with-current-buffer my-hub--buffer
       (save-excursion ,@body)
       (save-buffer))
     (unless my-hub--existing
       (kill-buffer my-hub--buffer))))

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
and appends

  - [[denote:IDENTIFIER][TITLE]] — DESCRIPTION

at the end of it.  IDENTIFIER and TITLE belong to the current note, and
TITLE is its `#+title:' value verbatim: a note whose title already
contains its signature contributes it, and no signature is added to a
note that has none.

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
            (my/denote-hub--append hub entry)
            (message "Added to hub: %s" (my/denote-hub--title hub))))
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
