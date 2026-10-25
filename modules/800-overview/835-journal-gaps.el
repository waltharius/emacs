;;; 835-journal-gaps.el --- Days without a journal entry, or without metrics -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; MyPKS-Switch: my/journal-gaps-module-mode

;;; Commentary:
;; A report of what is MISSING from the journal series, as opposed to
;; the dashboards in 821-dashboards.el which show what is there.
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
;; `405b-journal-metrics.el' is explicit that an absent keyword means
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
;; field added to 405b-journal-metrics.el starts being reported as
;; missing without touching this file, and a field removed there stops
;; being reported.  A second copy of that list would drift, and the
;; drift would be silent -- the report would keep demanding a field
;; that no command writes any more.
;;
;; `recalled' and `no_entry_reason' are deliberately NOT required.
;; Both are conditional: 405b-journal-metrics.el asks for them only when
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
;;   405b-journal-metrics.el  the field list, and `my/journal-set-metrics'
;;   205-notes.el             `my/denote-journal-create-backdated'
;;   212-transient.el         the menu entry
;; Each is guarded.  Without 05b the report still lists days with no
;; entry and says so; without 205-notes a missing day can be opened but
;; not created.
;;
;; Docs: ~/.emacs.d/function_helper.org::#journal-gaps

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'tabulated-list)

(declare-function my/journal-set-metrics "405b-journal-metrics" ())
(declare-function my/denote-journal-create-backdated "205-notes" (date encoded-time))
(declare-function my/journal-file-date "205-notes" (file))
(declare-function my/fixed-tab-goto "101-ui" (name &optional position))

