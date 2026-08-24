;;; 05b-journal-metrics.el --- Structured daily metrics for journal notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Daily metrics live in a property drawer under a dedicated "Metryki"
;; headline, NOT in a drawer placed after the front matter.  Per the Org
;; manual, a property block before the first headline must sit at the very
;; top of the buffer with only comments above it, so the drawer emitted by
;; the pre-2026-08 journal template was never parsed as properties at all.
;;
;; Only fields that WHOOP cannot supply are kept here.  Sleep, caffeine,
;; recovery and the behaviour checkboxes come from the WHOOP CSV export;
;; steps come from Samsung Health.  Do not duplicate them.
;;
;; Missing vs. zero:
;;   Enter          -> accept the field default (explicit 0 / none), or,
;;                     when there is no default, leave the field absent.
;;   "-"            -> delete the property (explicitly "not recorded").
;; A blank property value is never written.

;;; Code:

(require 'org)
(require 'seq)
(require 'subr-x)

(defvar my/journal-metrics-heading "Metryki"
  "Headline holding the daily metrics property drawer.")

(defvar my/journal-schema-version 1
  "Value written as #+schema: into new journal files.
Absent keyword means schema 0: metrics, if any, sit in the legacy
drawer position and are only reachable by regexp, not by org-element.")

(defvar my/journal-metrics-skip-marker "-"
  "Input that explicitly removes a property.")

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
Deliberately short.  Add a field only after the current set has survived
a few weeks of actually being filled in.")

;; ------------------------------------------------------------------
;; Locating the metrics drawer
;; ------------------------------------------------------------------

(defun my/journal--goto-metrics ()
  "Move point onto the metrics headline, creating it if absent.
The headline is inserted before the first existing headline so it stays
at the top while timestamped entries accumulate at the end."
  (goto-char (point-min))
  (let ((re (format "^\\* %s[ \t]*$"
                    (regexp-quote my/journal-metrics-heading))))
    (if (re-search-forward re nil t)
        (beginning-of-line)
      ;; Not there yet: insert it above the first headline, or at EOF.
      (goto-char (point-min))
      (if (re-search-forward "^\\*+ " nil t)
          (beginning-of-line)
        (goto-char (point-max))
        (unless (bolp) (insert "\n")))
      (save-excursion
        (insert (format "* %s\n\n" my/journal-metrics-heading))))))

(defun my/journal--valid-p (field answer)
  "Return non-nil when ANSWER is acceptable for FIELD."
  (let ((values (plist-get field :values)))
    (cond
     (values (member answer values))
     ((plist-get field :number) (string-match-p "\\`[0-9]+\\(\\.[0-9]+\\)?\\'" answer))
     (t t))))

(defun my/journal--ask (field)
  "Prompt for FIELD.  Return a string, or nil meaning \"delete it\".
Existing value wins over the declared default as the pre-filled answer."
  (let* ((key      (plist-get field :key))
         (values   (plist-get field :values))
         (existing (org-entry-get (point) key))
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
         ((string-empty-p answer)                          (throw 'done nil))
         ((my/journal--valid-p field answer)               (throw 'done answer))
         (t (message "Nieprawidłowa wartość dla %s" key) (sit-for 1)))))))

;;;###autoload
(defun my/journal-set-metrics ()
  "Prompt for the metrics of the journal file in the current buffer.
Re-running the command edits the existing values rather than clearing
them."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer"))
  (save-excursion
    (my/journal--goto-metrics)
    (dolist (field my/journal-metrics-fields)
      (let* ((key    (plist-get field :key))
             (answer (my/journal--ask field)))
        (if answer
            (org-entry-put (point) key answer)
          (org-entry-delete (point) key)))))
  (save-buffer)
  (message "Metryki zapisane"))

;; ------------------------------------------------------------------
;; Backfilling an earlier day
;; ------------------------------------------------------------------

(defun my/journal--file-for-date (date)
  "Return the journal file whose name encodes DATE (YYYY-MM-DD), or nil."
  (car (seq-filter
        (lambda (f)
          (string-match-p (concat "--" (regexp-quote date) "-journal")
                          (file-name-nondirectory f)))
        (directory-files my-notes-journal t "\\.org\\'"))))

;;;###autoload
(defun my/journal-set-metrics-for-date ()
  "Ask for a date, open that day's journal, and prompt for its metrics.
Refuses to create a file: metrics without an entry would be a data point
with no context.  Use `my/denote-journal-date' first if the day has no
journal at all."
  (interactive)
  (let* ((date (org-read-date nil nil nil "Data: "))
         (file (my/journal--file-for-date date)))
    (unless file
      (user-error "Brak wpisu dla %s -- utwórz go najpierw (C-c n j d)" date))
    (find-file file)
    (my/journal-set-metrics)))

(provide '05b-journal-metrics)
;;; 05b-journal-metrics.el ends here
