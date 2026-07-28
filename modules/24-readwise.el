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
     (format "#+identifier: %s\n" (format-time-string "%Y%m%dT%H%M%S"))
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

(defun my/readwise-open-directory ()
  "Open the Readwise import directory in Dired."
  (interactive)
  (make-directory my/readwise-directory t)
  (dired my/readwise-directory))

;; ============================================================
;; KEYBINDINGS
;; ============================================================
;; C-c r is otherwise unused in this configuration.  The review and
;; promotion commands will join this prefix once they exist.

(global-set-key (kbd "C-c r s") #'my/readwise-sync)
(global-set-key (kbd "C-c r o") #'my/readwise-open-directory)

(provide '24-readwise)
;;; 24-readwise.el ends here
