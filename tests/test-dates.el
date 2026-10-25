;;; test-dates.el --- ERT tests for the date functions of 00-core -*- lexical-binding: t; -*-

;; Tests: 00-core

;;; Commentary:

;; Every module counts days with the date functions of 00-core.el
;; (DATES), so they are tested here once, against dates written out by
;; hand -- never against the code's own arithmetic -- and under the
;; time zone of the owner's machines: the day summer time ends
;; (2026-10-25, 25 hours) and the day it begins (2026-03-29, 23 hours),
;; at the hours where a step of 86400 seconds goes wrong; the ends of a
;; month, a year and February in a leap year.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-dates.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules)

(defun my/dates-test--at (year month day hour minute)
  "The instant YEAR-MONTH-DAY HOUR:MINUTE in the local zone."
  (encode-time (list 0 minute hour day month year nil -1 nil)))

(ert-deftest my/dates-test-add-days-across-summer-time ()
  "Adding days crosses both transitions of 2026 a day at a time."
  (my/test-with-time-zone my/test-central-europe
    (should (equal (my/date-add-days "2026-10-25" 1) "2026-10-26"))
    (should (equal (my/date-add-days "2026-10-26" -1) "2026-10-25"))
    (should (equal (my/date-add-days "2026-10-24" 2) "2026-10-26"))
    (should (equal (my/date-add-days "2026-03-29" 1) "2026-03-30"))
    (should (equal (my/date-add-days "2026-03-29" -1) "2026-03-28"))
    (should (equal (my/date-add-days "2026-03-28" 2) "2026-03-30"))
    (should (equal (my/date-add-days "2026-10-25" 0) "2026-10-25"))))

(ert-deftest my/dates-test-add-days-month-and-year-ends ()
  "Days carry into the next month and year; February has 29 days in a
leap year only."
  (should (equal (my/date-add-days "2026-10-31" 1) "2026-11-01"))
  (should (equal (my/date-add-days "2026-12-31" 1) "2027-01-01"))
  (should (equal (my/date-add-days "2027-01-01" -1) "2026-12-31"))
  (should (equal (my/date-add-days "2028-02-28" 1) "2028-02-29"))
  (should (equal (my/date-add-days "2027-02-28" 1) "2027-03-01"))
  (should (equal (my/date-add-days "2026-01-01" 365) "2027-01-01"))
  (should (equal (my/date-add-days "2026-11-15" -45) "2026-10-01")))

(ert-deftest my/dates-test-date-of-on-the-long-day ()
  "The date of an instant is its local date on the day summer time
ends: half an hour after midnight, at 23:30, and an hour later, which
is the next day."
  (my/test-with-time-zone my/test-central-europe
    (should (equal (my/date-of (my/dates-test--at 2026 10 25 0 30)) "2026-10-25"))
    (should (equal (my/date-of (my/dates-test--at 2026 10 25 23 30)) "2026-10-25"))
    (should (equal (my/date-of (time-add (my/dates-test--at 2026 10 25 23 30) 3600))
                   "2026-10-26"))))

(ert-deftest my/dates-test-to-time-at-midday ()
  "A date becomes midday of the same date, also on both transition
days; its fields are the date's own."
  (my/test-with-time-zone my/test-central-europe
    (dolist (date '("2026-10-25" "2026-03-29" "2026-07-01"))
      (let ((time (my/date-to-time date)))
        (should (equal (format-time-string "%F %H:%M" time) (concat date " 12:00")))))
    (should (equal (format-time-string "%G-W%V" (my/date-to-time "2026-12-31")) "2026-W53"))))

(ert-deftest my/dates-test-days-between ()
  "Calendar days between dates and instants: across the 25-hour and the
23-hour day, late in the evening and just after midnight."
  (my/test-with-time-zone my/test-central-europe
    (should (= (my/date-days-between "2026-10-24" "2026-10-26") 2))
    (should (= (my/date-days-between "2026-03-28" "2026-03-30") 2))
    (should (= (my/date-days-between "2026-10-26" "2026-10-24") -2))
    (should (= (my/date-days-between (my/dates-test--at 2026 10 24 23 30) "2026-10-26") 2))
    (should (= (my/date-days-between (my/dates-test--at 2026 10 25 23 30) "2026-10-25") 0))
    (should (= (my/date-days-between (my/dates-test--at 2026 3 29 0 30) "2026-03-30") 1))
    (should (= (my/date-days-between "2026-12-31" "2027-01-01") 1))
    (should (= (- (my/date-day-number "2026-10-25") (my/date-day-number "2026-10-24")) 1))))

(ert-deftest my/dates-test-weekday ()
  "ISO weekdays: Monday 1, Sunday 7."
  (should (= (my/date-weekday "2026-10-26") 1))
  (should (= (my/date-weekday "2026-10-25") 7))
  (should (= (my/date-weekday "2026-03-29") 7)))

(provide 'test-dates)
;;; test-dates.el ends here
