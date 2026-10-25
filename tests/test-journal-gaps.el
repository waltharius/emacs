;;; test-journal-gaps.el --- ERT tests for 35-journal-gaps -*- lexical-binding: t; -*-

;; Tests: 35-journal-gaps

;;; Commentary:

;; 35-journal-gaps lists the days of the last N with no journal note, or
;; with a note missing metrics.  Its whole content is a claim about what
;; is missing, so these tests check what it leaves out as much as what
;; it lists: complete days, days before the first note, other silos'
;; notes; every calendar day counted across the start of summer time;
;; the missing metrics named; a missing day created when opened.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-journal-gaps.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "05-notes" "35-journal-gaps")

(defmacro my/jg-test-with-journal (&rest body)
  "Run BODY with a fresh journal folder as `my-notes-journal'.
Metrics required: mood and sleep."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-gaps-" t)))
          (my-notes-dir root)
          (my-notes-journal (file-name-as-directory (expand-file-name "journal" root)))
          (my/journal-gaps-extra-required '("mood" "sleep"))
          (inhibit-message t))
     (make-directory my-notes-journal t)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/jg-test-day (offset)
  "The date OFFSET days from today, YYYY-MM-DD."
  (car (nth (- offset) (my/journal-gaps--dates (1+ (- offset))))))

(defun my/jg-test-note (date &optional metrics name)
  "Write the journal note of DATE with METRICS, a list of (KEY . VALUE).
NAME overrides the file name (without folder)."
  (let ((file (expand-file-name
               (or name (format "%sT000000--%s__journal.org"
                                (replace-regexp-in-string "-" "" date) date))
               my-notes-journal)))
    (with-temp-file file
      (insert "#+title:      " date "\n#+filetags:   :journal:\n")
      (dolist (m metrics) (insert (format "#+%s: %s\n" (car m) (cdr m))))
      (insert "\nTekst.\n"))
    file))

(defun my/jg-test-rows (days)
  "The report's records for DAYS as (DATE KIND DETAIL)."
  (mapcar (lambda (r) (list (nth 0 r) (nth 2 r) (nth 3 r)))
          (my/journal-gaps--scan days)))

(ert-deftest my/jg-test-gaps-listed-complete-days-not ()
  "A day without a note is listed as no entry, a note without all
metrics as no metrics naming them; a complete day is not listed."
  (my/jg-test-with-journal
    (my/jg-test-note (my/jg-test-day -3) '(("mood" . "7") ("sleep" . "6")))
    (my/jg-test-note (my/jg-test-day -1) '(("mood" . "5")))
    (my/jg-test-note (my/jg-test-day 0) '(("mood" . "8") ("sleep" . "7")))
    (should (equal (my/jg-test-rows 4)
                   (list (list (my/jg-test-day -1) 'no-metrics "sleep")
                         (list (my/jg-test-day -2) 'no-entry ""))))))

(ert-deftest my/jg-test-nothing-before-the-first-note ()
  "Days before the first journal note are not missing."
  (my/jg-test-with-journal
    (my/jg-test-note (my/jg-test-day -1) '(("mood" . "7") ("sleep" . "6")))
    (should (equal (mapcar #'car (my/jg-test-rows 30))
                   (list (my/jg-test-day 0))))))

(ert-deftest my/jg-test-empty-value-is-missing ()
  "A metrics keyword written without a value counts as missing."
  (my/jg-test-with-journal
    (let ((file (my/jg-test-note (my/jg-test-day 0) '(("mood" . "") ("sleep" . "6")))))
      (should (equal (my/journal-gaps-missing-keys file '("mood" "sleep")) '("mood"))))))

(ert-deftest my/jg-test-journal-notes-by-keyword ()
  "A journal note is recognised by its keyword, also with a title of its
own; a note without the keyword is not a journal note."
  (my/jg-test-with-journal
    (my/jg-test-note "2026-10-20" nil "20261020T000000--wycieczka__journal.org")
    (my/jg-test-note "2026-10-21" nil "20261021T000000--2026-10-21__inne.org")
    (let ((map (my/journal-gaps--file-map)))
      (should (gethash "2026-10-20" map))
      (should-not (gethash "2026-10-21" map)))))

(ert-deftest my/jg-test-every-day-across-summer-time ()
  "Run at 00:30 on the day after summer time begins (2026-03-29 in
Central Europe, a day of 23 hours), every calendar day is in the
report's window, 2026-03-29 included.  Steps of 86400 seconds skipped
it."
  (let ((zone (getenv "TZ")))
    (unwind-protect
        (progn
          (setenv "TZ" "CET-1CEST,M3.5.0,M10.5.0/3")
          (set-time-zone-rule "CET-1CEST,M3.5.0,M10.5.0/3")
          (let ((now (encode-time (list 0 30 0 30 3 2026 nil -1 nil))))
            (should (equal (format-time-string "%Y-%m-%d %H:%M" now) "2026-03-30 00:30"))
            (should (equal (mapcar #'car (my/journal-gaps--dates 4 now))
                           '("2026-03-30" "2026-03-29" "2026-03-28" "2026-03-27")))
            (let ((now (encode-time (list 0 30 0 26 10 2026 nil -1 nil))))
              (should (equal (mapcar #'car (my/journal-gaps--dates 3 now))
                             '("2026-10-26" "2026-10-25" "2026-10-24"))))))
      (setenv "TZ" zone)
      (set-time-zone-rule zone))))

(ert-deftest my/jg-test-filter ()
  "The filter keeps the rows of one kind."
  (let ((records '(("2026-10-25" "nd." no-entry "" nil)
                   ("2026-10-24" "sob." no-metrics "sleep" nil))))
    (should (= (length (my/journal-gaps--entries records 'all)) 2))
    (should (equal (mapcar #'car (my/journal-gaps--entries records 'no-entry))
                   '("2026-10-25")))
    (should (equal (mapcar #'car (my/journal-gaps--entries records 'no-metrics))
                   '("2026-10-24")))))

(ert-deftest my/jg-test-visit-creates-the-missing-day ()
  "Opening a day without a note creates its backdated note, dated that
day, and visits it; opening it again visits the same file."
  (my/jg-test-with-journal
    (my/jg-test-note (my/jg-test-day -2) '(("mood" . "7") ("sleep" . "6")))
    (let ((missing (my/jg-test-day -1)))
      (cl-letf (((symbol-function 'tabulated-list-get-id) (lambda (&rest _) missing)))
        (my/journal-gaps-visit)
        (let ((file buffer-file-name))
          (should (string-match-p (concat "--" missing "__journal\\.org\\'") file))
          (should (equal (my/journal-file-date file) missing))
          (my/journal-gaps-visit)
          (should (equal buffer-file-name file))
          (should (= 1 (length (directory-files my-notes-journal nil
                                                (concat (replace-regexp-in-string "-" "" missing)
                                                        "T000000"))))))))))

(ert-deftest my/jg-test-summary-counts ()
  "The summary counts days without an entry and without metrics."
  (my/jg-test-with-journal
    (my/jg-test-note (my/jg-test-day -2) '(("mood" . "7")))
    (let ((said nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (setq said (apply #'format fmt args)))))
        (my/journal-gaps-summary 3))
      (should (equal said "Last 3 days: 2 without an entry, 1 without metrics")))))

(provide 'test-journal-gaps)
;;; test-journal-gaps.el ends here