(defgroup my-journal-gaps nil
  "Reporting days missing from the journal series.
Named without the slash, matching `my-dashboards' in 821-dashboards.el:
a group sharing a symbol with a command makes both harder to find, and
the pre-commit duplicate scan cannot tell the two apart."
  :tag "Journal gaps"
  :group 'mypks-notes)

(defcustom my/journal-gaps-default-days 90
  "Number of days back the report covers by default."
  :type 'integer :group 'my-journal-gaps)

(defcustom my/journal-gaps-buffer-name "*Journal Gaps*"
  "Name of the report buffer."
  :type 'string :group 'my-journal-gaps)

(defcustom my/journal-gaps-tab-name "Stats"
  "Tab the gap report opens in.

Its own option rather than a reference to `my/notes-stats-tab-name',
so that this module keeps working with 836-notes-stats.el deleted --
the default merely happens to name the same tab, because both reports
answer questions about the collection rather than showing a note.

Set to nil to open the report in the current window."
  :type '(choice (const :tag "Current window" nil) string)
  :group 'my-journal-gaps)

(defcustom my/journal-gaps-extra-required nil
  "Metrics keywords required in addition to `my/journal-metrics-fields'.
Normally empty: the required set is derived, so that adding a field in
405b-journal-metrics.el is enough.  This exists for a field that is
written by something other than that command."
  :type '(repeat string) :group 'my-journal-gaps)

;; ============================================================
;; WHAT COUNTS AS COMPLETE
;; ============================================================

(defun my/journal-gaps-required-keys ()
  "Return the metrics keywords a complete day must carry.
Derived from `my/journal-metrics-fields' when 405b-journal-metrics.el is
loaded; nil otherwise, which turns the metrics half of the report off
rather than inventing a field list."
  (append
   (when (boundp 'my/journal-metrics-fields)
     (mapcar (lambda (field) (plist-get field :key)) my/journal-metrics-fields))
   my/journal-gaps-extra-required))

;; ============================================================
;; READING THE SILO
;; ============================================================

(defun my/journal-gaps--file-map ()
  "Return a hash of YYYY-MM-DD -> file for every journal note.

Built from file names alone -- reading the front matter of a thousand
files to find dates the names already carry would make the report cost
proportional to how much has been written.

The date comes from `my/journal-file-date' (205-notes.el), which tests
the `journal' KEYWORD and then reads the date.  This module used to
match a `DATE-journal' slug itself, which made the title
load-bearing: a retitled journal note dropped out of the report
silently, and a report that silently omits days is worse than no
report, because its whole content is a claim about what is missing."
  (let ((map (make-hash-table :test #'equal)))
    (dolist (file (my/notes-files my-notes-journal "\\.org\\'") map)
      (when-let* ((date (and (fboundp 'my/journal-file-date)
                             (my/journal-file-date file))))
        ;; First one wins.  Two files for one day is a duplicate, and
        ;; 826-maintenance.el is where that gets reported.
        (unless (gethash date map)
          (puthash date file map))))))

(defun my/journal-gaps-missing-keys (file required)
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

(defun my/journal-gaps--dates (days &optional now)
  "Return the last DAYS dates as (DATE . TIME), today first.
DATE is YYYY-MM-DD, TIME midday of that day.  Counted in calendar days
from NOW (default: the current time), with the date functions of
000-core.el (since 2026-10-26; before, an encoding of its own): by
steps of 86400 seconds, as until 2026-10-25, a day of 23 hours (the
start of summer time) was skipped when the report ran in the first hour
after midnight -- a missing journal day left out of a report of missing
days."
  (let ((today (my/date-of now)))
    (mapcar (lambda (offset)
              (let ((date (my/date-add-days today (- offset))))
                (cons date (my/date-to-time date))))
            (number-sequence 0 (1- days)))))

(defun my/journal-gaps--scan (days &optional now)
  "Return a list of gap records for the last DAYS days before NOW.
Each record is (DATE WEEKDAY KIND DETAIL FILE), where KIND is
`no-entry' or `no-metrics'.  Complete days produce no record: this is a
report of what is missing, and a row per satisfactory day would bury
the answer."
  (let* ((files    (my/journal-gaps--file-map))
         (required (my/journal-gaps-required-keys))
         (earliest (car (sort (hash-table-keys files) #'string<)))
         records)
    (dolist (day (my/journal-gaps--dates days now))
      (let* ((date (car day))
             (weekday (format-time-string "%a" (cdr day)))
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
            (when-let* ((missing (my/journal-gaps-missing-keys file required)))
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
      (unless (fboundp 'my/denote-journal-create-backdated)
        (user-error "205-notes.el is not loaded; cannot create a backdated note"))
      (setq file (my/denote-journal-create-backdated
                  date (my/date-to-time date))))
    (find-file file)))

(defun my/journal-gaps-fill ()
  "Open the day on this line and record its metrics straight away.
The report exists to be emptied; this is the command that empties a
row.  Returning to the report afterwards is `g'."
  (interactive)
  (unless (fboundp 'my/journal-set-metrics)
    (user-error "405b-journal-metrics.el is not loaded"))
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
    ;; The tab named by `my/journal-gaps-tab-name' if 323-fixed-tabs.el
    ;; is present, the current window otherwise.  A report is a place,
    ;; not a document, and it belongs with the other places.
    (when (and my/journal-gaps-tab-name
               (fboundp 'my/fixed-tab-goto))
      (my/fixed-tab-goto my/journal-gaps-tab-name))
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
;; Inserted into the Overview column of my/notes-find-menu, before its
;; Quit, which 212-transient.el owns.  Loaded after 821-dashboards.el, so
;; it still lands right after the History entry when that module is on;
;; when it is off, Journal gaps stays in the menu.  (Until 2026-10-19 it
;; was anchored on "h" and disappeared without 821-dashboards.el.)

;; ============================================================
;; ON AND OFF
;; ============================================================
;; `my/journal-gaps-module-mode' is this module's switch (module
;; contract, rule 12): on, Journal gaps in Find → Overview (C-c n f j);
;; off, gone.  The commands stay defined for M-x.  Customize saves the
;; position in this machine's settings (M-x customize-option RET
;; my/journal-gaps-module-mode).

(defconst my/journal-gaps-module--menu-entries
  '((insert my/notes-find-menu "q" ("j" "Journal gaps" my/journal-gaps)))
  "Menu entries of this module, for `my/transient-entries'.")

(define-minor-mode my/journal-gaps-module-mode
  "Journal gaps as a module, switched on and off.
On: Journal gaps in Find → Overview (C-c n f j).  Off: they are gone,
and the commands remain for M-x.  Customize saves the position in this
machine's settings."
  :global t
  :init-value t
  :group 'my-journal-gaps
  (with-eval-after-load '212-transient
    (when (fboundp 'my/transient-entries)
      (my/transient-entries my/journal-gaps-module-mode my/journal-gaps-module--menu-entries))))

(my/journal-gaps-module-mode (if my/journal-gaps-module-mode 1 -1))

(provide '835-journal-gaps)
;;; 835-journal-gaps.el ends here
