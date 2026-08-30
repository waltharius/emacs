;;; 25-inbox-review.el --- Review migrated Obsidian notes -*- lexical-binding: t; -*-

;;; Commentary:
;; Review queue for notes migrated from Obsidian into ~/notes/inbox
;; (a staging folder, deliberately NOT a Denote silo).  Modeled on the
;; Readwise review list in 24-readwise.el: a `tabulated-list-mode'
;; buffer in its own tab, a side window for previews, and single-key
;; actions.
;;
;; M-x my/inbox-review opens the list.  Keys:
;;   RET   preview the note in a side window (focus stays on the list)
;;   o     step into the preview window (view-mode; q closes it)
;;   e     edit the note
;;   p / d move to the pks / docu silo: gives the note an identifier
;;         that is free in the silos first (bumping only the time, never
;;         the date, and never touching notes already filed), then
;;         rewrites [[wikilinks]] naming it into denote links
;;   z     promote: move to pks, open, run `my/zettel-adopt'
;;   t     edit tags (denote-rename-file)
;;   k     reject: move to ~/notes/inbox-odrzucone/
;;   /     filter by title/folder/tags, C-/ clears
;;   g     refresh, S/click sorts, q quits
;;
;; In a note buffer (opened from the list or any org buffer):
;;   M-x my/inbox-extract (C-c X in inbox notes) - carve out the
;;   region / subtree / paragraph into a NEW denote note in a chosen
;;   silo, leaving a denote link behind.
;;
;; The inbox stays invisible to Denote until notes are moved out; see
;; `denote-excluded-directories-regexp' below.

;;; Code:

(require 'org)
(require 'denote)
(require 'seq)
(require 'subr-x)

;; 27-denote-identifiers.el supplies the identifier-uniqueness helpers.
;; It cannot be pulled in with `require': modules in this configuration
;; are loaded by explicit path from init.el and `modules/' is not on
;; `load-path', so `require' would fail and abort this file halfway
;; through.  Load it by path if init.el has not already done so.
(unless (featurep '27-denote-identifiers)
  (let ((sibling (expand-file-name "modules/27-denote-identifiers.el"
                                   user-emacs-directory)))
    (if (file-exists-p sibling)
        (load sibling nil t)
      (message "25-inbox-review: 27-denote-identifiers.el not found; \
identifier clash protection is disabled"))))

;; ============================================================
;; CONFIG
;; ============================================================

(defcustom my/inbox-directory (expand-file-name "~/notes/inbox/")
  "Staging folder with migrated notes awaiting review."
  :type 'directory :group 'my)

(defcustom my/inbox-reject-directory
  (expand-file-name "~/notes/inbox-odrzucone/")
  "Where rejected notes go.  A trash folder, not deletion - review
mistakes are certain over months of processing; empty it once, at the
end."
  :type 'directory :group 'my)

(defcustom my/inbox-silos
  `(("pks"  . ,(expand-file-name "~/notes/pks/"))
    ("docu" . ,(expand-file-name "~/notes/docu/")))
  "Silos a reviewed note can be accepted into."
  :type '(alist :key-type string :value-type directory) :group 'my)

(defcustom my/inbox-journal-directory (expand-file-name "~/notes/journal/")
  "Journal silo.  Kept as its own variable because journal notes are the
main source of wikilinks to migrated notes."
  :type 'directory :group 'my)

(defcustom my/inbox-link-scan-directories
  (list (expand-file-name "~/notes/journal/")
        (expand-file-name "~/notes/pks/")
        (expand-file-name "~/notes/docu/")
        (expand-file-name "~/notes/inbox/"))
  "Directories searched for [[Title]] wikilinks when a note is accepted.
All silos, because an already-filed note may name this one; and the
inbox, because notes still awaiting review link to each other."
  :type '(repeat directory) :group 'my)

(defvar my/inbox-tab-name "Inbox"
  "Name of the tab-bar tab holding the review buffer.")

(defvar my/inbox--buffer "*Inbox Review*")

;; Keep the staging area and the trash invisible to Denote: with
;; `denote-directory' set to ~/notes/ every subdirectory is a silo by
;; default, and half-reviewed notes showing up in denote searches
;; would defeat the point of staging.  "inbox" also matches
;; "inbox-odrzucone" as a substring, which is exactly what we want.
(setq denote-excluded-directories-regexp "inbox")

;; ============================================================
;; COLLECTING ENTRIES
;; ============================================================

(defun my/inbox--files ()
  "Return org files awaiting review."
  (when (file-directory-p my/inbox-directory)
    (directory-files my/inbox-directory t "\\.org\\'")))

(defun my/inbox--file-meta (file)
  "Read FILE's front matter into a plist without visiting it."
  (with-temp-buffer
    (insert-file-contents file nil 0 4096)
    (cl-flet ((grab (re)
                (goto-char (point-min))
                (when (re-search-forward re nil t)
                  (string-trim (match-string 1)))))
      (let ((ident (or (grab "^#\\+identifier:\\s-*\\([0-9T]+\\)") "")))
        (list :file file
              :title (or (grab "^#\\+title:\\s-*\\(.+\\)$")
                         (file-name-nondirectory file))
              :date (if (>= (length ident) 8)
                        (format "%s-%s-%s" (substring ident 0 4)
                                (substring ident 4 6) (substring ident 6 8))
                      "")
              :tags (or (grab "^#\\+filetags:\\s-*\\(.+\\)$") "")
              :status (or (grab "^:status:\\s-*\\(.+\\)$") "")
              :source (or (grab "^:source_path:\\s-*\\(.+\\)$") ""))))))

(defun my/inbox--collect ()
  "Return metadata plists for every note in the inbox."
  (mapcar #'my/inbox--file-meta (my/inbox--files)))

;; ============================================================
;; LIST UI
;; ============================================================

(defvar-local my/inbox--entries nil
  "Entries backing the current list.")

(defvar my/inbox--filter ""
  "Text currently filtering the list.  Global so it survives refreshes;
shown in the mode line so a narrowed list never looks complete.")

(defvar my/inbox--sort-key '("Date" . nil)
  "Sort column and direction remembered across refreshes.")

(defvar my/inbox--note-window nil
  "Window used for previews.  Global on purpose - see the identical
variable in 24-readwise.el for the reasoning.")

(defun my/inbox--cell (value)
  "Return VALUE as a string fit for a `tabulated-list-mode' cell.

`tabulated-list-print-entry' requires a string and signals on anything
else, taking the whole list down with it -- one malformed note and a
thousand good ones become unreachable.  This is the boundary where that
type is demanded, so it is the boundary where it is guaranteed: a note
with a field this module cannot read shows an empty cell and stays on
the list, where it can be seen and fixed."
  (if (stringp value) value ""))

(defun my/inbox--folder (entry)
  "Return the source folder of ENTRY, as a string.

`file-name-directory' returns nil, not the empty string, when its
argument holds no directory part -- and the empty string holds none.  A
note without a `:source_path:\=' therefore used to put nil into the
Folder column and break the whole list.  Notes created in the inbox
rather than migrated into it have no source path at all, so this was
waiting for the first one of those."
  (let ((source (plist-get entry :source)))
    (or (and (stringp source)
             (not (string-empty-p source))
             (file-name-directory source))
        "")))

(defun my/inbox--list-entries (entries)
  "Convert ENTRIES into `tabulated-list-entries' form."
  (mapcar
   (lambda (e)
     (list e (vector
              (my/inbox--cell (plist-get e :date))
              (my/inbox--cell (plist-get e :status))
              (my/inbox--cell (plist-get e :tags))
              (my/inbox--cell (my/inbox--folder e))
              (my/inbox--cell (plist-get e :title)))))
   entries))

;; Defined before `define-derived-mode', which creates NAME-map itself
;; when the symbol is still unbound (same trick as in 24-readwise.el).
(defvar my/inbox-review-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'my/inbox-preview)
    (define-key map (kbd "o")   #'my/inbox-visit-preview)
    (define-key map (kbd "e")   #'my/inbox-edit)
    (define-key map (kbd "p")   (lambda () (interactive) (my/inbox-accept "pks")))
    (define-key map (kbd "d")   (lambda () (interactive) (my/inbox-accept "docu")))
    (define-key map (kbd "z")   #'my/inbox-promote-to-zettel)
    (define-key map (kbd "t")   #'my/inbox-edit-tags)
    (define-key map (kbd "k")   #'my/inbox-reject)
    (define-key map (kbd "/")   #'my/inbox-filter)
    (define-key map (kbd "C-/") #'my/inbox-clear-filter)
    (define-key map (kbd "g")   #'my/inbox-review)
    (define-key map (kbd "q")   #'quit-window)
    map)
  "Keymap for `my/inbox-review-mode'.")

(define-derived-mode my/inbox-review-mode tabulated-list-mode "Inbox"
  "Major mode for reviewing migrated notes.
\\{my/inbox-review-mode-map}"
  (setq tabulated-list-format
        (vector (list "Date" 11 t)
                (list "Status" 9 t)
                (list "Tags" 24 t)
                (list "Folder" 30 t)
                (list "Title" 0 t)))
  (setq tabulated-list-sort-key my/inbox--sort-key)
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header)
  (hl-line-mode 1))

(defun my/inbox--render ()
  "Redraw the list applying the current filter."
  (let* ((needle (downcase (string-trim my/inbox--filter)))
         (kept (if (string-empty-p needle)
                   my/inbox--entries
                 (seq-filter
                  (lambda (e)
                    (string-match-p
                     (regexp-quote needle)
                     (downcase (concat (plist-get e :title) " "
                                       (plist-get e :tags) " "
                                       (or (plist-get e :source) "")))))
                  my/inbox--entries))))
    (setq tabulated-list-entries (my/inbox--list-entries kept))
    (tabulated-list-print t)
    (setq mode-line-process
          (unless (string-empty-p needle) (format " [/%s]" needle)))
    (force-mode-line-update)
    (length kept)))

;;;###autoload
(defun my/inbox-review ()
  "List migrated notes awaiting review."
  (interactive)
  (let ((entries (my/inbox--collect)))
    (when (fboundp 'my/fixed-tab-goto)
      (my/fixed-tab-goto my/inbox-tab-name))
    (let ((buffer (get-buffer-create my/inbox--buffer)))
      (with-current-buffer buffer
        (when (derived-mode-p 'my/inbox-review-mode)
          (setq my/inbox--sort-key tabulated-list-sort-key))
        (my/inbox-review-mode)
        (setq my/inbox--entries entries)
        (my/inbox--render))
      (switch-to-buffer buffer)
      (message "%d note(s) left to review%s"
               (length entries)
               (if (string-empty-p my/inbox--filter) ""
                 (format ", filtered by \"%s\"" my/inbox--filter))))))

(defun my/inbox-filter (needle)
  "Filter the list by NEEDLE matching title, tags or source folder."
  (interactive "sFilter: ")
  (setq my/inbox--filter needle)
  (my/inbox--render))

(defun my/inbox-clear-filter ()
  "Clear the current filter."
  (interactive)
  (setq my/inbox--filter "")
  (my/inbox--render))

(defun my/inbox--entry ()
  "Entry at point, or an error naming what to do about it."
  (or (tabulated-list-get-id)
      (if (derived-mode-p 'my/inbox-review-mode)
          (user-error "Point is not on a note row - move to one first")
        (user-error "Not in the inbox list (M-x my/inbox-review)"))))

(defun my/inbox-preview ()
  "Show the note at point in a side window, keeping focus on the list.

Focus stays here on purpose: the action keys live in this buffer, and
in the preview buffer `view-mode\=' binds p and n to its own search
commands, so a preview that stole focus would silently swallow p/d/z.
Use o to step into the preview when you want to scroll it."
  (interactive)
  (let* ((entry (my/inbox--entry))
         (buffer (find-file-noselect (plist-get entry :file)))
         (window (if (window-live-p my/inbox--note-window)
                     my/inbox--note-window
                   (setq my/inbox--note-window (split-window-right 70)))))
    (set-window-buffer window buffer)
    (with-current-buffer buffer
      (view-mode 1)
      (goto-char (point-min)))
    (set-window-point window (point-min))))

(defun my/inbox-visit-preview ()
  "Move point into the preview window (q there returns to the list)."
  (interactive)
  (unless (window-live-p my/inbox--note-window)
    (my/inbox-preview))
  (select-window my/inbox--note-window))

(defun my/inbox-edit ()
  "Open the note at point for editing."
  (interactive)
  (let ((buffer (find-file-noselect (plist-get (my/inbox--entry) :file))))
    (with-current-buffer buffer (view-mode -1))
    (pop-to-buffer buffer)))

;; ============================================================
;; ACCEPT / REJECT / PROMOTE
;; ============================================================

(defun my/inbox--identifier (file)
  "Denote identifier from FILE's name."
  (when (string-match "\\`\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)"
                      (file-name-nondirectory file))
    (match-string 1 (file-name-nondirectory file))))

(defun my/inbox--link-names (entry)
  "Names under which other notes may wikilink to ENTRY: the original
Obsidian file name and the org title."
  (let ((names (list (plist-get entry :title))))
    (when-let* ((src (plist-get entry :source)))
      (unless (string-empty-p src)
        (push (file-name-sans-extension (file-name-nondirectory src))
              names)))
    (seq-uniq (seq-remove #'string-empty-p names))))

(defun my/inbox--fix-journal-links (entry ident)
  "Rewrite [[name]] wikilinks to ENTRY as denote links to IDENT.
Searches `my/inbox-link-scan-directories\=': the conversion could not
resolve these links, because the target note did not exist in Org yet
and might still be rejected.  Returns the number of links rewritten."
  (let ((total 0)
        (files (seq-mapcat (lambda (dir)
                             (when (file-directory-p dir)
                               (directory-files dir t "\\.org\\'")))
                           my/inbox-link-scan-directories)))
    (dolist (name (my/inbox--link-names entry))
      (let ((needle (concat "[[" name))
            (link-re (concat "\\[\\[" (regexp-quote name)
                             "\\(?:#[^]|]*\\)?\\(?:|\\([^]]*\\)\\)?\\]\\]")))
        (dolist (file files)
          ;; Never point a note at itself.  Before identifiers were made
          ;; unique this happened for real: a journal note and an
          ;; accepted note shared YYYYMMDDT000000, so the rewrite
          ;; resolved the journal note's own link to its own identifier.
          (when (and (not (equal (my/denote--file-identifier file) ident))
                     ;; Cheap containment check before visiting the file.
                     (with-temp-buffer
                       (insert-file-contents file)
                       (goto-char (point-min))
                       (search-forward needle nil t)))
            (with-current-buffer (find-file-noselect file)
              (save-excursion
                (goto-char (point-min))
                (while (re-search-forward link-re nil t)
                  (replace-match
                   (format "[[denote:%s][%s]]" ident
                           (or (match-string 1) name))
                   t t)
                  (setq total (1+ total))))
              (save-buffer))))))
    total))

(defun my/inbox--ensure-unique-identifier (file)
  "Return FILE, or its new path after resolving an identifier clash.

The migration gave notes of unknown creation time the identifier
YYYYMMDDT000000, and journal notes without a time in their first
heading got the same.  A note in the inbox therefore routinely shares
an identifier with a journal entry from the same day.  That is harmless
while it sits in the inbox, and must be settled at the moment it enters
a silo, because `denote:\=' links resolve through identifiers alone.

Only the INBOX note ever moves.  Notes already filed in journal, pks or
docu keep their identifiers, so every existing link in the collection
keeps working.  Only the time part changes - the date is what the
migration actually knew about the note."
  (unless (fboundp 'my/denote--silo-identifier-table)
    (user-error "27-denote-identifiers.el is not loaded - \
cannot check identifier uniqueness"))
  (let* ((id (my/denote--file-identifier file))
         (table (and id (my/denote--silo-identifier-table)))
         (clash (and id (car (gethash id table)))))
    (if (null clash)
        file
      (let ((new-id (my/denote--next-free-identifier id table)))
        (message "%s is taken by %s - this note becomes %s"
                 id (file-relative-name clash my-notes-dir) new-id)
        (my/denote-change-identifier file new-id)))))

(defun my/inbox--move (file dir)
  "Move FILE into DIR, return the new path."
  (make-directory dir t)
  (let ((target (expand-file-name (file-name-nondirectory file) dir)))
    (when (file-exists-p target)
      (user-error "Already exists: %s" target))
    (rename-file file target)
    target))

(defun my/inbox-accept (silo)
  "Move the note at point into SILO and repair journal links to it."
  (interactive (list (completing-read "Silo: " (mapcar #'car my/inbox-silos)
                                      nil t)))
  (let* ((entry (my/inbox--entry))
         (file (plist-get entry :file))
         (dir (cdr (assoc silo my/inbox-silos)))
         (ident (my/inbox--identifier file)))
    (unless dir (user-error "Unknown silo: %s" silo))
    ;; Resolve identifier clashes first: `ident' below must be the one
    ;; the note will actually keep, or the journal links would be
    ;; rewritten to point at the wrong note.
    (setq file (my/inbox--ensure-unique-identifier file))
    (setq ident (my/inbox--identifier file))
    (let ((target (my/inbox--move file dir))
          (fixed (if ident (my/inbox--fix-journal-links entry ident) 0)))
      (message "%s -> %s%s" (plist-get entry :title) silo
               (if (> fixed 0)
                   (format " (%d wikilink(s) repaired)" fixed) ""))
      (ignore target))
    (my/inbox-review)))

(defun my/inbox-reject ()
  "Move the note at point to the reject folder."
  (interactive)
  (let* ((entry (my/inbox--entry))
         (file (plist-get entry :file)))
    (when (yes-or-no-p (format "Reject \"%s\"? " (plist-get entry :title)))
      (my/inbox--move file my/inbox-reject-directory)
      (message "Rejected: %s" (plist-get entry :title))
      (my/inbox-review))))

(defun my/inbox-promote-to-zettel ()
  "Move the note at point to pks, open it and adopt it into the ZK.
The :luhmann: property (its number in the old Obsidian tree) is a
placement hint; follow with `my/zettel-reparent' to slot it under an
existing thread."
  (interactive)
  (let* ((entry (my/inbox--entry))
         (dir (cdr (assoc "pks" my/inbox-silos)))
         ;; Settle any identifier clash before the note enters the silo.
         (file (my/inbox--ensure-unique-identifier
                (plist-get entry :file)))
         (ident (my/inbox--identifier file))
         (target (my/inbox--move file dir)))
    (when ident (my/inbox--fix-journal-links entry ident))
    (find-file target)
    (if (fboundp 'my/zettel-adopt)
        (call-interactively #'my/zettel-adopt)
      (message "my/zettel-adopt not available - note moved to pks"))))

(defun my/inbox-edit-tags ()
  "Edit the tags of the note at point via `denote-rename-file'."
  (interactive)
  (let ((file (plist-get (my/inbox--entry) :file)))
    (with-current-buffer (find-file-noselect file)
      (call-interactively #'denote-rename-file))
    (my/inbox-review)))

;; ============================================================
;; EXTRACT PART OF A NOTE INTO A NEW NOTE
;; ============================================================

(defun my/inbox--content-start ()
  "Return the position where the note's body begins.

Everything above it describes the note rather than being part of it:
the leading run of `#+key:' lines, and a `:PROPERTIES:' drawer sitting
directly beneath them.  A note with no front matter at all returns
`point-min', which is correct - all of it is body."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      ;; Leading `#+key:' lines, and the blank lines among them.
      (while (and (not (eobp))
                  (looking-at "^[ \t]*\\(#\\+[^:\n]+:\\|$\\)"))
        (forward-line 1))
      ;; A properties drawer here belongs to the file, not to a heading.
      (when (looking-at "^[ \t]*:PROPERTIES:[ \t]*$")
        (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
          (forward-line 1)))
      (point))))

(defun my/inbox--extract-bounds ()
  "Bounds of the text to extract: region, else subtree, else paragraph.

Never reaches into the front matter.  Without that floor the paragraph
fallback silently took it: `#+key:' lines are contiguous, so with point
anywhere among them the surrounding \"paragraph\" IS the front matter
block.  Extracting it produced a new note whose body was the source's
header - duplicated, since the new note gets a header of its own - and,
far worse, removed that header from the source, because extracted text
is replaced by a link.

When point is in the body and only the paragraph reaches too far up,
the start is clamped instead.  When point is itself in the front matter
there is nothing to extract and this says so."
  (let* ((floor (my/inbox--content-start))
         (bounds
          (cond
           ((use-region-p)
            (cons (region-beginning) (region-end)))
           ((and (derived-mode-p 'org-mode)
                 (save-excursion (ignore-errors (org-back-to-heading t))))
            (save-excursion
              (org-back-to-heading t)
              (let ((beg (point)))
                (org-end-of-subtree t t)
                (cons beg (point)))))
           (t (cons (save-excursion (backward-paragraph) (point))
                    (save-excursion (forward-paragraph) (point)))))))
    (when (< (car bounds) floor)
      (if (>= (point) floor)
          (setcar bounds floor)
        (user-error "Point is in the front matter - nothing to extract")))
    (when (>= (car bounds) (cdr bounds))
      (user-error "Nothing to extract here"))
    (when (string-empty-p
           (string-trim (buffer-substring-no-properties
                         (car bounds) (cdr bounds))))
      (user-error "Nothing to extract here"))
    bounds))

;;;###autoload
(defun my/inbox-extract ()
  "Extract the region / subtree / paragraph into a new denote note.
Prompts for title, keywords and target silo.  The extracted text is
replaced with a denote link, so the source keeps its context; the new
note records where it came from in :extracted_from:."
  (interactive)
  (let* ((bounds (my/inbox--extract-bounds))
         (text (buffer-substring-no-properties (car bounds) (cdr bounds)))
         ;; First line with something on it, minus any heading stars.
         ;; A `#+key:' line cannot reach here now that the bounds refuse
         ;; the front matter, but stripping one costs nothing and makes
         ;; a bad default impossible rather than merely unlikely.
         (default-title
          (string-trim
           (replace-regexp-in-string
            "\\`\\(?:\\*+\\s-*\\|#\\+[^:\n]+:\\s-*\\)" ""
            (or (seq-find (lambda (line)
                            (not (string-empty-p (string-trim line))))
                          (split-string text "\n"))
                ""))))
         (title (read-string
                 (format "Title (%s): " default-title)
                 nil nil default-title))
         (keywords (denote-keywords-prompt))
         (silo (completing-read "Silo: " (mapcar #'car my/inbox-silos)
                                nil t nil nil "pks"))
         (dir (cdr (assoc silo my/inbox-silos)))
         ;; `format-time-string' has second resolution, so two quick
         ;; extractions in the same second would collide.
         (ident (my/denote--next-free-identifier
                 (format-time-string "%Y%m%dT%H%M%S")))
         (slug (denote-sluggify-title title))
         (fname (if keywords
                    (format "%s--%s__%s.org" ident slug
                            (string-join (denote-sluggify-keywords keywords)
                                         "_"))
                  (format "%s--%s.org" ident slug)))
         (target (expand-file-name fname dir))
         (source (file-name-nondirectory (or buffer-file-name
                                             (buffer-name)))))
    (with-temp-file target
      (insert (format "#+title:      %s\n" title)
              (format "#+date:       %s\n"
                      (format-time-string "[%Y-%m-%d %a %H:%M]"))
              (if keywords
                  (format "#+filetags:   :%s:\n"
                          (string-join keywords ":"))
                "")
              (format "#+identifier: %s\n" ident)
              ":PROPERTIES:\n"
              (format ":extracted_from: %s\n" source)
              ":END:\n\n"
              (string-trim text) "\n"))
    ;; Replace the extracted text with a link to the new note.
    (delete-region (car bounds) (cdr bounds))
    (insert (format "[[denote:%s][%s]]\n" ident title))
    (message "Extracted to %s" (file-name-nondirectory target))))

;; Make the extract command handy in inbox notes without claiming a
;; global key.  NOT "C-c x": that is `my/zotero-menu' globally, and a
;; minor-mode map would shadow it inside exactly the buffers where
;; bibliography lookups are likely.  Capital X is unbound repo-wide.
(defvar my/inbox-note-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c X") #'my/inbox-extract)
    map)
  "Keymap for `my/inbox-note-mode'.")

(define-minor-mode my/inbox-note-mode
  "Minor mode active in notes under `my/inbox-directory'."
  :lighter " Inbox")

(defun my/inbox--maybe-enable-note-mode ()
  "Enable `my/inbox-note-mode' for files inside the inbox."
  (when (and buffer-file-name
             (file-in-directory-p buffer-file-name my/inbox-directory))
    (my/inbox-note-mode 1)))

(add-hook 'find-file-hook #'my/inbox--maybe-enable-note-mode)


;; ============================================================
;; TRANSIENT MENU  (C-c n t i)
;; Docs: ~/.emacs.d/function_helper.org::#menu-inbox
;; ============================================================
;; Appended to the Tools submenu rather than the top level, following
;; the rule stated in function_helper.org: new external integrations
;; belong under `my/notes-tools-menu'.  The `unless' guard makes
;; reloading this file idempotent, as in 24-readwise.el.

(defun my/inbox-open-directory ()
  "Open the inbox folder in Dired."
  (interactive)
  (if (file-directory-p my/inbox-directory)
      (dired my/inbox-directory)
    (user-error "No inbox directory: %s" my/inbox-directory)))

(defun my/inbox-open-reject-directory ()
  "Open the reject folder in Dired."
  (interactive)
  (if (file-directory-p my/inbox-reject-directory)
      (dired my/inbox-reject-directory)
    (user-error "Nothing rejected yet: %s" my/inbox-reject-directory)))

(transient-define-prefix my/inbox-menu ()
  "Review notes migrated from Obsidian."
  [["Review"
    ;; Promotion into a silo happens inside the review list, on the note
    ;; at point - it needs a selected row, so it cannot be offered here.
    ("r" "Review inbox  (p/d file it, k reject)" my/inbox-review)]
   ["In a note"
    ;; NOT promotion: this splits a fragment out into a NEW note, with a
    ;; new identifier and today's date, and leaves the source in place
    ;; with a link where the fragment was.
    ("x" "Extract fragment to a new note" my/inbox-extract)]
   ["Files"
    ("o" "Open inbox folder"   my/inbox-open-directory)
    ("O" "Open rejects folder" my/inbox-open-reject-directory)]
   ["Identifiers"
    ("c" "Check duplicates"    my/denote-check-identifiers)
    ("f" "Fix duplicates"      my/denote-fix-duplicates)
    ("s" "Find self-links"     my/denote-find-self-links)
    ("R" "Change identifier"   my/denote-change-identifier)]
   [("q" "Quit" transient-quit-one)]])

;; `my/transient-append' degrades on a missing prefix or anchor, but
;; calling it unguarded still needs 12-transient.el to have been loaded:
;; without it init aborts here with a void-function error naming this
;; file rather than the missing one.
(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-tools-menu "z"
                         '("i" "Inbox \u2192" my/inbox-menu))))

(provide '25-inbox-review)
;;; 25-inbox-review.el ends here
