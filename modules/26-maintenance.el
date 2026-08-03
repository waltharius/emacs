;;; 26-maintenance.el --- Integrity checks and collection-wide repairs -*- lexical-binding: t; -*-

;;; Commentary:
;; A place to look after the collection rather than write in it: find
;; what the Obsidian migration broke, and reach the tools that fix it.
;;
;; MOSTLY A MENU, ON PURPOSE
;;
;; Almost nothing here is new.  Three of the four jobs this module was
;; asked for already existed and were reachable only through `M-x':
;;
;;   `my/denote-change-identifier'   27-denote-identifiers.el
;;   `my/denote-check-identifiers'   27-denote-identifiers.el
;;   `my/denote-fix-duplicates'      27-denote-identifiers.el
;;   `my/denote-find-self-links'     27-denote-identifiers.el
;;   `denote-explore-rename-keyword' denote-explore package
;;   `denote-explore-sync-metadata'  denote-explore package
;;
;; Denote itself deliberately does not solve the identifier problem:
;; its manual gives sample code for finding duplicates and says in as
;; many words that, being an edge case, it is not part of the code base.
;; Nor will `denote-rename-file-using-front-matter' change one -- Denote
;; treats the file name as the source of truth for identifiers.  So
;; 27-denote-identifiers.el is not duplicating anything upstream, and
;; this module calls it rather than reimplementing it.
;;
;; WHAT IS ACTUALLY NEW HERE
;;
;;   `my/denote-check-signatures'    duplicate Folgezettel signatures
;;   `my/denote-check-broken-links'  `denote:' links whose target does
;;                                   not exist
;;
;; denote-explore covers keywords and identifiers but not signatures,
;; and a duplicate signature breaks a sequence exactly the way a
;; duplicate identifier breaks a link.
;;
;; THE INBOX, AND WHY IT NEEDS SAYING
;;
;; Every denote-explore command works from `denote-directory-files',
;; which honours `denote-excluded-directories-regexp' -- set to "inbox"
;; in 25-inbox-review.el.  Left alone, renaming a keyword would silently
;; skip more than a thousand staged notes, and the old keyword would
;; reappear one note at a time as they were filed.
;;
;; The wrappers below therefore run denote-explore inside
;; `my/maintenance-with-full-scope'.  The checks written here do not
;; need it: they use `my/denote--all-files' from 27, which walks
;; `my-notes-dir' directly for this very reason.
;;
;; READ AND WRITE ARE SEPARATED IN THE MENU
;;
;; The menu keeps checks apart from repairs, because the two carry
;; different risk.  A check opens a buffer.  A repair renames files
;; across the whole collection, and the ones that do are grouped under
;; capital letters so that a mistyped key cannot start one.
;;
;; DEPENDENCIES
;;
;; 27-denote-identifiers.el, at call time only -- this module has a
;; lower number and therefore loads first, which does not matter because
;; nothing here runs until a command is invoked.  Commands that need it
;; check and say so.  denote-explore is required on demand by the
;; wrappers.  12-transient.el is optional: the menu entry goes through
;; `my/transient-append', which skips silently when absent.
;;
;; Docs: ~/.emacs.d/function_helper.org::#maintenance

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'transient)

;; Denote's, declared so the bindings below are dynamic.
(defvar denote-excluded-directories-regexp)
(defvar denote-excluded-files-regexp)

;; ============================================================
;; SCOPE
;; ============================================================

