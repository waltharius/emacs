;;; 26-maintenance.el --- Integrity checks and collection-wide repairs -*- lexical-binding: t; -*-

;;; Commentary:
;; A place to look after the collection rather than write in it: find
;; what the Obsidian migration broke, and repair it.
;;
;; WHAT COMES FROM WHERE
;;
;; Identifiers were already solved.  27-denote-identifiers.el holds
;; `my/denote-change-identifier' (change one, and repoint every link to
;; it), `my/denote-check-identifiers', `my/denote-fix-duplicates' and
;; `my/denote-find-self-links'.  They were reachable only through `M-x',
;; which is most of why this module exists.  It calls them; it does not
;; reimplement them.
;;
;; Denote upstream deliberately does not cover that ground: its manual
;; gives sample code for finding duplicate identifiers and says that,
;; being an edge case, it is not part of the code base.  Nor does
;; `denote-rename-file-using-front-matter' change an identifier --
;; Denote treats the file name as the source of truth for that field.
;;
;; WRITTEN HERE
;;
;;   `my/denote-check-signatures'          duplicate Folgezettel signatures
;;   `my/denote-check-broken-links'        `denote:' links with no target
;;   `my/maintenance-keyword-inventory'    every keyword, with counts
;;   `my/maintenance-notes-without-keywords'
;;   `my/maintenance-rename-keyword'       rename or remove one keyword
;;                                         across the collection, through
;;                                         a review list with a preview
;;
;; NOT DELEGATED TO denote-explore, AND WHY
;;
;; The first version of this module wrapped denote-explore, which does
;; cover keywords.  In this collection its writing commands produced a
;; second file holding only front matter while leaving the original
;; untouched, and carried out changes that had been declined at the
;; prompt.  Neither could be reproduced from the outside and it may well
;; depend on the state of this particular tree, so this is not a verdict
;; on the package.  It is a decision about what can be vouched for when
;; three thousand real notes are on the other end of the command.
;;
;; The keyword side is therefore written against Denote's own
;; primitive, `denote-rename-file-keywords' -- the same one behind
;; `C-c n d k', which touches the keyword field and nothing else.
;;
;; SCOPE: INBOX YES, ATTACHMENTS NO
;;
;; Everything here reads `my/denote--all-files' from 27, which walks
;; `my-notes-dir' directly and returns .org files only.  Two
;; consequences, both wanted:
;;
;;   The staging inbox IS included.  A keyword renamed everywhere except
;;   there comes back one note at a time as notes are filed -- a failure
;;   that would surface weeks later, attached to nothing.  (Denote's own
;;   listing would have excluded it, since 25-inbox-review.el sets
;;   `denote-excluded-directories-regexp' to "inbox".)
;;
;;   Attachments are NOT included.  A PDF or an image carries an
;;   identifier so that links can reach it, but it has no front matter
;;   and no keywords to review.
;;
;; DECISIONS BELONG IN A BUFFER, NOT IN A PROMPT
;;
;; The keyword rename first asked file by file with
;; `read-multiple-choice'.  That reads raw input events, so every mouse
;; movement redrew the prompt, and while it was reading, no other window
;; could receive input -- the note it had just displayed could not be
;; scrolled, which was the whole point of offering to display it.
;;
;; A blocking prompt cannot be made to allow free navigation.  The
;; review therefore happens in a `tabulated-list-mode' buffer, the shape
;; that already works in 25-inbox-review.el and 24-readwise.el.
;;
;; READ AND WRITE ARE SEPARATED IN THE MENU
;;
;; Checks are on lower-case keys and open a buffer.  Anything that
;; renames files across the collection is on a capital, so a mistyped
;; key cannot start one.
;;
;; DEPENDENCIES
;;
;; 27-denote-identifiers.el, at call time only -- this module has a
;; lower number and loads first, which does not matter because nothing
;; here runs until a command is invoked.  Commands that need it check
;; and say so.  12-transient.el is optional: the menu entry goes through
;; `my/transient-append', which skips silently when absent.
;;
;; Docs: ~/.emacs.d/function_helper.org::#maintenance

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'transient)

;; Declared, not defined: these belong to Denote.  Declaring marks them
;; special for this file so the bindings below are dynamic, and a name
;; absent from some version simply gets a binding nothing reads.
(defvar denote-rename-confirmations)
(defvar denote-save-buffers)

(defun my/maintenance--require-identifiers ()
  "Signal unless 27-denote-identifiers.el has been loaded."
  (unless (and (fboundp 'my/denote--all-files)
               (fboundp 'my/denote--identifier-table))
    (user-error "27-denote-identifiers.el is not loaded")))

;; ============================================================
;; REPORTS
;; ============================================================
;; One shape for every check written here, so that reading a second
;; report needs no second set of habits.  File names are buttons.

(defun my/maintenance--insert-file-button (file)
  "Insert FILE as a button that visits it, shown relative to the notes root."
  (insert-text-button
   (file-relative-name file my-notes-dir)
   'action (lambda (_) (find-file file))
   'follow-link t
   'help-echo file))

(defun my/maintenance--report (name intro groups)
  "Display a report called NAME.

INTRO is a paragraph shown above the findings.  GROUPS is a list of
\(HEADING . FILES), each rendered as a line followed by its files
indented and clickable.  Displays nothing and returns nil when GROUPS
is empty, so a clean collection produces a message rather than an empty
buffer to dismiss."
  (if (null groups)
      nil
    (with-current-buffer (get-buffer-create name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert intro "\n\n")
        (dolist (group groups)
          (insert (car group) "\n")
          (dolist (file (cdr group))
            (insert "    ")
            (my/maintenance--insert-file-button file)
            (insert "\n"))
          (insert "\n")))
      (goto-char (point-min))
      (special-mode)
      (display-buffer (current-buffer)))
    t))

;; ============================================================
;; CHECK: duplicate signatures
;; ============================================================

(defun my/maintenance--file-signature (file)
  "Return FILE's Denote signature, or nil when it has none.

Prefers Denote's own accessor.  The fallback reads the `==SIGNATURE'
field straight from the file name, which is where Denote keeps it and
where `denote-sequence' writes Folgezettel values such as 1a1."
  (if (fboundp 'denote-retrieve-filename-signature)
      (denote-retrieve-filename-signature file)
    (let ((name (file-name-nondirectory file)))
      (when (string-match "==\\([^-_.]+\\)" name)
        (match-string 1 name)))))

(defun my/maintenance--signature-groups ()
  "Return ((SIGNATURE . FILES) ...) for signatures used more than once."
  (let ((table (make-hash-table :test #'equal))
        groups)
    (dolist (file (my/denote--all-files))
      (when-let* ((signature (my/maintenance--file-signature file)))
        (unless (string-empty-p signature)
          (puthash signature (cons file (gethash signature table)) table))))
    (maphash (lambda (signature files)
               (when (> (length files) 1)
                 (push (cons signature (sort files #'string<)) groups)))
             table)
    (sort groups (lambda (a b) (string< (car a) (car b))))))

;;;###autoload
(defun my/denote-check-signatures ()
  "Report notes sharing a Denote signature.

A signature is a position in a sequence, so two notes holding the same
one make the sequence ambiguous in the same way a duplicate identifier
makes a link ambiguous.  `denote-sequence' assigns them correctly; the
ones worth finding came in from the migration or from a file renamed by
hand.

