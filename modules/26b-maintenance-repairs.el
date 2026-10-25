;;; 26b-maintenance-repairs.el --- Rename or remove a keyword across the collection -*- lexical-binding: t; -*-

;; MyPKS-Requires: 26-maintenance 27-denote-identifiers
;; MyPKS-Optional: yes
;; MyPKS-Switch: my/maintenance-repairs-mode
;; Docs: ~/.emacs.d/function_helper.org::#maintenance

;;; Commentary:
;; The repair half of the Maintenance menu (C-c n !): renaming or
;; removing one keyword across the collection, through a review list
;; with a preview, one decision per note.  Split from 26-maintenance.el
;; on 2026-10-25 (MODULES.org): that module reads and reports, this one
;; renames files.  It reads keywords with 26's `my/maintenance-file-
;; keywords', the inverse of the name builder here
;; (`my/maintenance--new-file-name'); the two must agree on where the
;; keyword field begins.  Off, the reports stay and K is gone from the
;; menu; the commands remain for M-x.

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'tabulated-list)

(declare-function my/maintenance-file-keywords "26-maintenance" (file))
(declare-function my/maintenance-keyword-table "26-maintenance" ())
(declare-function my/maintenance-keyword-names "26-maintenance" (&optional table))
(declare-function my/maintenance-require-identifiers "26-maintenance" ())

;; ============================================================
;; KEYWORD RENAME
;; ============================================================

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

;; ------------------------------------------------------------
;; Writing a note's keywords
;; ------------------------------------------------------------
;; Done here rather than through Denote's renaming commands.  Two
;; attempts to call them failed on argument count --
;; `denote-rename-file-keywords' and then `denote-rename-file' itself --
;; because those signatures have changed across Denote releases.
;; Correcting a call only moves the failure to the next release.
;;
;; What does not change is the file-naming scheme, which is the whole
;; point of Denote and is specified in its manual:
;;
;;   IDENTIFIER[==SIGNATURE][--TITLE][__KEYWORD_KEYWORD].EXTENSION
;;
;; and, for Org, the `#+filetags:' line holding the same keywords as
;; `:one:two:'.  Changing a keyword means editing those two places and
;; nothing else.  That is a smaller and more stable contract than any
;; function signature, and it is the contract Denote itself promises to
;; keep.
;;
;; The identifier, signature and title are never touched, so unlike
;; `denote-rename-file' -- which rebuilds the whole name from
;; components and would also "correct" a title that disagrees with its
;; front matter -- nothing arrives alongside the change that was asked
;; for.
;;
;; ORDER, AND WHAT AN INTERRUPTION LEAVES
;;
;; Front matter first, file name second.  Interrupted in between, the
;; note has its new keywords and its old name -- visible, and repaired
;; by running the same rename again.  The other order would leave a name
;; claiming keywords the note does not have.
;;
;; The edit itself goes to the file, not through whatever buffer happens
;; to be visiting it.  A buffer can be read-only for reasons that have
;; nothing to do with the file -- `view-mode', which the preview here
;; turns on -- and fighting that in order to write to disk is the wrong
;; way round.  An open buffer is re-read afterwards instead.

;; Denote's, declared so the reference below is dynamic.
(defvar denote-sort-keywords)

(defun my/maintenance--normalize-keyword (keyword)
  "Return KEYWORD in the shape a Denote file name can hold.

Underscore separates keywords in a file name and a space cannot appear
in one, so both become a hyphen; the rest is lower-cased.  This is not
Denote's full sluggification, and does not try to be: keywords here are
normally chosen from the completion list of those already in use, which
are in that shape already."
  (let ((clean (string-trim (or keyword ""))))
    (unless (string-empty-p clean)
      (downcase (replace-regexp-in-string "[ \t_]+" "-" clean)))))

(defun my/maintenance--sort-keywords (keywords)
  "Return KEYWORDS in the order Denote would store them.

Alphabetical unless `denote-sort-keywords' is bound and nil, matching
Denote's own default and its choice of `string-lessp'."
  (if (and (boundp 'denote-sort-keywords) (not denote-sort-keywords))
      keywords
    (sort (copy-sequence keywords) #'string-lessp)))

(defun my/maintenance--new-file-name (file keywords)
  "Return the path FILE would have carrying KEYWORDS.

Only the `__KEYWORDS' component is rebuilt.  Everything before it --
identifier, signature, title -- is carried across as text, so it cannot
be altered by mistake.  A title slug never contains a double underscore,
which is what makes the first one a reliable boundary."
  (let* ((directory (file-name-directory file))
         (extension (file-name-extension file t))
         (base (file-name-base file))
         (stem (if (string-match "__" base)
                   (substring base 0 (match-beginning 0))
                 base)))
    (expand-file-name
     (concat stem
             (when keywords (concat "__" (string-join keywords "_")))
             extension)
     directory)))

(defun my/maintenance--write-filetags (keywords)
  "Rewrite the `#+filetags:' line of the current buffer to hold KEYWORDS.

Removes the line when KEYWORDS is nil: a field asserting nothing is
noise.  Adds one above `#+identifier:', where Denote puts it, when the
note has none and keywords are being given to it.

Only the front matter is searched: the lines from the top of the file
that are `#+KEY:' lines, up to the first that is not.  A `#+filetags:'
further down -- an example in a source block, however early -- is the
note's text, not its metadata.  Until 2026-10-24 the bound was the
first 4096 characters, which a short note's example fell within
(outside audits of 2026-10-24)."
  (save-restriction
    (widen)
    (save-excursion
      (goto-char (point-min))
      (let ((value (when keywords
                     (concat ":" (string-join keywords ":") ":")))
            (limit (save-excursion
                     (goto-char (point-min))
                     (while (looking-at "#\\+[[:alnum:]_-]+:")
                       (forward-line 1))
                     (point))))
        (cond
         ((re-search-forward "^\\(#\\+filetags:[ \t]*\\)\\(.*\\)$" limit t)
          (if keywords
              (unless (equal (match-string 2) value)
                (replace-match (concat (match-string 1) value) t t))
            (delete-region (line-beginning-position)
                           (min (point-max) (1+ (line-end-position))))))
         (keywords
          (goto-char (point-min))
          (if (re-search-forward "^#\\+identifier:" limit t)
              (beginning-of-line)
            (goto-char (point-min))
            (forward-line 1))
          (insert "#+filetags:  " value "\n")))))))

(defun my/maintenance--set-keywords (file keywords)
  "Give FILE the keyword list KEYWORDS.  Return its path afterwards.

Writes the `#+filetags:' line, renames the file, and re-reads any buffer
that was visiting it.  Refuses rather than guesses in the two cases
where guessing would lose work: a buffer with unsaved changes, and a
destination name already taken.

THE EDIT GOES TO THE DISK, NOT THROUGH THE BUFFER

An earlier version edited the visiting buffer and saved it, which failed
with `Buffer is read-only' whenever that buffer happened to be in
`view-mode' -- which the preview here puts it in, and which any number
of other things might.  Fighting a buffer's read-only state in order to
write to a file is the wrong way round: nothing about the file requires
the buffer's cooperation.

So the file is edited through a temporary buffer, and a buffer visiting
it is brought back into line afterwards with `revert-buffer'.  Its
read-only state is preserved across `set-visited-file-name', and
`:preserve-modes' keeps `view-mode' and anything else it had."
  (unless (equal (file-name-extension file) "org")
    (user-error "Only Org notes are handled here: %s"
                (file-name-nondirectory file)))
  (let* ((wanted (my/maintenance--sort-keywords
                  (delete-dups
                   (delq nil (mapcar #'my/maintenance--normalize-keyword
                                     keywords)))))
         (new-file (my/maintenance--new-file-name file wanted))
         (buffer (find-buffer-visiting file)))
    (when (and buffer (buffer-modified-p buffer))
      (user-error "%s has unsaved changes - save it first"
                  (file-name-nondirectory file)))
    (when (and (not (equal new-file file)) (file-exists-p new-file))
      (user-error "%s already exists" (file-name-nondirectory new-file)))
    ;; 1. Front matter, on disk.
    (with-temp-buffer
      (insert-file-contents file)
      (my/maintenance--write-filetags wanted)
      (write-region (point-min) (point-max) file nil 'silent))
    ;; 2. File name.
    (unless (equal new-file file)
      (rename-file file new-file)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (let ((read-only buffer-read-only))
            ;; Third argument: the file has already been renamed, so do
            ;; not mark the buffer modified or offer to write it again.
            (set-visited-file-name new-file :no-query :along-with-file)
            (setq buffer-read-only read-only)))))
    ;; 3. Bring an open buffer back into line with what is now on disk.
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (revert-buffer :ignore-auto :noconfirm :preserve-modes)))
    new-file))

(defun my/maintenance--keyword-list-entries ()
  "Convert `my/maintenance--keyword-entries' into tabulated-list form."
  (mapcar
   (lambda (entry)
     (let ((file (plist-get entry :file)))
       (list entry
             (vector (plist-get entry :status)
                     (string-join (my/maintenance-file-keywords file) ",")
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
      (let* ((current (my/maintenance-file-keywords file))
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
  (my/maintenance-require-identifiers)
  (let* ((table (my/maintenance-keyword-table))
         (names (my/maintenance-keyword-names table))
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
;; ON AND OFF
;; ============================================================
;; `my/maintenance-repairs-mode' is this module's switch (module
;; contract, rule 12): on, K in the repairs column of the Maintenance
;; menu; off, gone.

(defgroup my/maintenance-repairs nil
  "Renaming or removing a keyword across the collection (26b-maintenance-repairs.el)."
  :tag "Maintenance repairs"
  :group 'mypks-notes)

(defconst my/maintenance-repairs--menu-entries
  '((append my/notes-maintenance-menu "W" ("K" "Rename or remove a keyword" my/maintenance-rename-keyword)))
  "Menu entries of this module, for `my/transient-entries'.")

(define-minor-mode my/maintenance-repairs-mode
  "Keyword repairs as a module, switched on and off.
On: K, rename or remove a keyword, in the repairs column of the
Maintenance menu (C-c n !).  Off: gone, and the commands remain for
M-x.  Customize saves the position in this machine's settings."
  :global t
  :init-value t
  :group 'my/maintenance-repairs
  (with-eval-after-load '12-transient
    (when (fboundp 'my/transient-entries)
      (my/transient-entries my/maintenance-repairs-mode
                            my/maintenance-repairs--menu-entries))))

(my/maintenance-repairs-mode (if my/maintenance-repairs-mode 1 -1))

(provide '26b-maintenance-repairs)
;;; 26b-maintenance-repairs.el ends here
