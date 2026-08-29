;;; 35-journal-gaps.el --- Days without a journal entry, or without metrics -*- lexical-binding: t; -*-
;;; Commentary:
;; A report of what is MISSING from the journal series, as opposed to
;; the dashboards in 21-dashboards.el which show what is there.
;;
;; Two kinds of gap, and they are not the same thing:
;;
;;   no entry      No journal file exists for that day at all.
;;   no metrics    A file exists, but one or more of the fields in
;;                 `my/journal-metrics-fields' is absent from its front
;;                 matter.
;;
;; WHY THE DISTINCTION MATTERS
;; ---------------------------
;; The metrics exist to be read by a local model as a time series, and
;; `05b-journal-metrics.el' is explicit that an absent keyword means
;; "not measured" and must never be read as zero.  That rule only holds
;; if the absences are visible.  A day with no file and a day with a
;; file but no `wellbeing' look identical in a query result and mean
;; different things: one is a day that was not written up, the other is
;; a day that was written up and not rated.
;;
;; The report also answers the question that motivates backfilling at
;; all -- whether the gaps are random or systematic.  The weekday
;; column is there for that: a series missing most Saturdays is not a
;; sample of all days, and the schema note in `docu/' says as much.
;;
;; WHICH FIELDS COUNT AS REQUIRED
;; ------------------------------
;; Derived from `my/journal-metrics-fields', not listed again here.  A
;; field added to 05b-journal-metrics.el starts being reported as
;; missing without touching this file, and a field removed there stops
;; being reported.  A second copy of that list would drift, and the
;; drift would be silent -- the report would keep demanding a field
;; that no command writes any more.
;;
;; `recalled' and `no_entry_reason' are deliberately NOT required.
;; Both are conditional: 05b-journal-metrics.el asks for them only when
;; the day is being backfilled or has no prose, so treating their
;; absence as a gap would mark almost every ordinary day incomplete.
;;
;; THE WINDOW
;; ----------
;; The report covers a fixed number of days back from today, prompted
;; for, defaulting to `my/journal-gaps-default-days'.  It is not the
;; whole series on purpose: journals here go back to 2015, and a list
;; of every un-backfilled day since then is several thousand rows that
;; nobody will act on.  A window is something that can be emptied.
;;
;; Days before the earliest journal file are dropped from the window
;; regardless -- there was nothing to miss yet.
;;
;; DEPENDENCIES, ALL OPTIONAL
;; --------------------------
;;   05b-journal-metrics.el  the field list, and `my/journal-set-metrics'
;;   05-notes.el             `my/denote-journal--create-backdated'
;;   12-transient.el         the menu entry
;; Each is guarded.  Without 05b the report still lists days with no
;; entry and says so; without 05-notes a missing day can be opened but
;; not created.
;;
;; Docs: ~/.emacs.d/function_helper.org::#journal-gaps

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'tabulated-list)

(declare-function my/journal-set-metrics "05b-journal-metrics" ())
(declare-function my/denote-journal--create-backdated "05-notes" (date encoded-time))
(declare-function my/fixed-tab-goto "23-fixed-tabs" (name))

(defgroup my-journal-gaps nil
  "Reporting days missing from the journal series.
Named without the slash, matching `my-dashboards' in 21-dashboards.el:
a group sharing a symbol with a command makes both harder to find, and
the pre-commit duplicate scan cannot tell the two apart."
  :group 'convenience)

(defcustom my/journal-gaps-default-days 90
  "Number of days back the report covers by default."
  :type 'integer :group 'my-journal-gaps)

(defcustom my/journal-gaps-buffer-name "*Journal Gaps*"
  "Name of the report buffer."
  :type 'string :group 'my-journal-gaps)

(defcustom my/journal-gaps-extra-required nil
  "Metrics keywords required in addition to `my/journal-metrics-fields'.
Normally empty: the required set is derived, so that adding a field in
05b-journal-metrics.el is enough.  This exists for a field that is
written by something other than that command."
  :type '(repeat string) :group 'my-journal-gaps)

