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
  "Return a hash table of Readwise ids already present in the pks silo.

Answering \"have I processed this quote?\" from pks rather than from a
local index means there is one source of truth, and that it survives
losing the whole import directory -- which an index kept beside those
disposable files would not.

Scanned in one pass over pks rather than once per quote: a book can
hold hundreds of highlights, and a grep each would be quadratic."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file (directory-files-recursively my-notes-pks "\\.org\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "rw-\\([0-9]+\\)" nil t)
          (puthash (match-string 1) file table))))
    table))

;; ============================================================
;; PROMOTION
;; ============================================================

(defun my/readwise--promote (record book &optional switch)
  "Create a note in the pks silo from RECORD of BOOK.

Prompts for a title, tags, and whether to carry over the personal
comment -- defaulting to yes, so a bare RET accepts it.  The comment is
optional because it is often a reaction to the passage rather than
material for the note itself.

The note embeds the book's title, author and the quote's location and
URL rather than linking back to the imported file, which is disposable
by design and may be regenerated or deleted at any time.

With SWITCH non-nil, leaves point in the new note; otherwise the note
is written and the current window arrangement is kept, so a run of
quotes can be promoted without losing the review position."
  (let* ((default-title (truncate-string-to-width
                         (or (plist-get record :quote) "") 60 nil nil "..."))
         (title (read-string "Note title: " nil nil default-title))
         (tags-input (read-string "Tags (space-separated): "))
         (keywords (unless (string-empty-p tags-input)
                     (split-string tags-input " " t)))
         (note (plist-get record :note))
         (with-note (and note (y-or-n-p "Include your comment? ")))
         (denote-directory my-notes-pks)
         (buffer nil))
    (save-window-excursion
      (denote title keywords)
      (setq buffer (current-buffer))
      (goto-char (point-max))
      (insert "\n:PROPERTIES:\n"
              (format ":RW_ID: rw-%s\n" (plist-get record :id))
              (if-let* ((u (plist-get record :url))) (format ":RW_URL: %s\n" u) "")
              (if-let* ((a (plist-get book :author)))
                  (format ":SOURCE_AUTHOR: %s\n" a) "")
              (if-let* ((tt (plist-get book :title)))
                  (format ":SOURCE_TITLE: %s\n" tt) "")
              (if-let* ((l (plist-get record :location)))
                  (format ":SOURCE_LOCATION: %s\n" l) "")
              ":END:\n\n"
              "#+begin_quote\n" (or (plist-get record :quote) "") "\n#+end_quote\n")
      (when with-note (insert "\n" note "\n"))
      (save-buffer))
    (if switch
        (progn (pop-to-buffer-same-window buffer)
               (goto-char (point-max)))
      (message "Promoted: %s" title))
    buffer))

;; ============================================================
;; REVIEW: BOOKS, THEN QUOTES
;; ============================================================
;; Two levels rather than one flat list.  With 89 books and hundreds of
;; highlights in some of them, a single list of every unprocessed quote
;; would be unusable -- and the book is shared context for all of its
;; quotes, so working through one book at a time matches how the
;; material is actually read.

(defvar my/readwise-tab-name "Readwise"
  "Name of the tab-bar tab holding the Readwise review buffers.")

(defvar my/readwise--books-buffer "*Readwise Books*")
(defvar my/readwise--quotes-buffer "*Readwise Quotes*")

(defvar-local my/readwise--book nil
  "Book plist the current quote list was built from.")

(defun my/readwise--files ()
  "Return the imported book files, newest first."
  (when (file-directory-p my/readwise-directory)
    (sort (directory-files my/readwise-directory t "\\`rw[0-9]+--.*\\.org\\'")
          (lambda (a b) (file-newer-than-file-p a b)))))