Scans everything under `my-notes-dir', the staging inbox included, so
that a collision is seen before the note is filed rather than after.
Sequences are supposed to live in the pks silo (22-zettelkasten.el), so
a signature reported from anywhere else is worth a second look on its
own account -- the report shows each file's path for that reason."
  (interactive)
  (my/maintenance--require-identifiers)
  (let ((groups (my/maintenance--signature-groups)))
    (if (my/maintenance--report
         "*Denote Signature Check*"
         (format (concat "%d duplicate signature(s) under %s.\n\n"
                         "Signatures are assigned by denote-sequence; change one with\n"
                         "M-x denote-sequence-reparent or by renaming the file with\n"
                         "M-x denote-rename-file, which leaves the identifier alone.")
                 (length groups) my-notes-dir)
         groups)
        (message "%d duplicate signature(s)" (length groups))
      (message "No duplicate signatures found"))))

;; ============================================================
;; CHECK: broken denote: links
;; ============================================================

(defun my/maintenance--link-targets ()
  "Return a hash of linked-to identifier -> list of files containing the link.

Reads every file under `my-notes-dir' once.  A link may carry a heading
suffix -- `denote:ID#heading' or `denote:ID::heading' -- and only the
identifier is collected, since that is the part that has to resolve."
  (let ((table (make-hash-table :test #'equal))
        (regexp (concat "denote:\\(" my/denote-identifier-regexp "\\)")))
    (dolist (file (my/denote--all-files))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let (seen)
          (while (re-search-forward regexp nil t)
            (let ((id (match-string 1)))
              (unless (member id seen)
                (push id seen)
                (puthash id (cons file (gethash id table)) table)))))))
    table))

