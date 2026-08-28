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
;; only the file, not the line -- and the line is where the description
;; lives.

(defconst my/denote-hub-entry-separator " — "
  "String written between a hub entry's link and its description.")

(defun my/denote-hub--file-contents (file)
  "Insert the contents of FILE into the current buffer.
A live buffer visiting FILE wins over the copy on disk, so a hub being
edited reports what it currently says rather than what was last saved."
  (if-let* ((buffer (find-buffer-visiting file)))
      (insert-buffer-substring buffer)
    (insert-file-contents file)))

(defun my/denote-hub--entry-description (line)
  "Return the description part of hub entry LINE, or nil when it has none.

Liberal on purpose.  What is in the file is whatever was written there,
possibly edited by hand since: everything after the closing brackets of
the link counts as the description, with a leading dash or em dash
removed."
  (when (and line (string-match "\\]\\][ \t]*\\(.*\\)\\'" line))
    (let ((rest (string-trim
                 (replace-regexp-in-string
                  "\\`[-–—][ \t]*" "" (string-trim (match-string 1 line))))))
      (unless (string-empty-p rest) rest))))

(defun my/denote-hub--entries (hub identifier)
  "Return the lines of HUB that link to IDENTIFIER, in file order.
More than one line means the note was added to that hub twice."
  (let ((needle (concat "denote:" identifier))
        (lines nil))
    (with-temp-buffer
      (my/denote-hub--file-contents hub)
      (goto-char (point-min))
      (while (search-forward needle nil t)
        (push (buffer-substring-no-properties
               (line-beginning-position) (line-end-position))
              lines)
        ;; Move past this line so a second link on it does not report
        ;; the same entry twice.
        (forward-line 1)))
    (nreverse lines)))

(defun my/denote-hub-membership (&optional file)
  "Return an alist of (HUB-FILE . ENTRY-LINES) for hubs that list FILE.
FILE defaults to the file of the current buffer.  Hubs that do not
mention it are absent from the result, so a nil return means the note
belongs to no hub."
  (let* ((file (or file (buffer-file-name)
                   (user-error "This buffer is not visiting a file")))
         (identifier (or (denote-retrieve-filename-identifier file)
                         (user-error "Not a Denote note (no identifier in the file name)")))
         (result nil))
    (dolist (hub (my/denote-hub-files) (nreverse result))
      (when-let* ((lines (my/denote-hub--entries hub identifier)))
        (push (cons hub lines) result)))))

(defun my/denote-hub-list-for-note ()
  "Report in the echo area which hubs list the current note, and how.

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
                          (or (my/denote-hub--entry-description (cadr cell))
                              "(no description)")))
                membership "\n"))
    (message "This note is not listed in any hub")))

;; ============================================================
;; WRITING INTO A HUB
;; ============================================================

(defun my/denote-hub--entry (identifier title description)
  "Return the hub list item linking to IDENTIFIER and shown as TITLE.
DESCRIPTION follows an em dash.  Assumption: an empty description
produces the link alone rather than a trailing dash."
  (if (string-empty-p description)
      (format "- [[denote:%s][%s]]" identifier title)
    (format "- [[denote:%s][%s]]%s%s"
            identifier title my/denote-hub-entry-separator description)))

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
  "Replace the line of FILE linking to IDENTIFIER with ENTRY.
The line is rewritten where it stands, so an entry keeps its position in
the hub when its description is edited."
  (my/denote-hub--with-hub file
    (goto-char (point-min))
    (if (search-forward (concat "denote:" identifier) nil t)
        (progn
          (delete-region (line-beginning-position) (line-end-position))
          (insert entry))
      (user-error "Entry for %s is no longer in %s" identifier file))))

;; ============================================================
;; THE HUB PROMPT
;; ============================================================

(defun my/denote-hub--annotation (lines)
  "Return the text shown beside a hub that already lists the note.
LINES are its entry lines there, so the description in the first one is
what the annotation reports."
  (let ((description (my/denote-hub--entry-description (car lines)))
        (count (length lines)))
    (propertize
     (concat "  already listed"
             (when description (concat ": " description))
             (when (> count 1) (format "  [%d entries]" count)))
     'face 'completions-annotations)))

(defun my/denote-hub--completion-table (candidates annotations)
  "Return a completion table over CANDIDATES with ANNOTATIONS beside them.

Two pieces of metadata do the work.  `identity' as the sort function
keeps the given order, which is what puts the hubs already listing the
note at the top and `my/denote-hub-new-label' at the bottom; without it
the completion frontend files them alphabetically.  The annotation
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

CANDIDATES are labels in display order: hubs that already list the note
first, then the rest, then `my/denote-hub-new-label'.  FILES maps a
label to its hub file, ANNOTATIONS maps a label to the text shown beside
it.  MEMBERSHIP is the return value of `my/denote-hub-membership'."
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
    (list (nreverse (cons my/denote-hub-new-label labels))
          files annotations)))

;; ============================================================
;; COMMAND
;; ============================================================

(defun my/denote-add-to-hub ()
  "Add a link to the current note to a hub note, or edit an existing one.

The prompt lists every hub, with the ones that already link to this note
at the top and their current description shown beside them.  Membership
is read from the hubs themselves rather than recorded in the note, so
there is nothing to keep in step and nothing that can go stale.

Choosing a hub that does not list the note yet asks for a one-line
description and appends

  - [[denote:IDENTIFIER][TITLE]] — DESCRIPTION

at the end of it.  IDENTIFIER and TITLE belong to the current note, and
TITLE is its `#+title:' value verbatim: a note whose title already
contains its signature contributes it, and no signature is added to a
note that has none.

Choosing a hub that already lists the note re-asks for the description
with the current one filled in, and rewrites that line where it stands.
This is how a duplicate entry is avoided: adding a note twice is not
something the command can do.

Choosing `my/denote-hub-new-label' creates a note in
`my/denote-hub-directory' with the hub keyword and the title given at
the prompt.  Its own one-line description becomes the first line of the
body, and the link entry goes one blank line below it."
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
          ;; INITIAL-INPUT rather than DEFAULT-VALUE: the point of this
          ;; prompt is to edit the existing text, and a default can only
          ;; be accepted or discarded, not amended.
          (let ((description (read-string
                              "Entry description: "
                              (or (my/denote-hub--entry-description (car entries))
                                  ""))))
            (my/denote-hub--replace-entry
             hub identifier (my/denote-hub--entry identifier title description))
            (message "Updated entry in hub: %s" (my/denote-hub--title hub))))
         ;; An existing hub that does not list the note yet.
         (hub
          (let ((entry (my/denote-hub--entry
                        identifier title (read-string "Entry description: "))))
            (my/denote-hub--append hub entry)
            (message "Added to hub: %s" (my/denote-hub--title hub))))
         ;; New hub.  Every prompt is answered before anything is
         ;; created, so C-g leaves no half-built note behind.
         (t
          (let ((hub-title (string-trim (read-string "New HUB title: "))))
            (when (string-empty-p hub-title)
              (user-error "A hub needs a title"))
            (let* ((hub-description (read-string "HUB description: "))
                   (entry (my/denote-hub--entry
                           identifier title (read-string "Entry description: ")))
                   ;; `denote' returns the path of the note it created
                   ;; and visits it.  Assumption: the new hub is left
                   ;; open, which is Denote's own behaviour and the
                   ;; simplest outcome.
                   (new-hub (let ((denote-directory my/denote-hub-directory))
                              (denote hub-title (list my/denote-hub-keyword)))))
              (my/denote-hub--append
               new-hub (concat hub-description "\n\n" entry))
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
