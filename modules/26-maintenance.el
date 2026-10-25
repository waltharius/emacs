;;; 26-maintenance.el --- Integrity reports and the Maintenance menu -*- lexical-binding: t; -*-

;; MyPKS-Requires: 27-denote-identifiers
;; MyPKS-Optional: yes
;; MyPKS-Switch: my/maintenance-mode

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
;;
;; REPORTS HERE, REPAIRS IN 26b
;;
;; Split on 2026-10-25 (MODULES.org): this module reads the collection
;; and reports, and owns the Maintenance menu (C-c n !), with a column
;; of reports and a column of repairs.  Renaming or removing a keyword
;; across the collection -- the one repair written here -- is
;; 26b-maintenance-repairs.el, which adds itself to the repairs column;
;; the identifier repairs are 27-denote-identifiers.el's.
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
;; The keyword side is therefore written against Denote's FILE-NAMING
;; SCHEME rather than against its functions.  Two attempts to call them
;; failed on argument count -- `denote-rename-file-keywords', then
;; `denote-rename-file' -- because those signatures have changed across
;; releases, and correcting a call only moves the failure to the next
;; one.  The scheme itself does not change: it is what Denote exists to
;; promise.  See the section on writing keywords below.
;;
;; SCOPE: INBOX YES, ATTACHMENTS NO
;;
;; Everything here reads `my/denote-all-files' from 27, which walks
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
;; Reports are on lower-case keys and open a buffer.  Anything that
;; renames files across the collection is on a capital, in the repairs
;; column, so a mistyped key cannot start one.
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

(defun my/maintenance-require-identifiers ()
  "Signal unless 27-denote-identifiers.el has been loaded."
  (unless (and (fboundp 'my/denote-all-files)
               (fboundp 'my/denote-identifier-table))
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
    (dolist (file (my/denote-all-files))
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
  (my/maintenance-require-identifiers)
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
    (dolist (file (my/denote-all-files))
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
  (my/maintenance-require-identifiers)
  (let* ((known (my/denote-identifier-table (my/denote-all-files)))
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
;; Keywords are read from file names, which is where Denote keeps them.
;; The reader below and the name builder of 26b-maintenance-repairs.el
;; are inverses of each other and must agree exactly about where the
;; keyword field begins, which is why both parse the scheme rather than
;; one of them borrowing an accessor from Denote.  See the Commentary above for
;; what the scope includes.

(defun my/maintenance-file-keywords (file)
  "Return FILE's keywords, read from its file name, as a list of strings.

The inverse of the name builder of 26b-maintenance-repairs.el.  Both find the keyword
field at the first double underscore of the base name: a title slug
never contains one, so it is a reliable boundary, and having the two
agree by construction is what stops a rename from computing a name for a
file it misread."
  (let ((base (file-name-base file)))
    (when (string-match "__" base)
      (split-string (substring base (match-end 0)) "_" t))))

(defun my/maintenance-keyword-table ()
  "Return a hash of keyword -> list of files using it."
  (my/maintenance-require-identifiers)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file (my/denote-all-files))
      (dolist (keyword (my/maintenance-file-keywords file))
        (puthash keyword (cons file (gethash keyword table)) table)))
    table))

(defun my/maintenance-keyword-names (&optional table)
  "Return every keyword in TABLE, sorted alphabetically."
  (let (names)
    (maphash (lambda (keyword _files) (push keyword names))
             (or table (my/maintenance-keyword-table)))
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

Each keyword is a button that starts a rename of it, when
26b-maintenance-repairs.el is loaded."
  (interactive)
  (let* ((table (my/maintenance-keyword-table))
         (names (my/maintenance-keyword-names table))
         (buffer (get-buffer-create "*Denote Keyword Inventory*")))
    (if (null names)
        (message "No keywords found")
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "%d keyword(s) across %d note(s) under %s.\n"
                          (length names)
                          (length (my/denote-all-files))
                          my-notes-dir))
          (insert "Attachments are not listed: they carry identifiers, not keywords.\n")
          (when (fboundp 'my/maintenance-rename-keyword)
            (insert "Click a keyword to rename or remove it everywhere.\n"))
          (insert "A keyword used once is marked - usually specific, sometimes a typo.\n\n")
          (dolist (keyword names)
            (let ((count (length (gethash keyword table))))
              (insert (format "%5d  " count))
              ;; A button only with 26b-maintenance-repairs.el loaded,
              ;; which does the renaming.
              (if (fboundp 'my/maintenance-rename-keyword)
                  (insert-text-button
                   keyword
                   'action (lambda (_) (my/maintenance-rename-keyword keyword))
                   'follow-link t
                   'help-echo (format "Rename or remove `%s' across the collection"
                                      keyword))
                (insert keyword))
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
  (my/maintenance-require-identifiers)
  (let ((files (seq-remove #'my/maintenance-file-keywords
                           (my/denote-all-files))))
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
;; ============================================================
;; MENU
;; ============================================================

(transient-define-prefix my/notes-maintenance-menu ()
  "Check the collection's integrity and repair what is broken."
  [["Reports (read only)"
    ("i" "Duplicate identifiers" my/denote-check-identifiers)
    ("g" "Duplicate signatures"  my/denote-check-signatures)
    ("b" "Broken denote: links"  my/denote-check-broken-links)
    ("l" "Self-links"            my/denote-find-self-links)
    ("w" "Links to the wrong note?" my/denote-check-suspect-links)
    ("k" "Keyword inventory"     my/maintenance-keyword-inventory)
    ("z" "Notes with no keywords" my/maintenance-notes-without-keywords)]
   ["Repairs (rename files)"
    ("R" "Change this note's identifier" my/denote-change-identifier)
    ("I" "Fix duplicate identifiers"     my/denote-fix-duplicates)
    ("W" "Repoint links to the wrong note" my/denote-repair-suspect-links)]
   [("q" "Quit" transient-quit-one)]])

;; Appended after "," (Settings), which 12-transient.el owns, in the
;; second column -- not after "a" (Add to dict), which belongs to
;; 03-spelling.el and is absent without it.  Through the helper that
;; degrades gracefully when 12-transient.el is absent.
(defgroup my/maintenance nil
  "Integrity reports and the Maintenance menu (26-maintenance.el)."
  :tag "Maintenance"
  :group 'mypks-notes)

;; ============================================================
;; ON AND OFF
;; ============================================================
;; `my/maintenance-mode' is this module's switch (module contract, rule
;; 12): on, the Maintenance entry of the main menu (C-c n !); off, gone.
;; The commands stay defined for M-x.  Customize saves the position in
;; this machine's settings (M-x customize-option RET my/maintenance-
;; mode).

(defconst my/maintenance--menu-entries
  '((append my/notes-menu "," ("!" "Maintenance → integrity/keywords/repair" my/notes-maintenance-menu)))
  "Menu entries of this module, for `my/transient-entries'.")

(define-minor-mode my/maintenance-mode
  "Maintenance as a module, switched on and off.
On: the Maintenance entry of the main menu (C-c n !).  Off: they are
gone, and the commands remain for M-x.  Customize saves the position
in this machine's settings."
  :global t
  :init-value t
  :group 'my/maintenance
  (with-eval-after-load '12-transient
    (when (fboundp 'my/transient-entries)
      (my/transient-entries my/maintenance-mode my/maintenance--menu-entries))))

(my/maintenance-mode (if my/maintenance-mode 1 -1))

(provide '26-maintenance)
;;; 26-maintenance.el ends here