;;;###autoload
(defun my/denote-check-broken-links ()
  "Report `denote:' links whose target identifier belongs to no file.

This is what a deleted note or a hand-edited identifier leaves behind:
the link still looks like a link and still fontifies, and following it
fails.  Grouped by the missing identifier, listing the files that point
at it, so that one bad identifier does not read as several problems.

Both sides are scanned across the whole of `my-notes-dir', inbox
included, since staged notes link to filed ones and to each other."
  (interactive)
  (my/maintenance--require-identifiers)
  (let* ((known (my/denote--identifier-table (my/denote--all-files)))
         (targets (my/maintenance--link-targets))
         groups)
    (maphash (lambda (id files)
               (unless (gethash id known)
                 (push (cons (format "%s — no file has this identifier" id)
                             (sort files #'string<))
                       groups)))
             targets)
    (setq groups (sort groups (lambda (a b) (string< (car a) (car b)))))
    (if (my/maintenance--report
         "*Denote Broken Links*"
         (format (concat "%d unresolved identifier(s) linked from %s.\n\n"
                         "Either the target was deleted, or its identifier was changed\n"
                         "outside M-x my/denote-change-identifier, which rewrites links.")
                 (length groups) my-notes-dir)
         groups)
        (message "%d unresolved identifier(s)" (length groups))
      (message "No broken denote: links found"))))

;; ============================================================
;; KEYWORDS
;; ============================================================
;; Keywords are read from file names, which is where Denote keeps them
;; and what its own rename rebuilds.  See the Commentary above for why
;; this is written against `denote-rename-file-keywords' rather than
;; delegated, and for what the scope includes.

(defun my/maintenance--file-keywords (file)
  "Return FILE's keywords, read from its file name, as a list of strings."
  (cond
   ((fboundp 'denote-extract-keywords-from-path)
    (denote-extract-keywords-from-path file))
   ((fboundp 'denote-retrieve-filename-keywords)
    (when-let* ((raw (denote-retrieve-filename-keywords file)))
      (split-string raw "_" t)))
   (t
    (let ((name (file-name-nondirectory file)))
      (when (string-match "__\\([^.]+\\)" name)
        (split-string (match-string 1 name) "_" t))))))

(defun my/maintenance--keyword-table ()
  "Return a hash of keyword -> list of files using it."
  (my/maintenance--require-identifiers)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file (my/denote--all-files))
      (dolist (keyword (my/maintenance--file-keywords file))
        (puthash keyword (cons file (gethash keyword table)) table)))
    table))