(defun my/readwise-review ()
  "List imported books with their unprocessed quote counts.
Books with nothing left to process are omitted."
  (interactive)
  (let* ((promoted (my/readwise--promoted-ids))
         (entries nil))
    (dolist (file (my/readwise--files))
      (let* ((book (my/readwise--file-book-meta file))
             (pending (seq-remove
                       (lambda (r) (gethash (plist-get r :id) promoted))
                       (my/readwise--parse-records file))))
        (when pending
          (push (list :book book :pending pending) entries))))
    (setq entries (nreverse entries))
    (my/fixed-tab-goto my/readwise-tab-name)
    (let ((buffer (get-buffer-create my/readwise--books-buffer)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (my/readwise-books-mode)
          (insert "Readwise -- books with unprocessed quotes\n\n")
          (if (null entries)
              (insert "  Nothing left to process.\n")
            (dolist (entry entries)
              (let ((book (plist-get entry :book))
                    (pending (plist-get entry :pending)))
                (insert (format "  %4d / %-4d  "
                                (length pending)
                                (plist-get book :count)))
                (insert-text-button
                 (or (plist-get book :title) "(untitled)")
                 'follow-link t
                 'help-echo (plist-get book :file)
                 'my-book book
                 'my-pending pending
                 'action (lambda (b)
                           (my/readwise--show-quotes
                            (button-get b 'my-book)
                            (button-get b 'my-pending))))
                (insert "\n"))))
          (goto-char (point-min))
          (forward-line 2)))
      (switch-to-buffer buffer)
      (delete-other-windows))))

(defun my/readwise--show-quotes (book pending)
  "List PENDING quotes of BOOK for review."
  (let ((buffer (get-buffer-create my/readwise--quotes-buffer)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/readwise-quotes-mode)
        (setq my/readwise--book book)
        (insert (or (plist-get book :title) "") "\n"
                (format "%d unprocessed  |  RET promote and stay  |  o promote and open  |  q back\n\n"
                        (length pending)))
        (dolist (record pending)
          (insert (format "  [%s]%s\n"
                          (plist-get record :id)
                          (if-let* ((l (plist-get record :location)))
                              (concat "  " l) "")))
          (let ((start (point)))
            (insert "  " (or (plist-get record :quote) "") "\n")
            (fill-region start (point))
            (make-text-button start (point)
                              'follow-link t
                              'my-record record
                              'my-done nil
                              'mouse-face 'highlight
                              'action (lambda (b)
                                        (my/readwise--promote-button b nil))))
          (when (plist-get record :note)
            (insert "      > " (plist-get record :note) "\n"))
          (insert "\n"))
        (goto-char (point-min))
        (forward-line 3)))
    (switch-to-buffer buffer)))

(defun my/readwise--button-at-point ()
  "Return the quote button on or just below point, or nil.
The id line sits above its quote button, so a bare `button-at\=' would
fail there -- which is exactly where point lands after moving line by
line."
  (or (button-at (point))
      (save-excursion (forward-line 0) (button-at (point)))
      (save-excursion (forward-line 1) (button-at (point)))))

(defun my/readwise--mark-button-done (button)
  "Dim BUTTON and disarm it after its quote has been promoted.

The list is not rebuilt after a promotion, since that would lose the
review position mid-run.  Without marking, a promoted quote looks
exactly like an unprocessed one and is easy to promote twice."
  (button-put button 'my-done t)
  (button-put button 'face 'shadow)
  (button-put button 'mouse-face nil)
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (button-start button))
      (forward-line -1)
      (when (looking-at "^  \\[")
        (insert "DONE ")))))

(defun my/readwise--promote-button (button switch)
  "Promote BUTTON\='s quote, then mark it done.  SWITCH as in `my/readwise--promote\='."
  (if (button-get button 'my-done)
      (message "Already promoted in this session")
    (my/readwise--promote (button-get button 'my-record)
                          my/readwise--book switch)
    (my/readwise--mark-button-done button)))

(defun my/readwise-promote-at-point ()
  "Promote the quote at point into pks, staying in the review list."
  (interactive)
  (if-let* ((b (my/readwise--button-at-point)))
      (my/readwise--promote-button b nil)
    (message "No quote on this line")))

(defun my/readwise-promote-and-open ()
  "Promote the quote at point and switch to the new note."
  (interactive)
  (if-let* ((b (my/readwise--button-at-point)))
      (my/readwise--promote-button b t)
    (message "No quote on this line")))

(defvar my/readwise-books-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'my/readwise-review)
    map)
  "Keymap for `my/readwise-books-mode'.")

(define-derived-mode my/readwise-books-mode special-mode "RW Books"
  "Major mode for the Readwise book list.
\\{my/readwise-books-mode-map}"
  (hl-line-mode 1))

(defvar my/readwise-quotes-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'my/readwise-promote-at-point)
    (define-key map (kbd "o")   #'my/readwise-promote-and-open)
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

(unless (ignore-errors (transient-get-suffix 'my/notes-tools-menu "r"))
  (transient-append-suffix 'my/notes-tools-menu "z"
    '("r" "Readwise →" my/readwise-menu)))

;; ============================================================
;; KEYBINDINGS
;; ============================================================
;; C-c r is otherwise unused in this configuration.

(global-set-key (kbd "C-c r s") #'my/readwise-sync)
(global-set-key (kbd "C-c r o") #'my/readwise-open-directory)
(global-set-key (kbd "C-c r r") #'my/readwise-review)

(provide '24-readwise)
;;; 24-readwise.el ends here
