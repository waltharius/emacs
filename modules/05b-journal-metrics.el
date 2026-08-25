;;; 05b-journal-metrics.el --- Structured daily metrics for journal notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Daily metrics are stored as front-matter keywords at the top of the
;; journal file:
;;
;;     #+identifier: 20260111T000000
;;     #+language:   pl
;;     #+schema:     2
;;     #+wellbeing:  6
;;     #+alcohol_u:  0
;;     #+illness:    none
;;     #+recalled:   t
;;     #+metrics_added: [2026-08-25 wto 03:26]
;;
;; WHY KEYWORDS AND NOT A PROPERTY DRAWER
;; --------------------------------------
;; Org parses a property drawer before the first headline only when it is
;; at the very top of the buffer with nothing but comments above it, which
;; would mean putting it above #+title: and fighting Denote's front-matter
;; tooling.  The alternative was a "* Metryki" headline, which worked but
;; put a second :PROPERTIES: drawer in a file that already has one under
;; "* Uzupełnienie" -- an ambiguity that produced a duplicated metrics
;; block in practice.  A keyword name is unique in the file, has no
;; positional rules, and is trivial for the external indexer to parse.
;;
;; The cost is real: org-set-property, org-columns and org-ql do not see
;; keywords.  That is acceptable here because the query layer is an
;; external DuckDB index, and editing goes through the commands below.
;;
;; SCHEMA VERSIONS
;; ---------------
;;   0  no #+schema:.  :well-being: in a drawer under the front matter,
;;      which Org never parsed at all.  Read by regexp.
;;   1  metrics in a property drawer under a "* Metryki" headline.
;;      Short-lived; converted by `my/journal-migrate-metrics-format'.
;;   2  metrics as front-matter keywords.  Current.
;; All three are readable; only 2 is written.
;;
;; MISSING VS. ZERO
;; ----------------
;;   RET   -> accept the field default (an explicit 0 / none), or, when the
;;            field has no default, write nothing.
;;   "-"   -> remove the keyword: "this was not recorded".
;; An absent keyword means no measurement.  It must never be read as zero.
;; The distinction matters most when backfilling: 0 alcohol units means
;; "I did not drink", no keyword means "I do not remember whether I did".
;;
;; ATOMICITY
;; ---------
;; `my/journal-set-metrics' runs in three phases: read, prompt, write.
;; Nothing is inserted before every prompt has been answered, so C-g at any
;; point leaves the buffer byte-identical.  (The previous version created
;; the "* Metryki" headline before prompting and did not have this
;; property.)
;;
;; COMMANDS
;; --------
;;   my/journal-set-metrics             (C-c n c w)  current buffer
;;   my/journal-set-metrics-for-date    (C-c n c W)  pick a date
;;   my/journal-migrate-metrics-format               batch 1 -> 2, dry run
;;                                                   unless given a prefix
;;
;; Deleting this file is safe: init.el loads it with NOERROR, the journal
;; template in 05-notes.el does not depend on it, and the menu entries go
;; through `my/transient-append', which degrades quietly.

;;; Code:

(require 'org)
(require 'seq)
(require 'subr-x)

(declare-function my/denote-journal--create-backdated "05-notes" (date encoded-time))

;; ============================================================
;; FIELDS
;; ============================================================

(defvar my/journal-metrics-skip-marker "-"
  "Input that removes the keyword instead of setting it.")

(defvar my/journal-prose-threshold 20
  "Minimum number of prose characters for a day to count as written up.
Below this the day is metrics-only and NO_ENTRY_REASON is offered.
Front matter, headline lines and property drawers never count.")

(defvar my/journal-no-entry-reasons
  '("busy" "travel" "low" "forgot" "other")
  "Allowed values for the no_entry_reason keyword.
Explanatory only: the word count computed at index time stays
authoritative for whether a day was written up, so a stale value here
after prose is added later is harmless.")

(defvar my/journal-metrics-fields
  '((:key "wellbeing"
     :prompt "Samopoczucie 1-10"
     :values ("1" "2" "3" "4" "5" "6" "7" "8" "9" "10")
     :default nil)
    (:key "alcohol_u"
     :prompt "Alkohol (U, 1 U = 10 g etanolu; piwo 0.5 l 5% = 2)"
     :values nil
     :default "0"
     :number t)
    (:key "illness"
     :prompt "Zdrowie"
     :values ("none" "mild" "significant")
     :default "none"))
  "Fields prompted for, in order.
Deliberately short: every field is a tax paid daily, and a field that
stops being filled in leaves gaps worse than never having had it.")

(defvar my/journal-metrics-keyword-order
  '("wellbeing" "alcohol_u" "illness" "recalled" "no_entry_reason"
    "metrics_added")
  "Order in which metrics keywords are written into the front matter.
Keeps diffs stable: without a fixed order, re-running the command would
reshuffle lines and every commit would look like a rewrite.")

(defconst my/journal--front-matter-column 14
  "Column at which front-matter values are aligned, matching Denote.")

;; ============================================================
;; FRONT-MATTER KEYWORDS
;; ============================================================
;; Read and write go through the same regexp so the two can never
;; disagree.  `org-collect-keywords' would do the reading, but it gives no
;; buffer positions, and a second mechanism for writing is exactly how the
;; :well-being: drawer came to be readable by eye and by nothing else.