(defun my/maintenance--keyword-names (&optional table)
  "Return every keyword in TABLE, sorted alphabetically."
  (let (names)
    (maphash (lambda (keyword _files) (push keyword names))
             (or table (my/maintenance--keyword-table)))
    (sort names #'string<)))

;; ------------------------------------------------------------
;; Inventory
;; ------------------------------------------------------------

;;;###autoload
(defun my/maintenance-keyword-inventory ()
  "List every keyword with the number of notes using it.

Sorted alphabetically on purpose rather than by frequency: near
duplicates are what a migrated collection accumulates, and `filozofia'
directly above `flozofia' is what makes them visible.  The count is the
second signal -- a keyword used once beside one used four hundred times
is usually a typo of it, and those are marked.

Each keyword is a button that starts a rename of it."
  (interactive)
  (let* ((table (my/maintenance--keyword-table))
         (names (my/maintenance--keyword-names table))
         (buffer (get-buffer-create "*Denote Keyword Inventory*")))
    (if (null names)
        (message "No keywords found")
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "%d keyword(s) across %d note(s) under %s.\n"
                          (length names)
                          (length (my/denote--all-files))
                          my-notes-dir))
          (insert "Attachments are not listed: they carry identifiers, not keywords.\n")
          (insert "Click a keyword to rename or remove it everywhere.\n")
          (insert "A keyword used once is marked - usually specific, sometimes a typo.\n\n")
          (dolist (keyword names)
            (let ((count (length (gethash keyword table))))
              (insert (format "%5d  " count))
              (insert-text-button
               keyword
               'action (lambda (_) (my/maintenance-rename-keyword keyword))
               'follow-link t
               'help-echo (format "Rename or remove `%s' across the collection"
                                  keyword))
              (when (= count 1) (insert "   ·"))
              (insert "\n"))))
        (goto-char (point-min))
        (special-mode)
        (display-buffer (current-buffer)))
      (message "%d keyword(s)" (length names)))))

