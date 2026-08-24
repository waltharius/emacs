;;; 05b-journal-metrics.el --- Structured daily metrics for journal notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Daily metrics live in a property drawer under the headline named by
;; `my-journal-metrics-heading' (00-core.el), NOT in a drawer placed after
;; the front matter.  Per the Org manual, a property block before the first
;; headline must sit at the very top of the buffer with only comments above
;; it, so the drawer emitted by the pre-2026-08 journal template was never
;; parsed as properties at all.  Notes written that way are schema 0 and are
;; migrated opportunistically -- see "Legacy migration" below.
;;
;; WHAT LIVES HERE AND WHAT DOES NOT
;; ---------------------------------
;; Only fields that WHOOP cannot supply.  Sleep duration and efficiency,
;; caffeine, recovery and the behaviour checkboxes come from the WHOOP CSV
;; export (journal_entries.csv, physiological_cycles.csv); steps come from
;; Samsung Health.  Duplicating them by hand would cost a daily tax and buy
;; a second, worse copy.
;;
;; MISSING VS. ZERO
;; ----------------
;;   RET   -> accept the field default (an explicit 0 / none), or, when the
;;            field has no default, leave the property absent.
;;   "-"   -> delete the property: "this was not recorded".
;; A blank property value is never written.  An absent property means no
;; measurement; it must never be read as zero.
;;
;; LEGACY MIGRATION
;; ----------------
;; `my/journal-set-metrics' upgrades the file it touches: it seeds WELLBEING
;; from the old :well-being: value, writes the new drawer, then deletes the
;; legacy drawer and stamps #+schema:.  Nothing is migrated in bulk; a note
;; is only rewritten when you deliberately open it and answer the prompts,
;; and aborting with C-g leaves the file untouched.
;;
;; MEASUREMENT LAG
;; ---------------
;; METRICS_ADDED records when the metrics were FIRST written.  A day rated
;; the same evening and a day reconstructed three weeks later are not the
;; same measurement: recalled affect flattens towards how you feel now.  The
;; indexer computes lag_days from METRICS_ADDED against the date in the file
;; name, so analyses can restrict themselves to lag <= 1 when that matters.
;; This overlaps with ADDED_AT on the '* Uzupełnienie' heading but is not
;; redundant: ADDED_AT only exists for backdated *prose*, while metrics can
;; be added to a same-day file weeks after it was written.
;;
;; COMMANDS
;; --------
;;   M-x my/journal-set-metrics            (C-c n c w)  current buffer
;;   M-x my/journal-set-metrics-for-date   (C-c n c W)  pick a date
;;
;; Deleting this file is safe: init.el loads it with NOERROR, the journal
;; template in 05-notes.el does not depend on it, and the two menu entries
;; are added through `my/transient-append', which degrades quietly.

;;; Code:

(require 'org)
(require 'seq)
(require 'subr-x)

;; 05-notes.el is always loaded first by init.el; declared to keep the
;; byte-compiler quiet about the backdating helper.
(declare-function my/denote-journal--create-backdated "05-notes" (date encoded-time))

;; ============================================================
;; FIELDS
;; ============================================================

(defvar my/journal-metrics-skip-marker "-"
  "Input that explicitly deletes a property instead of setting it.")

(defvar my/journal-prose-threshold 20
  "Minimum number of prose characters for a day to count as written up.
Below this the day is treated as metrics-only and NO_ENTRY_REASON is
offered.  Headlines, front matter, property drawers and the metrics
subtree never count towards the total.")

(defvar my/journal-no-entry-reasons
  '("busy" "travel" "low" "forgot" "other")
  "Allowed values for NO_ENTRY_REASON.
Only asked for on days that have no prose.  Purely explanatory: the word
count computed at index time stays authoritative for whether a day was
written up, so a stale value here is harmless.")

(defvar my/journal-metrics-fields
  '((:key "WELLBEING"
     :prompt "Samopoczucie 1-10"
     :values ("1" "2" "3" "4" "5" "6" "7" "8" "9" "10")
     :default nil)
    (:key "ALCOHOL_U"
     :prompt "Alkohol (U, 1 U = 10 g etanolu; piwo 0.5 l 5% = 2)"
     :values nil
     :default "0"
     :number t)
    (:key "ILLNESS"
     :prompt "Zdrowie"
     :values ("none" "mild" "significant")
     :default "none"))
  "Fields prompted for, in order.
Deliberately short: every field is a tax paid daily, and a field that
stops being filled in produces gaps that are worse than never having
had it.  Add one only after the current set has survived a few weeks.")

;; ============================================================
;; SCHEMA
;; ============================================================

(defun my/journal--schema ()
  "Return the buffer's #+schema: value as a number, 0 when absent."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^#\\+schema:[ \t]*\\([0-9]+\\)" nil t)
        (string-to-number (match-string 1))
      0)))

(defun my/journal--ensure-schema ()
  "Write #+schema: into the front matter when it is absent.
Placed after #+identifier: when that exists, otherwise after the last
front-matter keyword."
  (save-excursion
    (goto-char (point-min))
    (unless (re-search-forward "^#\\+schema:" nil t)
      (goto-char (point-min))
      (if (re-search-forward "^#\\+identifier:.*$" nil t)
          (progn
            (end-of-line)
            (insert (format "\n#+schema:     %d" my-journal-schema-version)))
        (goto-char (point-min))
        (while (looking-at "^#\\+")
          (forward-line 1))
        (insert (format "#+schema:     %d\n" my-journal-schema-version))))))

;; ============================================================
;; LEGACY DRAWER (schema 0)
;; ============================================================

(defun my/journal--legacy-drawer-bounds ()
  "Return (BEG . END) of the legacy property drawer, or nil.
The legacy drawer is the one the old journal template wrote between the
front matter and the first headline.  END swallows one trailing blank
line so that removing the drawer does not leave a gap."
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
  "Return the legacy :well-being: value as a string, or nil."
  (let ((bounds (my/journal--legacy-drawer-bounds)))
    (when bounds
      (save-excursion
        (goto-char (car bounds))
        (when (re-search-forward "^[ \t]*:well-being:[ \t]*\\([0-9]+\\)"
                                 (cdr bounds) t)
          (match-string 1))))))

(defun my/journal--drop-legacy-drawer ()
  "Delete the legacy drawer.  Return non-nil when something was removed."
  (let ((bounds (my/journal--legacy-drawer-bounds)))
    (when bounds
      (delete-region (car bounds) (cdr bounds))
      t)))

;; ============================================================
;; METRICS DRAWER
;; ============================================================

(defun my/journal--goto-metrics ()
  "Move point onto the metrics headline, creating it if absent.
The headline is inserted above the first existing headline so that it
stays at the top while timestamped entries accumulate at the end."
  (goto-char (point-min))
  (let ((re (format "^\\* %s[ \t]*$"
                    (regexp-quote my-journal-metrics-heading))))
    (if (re-search-forward re nil t)
        (beginning-of-line)
      (goto-char (point-min))
      (if (re-search-forward "^\\*+ " nil t)
          (beginning-of-line)
        (goto-char (point-max))
        (unless (bolp) (insert "\n")))
      (save-excursion
        (insert (format "* %s\n\n" my-journal-metrics-heading))))))

(defun my/journal--prose-chars ()
  "Return the number of prose characters outside the metrics subtree.
Front matter, headline lines, property drawers and everything under the
metrics headline are excluded."
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

(defun my/journal--ask (field &optional seed)
  "Prompt for FIELD.  Return a string, or nil meaning \"delete it\".
The pre-filled answer is the current property value, then SEED (used to
carry a legacy value across), then the field default."
  (let* ((key      (plist-get field :key))
         (values   (plist-get field :values))
         (existing (or (org-entry-get (point) key) seed))
         (def      (or existing (plist-get field :default)))
         (prompt   (format "%s%s: "
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
  "Prompt for the metrics of the journal file in the current buffer.
Re-running the command edits the existing values rather than clearing
them.  On a schema 0 note the legacy :well-being: value is offered as the
default for WELLBEING and the legacy drawer is removed afterwards, so a
note is upgraded simply by being touched."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer"))
  (let* ((legacy (my/journal--legacy-wellbeing))
         (prose  (>= (my/journal--prose-chars) my/journal-prose-threshold)))
    ;; All prompting happens first: aborting with C-g here leaves the file
    ;; exactly as it was, legacy drawer included.
    (save-excursion
      (my/journal--goto-metrics)
      (dolist (field my/journal-metrics-fields)
        (let* ((key    (plist-get field :key))
               (seed   (and legacy (string= key "WELLBEING") legacy))
               (answer (my/journal--ask field seed)))
          (if answer
              (org-entry-put (point) key answer)
            (org-entry-delete (point) key))))

      (when (and (not prose)
                 (not (org-entry-get (point) "NO_ENTRY_REASON")))
        (let ((reason (string-trim
                       (completing-read "Brak wpisu, powód (RET = pomiń): "
                                        my/journal-no-entry-reasons nil nil))))
          (unless (string-empty-p reason)
            (org-entry-put (point) "NO_ENTRY_REASON" reason))))

      ;; Written once, never refreshed: this is when the metrics were first
      ;; recorded, not when they were last edited.
      (unless (org-entry-get (point) "METRICS_ADDED")
        (org-entry-put (point) "METRICS_ADDED"
                       (format-time-string "[%Y-%m-%d %a %H:%M]"))))

    ;; Migration, only once the new drawer is safely in place.
    (let ((upgraded (my/journal--drop-legacy-drawer)))
      (my/journal--ensure-schema)
      (save-buffer)
      (message (if upgraded
                   "Metryki zapisane; stary drawer :well-being: usunięty"
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
create the file would leave a hole in the series with no explanation of
why it is there.  The cursor is left at the end of the buffer, which is
the cheapest available prompt to actually write the day up."
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
;; TRANSIENT
;; ============================================================
;; 12-transient.el loads after this module, so the entries are added when
;; (and if) it provides itself.  `my/transient-append' already degrades on
;; a missing prefix, anchor or duplicate key; the `fboundp' guard covers
;; the case where 12-transient.el has been replaced by something else.

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-create-menu "J"
                         '("w" "Metrics today" my/journal-set-metrics))
    (my/transient-append 'my/notes-create-menu "w"
                         '("W" "Metrics for date" my/journal-set-metrics-for-date))))

(provide '05b-journal-metrics)
;;; 05b-journal-metrics.el ends here