(defun my/journal--front-matter-end ()
  "Return the position just after the last front-matter keyword line."
  (save-excursion
    (goto-char (point-min))
    (let ((end (point-min)))
      (while (looking-at "^#\\+")
        (forward-line 1)
        (setq end (point)))
      end)))

(defun my/journal--keyword-bounds (key)
  "Return (BEG . END) of the whole line defining KEY, or nil.
END includes the newline."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t)
          (limit (my/journal--front-matter-end)))
      (when (re-search-forward (format "^#\\+%s:" (regexp-quote key)) limit t)
        (cons (line-beginning-position) (line-beginning-position 2))))))

(defun my/journal--keyword-get (key)
  "Return the value of front-matter keyword KEY as a trimmed string, or nil.
An empty value reads as nil: a keyword with nothing after the colon is
not a measurement."
  (let ((bounds (my/journal--keyword-bounds key)))
    (when bounds
      (save-excursion
        (goto-char (car bounds))
        (when (looking-at (format "^#\\+%s:[ \t]*\\(.*?\\)[ \t]*$"
                                  (regexp-quote key)))
          (let ((value (match-string-no-properties 1)))
            (unless (string-empty-p value) value)))))))

(defun my/journal--keyword-line (key value)
  "Return the front-matter line for KEY and VALUE, Denote-aligned."
  (let* ((prefix (format "#+%s:" key))
         (pad (max 1 (- my/journal--front-matter-column (length prefix)))))
    (concat prefix (make-string pad ?\s) value "\n")))

(defun my/journal--keyword-delete (key)
  "Remove the front-matter line defining KEY, if present."
  (let ((bounds (my/journal--keyword-bounds key)))
    (when bounds
      (delete-region (car bounds) (cdr bounds))
      t)))