;;;###autoload
(defun my/maintenance-notes-without-keywords ()
  "Report notes carrying no keywords at all."
  (interactive)
  (my/maintenance--require-identifiers)
  (let ((files (seq-remove #'my/maintenance--file-keywords
                           (my/denote--all-files))))
    (if (my/maintenance--report
         "*Denote Notes Without Keywords*"
         (format "%d note(s) under %s carry no keywords."
                 (length files) my-notes-dir)
         (when files (list (cons "No keywords" (sort files #'string<)))))
        (message "%d note(s) without keywords" (length files))
      (message "Every note has at least one keyword"))))

;; ------------------------------------------------------------
;; Rename: a review list, not a prompt
;; ------------------------------------------------------------
;; The first version asked file by file with `read-multiple-choice',
;; which is the wrong tool here and failed in a way worth recording.
;; That function reads raw input events.  A mouse movement or a click is
;; not one of its answers, so every one of them redraws the prompt; and
;; while it is reading, nothing else receives input, so the note it had
;; just displayed could not be scrolled.  Reading a note before deciding
;; about it was exactly the point of the option.
;;
;; A blocking prompt cannot be fixed into allowing free navigation.  So
;; the decision moves into a buffer instead, following the pattern that
;; already works in 25-inbox-review.el and 24-readwise.el: a
;; `tabulated-list-mode' of affected notes, a preview in a side window,
;; and one key per decision.  Nothing holds the input stream, so the
;; preview scrolls, the mouse behaves, and stepping away and coming back
;; costs nothing.
;;
;; Per-file confirmation is unchanged in substance: nothing is written
;; until `y' is pressed on that row.

(defconst my/maintenance--keyword-buffer "*Keyword Rename*"
  "Name of the keyword review buffer.")

(defvar my/maintenance--keyword-entries nil
  "Rows of the keyword review: plists with :file and :status.")

(defvar my/maintenance--keyword-old nil
  "Keyword being renamed in the current review.")

(defvar my/maintenance--keyword-new nil
  "Replacement keyword, or the empty string to remove.")

(defvar my/maintenance--note-window nil
  "Window used for previews.  Global for the same reason as the
identical variable in 25-inbox-review.el: one preview window reused
across the session, rather than a new split per note.")

(defun my/maintenance--keyword-list-entries ()
  "Convert `my/maintenance--keyword-entries' into tabulated-list form."
  (mapcar
   (lambda (entry)
     (let ((file (plist-get entry :file)))
       (list entry
             (vector (plist-get entry :status)
                     (string-join (my/maintenance--file-keywords file) ",")
                     (file-name-nondirectory
                      (directory-file-name (file-name-directory file)))
                     (file-name-nondirectory file)))))
   my/maintenance--keyword-entries))

(defun my/maintenance--keyword-pending ()
  "Return the rows still awaiting a decision."
  (seq-filter (lambda (entry) (equal (plist-get entry :status) "pending"))
              my/maintenance--keyword-entries))

;; Defined before `define-derived-mode', which would otherwise create
;; the map itself while the symbol is unbound -- same order as
;; 25-inbox-review.el.
(defvar my/keyword-rename-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'my/keyword-rename-preview)
    (define-key map (kbd "o")   #'my/keyword-rename-visit-preview)
    (define-key map (kbd "y")   #'my/keyword-rename-apply)
    (define-key map (kbd "n")   #'my/keyword-rename-skip)
    (define-key map (kbd "g")   #'my/keyword-rename-refresh)
    (define-key map (kbd "q")   #'quit-window)
    map)
  "Keymap for `my/keyword-rename-mode'.")

(define-derived-mode my/keyword-rename-mode tabulated-list-mode "KeywordRename"
  "Major mode for renaming one keyword across the notes that use it.

Nothing is written until `y' is pressed on a row, and each row is
written on its own.  Leaving the buffer and returning later is safe:
the rows that were already handled say so.

\\{my/keyword-rename-mode-map}"
  (setq tabulated-list-format
        (vector (list "State" 8 t)
                (list "Keywords" 34 t)
                (list "Folder" 10 t)
                (list "File" 0 t)))
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header)
  (hl-line-mode 1))

(defun my/maintenance--keyword-render ()
  "Redraw the review list, keeping point on the same row."
  (setq tabulated-list-entries (my/maintenance--keyword-list-entries))
  (tabulated-list-print t)
  (setq mode-line-process
        (format " [%d left]" (length (my/maintenance--keyword-pending))))
  (force-mode-line-update))

(defun my/maintenance--keyword-entry ()
  "Row at point, or an error naming what to do about it."
  (or (tabulated-list-get-id)
      (if (derived-mode-p 'my/keyword-rename-mode)
          (user-error "Point is not on a note row - move to one first")
        (user-error "Not in a keyword review (M-x my/maintenance-rename-keyword)"))))

(defun my/keyword-rename-preview ()
  "Show the note at point in a side window, keeping focus on the list.

Focus stays here because the decision keys live in this buffer, and
`view-mode' in the preview binds n to its own command.  Press o to step
into the preview when you want to scroll it -- q there comes back."
  (interactive)
  (let* ((entry (my/maintenance--keyword-entry))
         (buffer (find-file-noselect (plist-get entry :file)))
         (window (if (window-live-p my/maintenance--note-window)
                     my/maintenance--note-window
                   (setq my/maintenance--note-window (split-window-right 70)))))
    (set-window-buffer window buffer)
    (with-current-buffer buffer
      (view-mode 1)
      (goto-char (point-min)))
    (set-window-point window (point-min))))

(defun my/keyword-rename-visit-preview ()
  "Move point into the preview window, where the note can be scrolled freely."
  (interactive)
  (unless (window-live-p my/maintenance--note-window)
    (my/keyword-rename-preview))
  (select-window my/maintenance--note-window))

(defun my/keyword-rename-refresh ()
  "Redraw the list."
  (interactive)
  (my/maintenance--keyword-render))

(defun my/keyword-rename-skip ()
  "Leave the note at point alone and move to the next row."
  (interactive)
  (let ((entry (my/maintenance--keyword-entry)))
    (when (equal (plist-get entry :status) "pending")
      (plist-put entry :status "skipped"))
    (my/maintenance--keyword-render)
    (forward-line 1)))

(defun my/keyword-rename-apply ()
  "Rename the keyword in the note at point, then move to the next row.

The only command here that writes.  Denote returns the new path, which
replaces the old one in the row, so a second press cannot act on a name
that no longer exists."
  (interactive)
  (let* ((entry (my/maintenance--keyword-entry))
         (file (plist-get entry :file)))
    (if (not (equal (plist-get entry :status) "pending"))
        (progn
          (message "Already %s" (plist-get entry :status))
          (forward-line 1))
      (let* ((current (my/maintenance--file-keywords file))
             (kept (remove my/maintenance--keyword-old current))
             (wanted (if (string-empty-p my/maintenance--keyword-new)
                         kept
                       (delete-dups
                        (append kept (list my/maintenance--keyword-new)))))
             (result (my/maintenance--set-keywords file wanted)))
        (plist-put entry :file (if (stringp result) result file))
        (plist-put entry :status "renamed")
        (my/maintenance--keyword-render)
        (forward-line 1)
        (message "%d note(s) left" (length (my/maintenance--keyword-pending)))))))

;;;###autoload
(defun my/maintenance-rename-keyword (&optional keyword replacement)
  "Rename KEYWORD to REPLACEMENT across the collection, note by note.

An empty REPLACEMENT removes the keyword.  Interactively both are read
with completion over the keywords already in use, so merging two
spellings into one is a matter of picking the survivor from the list.

Opens a review list of the affected notes.  Nothing is written until a
decision is made on a row:

  RET  preview the note in a side window
  o    step into the preview, where it scrolls normally (q returns)
  y    rename this note
  n    leave it alone
  g    redraw
  q    leave; unhandled notes keep their keyword

Only the keyword field is written -- title, identifier and signature
stay as they are -- and each note is saved to disk as it changes, so
leaving part-way through is safe and leaves no modified buffers."
  (interactive)
  (my/maintenance--require-identifiers)
  (let* ((table (my/maintenance--keyword-table))
         (names (my/maintenance--keyword-names table))
         (old (or keyword
                  (completing-read "Rename which keyword: " names nil t)))
         (files (gethash old table)))
    (unless files
      (user-error "No note uses the keyword `%s'" old))
    (let ((new (string-trim
                (or replacement
                    (completing-read
                     (format "Rename `%s' to (empty removes it): " old)
                     names nil nil)))))
      (when (string= new old)
        (user-error "That is already the keyword"))
      (setq my/maintenance--keyword-old old
            my/maintenance--keyword-new new
            my/maintenance--keyword-entries
            (mapcar (lambda (file) (list :file file :status "pending"))
                    (sort (copy-sequence files) #'string<)))
      (let ((buffer (get-buffer-create my/maintenance--keyword-buffer)))
        (with-current-buffer buffer
          (my/keyword-rename-mode)
          (setq header-line-format
                (if (string-empty-p new)
                    (format " Remove keyword `%s'   |   RET preview  o scroll it  y remove  n keep  q leave"
                            old)
                  (format " `%s' -> `%s'   |   RET preview  o scroll it  y rename  n keep  q leave"
                          old new)))
          (my/maintenance--keyword-render)
          (goto-char (point-min)))
        (pop-to-buffer buffer)
        (message "%d note(s) use `%s'" (length files) old)))))

;; ============================================================
;; MENU
;; ============================================================

(transient-define-prefix my/notes-maintenance-menu ()
  "Check the collection's integrity and repair what is broken."
  [["Check (reads only)"
    ("i" "Duplicate identifiers" my/denote-check-identifiers)
    ("g" "Duplicate signatures"  my/denote-check-signatures)
    ("b" "Broken denote: links"  my/denote-check-broken-links)
    ("l" "Self-links"            my/denote-find-self-links)
    ("k" "Keyword inventory"     my/maintenance-keyword-inventory)
    ("z" "Notes with no keywords" my/maintenance-notes-without-keywords)]
   ["Repair (renames files)"
    ("R" "Change this note's identifier" my/denote-change-identifier)
    ("I" "Fix duplicate identifiers"     my/denote-fix-duplicates)
    ("K" "Rename or remove a keyword"    my/maintenance-rename-keyword)]
   [("q" "Quit" transient-quit-one)]])

;; Appended after "a" (Add to dict), the last entry of the second
;; column, through the helper that degrades gracefully when
;; 12-transient.el is absent.
(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-menu "a"
                       '("!" "Maintenance → integrity/keywords/repair"
                         my/notes-maintenance-menu)))

(provide '26-maintenance)
;;; 26-maintenance.el ends here