;; ============================================================
;; WHAT COUNTS AS COMPLETE
;; ============================================================

(defun my/journal-gaps--required-keys ()
  "Return the metrics keywords a complete day must carry.
Derived from `my/journal-metrics-fields' when 05b-journal-metrics.el is
loaded; nil otherwise, which turns the metrics half of the report off
rather than inventing a field list."
  (append
   (when (boundp 'my/journal-metrics-fields)
     (mapcar (lambda (field) (plist-get field :key)) my/journal-metrics-fields))
   my/journal-gaps-extra-required))

;; ============================================================
;; READING THE SILO
;; ============================================================

(defconst my/journal-gaps--name-regexp
  "--\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)-journal"
  "Regexp matching the date a journal file name encodes.
The same test 05b-journal-metrics.el uses, and for the same reason:
the file name is what this configuration treats as authoritative for
which day a journal note describes.")

(defun my/journal-gaps--file-map ()
  "Return a hash of YYYY-MM-DD -> file for every journal note.
Built from file names alone.  Reading the front matter of every file
in the silo to find its date would mean opening a thousand files to
answer a question the names already answer."
  (let ((map (make-hash-table :test #'equal)))
    (dolist (file (directory-files my-notes-journal t "\\.org\\'") map)
      (let ((name (file-name-nondirectory file)))
        (when (string-match my/journal-gaps--name-regexp name)
          ;; First one wins.  Two files for one day is a duplicate, and
          ;; 26-maintenance.el is where that gets reported.
          (unless (gethash (match-string 1 name) map)
            (puthash (match-string 1 name) file map)))))))

(defun my/journal-gaps--missing-keys (file required)
  "Return the members of REQUIRED absent from FILE's front matter.
Reads the first kilobyte only: front matter is at the top by
construction, and scanning whole files would make the report cost
proportional to how much has been written rather than to how many days
are covered."
  (with-temp-buffer
    (insert-file-contents file nil 0 1200)
    (seq-remove
     (lambda (key)
       (goto-char (point-min))
       (re-search-forward (format "^#\\+%s:[ \t]*[^ \t\n]" (regexp-quote key))
                          nil t))
     required)))

(defun my/journal-gaps--title (file)
  "Return FILE's title, or its base name."
  (with-temp-buffer
    (insert-file-contents file nil 0 400)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+title:[ \t]+\\(.+\\)$" nil t)
        (string-trim (match-string 1))
      (file-name-base file))))

;; ============================================================
;; BUILDING THE REPORT
;; ============================================================

(defvar-local my/journal-gaps--days nil
  "Number of days the current report covers.")

(defvar-local my/journal-gaps--filter 'all
  "Which rows the current report shows: `all', `no-entry' or `no-metrics'.")

(defun my/journal-gaps--scan (days)
  "Return a list of gap records for the last DAYS days.
Each record is (DATE WEEKDAY KIND DETAIL FILE), where KIND is
`no-entry' or `no-metrics'.  Complete days produce no record: this is a
report of what is missing, and a row per satisfactory day would bury
the answer."
  (let* ((files    (my/journal-gaps--file-map))
         (required (my/journal-gaps--required-keys))
         (earliest (car (sort (hash-table-keys files) #'string<)))
         (today    (time-convert nil 'integer))
         records)
    (dotimes (offset days)
      (let* ((time (time-add today (* -86400 offset)))
             (date (format-time-string "%Y-%m-%d" time))
             (weekday (format-time-string "%a" time))
             (file (gethash date files)))
        ;; Nothing was missed before the series began.
        ;;
        ;; `(not (string< ...))' rather than a `string>=': Emacs Lisp
        ;; has `string<', `string=' and `string>' and no `=' variants
        ;; of the inequalities, so `string>=' reads as obvious and is
        ;; `void-function' at runtime.  Both dates are ISO, so a
        ;; lexical comparison is a chronological one.
        (when (or (null earliest) (not (string< date earliest)))
          (cond
           ((null file)
            (push (list date weekday 'no-entry "" nil) records))
           (required
            (when-let* ((missing (my/journal-gaps--missing-keys file required)))
              (push (list date weekday 'no-metrics
                          (string-join missing ", ") file)
                    records)))))))
    ;; Newest first, matching every other dated view in this
    ;; configuration.
    (nreverse (sort records (lambda (a b) (string< (car a) (car b)))))))

(defun my/journal-gaps--entries (records filter)
  "Convert RECORDS to `tabulated-list-entries', keeping those matching FILTER."
  (mapcar
   (lambda (record)
     (pcase-let ((`(,date ,weekday ,kind ,detail ,file) record))
       (list date
             (vector date
                     weekday
                     (if (eq kind 'no-entry) "no entry" "no metrics")
                     detail
                     (if file (my/journal-gaps--title file) "")))))
   (if (eq filter 'all)
       records
     (seq-filter (lambda (record) (eq (nth 2 record) filter)) records))))

;; ============================================================
;; THE BUFFER
;; ============================================================

(defun my/journal-gaps--encode (date)
  "Return DATE (YYYY-MM-DD) as a time value, at midday.

The decoded-time LIST form of `encode-time', matching 05-notes.el and
05b-journal-metrics.el.  The six-positional-argument form reads more
naturally and has been obsolete since Emacs 27; it still works today
and is exactly the kind of call that stops working on an upgrade.

Midday rather than midnight so that a daylight-saving transition
cannot move the timestamp into the previous or next day.  The hour is
never displayed -- journal identifiers are T000000 -- so nothing else
depends on it."
  (encode-time (list 0 0 12
                     (string-to-number (substring date 8 10))
                     (string-to-number (substring date 5 7))
                     (string-to-number (substring date 0 4))
                     nil -1 nil)))

(defun my/journal-gaps--date-at-point ()
  "Return the date on the current line, or signal."
  (or (tabulated-list-get-id)
      (user-error "No day on this line")))

(defun my/journal-gaps-visit ()
  "Open the journal note for the day on this line, creating it if needed.
Creating a file for a day that has none is the point of the report, so
it happens without a confirmation prompt -- the row itself already said
the file was absent."
  (interactive)
  (let* ((date (my/journal-gaps--date-at-point))
         (files (my/journal-gaps--file-map))
         (file (gethash date files)))
    (unless file
      (unless (fboundp 'my/denote-journal--create-backdated)
        (user-error "05-notes.el is not loaded; cannot create a backdated note"))
      (setq file (my/denote-journal--create-backdated
                  date (my/journal-gaps--encode date))))
    (find-file file)))

(defun my/journal-gaps-fill ()
  "Open the day on this line and record its metrics straight away.
The report exists to be emptied; this is the command that empties a
row.  Returning to the report afterwards is `g'."
  (interactive)
  (unless (fboundp 'my/journal-set-metrics)
    (user-error "05b-journal-metrics.el is not loaded"))
  (my/journal-gaps-visit)
  (my/journal-set-metrics))

(defun my/journal-gaps-filter ()
  "Cycle the report between all rows, missing entries and missing metrics."
  (interactive)
  (setq my/journal-gaps--filter
        (pcase my/journal-gaps--filter
          ('all 'no-entry)
          ('no-entry 'no-metrics)
          (_ 'all)))
  (my/journal-gaps-refresh))

(defun my/journal-gaps-widen ()
  "Ask for a different window and rebuild the report."
  (interactive)
  (setq my/journal-gaps--days
        (read-number "Days back: " my/journal-gaps--days))
  (my/journal-gaps-refresh))

(defun my/journal-gaps-refresh ()
  "Rebuild the report from disk."
  (interactive)
  (let* ((records (my/journal-gaps--scan my/journal-gaps--days))
         (entries (my/journal-gaps--entries records my/journal-gaps--filter))
         (no-entry (seq-count (lambda (r) (eq (nth 2 r) 'no-entry)) records))
         (no-metrics (- (length records) no-entry)))
    (setq tabulated-list-entries entries)
    (tabulated-list-print t)
    (message "%d days: %d without an entry, %d without metrics%s"
             my/journal-gaps--days no-entry no-metrics
             (pcase my/journal-gaps--filter
               ('all "")
               ('no-entry "  [showing: no entry]")
               (_ "  [showing: no metrics]")))))

(defvar my/journal-gaps-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'my/journal-gaps-visit)
    (define-key map (kbd "o")   #'my/journal-gaps-visit)
    (define-key map (kbd "m")   #'my/journal-gaps-fill)
    (define-key map (kbd "f")   #'my/journal-gaps-filter)
    (define-key map (kbd "w")   #'my/journal-gaps-widen)
    (define-key map (kbd "g")   #'my/journal-gaps-refresh)
    map)
  "Keymap for `my/journal-gaps-mode'.")

(define-derived-mode my/journal-gaps-mode tabulated-list-mode "Journal Gaps"
  "Major mode listing days missing from the journal series.
\\{my/journal-gaps-mode-map}"
  (setq tabulated-list-format
        [("Date" 12 t) ("Day" 5 t) ("Gap" 12 t) ("Missing" 26 nil) ("Title" 0 nil)])
  ;; Newest first.  `t' as the third element of the sort cons means
  ;; descending, which for dates as strings is chronological reverse.
  (setq tabulated-list-sort-key '("Date" . t))
  (tabulated-list-init-header)
  (hl-line-mode 1))

;;;###autoload
(defun my/journal-gaps (&optional days)
  "Report days with no journal entry, or with an entry but no metrics.

DAYS is how far back to look, prompted for with
`my/journal-gaps-default-days' as the default.

Keys in the report:
  RET, o  open the day, creating the note when there is none
  m       open it and record the metrics immediately
  f       cycle: all rows / no entry / no metrics
  w       change the window
  g       rebuild from disk"
  (interactive
   (list (read-number "Days back: " my/journal-gaps-default-days)))
  (let ((buffer (get-buffer-create my/journal-gaps-buffer-name)))
    (with-current-buffer buffer
      (my/journal-gaps-mode)
      (setq my/journal-gaps--days (or days my/journal-gaps-default-days))
      (setq my/journal-gaps--filter 'all)
      (my/journal-gaps-refresh))
    ;; The history tab if 23-fixed-tabs.el is present, the current
    ;; window otherwise.  A report is a place, not a document, and it
    ;; belongs with the other places.
    (when (fboundp 'my/fixed-tab-goto)
      (my/fixed-tab-goto (bound-and-true-p my/dashboards-tab-name)))
    (switch-to-buffer buffer)))

;;;###autoload
(defun my/journal-gaps-summary (&optional days)
  "Echo how many days in the window are missing an entry or metrics.
The cheap version: no buffer, no window change, just the two numbers.
Useful from a hook or when the answer is `none, carry on'."
  (interactive
   (list (read-number "Days back: " my/journal-gaps-default-days)))
  (let* ((records (my/journal-gaps--scan (or days my/journal-gaps-default-days)))
         (no-entry (seq-count (lambda (r) (eq (nth 2 r) 'no-entry)) records)))
    (message "Last %d days: %d without an entry, %d without metrics"
             (or days my/journal-gaps-default-days)
             no-entry (- (length records) no-entry))))

;; ============================================================
;; MENU
;; ============================================================
;; Appended to the Overview group of my/notes-find-menu, after the
;; History entry that 21-dashboards.el adds there.  Anchoring on "h"
;; rather than on "r" keeps the two dated views next to each other; if
;; 21-dashboards.el is absent the anchor is missing and
;; `my/transient-append' skips this, which is the intended degradation.

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-find-menu "h"
                         '("j" "Journal gaps" my/journal-gaps))))

(provide '35-journal-gaps)
;;; 35-journal-gaps.el ends here