(defun my/journal--keyword-put (key value)
  "Set front-matter keyword KEY to VALUE.
Replaces the line in place when the keyword exists, so that the order in
`my/journal-metrics-keyword-order' is preserved once established.  A new
keyword is appended after the last front-matter line."
  (let ((bounds (my/journal--keyword-bounds key))
        (line (my/journal--keyword-line key value)))
    (save-excursion
      (if bounds
          (progn
            (delete-region (car bounds) (cdr bounds))
            (goto-char (car bounds))
            (insert line))
        (goto-char (my/journal--front-matter-end))
        (insert line)))))

(defun my/journal--write-metrics (values)
  "Write VALUES, an alist of keyword to string or nil, in canonical order.
A nil value removes the keyword rather than blanking it."
  (dolist (key my/journal-metrics-keyword-order)
    (when (assoc key values)
      (let ((value (cdr (assoc key values))))
        (if value
            (my/journal--keyword-put key value)
          (my/journal--keyword-delete key))))))

;; ============================================================
;; SCHEMA
;; ============================================================

(defun my/journal--schema ()
  "Return the buffer's #+schema: value as a number, 0 when absent."
  (let ((value (my/journal--keyword-get "schema")))
    (if value (string-to-number value) 0)))

(defun my/journal--ensure-language ()
  "Write #+language: pl when the keyword is absent.
Only ever added, never corrected: the indexer verifies the declared
language against a detector and logs disagreements, which is the right
place for that check."
  (unless (my/journal--keyword-get "language")
    (my/journal--keyword-put "language" "pl")))

;; ============================================================
;; OLDER FORMATS
;; ============================================================

(defun my/journal--legacy-drawer-bounds ()
  "Return (BEG . END) of the schema 0 drawer below the front matter, or nil.
END swallows one trailing blank line so removal leaves no gap."
  (save-excursion
    (goto-char (point-min))
    (let ((limit (or (save-excursion
                       (when (re-search-forward "^\\*+ " nil t)
                         (match-beginning 0)))
                     (point-max))))
      (when (re-search-forward "^[ \t]*:PROPERTIES:[ \t]*$" limit t)
        (let ((beg (match-beginning 0)))
          (when (re-search-forward "^[ \t]*:END:[ \t]*$" limit t)
            (goto-char (match-end 0))
            (forward-line 1)
            (when (and (not (eobp)) (looking-at "^[ \t]*$"))
              (forward-line 1))
            (cons beg (min (point) limit))))))))

(defun my/journal--legacy-wellbeing ()
  "Return the schema 0 :well-being: value as a string, or nil."
  (let ((bounds (my/journal--legacy-drawer-bounds)))
    (when bounds
      (save-excursion
        (goto-char (car bounds))
        (when (re-search-forward "^[ \t]*:well-being:[ \t]*\\([0-9]+\\)"
                                 (cdr bounds) t)
          (match-string-no-properties 1))))))

(defun my/journal--metrics-heading-bounds ()
  "Return (BEG . END) of the schema 1 \"* Metryki\" subtree, or nil.
END swallows trailing blank lines up to the next headline."
  (save-excursion
    (goto-char (point-min))
    (let ((re (format "^\\* %s[ \t]*$"
                      (regexp-quote my-journal-metrics-heading))))
      (when (re-search-forward re nil t)
        (let ((beg (line-beginning-position)))
          (forward-line 1)
          (if (re-search-forward "^\\*+ " nil t)
              (goto-char (match-beginning 0))
            (goto-char (point-max)))
          (cons beg (point)))))))

(defun my/journal--heading-property (key)
  "Return property KEY from the schema 1 metrics subtree, or nil.
KEY is the lower-case keyword name; the drawer used upper case."
  (let ((bounds (my/journal--metrics-heading-bounds)))
    (when bounds
      (save-excursion
        (goto-char (car bounds))
        (when (re-search-forward
               (format "^[ \t]*:%s:[ \t]*\\(.*?\\)[ \t]*$" (upcase key))
               (cdr bounds) t)
          (let ((value (match-string-no-properties 1)))
            (unless (string-empty-p value) value)))))))

(defun my/journal--existing (key)
  "Return the current value of metric KEY from whichever format is present.
Keywords win, then the schema 1 drawer, then the schema 0 drawer."
  (or (my/journal--keyword-get key)
      (my/journal--heading-property key)
      (and (string= key "wellbeing") (my/journal--legacy-wellbeing))))

(defun my/journal--purge-old-formats ()
  "Remove the schema 0 drawer and the schema 1 metrics subtree.
Returns a list of what was removed, for the echo-area message."
  (let (removed)
    (when (my/journal--metrics-heading-bounds)
      (let ((bounds (my/journal--metrics-heading-bounds)))
        (delete-region (car bounds) (cdr bounds))
        (push my-journal-metrics-heading removed)))
    (when (my/journal--legacy-drawer-bounds)
      (let ((bounds (my/journal--legacy-drawer-bounds)))
        (delete-region (car bounds) (cdr bounds))
        (push ":well-being:" removed)))
    removed))

;; ============================================================
;; PROSE
;; ============================================================

(defun my/journal--prose-chars ()
  "Return the number of prose characters in the buffer.
Front matter, headline lines, property drawers and the schema 1 metrics
subtree are excluded."
  (save-excursion
    (goto-char (point-min))
    (let ((metrics-re (format "^\\* %s[ \t]*$"
                              (regexp-quote my-journal-metrics-heading)))
          (in-drawer nil)
          (in-metrics nil)
          (count 0))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (cond
           ((string-match-p "^\\*+ " line)
            (setq in-drawer nil)
            (setq in-metrics (and (string-match-p metrics-re line) t)))
           ((string-match-p "^[ \t]*:PROPERTIES:[ \t]*$" line)
            (setq in-drawer t))
           ((string-match-p "^[ \t]*:END:[ \t]*$" line)
            (setq in-drawer nil))
           ((or in-drawer in-metrics) nil)
           ((string-match-p "^#\\+" line) nil)
           (t (setq count (+ count (length (string-trim line)))))))
        (forward-line 1))
      count)))

(defun my/journal--file-date ()
  "Return the day the current journal file describes, as YYYY-MM-DD.
Read from the file name, which is what the rest of this configuration
treats as authoritative for journal notes.  Nil outside a journal file."
  (let ((name (and buffer-file-name
                   (file-name-nondirectory buffer-file-name))))
    (when (and name
               (string-match "--\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)-journal"
                             name))
      (match-string 1 name))))

;; ============================================================
;; PROMPTING
;; ============================================================

(defun my/journal--valid-p (field answer)
  "Return non-nil when ANSWER is acceptable for FIELD."
  (let ((values (plist-get field :values)))
    (cond
     (values (and (member answer values) t))
     ((plist-get field :number)
      (string-match-p "\\`[0-9]+\\(\\.[0-9]+\\)?\\'" answer))
     (t t))))

