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
;;                                         across the collection
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
;; Rename
;; ------------------------------------------------------------

(defun my/maintenance--set-keywords (file keywords)
  "Give FILE the keyword list KEYWORDS and save it.  Return the new path.

Uses `denote-rename-file-keywords', the same primitive behind
`C-c n d k', which touches the keyword field and nothing else.

Denote's own confirmations are switched off for the duration: this
command has already asked about this file, and a second prompt whose
answer means something different is how a declined change turns into a
carried-out one.  `denote-save-buffers' is switched on so the note
reaches the disk rather than sitting modified in a buffer -- with a
belt-and-braces save afterwards for the case where Denote leaves it to
the caller."
  (let ((denote-rename-confirmations nil)
        (denote-save-buffers t))
    (let ((new (if (fboundp 'denote-rename-file-keywords)
                   (denote-rename-file-keywords file keywords)
                 (denote-rename-file file 'keep-current keywords
                                     'keep-current 'keep-current))))
      (when-let* ((path (if (stringp new) new file))
                  (buffer (find-buffer-visiting path)))
        (with-current-buffer buffer
          (when (buffer-modified-p) (save-buffer))))
      new)))

(defun my/maintenance--view-file (file)
  "Show FILE in another window without selecting it."
  (display-buffer (find-file-noselect file)
                  '(display-buffer-pop-up-window (inhibit-same-window . t))))

(defun my/maintenance--preview-keyword-change (keyword replacement files)
  "Show what renaming KEYWORD to REPLACEMENT would touch across FILES."
  (my/maintenance--report
   "*Denote Keyword Rename Preview*"
   (format (concat "%s\n\n"
                   "%d note(s) affected.  Each will be confirmed separately:\n"
                   "  y  rename    n  leave alone    v  view the note    q  stop here\n\n"
                   "Only the keyword field changes.  Title, identifier and signature\n"
                   "are left exactly as they are, and every note is saved to disk.")
           (if (string-empty-p replacement)
               (format "Remove keyword `%s'." keyword)
             (format "Rename keyword `%s' to `%s'." keyword replacement))
           (length files))
   (list (cons "Affected notes" (sort (copy-sequence files) #'string<)))))

;;;###autoload
(defun my/maintenance-rename-keyword (&optional keyword replacement)
  "Rename KEYWORD to REPLACEMENT everywhere, one note at a time.

An empty REPLACEMENT removes the keyword.  Interactively both are read
with completion over the keywords already in use, so a rename onto an
existing keyword -- merging two spellings into one -- is a matter of
picking the survivor from the list.

A preview of the affected notes is shown first.  Then each note is
confirmed on its own, with four answers:

  y  rename this note
  n  leave it alone and move on
  v  show the note in another window and ask again
  q  stop, leaving the remaining notes untouched

`v' exists because a keyword that looks wrong in a list sometimes turns
out to be right in the note, and deciding that used to mean leaving the
command, finding the file, and starting over.  It does not end the run:
the same question comes back with the note on screen beside it.

Only the keyword field is written.  A note is saved to disk as it is
changed, so an interrupted run leaves no modified buffers behind."
  (interactive)
  (my/maintenance--require-identifiers)
  (let* ((table (my/maintenance--keyword-table))
         (names (my/maintenance--keyword-names table))
         (keyword (or keyword
                      (completing-read "Rename which keyword: " names nil t)))
         (files (gethash keyword table)))
    (unless files
      (user-error "No note uses the keyword `%s'" keyword))
    (setq replacement
          (string-trim
           (or replacement
               (completing-read
                (format "Rename `%s' to (empty removes it): " keyword)
                names nil nil))))
    (when (string= replacement keyword)
      (user-error "That is already the keyword"))
    (my/maintenance--preview-keyword-change keyword replacement files)
    (let ((changed 0)
          (skipped 0))
      (catch 'my/maintenance--stop
        (dolist (file (sort (copy-sequence files) #'string<))
          (let ((decided nil))
            (while (not decided)
              (pcase (car (read-multiple-choice
                           (format "%s [%s]"
                                   (file-relative-name file my-notes-dir)
                                   (string-join
                                    (my/maintenance--file-keywords file) ","))
                           '((?y "yes" "Rename this note")
                             (?n "no" "Leave this note alone")
                             (?v "view" "Show the note, then ask again")
                             (?q "quit" "Stop, leaving the rest untouched"))))
                (?y
                 (let* ((current (my/maintenance--file-keywords file))
                        (kept (remove keyword current))
                        (new (if (string-empty-p replacement)
                                 kept
                               (delete-dups (append kept (list replacement))))))
                   (my/maintenance--set-keywords file new))
                 (setq changed (1+ changed) decided t))
                (?n (setq skipped (1+ skipped) decided t))
                (?v (my/maintenance--view-file file))
                (?q (throw 'my/maintenance--stop nil)))))))
      (message "%s: %d note(s) changed, %d left alone"
               (if (string-empty-p replacement)
                   (format "Removed `%s'" keyword)
                 (format "`%s' -> `%s'" keyword replacement))
               changed skipped))))

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