(defconst my/maintenance-unrestricted-regexp "\\`\\'"
  "A regexp that matches nothing a path can ever be.

It matches the empty string only, so binding Denote's exclusion
options to it excludes nothing.  An empty string is used rather than
nil because Denote is free to treat nil and a regexp differently in
future, while a regexp that cannot match is safe under either
reading.")

(defmacro my/maintenance-with-full-scope (&rest body)
  "Run BODY with every note visible to Denote, staging inbox included.

Maintenance is the one activity that must see the whole collection.
Everywhere else the inbox is excluded on purpose: a staged note may
duplicate a filed one until it is accepted, and hiding it keeps prompts
and backlinks honest.  A keyword rename that skipped it would be wrong
in a way that only shows up weeks later."
  (declare (indent 0) (debug t))
  `(let ((denote-excluded-directories-regexp my/maintenance-unrestricted-regexp)
         (denote-excluded-files-regexp my/maintenance-unrestricted-regexp))
     ,@body))

(defun my/maintenance--require-identifiers ()
  "Signal unless 27-denote-identifiers.el has been loaded."
  (unless (and (fboundp 'my/denote--all-files)
               (fboundp 'my/denote--identifier-table))
    (user-error "27-denote-identifiers.el is not loaded")))

(defun my/maintenance--call-explore (command)
  "Load denote-explore, then run COMMAND over the whole collection."
  (unless (require 'denote-explore nil t)
    (user-error "The denote-explore package is not available"))
  (unless (fboundp command)
    (user-error "%s is not defined in this version of denote-explore" command))
  (my/maintenance-with-full-scope
    (call-interactively command)))

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
;; KEYWORD TOOLS (denote-explore, run over the whole collection)
;; ============================================================
;; Thin wrappers, each doing three things the bare command cannot: load
;; denote-explore, widen the scope to include the inbox, and say
;; something useful when the package is missing.

;;;###autoload
(defun my/maintenance-rename-keyword ()
  "Rename or remove one keyword across the whole collection.

`denote-explore-rename-keyword' with the inbox in scope.  It works from
the front matter, asks for confirmation per file, and treats an empty
replacement as removal.

On a keyword used by hundreds of notes this means hundreds of prompts.
Renaming a rare keyword first is the cheap way to see what the command
does before committing to a common one."
  (interactive)
  (my/maintenance--call-explore 'denote-explore-rename-keyword))

;;;###autoload
(defun my/maintenance-zero-keywords ()
  "List notes carrying no keywords at all."
  (interactive)
  (my/maintenance--call-explore 'denote-explore-zero-keywords))

;;;###autoload
(defun my/maintenance-single-keywords ()
  "List keywords used by exactly one note.

The most useful of the keyword reports after a migration: a keyword
that appears once is either genuinely specific or a misspelling of one
that appears often, and the two are easy to tell apart by eye."
  (interactive)
  (my/maintenance--call-explore 'denote-explore-single-keywords))

;;;###autoload
(defun my/maintenance-sort-keywords ()
  "Alphabetise the keywords of every note, renaming files where needed."
  (interactive)
  (my/maintenance--call-explore 'denote-explore-sort-keywords))

;;;###autoload
(defun my/maintenance-count-keywords ()
  "Report how many distinct keywords the collection uses."
  (interactive)
  (my/maintenance--call-explore 'denote-explore-count-keywords))

;;;###autoload
(defun my/maintenance-sync-metadata ()
  "Bring file names into line with front matter, note by note.

`denote-explore-sync-metadata' compares each note's front matter with
its file name and offers to rename where they disagree.  This is the
best single check against migration damage, because a script that wrote
front matter and file names separately could get them out of step
without either looking wrong on its own.

It does NOT touch identifiers: Denote treats the file name as the source
of truth for those, so a wrong identifier needs
`my/denote-change-identifier', which also repoints the links."
  (interactive)
  (my/maintenance--call-explore 'denote-explore-sync-metadata))

;; ============================================================
;; MENU
;; ============================================================

(transient-define-prefix my/notes-maintenance-menu ()
  "Check the collection's integrity and repair what is broken."
  [["Check (reads only)"
    ("i" "Duplicate identifiers" my/denote-check-identifiers)
    ("g" "Duplicate signatures"  my/denote-check-signatures)
    ("b" "Broken denote: links"  my/denote-check-broken-links)
    ("l" "Self-links"            my/denote-find-self-links)]
   ["Keywords"
    ("u" "Used once only"        my/maintenance-single-keywords)
    ("z" "Notes with none"       my/maintenance-zero-keywords)
    ("c" "Count distinct"        my/maintenance-count-keywords)]
   ["Repair (renames files)"
    ("R" "Change this note's identifier" my/denote-change-identifier)
    ("I" "Fix duplicate identifiers"     my/denote-fix-duplicates)
    ("K" "Rename or remove a keyword"    my/maintenance-rename-keyword)
    ("O" "Alphabetise all keywords"      my/maintenance-sort-keywords)
    ("S" "Sync front matter ↔ names"     my/maintenance-sync-metadata)]
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