(defun my/journal--ask (field &optional existing)
  "Prompt for FIELD.  Return a string, or nil meaning \"remove it\".
EXISTING is the value already recorded in any of the supported formats;
it is offered as the answer, falling back to the field default."
  (let* ((key    (plist-get field :key))
         (values (plist-get field :values))
         (def    (or existing (plist-get field :default)))
         (prompt (format "%s%s: "
                         (plist-get field :prompt)
                         (if def (format " [%s]" def) "")))
         answer)
    (catch 'done
      (while t
        (setq answer (string-trim
                      (if values
                          (completing-read prompt values nil nil nil nil def)
                        (read-string prompt nil nil def))))
        (cond
         ((string= answer my/journal-metrics-skip-marker) (throw 'done nil))
         ((string-empty-p answer)                         (throw 'done nil))
         ((my/journal--valid-p field answer)              (throw 'done answer))
         (t (message "Nieprawidłowa wartość dla %s" key) (sit-for 1)))))))

;; ============================================================
;; COMMANDS
;; ============================================================

;;;###autoload
(defun my/journal-set-metrics ()
  "Record the metrics of the journal file in the current buffer.

Three phases.  Read: gather what is already recorded, in whichever of
the three formats the file uses.  Prompt: ask for everything, keeping
the answers in memory.  Write: purge older formats, write the keywords,
save.  Nothing touches the buffer until every prompt is answered, so
C-g leaves the file byte-identical."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer"))
  (let* ((file-date (my/journal--file-date))
         (today     (format-time-string "%Y-%m-%d"))
         (past-day  (and file-date (not (string= file-date today))))
         (prose     (>= (my/journal--prose-chars) my/journal-prose-threshold))
         (existing  (mapcar (lambda (field)
                              (let ((key (plist-get field :key)))
                                (cons key (my/journal--existing key))))
                            my/journal-metrics-fields))
         (answers   nil))

    ;; --- prompt phase: no buffer modification below this line ---
    (dolist (field my/journal-metrics-fields)
      (let* ((key (plist-get field :key))
             (answer (my/journal--ask field (cdr (assoc key existing)))))
        (push (cons key answer) answers)))

    (when (and (not prose)
               (not (my/journal--existing "no_entry_reason")))
      (let ((reason (string-trim
                     (completing-read "Brak wpisu, powód (RET = pomiń): "
                                      my/journal-no-entry-reasons nil nil))))
        (unless (string-empty-p reason)
          (push (cons "no_entry_reason" reason) answers))))

    ;; Set once, never unset: a value supplied or revised for a past day
    ;; is a memory, and stays one even if edited again later.
    (let ((wb (cdr (assoc "wellbeing" answers)))
          (wb-prior (cdr (assoc "wellbeing" existing))))
      (when (and wb past-day (not (equal wb wb-prior)))
        (push (cons "recalled" "t") answers)))

    ;; Records the first write, never refreshed.
    (unless (my/journal--existing "metrics_added")
      (push (cons "metrics_added"
                  (format-time-string "[%Y-%m-%d %a %H:%M]"))
            answers))

    ;; --- write phase ---
    (let ((removed (my/journal--purge-old-formats)))
      (my/journal--ensure-language)
      (my/journal--keyword-put "schema"
                               (number-to-string my-journal-schema-version))
      (my/journal--write-metrics answers)
      (save-buffer)
      (message (if removed
                   (format "Metryki zapisane; usunięto %s"
                           (string-join removed ", "))
                 "Metryki zapisane")))))

(defun my/journal--file-for-date (date)
  "Return the journal file whose name encodes DATE (YYYY-MM-DD), or nil."
  (car (seq-filter
        (lambda (f)
          (string-match-p (concat "--" (regexp-quote date) "-journal")
                          (file-name-nondirectory f)))
        (directory-files my-notes-journal t "\\.org\\'"))))

;;;###autoload
(defun my/journal-set-metrics-for-date ()
  "Ask for a date and record that day's metrics, creating the file if needed.
A day rated with no prose is still a valid observation: refusing to
create the file would leave a hole in the series with no record of why
it is there.  The cursor is left at the end of the buffer afterwards,
which is the cheapest available prompt to write the day up."
  (interactive)
  (let* ((date-input (org-read-date nil nil nil "Data: "))
         (encoded    (apply #'encode-time (org-parse-time-string date-input)))
         (day        (format-time-string "%Y-%m-%d" encoded))
         (file       (my/journal--file-for-date day)))
    (unless file
      (if (y-or-n-p (format "Brak wpisu dla %s.  Utworzyć? " day))
          (setq file (my/denote-journal--create-backdated day encoded))
        (user-error "Przerwano")))
    (find-file file)
    (my/journal-set-metrics)
    (goto-char (point-max))))

;; ============================================================
;; BATCH FORMAT MIGRATION
;; ============================================================

(defun my/journal--migrate-buffer ()
  "Convert the current buffer from schema 0 or 1 to keywords.
Pure format translation: no value is invented, changed or dropped, so
this needs no prompting and is safe to run unattended.  Returns non-nil
when the buffer was changed."
  (let ((values (mapcar (lambda (key) (cons key (my/journal--existing key)))
                        my/journal-metrics-keyword-order)))
    (when (or (my/journal--metrics-heading-bounds)
              (my/journal--legacy-drawer-bounds))
      (my/journal--purge-old-formats)
      (my/journal--ensure-language)
      (my/journal--keyword-put "schema"
                               (number-to-string my-journal-schema-version))
      ;; Only write keys that actually had a value: a file with an empty
      ;; legacy drawer becomes a file with no metrics, not a file with
      ;; empty metrics.
      (my/journal--write-metrics
       (seq-filter #'cdr values))
      t)))

;;;###autoload
(defun my/journal-migrate-metrics-format (&optional write include-schema-0)
  "Convert journal files from the older metrics formats to keywords.

Without a prefix argument this is a dry run: it reports what it would do
and changes nothing.  With \\[universal-argument] it writes.  With
\\[universal-argument] \\[universal-argument] it also converts schema 0
notes, which is the 3500-file case and produces a very large commit --
by default only schema 1 files are touched, since those were created by
this configuration over a single day and are few.

Commit or stash the notes repository before running this with WRITE."
  (interactive (list (and current-prefix-arg t)
                     (equal current-prefix-arg '(16))))
  (let ((changed 0)
        (scanned 0)
        (names nil))
    (dolist (file (directory-files my-notes-journal t "\\.org\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        (org-mode)
        (setq scanned (1+ scanned))
        (let ((schema-1 (my/journal--metrics-heading-bounds))
              (schema-0 (my/journal--legacy-drawer-bounds)))
          (when (or schema-1 (and schema-0 include-schema-0))
            (when (my/journal--migrate-buffer)
              (setq changed (1+ changed))
              (push (file-name-nondirectory file) names)
              (when write
                (write-region (point-min) (point-max) file nil 'quiet)))))))
    (with-current-buffer (get-buffer-create "*journal-migration*")
      (erase-buffer)
      (insert (format "%s: %d of %d files\n\n"
                      (if write "Converted" "Would convert")
                      changed scanned))
      (dolist (name (nreverse names))
        (insert name "\n"))
      (display-buffer (current-buffer)))
    (message "%s %d/%d journal files"
             (if write "Converted" "Dry run:") changed scanned)))

;; ============================================================
;; TRANSIENT
;; ============================================================
;; 12-transient.el loads after this module, so the entries are added when
;; (and if) it provides itself.

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-create-menu "J"
                         '("w" "Metrics today" my/journal-set-metrics))
    (my/transient-append 'my/notes-create-menu "w"
                         '("W" "Metrics for date" my/journal-set-metrics-for-date))))

(provide '05b-journal-metrics)
;;; 05b-journal-metrics.el ends here
