;;; 24-readwise.el --- Import Readwise highlights -*- lexical-binding: t; -*-
;;; Commentary:
;; Pulls highlights from Readwise into one Org file per book, kept in
;; `my/readwise-directory' (~/Downloads/readwise by default).
;;
;; These files are deliberately OUTSIDE ~/notes/.  `denote-directory'
;; is the notes root, so anything under it is visible to every Denote
;; command, every dashboard and every search in this configuration.
;; Readwise material is raw input awaiting triage, not part of the
;; collection, so keeping it outside makes it invisible by default
;; rather than visible-with-exclusions.  It follows that these files
;; are disposable: nothing links to them, and losing them costs only
;; the time to re-sync.
;;
;; What makes that safe is that no local knowledge lives here.  Your
;; own commentary on a highlight is stored by Readwise in the
;; highlight's `note' field and comes back on every sync, so a book
;; file can always be regenerated exactly.
;;
;; Once a highlight has been promoted into ~/notes/pks/, the promoted
;; note carries the highlight's RW_ID.  "Have I processed this quote
;; already?" is therefore answered by searching pks, not by any index
;; kept here -- one source of truth, and it survives losing this
;; directory entirely.
;;
;; API reference: https://readwise.io/api_deets

;;; Code:

(require 'url)
(require 'auth-source)
(require 'json)
(require 'seq)
(require 'transient)

(defgroup my/readwise nil
  "Importing Readwise highlights into Org files."
  :group 'convenience)

;; ============================================================
;; SETTINGS
;; ============================================================

(defcustom my/readwise-directory (expand-file-name "~/Downloads/readwise/")
  "Directory holding one Org file per Readwise book.
Outside the notes tree on purpose; see the Commentary."
  :type 'directory
  :group 'my/readwise)

(defcustom my/readwise-categories '("books")
  "Readwise categories to import.
Readwise classifies every source into a category: books, articles,
tweets, podcasts, supplementals.  Only the ones listed here are
written to disk; everything else is fetched and discarded.

Adding a category is a one-item change here and needs no other edit,
which is the reason this is a list rather than a hardcoded test."
  :type '(repeat string)
  :group 'my/readwise)

(defcustom my/readwise-file-keywords '("readwise")
  "Denote keywords put in the front matter of every imported file.
The book's own category is appended automatically, so a book gets
`:readwise:books:'."
  :type '(repeat string)
  :group 'my/readwise)

(defvar my/readwise-state-file
  (expand-file-name "last-sync.txt" my/readwise-directory)
  "File recording the timestamp of the last successful sync.

Stored beside the imported files, not in .emacs.d, and that placement
is deliberate: losing the directory should mean losing the state too,
so that the next sync re-imports everything rather than silently
skipping books whose files are gone.")

(defconst my/readwise--export-url "https://readwise.io/api/v2/export/"
  "Readwise export endpoint.")

;; ============================================================
;; AUTHENTICATION
;; ============================================================

(defun my/readwise--token ()
  "Return the Readwise API token from auth-source.
Expects a line in ~/.authinfo.gpg of the form:

  machine readwise.io login apikey password YOUR-TOKEN"
  (if-let* ((found (car (auth-source-search :host "readwise.io"
                                            :user "apikey"
                                            :require '(:secret)
                                            :max 1)))
            (secret (plist-get found :secret)))
      (if (functionp secret) (funcall secret) secret)
    (user-error
     "No Readwise token found.  Add to ~/.authinfo.gpg: machine readwise.io login apikey password TOKEN")))

;; ============================================================
;; HTTP
;; ============================================================

(defun my/readwise--request (params)
  "GET the export endpoint with PARAMS, an alist of query parameters.
Returns the parsed JSON as an alist.  Signals on a non-200 response
rather than returning partial data, so a failed page cannot be
mistaken for an empty one."
  (let* ((query (mapconcat (lambda (cell)
                             (concat (url-hexify-string (car cell)) "="
                                     (url-hexify-string (cdr cell))))
                           (seq-filter #'cdr params) "&"))
         (url (if (string-empty-p query)
                  my/readwise--export-url
                (concat my/readwise--export-url "?" query)))
         (url-request-method "GET")
         (url-request-extra-headers
          (list (cons "Authorization" (concat "Token " (my/readwise--token))))))
    (with-current-buffer (url-retrieve-synchronously url t t 60)
      (unwind-protect
          (progn
            (goto-char (point-min))
            (unless (re-search-forward "^HTTP/[0-9.]+ 200" (line-end-position) t)
              (goto-char (point-min))
              (user-error "Readwise API error: %s"
                          (buffer-substring (point) (line-end-position))))
            (goto-char (point-min))
            (unless (re-search-forward "\n\r?\n" nil t)
              (user-error "Malformed HTTP response from Readwise"))
            (let ((json-object-type 'alist)
                  (json-array-type 'list)
                  (json-key-type 'symbol))
              (json-read)))
        (kill-buffer)))))

(defun my/readwise--fetch-all (&optional updated-after book-ids)
  "Fetch book records from Readwise, following pagination to the end.

UPDATED-AFTER is an ISO 8601 string; only highlights changed since
then are returned.  BOOK-IDS is a comma-separated string restricting
the export to those books.

Returns a list of book alists.  Note that with UPDATED-AFTER set, each
book carries only its CHANGED highlights -- which is why
`my/readwise-sync' uses this call to discover which books moved, then
re-fetches those books in full."
  (let ((cursor nil)
        (books nil)
        (page 0)
        (more t))
    (while more
      (setq page (1+ page))
      (message "Readwise: fetching page %d..." page)
      (let* ((data (my/readwise--request
                    `(("updatedAfter" . ,updated-after)
                      ("ids" . ,book-ids)
                      ("pageCursor" . ,cursor))))
             (results (alist-get 'results data))
             (next (alist-get 'nextPageCursor data)))
        (setq books (append books results))
        ;; json-read renders JSON null as :null, which is non-nil, so
        ;; testing for it explicitly is required to terminate.
        (if (and next (not (eq next :null)) (not (equal next "")))
            (setq cursor (format "%s" next))
          (setq more nil))))
    books))

;; ============================================================
;; RENDERING
;; ============================================================

(defun my/readwise--sanitize (string)
  "Return STRING safe to place in Org body text.
Only line-leading `*' and `#+' need neutralising: at column zero they
would start a heading or a keyword and break the file structure."
  (if (not (stringp string))
      ""
    (replace-regexp-in-string
     "^\\([*]+ \\|#\\+\\)" " \\1" (string-trim string))))

(defun my/readwise--location-string (highlight)
  "Return a human-readable location for HIGHLIGHT, or nil.
Readwise reports `location_type' as page, order or location; the
number means something different in each case, so the type is kept
rather than assuming pages."
  (let ((loc (alist-get 'location highlight))
        (type (alist-get 'location_type highlight)))
    (when (and loc (numberp loc))
      (pcase type
        ("page" (format "s. %d" loc))
        ("order" (format "poz. %d" loc))
        (_ (format "loc. %d" loc))))))

(defun my/readwise--render-highlight (highlight)
  "Return the Org representation of one HIGHLIGHT.

The Readwise id goes on a `#+name:' affiliated keyword rather than
into a heading with a property drawer.  Affiliated keywords attach to
the block without requiring a title, and these quotes have no natural
title -- one would have to be invented at import time and discarded at
promotion time.

The personal note is placed AFTER the quote block, not inside it.  A
heading at column zero inside `#+begin_quote' terminates the enclosing
section, leaving the block unclosed as far as `org-element' is
concerned even though it still renders acceptably."
  (let* ((id (alist-get 'id highlight))
         (text (my/readwise--sanitize (alist-get 'text highlight)))
         (note (alist-get 'note highlight))
         (location (my/readwise--location-string highlight))
         (url (alist-get 'readwise_url highlight)))
    (concat
     (format "#+name: rw-%s\n" id)
     (when location (format "#+rw_location: %s\n" location))
     (when (and url (stringp url)) (format "#+rw_url: %s\n" url))
     "#+begin_quote\n" text "\n#+end_quote\n"
     (when (and note (stringp note) (not (string-empty-p (string-trim note))))
       (concat "\n" (my/readwise--sanitize note) "\n"))
     "\n")))

(defun my/readwise--render-book (book)
  "Return the full Org file content for BOOK."
  (let* ((id (alist-get 'user_book_id book))
         (title (or (alist-get 'readable_title book)
                    (alist-get 'title book)
                    "Untitled"))
         (author (or (alist-get 'author book) ""))
         (category (or (alist-get 'category book) ""))
         (source (or (alist-get 'source book) ""))
         (url (alist-get 'unique_url book))
         (highlights (alist-get 'highlights book))
         (keywords (append my/readwise-file-keywords
                           (unless (string-empty-p category) (list category)))))
    (concat
     (format "#+title:      %s%s\n"
             (if (string-empty-p author) "" (concat author " - "))
             title)
     (format "#+date:       %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]"))
     (format "#+filetags:   :%s:\n" (string-join keywords ":"))
     ;; No #+identifier: on purpose.  These files live outside
     ;; `denote-directory', so Denote never indexes them and the field
     ;; would serve no function -- while a whole sync run completes
     ;; within the same second, so every file would claim the same
     ;; identifier.  A duplicated identifier is worse than none: it
     ;; would collide the moment a file was moved into the notes tree.
     "\n"
     ":PROPERTIES:\n"
     (format ":RW_BOOK_ID: %s\n" id)
     (unless (string-empty-p author) (format ":AUTHOR: %s\n" author))
     (unless (string-empty-p category) (format ":CATEGORY: %s\n" category))
     (unless (string-empty-p source) (format ":SOURCE: %s\n" source))
     (when (and url (stringp url)) (format ":URL: %s\n" url))
     (format ":IMPORT_DATE: %s\n" (format-time-string "[%Y-%m-%d %a]"))
     (format ":HIGHLIGHT_COUNT: %d\n" (length highlights))
     ":END:\n\n"
     "* Cytaty\n\n"
     (mapconcat #'my/readwise--render-highlight highlights ""))))

(defun my/readwise--slug (string)
  "Return a file-name-safe slug for STRING."
  (let ((s (downcase (or string ""))))
    (setq s (replace-regexp-in-string "[^[:alnum:][:space:]-]" "" s))
    (setq s (replace-regexp-in-string "[[:space:]]+" "-" (string-trim s)))
    (substring s 0 (min 70 (length s)))))

(defun my/readwise--file-for (book)
  "Return the path this BOOK is written to.

The name is derived from the Readwise book id, not from the import
time.  That keeps re-import idempotent: the same book always lands on
the same path and is overwritten, instead of accumulating a new copy
per sync."
  (let* ((id (alist-get 'user_book_id book))
         (title (or (alist-get 'readable_title book)
                    (alist-get 'title book) "untitled"))
         (author (alist-get 'author book)))
    (expand-file-name
     (format "rw%s--%s.org"
             id
             (my/readwise--slug (if (and author (not (string-empty-p author)))
                                    (concat author " " title)
                                  title)))
     my/readwise-directory)))

;; ============================================================
;; STATE
;; ============================================================

(defun my/readwise--last-sync ()
  "Return the stored last-sync timestamp, or nil when there is none."
  (when (file-readable-p my/readwise-state-file)
    (with-temp-buffer
      (insert-file-contents my/readwise-state-file)
      (let ((s (string-trim (buffer-string))))
        (unless (string-empty-p s) s)))))

(defun my/readwise--save-sync-time (time)
  "Write TIME, an ISO 8601 string, to `my/readwise-state-file'."
  (make-directory my/readwise-directory t)
  (with-temp-file my/readwise-state-file
    (insert time "\n")))

;; ============================================================
;; SYNC
;; ============================================================

(defun my/readwise-sync (&optional full)
  "Import Readwise highlights into `my/readwise-directory'.

Incremental by default: asks Readwise which books changed since the
last sync, then re-fetches each of those books IN FULL and rewrites
its file.

The two-phase approach is deliberate.  With `updatedAfter' alone, a
book comes back carrying only its changed highlights, so writing that
directly would replace a complete file with a partial one.  Re-fetching
the affected books whole keeps every file complete, and makes each
file a pure function of Readwise's current state.

With a prefix argument, or when no previous sync is recorded, imports
everything from scratch."
  (interactive "P")
  (make-directory my/readwise-directory t)
  (let* ((since (unless full (my/readwise--last-sync)))
         ;; Recorded BEFORE fetching: a highlight changed while the
         ;; sync runs would otherwise fall in the gap between the fetch
         ;; and the timestamp, and never be seen again.
         (started (format-time-string "%Y-%m-%dT%H:%M:%SZ" nil t))
         (changed (my/readwise--fetch-all since))
         (wanted (seq-filter
                  (lambda (book)
                    (member (alist-get 'category book) my/readwise-categories))
                  changed))
         (books (cond
                 ((null wanted) nil)
                 ;; Full import already carries every highlight.
                 ((null since) wanted)
                 (t (my/readwise--fetch-all
                     nil
                     (mapconcat (lambda (b)
                                  (format "%s" (alist-get 'user_book_id b)))
                                wanted ",")))))
         (written 0))
    (dolist (book books)
      (when (member (alist-get 'category book) my/readwise-categories)
        (let ((file (my/readwise--file-for book)))
          (with-temp-file file
            (insert (my/readwise--render-book book)))
          (setq written (1+ written)))))
    (my/readwise--save-sync-time started)
    (message "Readwise: %d book file(s) written to %s%s"
             written
             (abbreviate-file-name my/readwise-directory)
             (if (and (null books) since)
                 " (nothing changed since last sync)" ""))))

(defun my/readwise-sync-all ()
  "Re-import every Readwise book from scratch, ignoring the stored state.
Named rather than an inline lambda so that `describe-key' and the
transient help show something meaningful."
  (interactive)
  (my/readwise-sync t))

(defun my/readwise-open-directory ()
  "Open the Readwise import directory in Dired."
  (interactive)
  (make-directory my/readwise-directory t)
  (dired my/readwise-directory))

;; ============================================================
;; PARSING IMPORTED FILES
;; ============================================================
;; Deliberately regexp-based rather than org-element: these files are
;; generated by `my/readwise--render-book' above, so their shape is
;; known exactly.  Parsing them with the full Org parser would be
;; slower and would buy tolerance for variation that cannot occur.

(defconst my/readwise--record-regexp "^#\\+name: rw-\\([0-9]+\\)$"
  "Match the affiliated keyword that begins one highlight record.")

(defun my/readwise--file-book-meta (file)
  "Return a plist of book-level metadata read from FILE."
  (with-temp-buffer
    (insert-file-contents file nil 0 2000)
    (goto-char (point-min))
    (let ((get (lambda (re)
                 (goto-char (point-min))
                 (when (re-search-forward re nil t)
                   (string-trim (match-string 1))))))
      (list :file file
            :title (funcall get "^#\\+title:[ \t]*\\(.*\\)$")
            :author (funcall get "^:AUTHOR:[ \t]*\\(.*\\)$")
            :book-id (funcall get "^:RW_BOOK_ID:[ \t]*\\(.*\\)$")
            :count (string-to-number
                    (or (funcall get "^:HIGHLIGHT_COUNT:[ \t]*\\([0-9]+\\)$") "0"))))))

(defun my/readwise--parse-records (file)
  "Return the highlight records in FILE as a list of plists.

Each record carries :id, :location, :url, :quote and :note.  The note
is whatever follows the quote block before the next record, which is
where `my/readwise--render-highlight' puts it."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (records)
      (while (re-search-forward my/readwise--record-regexp nil t)
        (let* ((id (match-string 1))
               (start (point))
               (end (save-excursion
                      (if (re-search-forward my/readwise--record-regexp nil t)
                          (match-beginning 0)
                        (point-max))))
               (chunk (buffer-substring-no-properties start end))
               (location (when (string-match "^#\\+rw_location:[ \t]*\\(.*\\)$" chunk)
                           (string-trim (match-string 1 chunk))))
               (url (when (string-match "^#\\+rw_url:[ \t]*\\(.*\\)$" chunk)
                      (string-trim (match-string 1 chunk))))
               (quote-text (when (string-match
                                  "#\\+begin_quote\n\\(\\(?:.\\|\n\\)*?\\)\n#\\+end_quote"
                                  chunk)
                             (string-trim (match-string 1 chunk))))
               (note (when (string-match
                            "#\\+end_quote\n\\(\\(?:.\\|\n\\)*\\)\\'" chunk)
                       (let ((tail (string-trim (match-string 1 chunk))))
                         (unless (string-empty-p tail) tail)))))
          (push (list :id id :location location :url url
                      :quote quote-text :note note)
                records)))
      (nreverse records))))

;; ============================================================
;; WHICH QUOTES ARE ALREADY PROMOTED
;; ============================================================

(defun my/readwise--promoted-ids ()
  "Return a hash of Readwise id -> \='own or \='cited, scanning pks once.

Two ways a quote reaches pks, and they mean different things:

  :RW_ID: rw-123   the note IS that quote -- consumed, nothing left
                   to do, so it drops off the review list.
  #+name: rw-123   the note QUOTES it as evidence, typically a note
                   about the book rather than about this passage.  The
                   quote is still available to become a note of its
                   own, so it stays on the list, marked.

Distinguishing them costs one extra regexp and avoids the failure mode
where citing a passage in a book note silently hides it from review.

Scanned in one pass over pks: a book can hold hundreds of highlights,
and grepping per quote would be quadratic."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file (directory-files-recursively my-notes-pks "\\.org\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^:RW_ID:[ \t]*rw-\\([0-9]+\\)" nil t)
          (puthash (match-string 1) 'own table))
        (goto-char (point-min))
        (while (re-search-forward "^#\\+name: rw-\\([0-9]+\\)" nil t)
          (unless (eq (gethash (match-string 1) table) 'own)
            (puthash (match-string 1) 'cited table)))))
    table))

;; ============================================================
;; PROMOTION
;; ============================================================

(defun my/readwise--source-drawer (record book &optional own)
  "Return the property drawer describing RECORD of BOOK.
With OWN non-nil, include :RW_ID:, which marks the note as BEING this
quote rather than merely citing it."
  (concat ":PROPERTIES:\n"
          (if own (format ":RW_ID: rw-%s\n" (plist-get record :id)) "")
          (if-let* ((u (plist-get record :url))) (format ":RW_URL: %s\n" u) "")
          (if-let* ((a (plist-get book :author)))
              (format ":SOURCE_AUTHOR: %s\n" a) "")
          (if-let* ((tt (plist-get book :title)))
              (format ":SOURCE_TITLE: %s\n" tt) "")
          (if-let* ((l (plist-get record :location)))
              (format ":SOURCE_LOCATION: %s\n" l) "")
          ":END:\n"))

(defun my/readwise--ask-include-note (record)
  "Ask whether RECORD's personal comment should be carried over.

Defaults to yes, so a bare RET accepts.  `y-or-n-p' has no notion of a
default answer, hence reading a string instead: anything starting with
n declines, everything else -- including an empty answer -- accepts."
  (let ((note (plist-get record :note)))
    (and note
         (not (string-prefix-p
               "n" (downcase (string-trim
                              (read-string "Include your comment? (Y/n): "))))))))

(defun my/readwise--insert-quote (record book &optional own with-note)
  "Insert RECORD of BOOK at point.  OWN and WITH-NOTE as described above."
  (insert "\n" (my/readwise--source-drawer record book own) "\n")
  (unless own
    ;; The affiliated keyword is what marks the quote as cited rather
    ;; than consumed, so it is only written on this path.
    (insert (format "#+name: rw-%s\n" (plist-get record :id))))
  (insert "#+begin_quote\n" (or (plist-get record :quote) "") "\n#+end_quote\n")
  (when with-note (insert "\n" (plist-get record :note) "\n")))

(defun my/readwise--promote (record book action)
  "Create or extend a note in pks from RECORD of BOOK.

ACTION selects what happens:
  \\='stay    write the note, keep point in the review list
  \\='open    write the note and show it beside the list
  \\='zettel  write the note, give it a Folgezettel signature, show it
  \\='append  add the quote to an EXISTING note, as cited evidence

The first three create a note that IS the quote, so it carries
:RW_ID: and drops off the review list.  \\='append cites the quote in a
note about something else -- typically the book -- so it is marked
with #+name: instead and stays available.

Metadata is embedded rather than linked: the imported file is
disposable by design, so a link to it would eventually dangle."
  (let* ((denote-directory my-notes-pks)
         (with-note (my/readwise--ask-include-note record))
         (buffer nil))
    (if (eq action 'append)
        (let ((file (read-file-name "Add quote to note: " my-notes-pks nil t)))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (goto-char (point-max))
            (my/readwise--insert-quote record book nil with-note)
            (save-buffer)))
      (let* ((default-title (truncate-string-to-width
                             (or (plist-get record :quote) "") 60 nil nil "..."))
             (title (read-string "Note title: " nil nil default-title))
             (tags-input (read-string "Tags (space-separated): "))
             (keywords (unless (string-empty-p tags-input)
                         (split-string tags-input " " t))))
        (save-window-excursion
          (denote title keywords)
          (setq buffer (current-buffer))
          (goto-char (point-max))
          (my/readwise--insert-quote record book t with-note)
          (save-buffer))))
    (when (eq action 'zettel)
      (with-current-buffer buffer
        ;; Runs on the finished note, so the sequence commands see a
        ;; real file with front matter already in place.
        (call-interactively #'my/zettel-adopt)
        (when (y-or-n-p "Place under an existing thread? ")
          (call-interactively #'my/zettel-reparent))
        (setq buffer (current-buffer))))
    (if (memq action '(open zettel))
        (my/readwise--show-note buffer)
      (message "%s: %s"
               (if (eq action 'append) "Quote added to" "Promoted")
               (buffer-name buffer)))
    buffer))

;; ============================================================
;; REVIEW: BOOKS, THEN QUOTES
;; ============================================================
;; Two levels rather than one flat list.  With dozens of books and
;; hundreds of highlights in some of them, a single list of every
;; unprocessed quote would be unusable -- and the book is shared
;; context for all of its quotes, so working through one book at a
;; time matches how the material was read.

(defvar my/readwise-tab-name "Readwise"
  "Name of the tab-bar tab holding the Readwise review buffers.")

(defvar my/readwise--books-buffer "*Readwise Books*")
(defvar my/readwise--quotes-buffer "*Readwise Quotes*")

(defvar-local my/readwise--book nil
  "Book plist the current quote list was built from.")

(defvar my/readwise--note-window nil
  "Window used to display notes created from the review list.

Global rather than buffer-local on purpose: rebuilding the quote list
re-runs its major mode, which would clear a buffer-local value and
leave the next promotion splitting a third window instead of reusing
the second.

Always checked with `window-live-p' before use, since closing it is a
perfectly normal thing to do.")

(defun my/readwise--show-note (buffer)
  "Show BUFFER beside the review list and select it."
  (let* ((list-window (selected-window))
         (window (if (window-live-p my/readwise--note-window)
                     my/readwise--note-window
                   (setq my/readwise--note-window
                         (split-window-right 60)))))
    (set-window-buffer window buffer)
    (select-window window)
    (goto-char (point-max))
    (ignore list-window)))

(defun my/readwise--files ()
  "Return the imported book files."
  (when (file-directory-p my/readwise-directory)
    (directory-files my/readwise-directory t "\\`rw[0-9]+--.*\\.org\\'")))

(defun my/readwise--collect ()
  "Return one entry per book that still has unprocessed quotes."
  (let ((promoted (my/readwise--promoted-ids))
        (entries nil))
    (dolist (file (my/readwise--files))
      (let* ((book (my/readwise--file-book-meta file))
             (records (my/readwise--parse-records file))
             (pending (seq-remove
                       (lambda (r) (eq (gethash (plist-get r :id) promoted) 'own))
                       records)))
        (when pending
          (push (list :book book :pending pending :promoted promoted
                      :mtime (file-attribute-modification-time
                              (file-attributes file)))
                entries))))
    (nreverse entries)))

;; --- Book list -----------------------------------------------------
;; `tabulated-list-mode' rather than plain text: it provides column
;; sorting by clicking a header or pressing S, which is most of what
;; was wanted here, and gets alignment right for free.

(defvar-local my/readwise--entries nil
  "Entries backing the current book list.")

(defvar my/readwise--filter ""
  "Text currently filtering the book list.

Global, like the sort key, so it survives going into a book and back.
A filter that silently reset on every return would be worse than no
filter, since the list would look complete when it is not -- which is
also why the active filter is shown in the mode line.")

(defun my/readwise--book-list-entries (entries)
  "Convert ENTRIES into `tabulated-list-entries' form."
  (mapcar
   (lambda (entry)
     (let ((book (plist-get entry :book)))
       (list entry
             (vector
              (number-to-string (length (plist-get entry :pending)))
              (number-to-string (plist-get book :count))
              (or (plist-get book :author) "")
              (format-time-string "%Y-%m-%d" (plist-get entry :mtime))
              (or (plist-get book :title) "(untitled)")))))
   entries))

(defun my/readwise--sort-numeric (column)
  "Return a predicate sorting `tabulated-list' rows numerically on COLUMN."
  (lambda (a b)
    (< (string-to-number (aref (cadr a) column))
       (string-to-number (aref (cadr b) column)))))

;; Defined before `define-derived-mode', which creates NAME-map itself
;; when the symbol is still unbound.  A defvar afterwards would be a
;; no-op on the already-bound variable and the bindings would vanish.
(defvar my/readwise-books-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET")  #'my/readwise-open-book)
    (define-key map (kbd "o")    #'my/readwise-open-book)
    (define-key map [mouse-1]    #'my/readwise-open-book-mouse)
    (define-key map (kbd "/")   #'my/readwise-filter)
    (define-key map (kbd "g")   #'my/readwise-review)
    (define-key map (kbd "q")   #'quit-window)
    map)
  "Keymap for `my/readwise-books-mode'.")

(defvar my/readwise--sort-key '("Left" . t)
  "Sort column and direction remembered across visits to the book list.

`tabulated-list-sort-key' is buffer-local and reset by
`define-derived-mode', so a chosen sort would otherwise be lost every
time the list is rebuilt -- which happens on every return from a
book.")

(define-derived-mode my/readwise-books-mode tabulated-list-mode "RW Books"
  "Major mode for the Readwise book list.
\\{my/readwise-books-mode-map}"
  (setq tabulated-list-format
        (vector (list "Left" 6 (my/readwise--sort-numeric 0))
                (list "All" 6 (my/readwise--sort-numeric 1))
                (list "Author" 28 t)
                (list "Imported" 11 t)
                (list "Title" 0 t)))
  (setq tabulated-list-sort-key my/readwise--sort-key)
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header)
  (hl-line-mode 1))

(defun my/readwise--remember-sort ()
  "Copy this buffer\='s sort key into `my/readwise--sort-key'."
  (when (derived-mode-p 'my/readwise-books-mode)
    (setq my/readwise--sort-key tabulated-list-sort-key)))

(defun my/readwise-open-book-mouse (event)
  "Open the book clicked on by EVENT."
  (interactive "e")
  (mouse-set-point event)
  (my/readwise-open-book))

(defun my/readwise-review ()
  "List imported books that still have unprocessed quotes.

Sort with `S' on a column, or click its header; the choice is kept
for later visits.  `/' filters by author or title, narrowing as you
type, and `C-/' clears it.  An active filter is shown in the mode
line, since a persistent one that were invisible would make a partial
list look complete."
  (interactive)
  (let ((entries (my/readwise--collect)))
    (my/fixed-tab-goto my/readwise-tab-name)
    (let ((buffer (get-buffer-create my/readwise--books-buffer)))
      (with-current-buffer buffer
        (my/readwise-books-mode)
        (setq my/readwise--entries entries)
        (my/readwise--render buffer my/readwise--filter))
      (switch-to-buffer buffer)
      (delete-other-windows)
      (message "%d book(s) with unprocessed quotes%s"
               (length entries)
               (if (string-empty-p my/readwise--filter) ""
                 (format ", filtered by \"%s\"" my/readwise--filter))))))

(defun my/readwise--matches-filter-p (entry needle)
  "Return non-nil when ENTRY's author or title contains NEEDLE.

Author and title are matched as one string, so a search need not know
which field a word lives in.  That also covers the case this was asked
for: the same author recorded as \"Emil Cioran\" in one book and
\"Cioran Emil\" in another still matches a search for \"cioran\"."
  (let ((book (plist-get entry :book)))
    (string-match-p
     (regexp-quote needle)
     (downcase (concat (or (plist-get book :author) "") " "
                       (or (plist-get book :title) ""))))))

(defun my/readwise--render (buffer needle)
  "Redraw BUFFER's book list, keeping only entries matching NEEDLE."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let* ((needle (downcase (string-trim (or needle ""))))
             (kept (if (string-empty-p needle)
                       my/readwise--entries
                     (seq-filter (lambda (e)
                                   (my/readwise--matches-filter-p e needle))
                                 my/readwise--entries))))
        (setq tabulated-list-entries (my/readwise--book-list-entries kept))
        (tabulated-list-print t)
        (setq mode-line-process
              (unless (string-empty-p needle) (format " [/%s]" needle)))
        (force-mode-line-update)
        (length kept)))))

(defun my/readwise-filter ()
  "Filter the book list by author or title, live as you type.

Redrawing runs from `post-command-hook' inside the minibuffer, so the
list narrows on each keystroke rather than only on RET.  With fewer
than a hundred books the redraw is not noticeable; if it ever were,
the same function works unchanged from a plain prompt.

RET keeps the filter, C-g restores whatever was in effect before."
  (interactive)
  (unless (derived-mode-p 'my/readwise-books-mode)
    (user-error "Not in the Readwise book list"))
  (let ((buffer (current-buffer))
        (previous my/readwise--filter))
    (condition-case nil
        (let ((text (minibuffer-with-setup-hook
                        (lambda ()
                          (add-hook 'post-command-hook
                                    (lambda ()
                                      (my/readwise--render
                                       buffer (minibuffer-contents)))
                                    nil t))
                      (read-string "Filter (author or title): "
                                   my/readwise--filter))))
          (setq my/readwise--filter (string-trim text))
          (message "%d of %d book(s)"
                   (or (my/readwise--render buffer my/readwise--filter) 0)
                   (length (buffer-local-value 'my/readwise--entries buffer))))
      (quit
       (setq my/readwise--filter previous)
       (my/readwise--render buffer previous)
       (message "Filter unchanged")))))

(defun my/readwise-filter-clear ()
  "Remove the book list filter."
  (interactive)
  (setq my/readwise--filter "")
  (my/readwise--render (current-buffer) "")
  (message "Filter cleared"))

(defun my/readwise-open-book ()
  "Open the quote list for the book at point."
  (interactive)
  (my/readwise--remember-sort)
  (if-let* ((entry (tabulated-list-get-id)))
      (my/readwise--show-quotes (plist-get entry :book)
                                (plist-get entry :pending)
                                (plist-get entry :promoted))
    (message "No book on this line")))

;; --- Quote list ----------------------------------------------------

(defun my/readwise--insert-action-buttons (anchor)
  "Insert the four action buttons for the quote whose button starts at ANCHOR.

ANCHOR is a marker rather than a record, so every button resolves back
to the one quote button that carries the done state.  Marking that
single button therefore disarms all five entry points at once, instead
of each needing its own bookkeeping."
  (insert "      ")
  (dolist (spec '(("note" . stay)
                  ("note+open" . open)
                  ("zettel" . zettel)
                  ("add to existing" . append)))
    (insert-text-button
     (concat "[" (car spec) "]")
     'follow-link t
     'my-anchor anchor
     'my-action (cdr spec)
     'face 'link
     'action (lambda (b)
               (if-let* ((quote-button (button-at (button-get b 'my-anchor))))
                   (my/readwise--promote-button quote-button
                                                (button-get b 'my-action))
                 (message "Quote no longer available"))))
    (insert " "))
  (insert "\n"))

(defun my/readwise--show-quotes (book pending promoted)
  "List PENDING quotes of BOOK.  PROMOTED classifies already-used ids."
  (let ((buffer (get-buffer-create my/readwise--quotes-buffer)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/readwise-quotes-mode)
        (setq my/readwise--book book)
        (insert (or (plist-get book :title) "") "\n"
                (format "%d unprocessed | RET note | o note+open | z zettel | a add to existing | q back\n\n"
                        (length pending)))
        (dolist (record pending)
          (let ((cited (eq (gethash (plist-get record :id) promoted) 'cited)))
            (insert (format "  [%s]%s"
                            (plist-get record :id)
                            (if-let* ((l (plist-get record :location)))
                                (concat "  " l) "")))
            (when-let* ((u (plist-get record :url)))
              (insert "  ")
              (insert-text-button
               u
               'follow-link t
               'help-echo "Open this highlight in Readwise"
               'face 'link
               'action (let ((target u)) (lambda (_b) (browse-url target)))))
            (when cited (insert "   [CYTOWANY]"))
            (insert "\n")
            (let ((start (point)))
              (insert "  " (or (plist-get record :quote) "") "\n")
              (fill-region start (point))
              (make-text-button start (point)
                                'follow-link t
                                'my-record record
                                'my-done nil
                                'face (if cited 'font-lock-comment-face 'default)
                                'mouse-face 'highlight
                                'action (lambda (b)
                                          (my/readwise--promote-button b 'stay)))
              (when (plist-get record :note)
                (insert "      > " (plist-get record :note) "\n"))
              (my/readwise--insert-action-buttons (copy-marker start)))
            (insert "\n")))
        (goto-char (point-min))
        (forward-line 3)))
    (switch-to-buffer buffer)))

(defun my/readwise-refresh-quotes ()
  "Rebuild the quote list for the current book from disk and pks."
  (interactive)
  (unless my/readwise--book
    (user-error "Not in a Readwise quote list"))
  (let* ((book my/readwise--book)
         (file (plist-get book :file))
         (promoted (my/readwise--promoted-ids))
         (pending (seq-remove
                   (lambda (r) (eq (gethash (plist-get r :id) promoted) 'own))
                   (my/readwise--parse-records file))))
    (my/readwise--show-quotes book pending promoted)))

(defun my/readwise--button-at-point ()
  "Return the quote button on or just below point, or nil.
The id line sits above its quote button, so a bare `button-at' fails
there -- which is exactly where point lands when moving line by line."
  (or (button-at (point))
      (save-excursion (forward-line 0) (button-at (point)))
      (save-excursion (forward-line 1) (button-at (point)))))

(defun my/readwise--mark-button-done (button label)
  "Dim BUTTON, disarm it and prefix its id line with LABEL.

The list is not rebuilt after a promotion -- that would lose the review
position mid-run -- so without marking, a used quote looks identical to
an unused one and is easy to process twice."
  (button-put button 'my-done t)
  (button-put button 'face 'shadow)
  (button-put button 'mouse-face nil)
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (button-start button))
      (forward-line -1)
      (when (looking-at "^  \\[")
        (goto-char (line-end-position))
        (insert "   " label)))))

(defun my/readwise--promote-button (button action)
  "Run ACTION on BUTTON's quote, then update the list.

For `stay' and `append' the button is only marked, because the point
of those actions is to keep working down the list and a rebuild would
lose the position.

For `open' and `zettel' the list is rebuilt instead, so the consumed
quote disappears rather than lingering as a struck-through line.  That
is affordable precisely because attention moves to the new note
anyway, so there is no position left to preserve."
  (if (button-get button 'my-done)
      (message "Already handled in this session")
    (let ((note-buffer (my/readwise--promote (button-get button 'my-record)
                                             my/readwise--book action)))
      (if (memq action '(open zettel))
          (save-selected-window
            (when-let* ((window (get-buffer-window my/readwise--quotes-buffer)))
              (select-window window)
              (my/readwise-refresh-quotes)))
        (my/readwise--mark-button-done
         button (if (eq action 'append) "[CYTOWANY]" "[GOTOWE]")))
      note-buffer)))

(defun my/readwise-promote-at-point ()
  "Create a note from the quote at point, staying in the list."
  (interactive)
  (if-let* ((b (my/readwise--button-at-point)))
      (my/readwise--promote-button b 'stay)
    (message "No quote on this line")))

(defun my/readwise-promote-and-open ()
  "Create a note from the quote at point and show it beside the list."
  (interactive)
  (if-let* ((b (my/readwise--button-at-point)))
      (my/readwise--promote-button b 'open)
    (message "No quote on this line")))

(defun my/readwise-promote-as-zettel ()
  "Create a note from the quote at point and give it a Folgezettel signature."
  (interactive)
  (if-let* ((b (my/readwise--button-at-point)))
      (my/readwise--promote-button b 'zettel)
    (message "No quote on this line")))

(defun my/readwise-add-to-existing ()
  "Add the quote at point to an existing note as cited evidence.
The quote stays on the review list, marked, since citing it does not
use it up."
  (interactive)
  (if-let* ((b (my/readwise--button-at-point)))
      (my/readwise--promote-button b 'append)
    (message "No quote on this line")))

(defvar my/readwise-quotes-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'my/readwise-promote-at-point)
    (define-key map (kbd "o")   #'my/readwise-promote-and-open)
    (define-key map (kbd "z")   #'my/readwise-promote-as-zettel)
    (define-key map (kbd "a")   #'my/readwise-add-to-existing)
    (define-key map (kbd "g")   #'my/readwise-refresh-quotes)
    (define-key map (kbd "q")   #'my/readwise-review)
    map)
  "Keymap for `my/readwise-quotes-mode'.")

(define-derived-mode my/readwise-quotes-mode special-mode "RW Quotes"
  "Major mode for the Readwise quote list.
\\{my/readwise-quotes-mode-map}"
  (hl-line-mode 1)
  (visual-line-mode 1))

;; ============================================================
;; MENU
;; ============================================================
;; Appended to the Tools submenu next to Zotero, since both are
;; external-service integrations feeding the same bibliographic
;; workflow.  Same append mechanism as 19-philosophy-notes.el and
;; 22-zettelkasten.el use on the main menu, with the same guard
;; against stacking a duplicate entry on re-evaluation.
;;
;; The review and promotion commands will join this submenu once they
;; exist; the direct C-c r bindings stay as a fast path for the one
;; command used often enough to deserve it.

(transient-define-prefix my/readwise-menu ()
  "Readwise import and review."
  [["Sync"
    ("s" "Sync (incremental)" my/readwise-sync)
    ("S" "Sync everything"    my/readwise-sync-all)]
   ["Review"
    ("r" "Review books"       my/readwise-review)]
   ["Files"
    ("o" "Open import folder" my/readwise-open-directory)]
   [("q" "Quit" transient-quit-one)]])

(my/transient-append 'my/notes-tools-menu "z"
                     '("r" "Readwise →" my/readwise-menu))

;; ============================================================
;; KEYBINDINGS
;; ============================================================
;; C-c r is otherwise unused in this configuration.

(global-set-key (kbd "C-c r s") #'my/readwise-sync)
(global-set-key (kbd "C-c r o") #'my/readwise-open-directory)
(global-set-key (kbd "C-c r r") #'my/readwise-review)

(provide '24-readwise)
;;; 24-readwise.el ends here
