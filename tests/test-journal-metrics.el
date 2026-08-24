;;; test-journal-metrics.el --- ERT tests for 05b-journal-metrics -*- lexical-binding: t; -*-
;;; Commentary:
;; Covers everything in 05b-journal-metrics.el and 21-dashboards.el that can
;; be exercised without a human at the minibuffer: schema detection, legacy
;; drawer parsing and removal, prose counting, the metrics drawer itself,
;; and the two end-to-end paths through `my/journal-set-metrics' with the
;; prompts stubbed out.
;;
;; Run inside the real configuration, so that the modules under test are
;; already loaded:
;;
;;   M-x load-file RET /path/to/test-journal-metrics.el RET
;;   M-x ert RET t RET
;;
;; Or from a shell, which is what to use before a commit:
;;
;;   emacs -Q --batch \
;;     -l ~/.emacs.d/init.el \
;;     -l /path/to/test-journal-metrics.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; Nothing here touches ~/notes: every test builds a temp file and deletes
;; it afterwards.
;;
;; If a test fails, check whether the test or the code is wrong before
;; changing either -- these assertions were written from the specification,
;; not derived from a passing run.

;;; Code:

(require 'ert)
(require 'org)
(require 'cl-lib)

;; ============================================================
;; FIXTURES
;; ============================================================

(defconst my/jm-test--legacy
  "#+title:      2026-08-24 Journal
#+date:       [2026-08-24 pon 09:12]
#+filetags:   :journal:
#+identifier: 20260824T091200
:PROPERTIES:
:well-being:  7
:END:

* 09:12
Dzisiaj było całkiem znośnie, mimo wszystko poszło lepiej niż wczoraj.
"
  "A journal file as the pre-2026-08 template wrote them (schema 0).")

(defconst my/jm-test--schema1
  "#+title:      2026-08-24 Journal
#+date:       [2026-08-24 pon 09:12]
#+filetags:   :journal:
#+identifier: 20260824T091200
#+language:   pl
#+schema:     1

* Metryki

* 09:12
Dzisiaj było całkiem znośnie, mimo wszystko poszło lepiej niż wczoraj.
"
  "A journal file in the current format, metrics not yet filled in.")

(defconst my/jm-test--metrics-only
  "#+title:      2026-08-24 Journal
#+date:       [2026-08-24 pon]
#+filetags:   :journal:
#+identifier: 20260824T000000
#+language:   pl
#+schema:     1

* Metryki
:PROPERTIES:
:WELLBEING:  6
:END:

* Uzupełnienie
:PROPERTIES:
:ADDED_AT:   [2026-08-25 wto 10:00]
:EVENT_DATE: [2026-08-24]
:END:

"
  "A day that was rated but never written up.")

(defmacro my/jm-test--with-journal (content &rest body)
  "Run BODY in a buffer visiting a temp journal file holding CONTENT.
The file name carries both markers real journal files have: the
--YYYY-MM-DD-journal segment and the `journal' Denote keyword.  Bound to
`file' inside BODY."
  (declare (indent 1) (debug t))
  `(let ((file (make-temp-file "jmtest-" nil
                               "--2026-08-24-journal__journal.org"
                               ,content)))
     (unwind-protect
         (with-current-buffer (find-file-noselect file)
           (should (derived-mode-p 'org-mode))
           ,@body)
       (let ((buf (get-file-buffer file)))
         (when buf
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (ignore-errors (delete-file file)))))

(defun my/jm-test--goto-metrics-point ()
  "Move to the metrics headline and return point."
  (my/journal--goto-metrics)
  (point))

;; ============================================================
;; THE CENTRAL CLAIM
;; ============================================================
;; The whole redesign rests on one assertion: the old drawer position is
;; not parsed as properties and the new one is.  If only one test in this
;; file is ever run, make it this pair.

(ert-deftest my/jm-test-legacy-drawer-is-not-properties ()
  "The pre-2026-08 drawer position is invisible to `org-entry-get'."
  (my/jm-test--with-journal my/jm-test--legacy
    (goto-char (point-min))
    (should (search-forward ":well-being:  7" nil t))
    ;; Present in the text, absent from Org's property model.
    (save-excursion
      (goto-char (point-min))
      (re-search-forward "^\\* " nil t)
      (should (null (org-entry-get (point) "well-being"))))))

(ert-deftest my/jm-test-metrics-drawer-is-properties ()
  "A value written under the metrics headline round-trips through Org."
  (my/jm-test--with-journal my/jm-test--schema1
    (save-excursion
      (my/jm-test--goto-metrics-point)
      (org-entry-put (point) "WELLBEING" "6")
      (should (equal "6" (org-entry-get (point) "WELLBEING"))))))

;; ============================================================
;; SCHEMA
;; ============================================================

(ert-deftest my/jm-test-schema-absent-is-zero ()
  (my/jm-test--with-journal my/jm-test--legacy
    (should (= 0 (my/journal--schema)))))

(ert-deftest my/jm-test-schema-present ()
  (my/jm-test--with-journal my/jm-test--schema1
    (should (= 1 (my/journal--schema)))))

(ert-deftest my/jm-test-ensure-schema-inserts-once ()
  "Stamping is idempotent and lands after #+identifier:."
  (my/jm-test--with-journal my/jm-test--legacy
    (my/journal--ensure-schema)
    (my/journal--ensure-schema)
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^#\\+schema:" nil t)
        (setq count (1+ count)))
      (should (= 1 count)))
    (should (= my-journal-schema-version (my/journal--schema)))
    ;; Order: identifier, then schema.
    (goto-char (point-min))
    (let ((id-pos (progn (re-search-forward "^#\\+identifier:" nil t) (point)))
          (sc-pos (progn (goto-char (point-min))
                         (re-search-forward "^#\\+schema:" nil t) (point))))
      (should (< id-pos sc-pos)))))

;; ============================================================
;; LEGACY DRAWER
;; ============================================================

(ert-deftest my/jm-test-legacy-wellbeing-read ()
  (my/jm-test--with-journal my/jm-test--legacy
    (should (equal "7" (my/journal--legacy-wellbeing)))))

(ert-deftest my/jm-test-legacy-wellbeing-absent-in-schema1 ()
  "A metrics drawer under a headline is not mistaken for the legacy one."
  (my/jm-test--with-journal my/jm-test--metrics-only
    (should (null (my/journal--legacy-drawer-bounds)))
    (should (null (my/journal--legacy-wellbeing)))))

(ert-deftest my/jm-test-drop-legacy-drawer ()
  (my/jm-test--with-journal my/jm-test--legacy
    (should (my/journal--drop-legacy-drawer))
    (should (null (my/journal--legacy-wellbeing)))
    (goto-char (point-min))
    (should (null (search-forward ":well-being:" nil t)))
    ;; Front matter and prose survive intact.
    (goto-char (point-min))
    (should (search-forward "#+identifier: 20260824T091200" nil t))
    (goto-char (point-min))
    (should (search-forward "poszło lepiej niż wczoraj" nil t))
    ;; Second call finds nothing left to do.
    (should (null (my/journal--drop-legacy-drawer)))))

;; ============================================================
;; METRICS HEADLINE
;; ============================================================

(ert-deftest my/jm-test-goto-metrics-creates-once ()
  "The headline is created when missing and reused when present."
  (my/jm-test--with-journal my/jm-test--legacy
    (my/journal--goto-metrics)
    (my/journal--goto-metrics)
    (goto-char (point-min))
    (let ((count 0)
          (re (format "^\\* %s[ \t]*$"
                      (regexp-quote my-journal-metrics-heading))))
      (while (re-search-forward re nil t)
        (setq count (1+ count)))
      (should (= 1 count)))))

(ert-deftest my/jm-test-goto-metrics-precedes-entries ()
  "The metrics headline is inserted above the first existing headline."
  (my/jm-test--with-journal my/jm-test--legacy
    (my/journal--goto-metrics)
    (goto-char (point-min))
    (let ((metrics-pos (re-search-forward
                        (format "^\\* %s"
                                (regexp-quote my-journal-metrics-heading))
                        nil t))
          (entry-pos (progn (goto-char (point-min))
                            (re-search-forward "^\\* 09:12" nil t))))
      (should metrics-pos)
      (should entry-pos)
      (should (< metrics-pos entry-pos)))))

;; ============================================================
;; PROSE COUNTING
;; ============================================================

(ert-deftest my/jm-test-prose-counted ()
  (my/jm-test--with-journal my/jm-test--schema1
    (should (>= (my/journal--prose-chars) my/journal-prose-threshold))))

(ert-deftest my/jm-test-prose-excludes-drawers-and-front-matter ()
  "A rated day with no writing counts as no prose."
  (my/jm-test--with-journal my/jm-test--metrics-only
    (should (< (my/journal--prose-chars) my/journal-prose-threshold))))

(ert-deftest my/jm-test-prose-excludes-metrics-subtree ()
  "Text under the metrics headline does not make a day look written up."
  (my/jm-test--with-journal my/jm-test--metrics-only
    (goto-char (point-min))
    (re-search-forward "^:END:$" nil t)
    (forward-line 1)
    (insert "To jest notatka o metrykach, a nie opis dnia i tak dalej.\n")
    (should (< (my/journal--prose-chars) my/journal-prose-threshold))))

;; ============================================================
;; FILE DATE
;; ============================================================

(ert-deftest my/jm-test-file-date ()
  (my/jm-test--with-journal my/jm-test--schema1
    (should (equal "2026-08-24" (my/journal--file-date)))))

(ert-deftest my/jm-test-file-date-nil-outside-journal ()
  (with-temp-buffer
    (org-mode)
    (should (null (my/journal--file-date)))))

;; ============================================================
;; VALIDATION
;; ============================================================

(ert-deftest my/jm-test-validation ()
  (let ((wb  (car my/journal-metrics-fields))
        (alc (nth 1 my/journal-metrics-fields))
        (ill (nth 2 my/journal-metrics-fields)))
    (should (equal "WELLBEING" (plist-get wb :key)))
    (should (my/journal--valid-p wb "7"))
    (should-not (my/journal--valid-p wb "11"))
    (should-not (my/journal--valid-p wb "0"))
    (should-not (my/journal--valid-p wb "siedem"))
    (should (my/journal--valid-p alc "0"))
    (should (my/journal--valid-p alc "2.5"))
    (should-not (my/journal--valid-p alc "dwa"))
    (should-not (my/journal--valid-p alc "-1"))
    (should (my/journal--valid-p ill "none"))
    (should-not (my/journal--valid-p ill "chory"))))

(ert-deftest my/jm-test-defaults ()
  "Alcohol and illness have defaults so RET writes an explicit value;
well-being has none so RET leaves the day unrated."
  (should (null (plist-get (car my/journal-metrics-fields) :default)))
  (should (equal "0" (plist-get (nth 1 my/journal-metrics-fields) :default)))
  (should (equal "none" (plist-get (nth 2 my/journal-metrics-fields) :default))))

;; ============================================================
;; END TO END, PROMPTS STUBBED
;; ============================================================

(defmacro my/jm-test--answering (answers &rest body)
  "Run BODY with `my/journal--ask' returning values from ANSWERS.
ANSWERS is an alist of property key to string, or nil to delete."
  (declare (indent 1) (debug t))
  `(cl-letf (((symbol-function 'my/journal--ask)
              (lambda (field &optional _seed)
                (cdr (assoc (plist-get field :key) ,answers))))
             ((symbol-function 'completing-read)
              (lambda (&rest _) ""))
             ((symbol-function 'y-or-n-p)
              (lambda (&rest _) t)))
     ,@body))

(ert-deftest my/jm-test-migration-preserves-unchanged-value ()
  "Answering RET on a migrated note keeps the value and does not flag it.
The value was the author's own same-day judgement; carrying it across a
format change does not turn it into a memory."
  (my/jm-test--with-journal my/jm-test--legacy
    (my/jm-test--answering '(("WELLBEING" . "7")
                             ("ALCOHOL_U" . "0")
                             ("ILLNESS"   . "none"))
      (my/journal-set-metrics))
    (save-excursion
      (my/journal--goto-metrics)
      (should (equal "7" (org-entry-get (point) "WELLBEING")))
      (should (equal "0" (org-entry-get (point) "ALCOHOL_U")))
      (should (equal "none" (org-entry-get (point) "ILLNESS")))
      (should (org-entry-get (point) "METRICS_ADDED"))
      (should (null (org-entry-get (point) "RECALLED"))))
    ;; Migrated: legacy drawer gone, schema stamped.
    (should (null (my/journal--legacy-wellbeing)))
    (should (= my-journal-schema-version (my/journal--schema)))))

(ert-deftest my/jm-test-changed-value-is-recalled ()
  "Revising a past day's rating flags it as reconstructed."
  (my/jm-test--with-journal my/jm-test--legacy
    (my/jm-test--answering '(("WELLBEING" . "5")
                             ("ALCOHOL_U" . "4")
                             ("ILLNESS"   . "none"))
      (my/journal-set-metrics))
    (save-excursion
      (my/journal--goto-metrics)
      (should (equal "5" (org-entry-get (point) "WELLBEING")))
      (should (equal "t" (org-entry-get (point) "RECALLED"))))))

(ert-deftest my/jm-test-new-value-on-past-day-is-recalled ()
  "Supplying a rating a past day never had is also a memory."
  (my/jm-test--with-journal my/jm-test--schema1
    (my/jm-test--answering '(("WELLBEING" . "6")
                             ("ALCOHOL_U" . "0")
                             ("ILLNESS"   . "none"))
      (my/journal-set-metrics))
    (save-excursion
      (my/journal--goto-metrics)
      (should (equal "t" (org-entry-get (point) "RECALLED"))))))

(ert-deftest my/jm-test-metrics-added-not-refreshed ()
  "METRICS_ADDED records the first write, not the last edit."
  (my/jm-test--with-journal my/jm-test--schema1
    (my/jm-test--answering '(("WELLBEING" . "6")
                             ("ALCOHOL_U" . "0")
                             ("ILLNESS"   . "none"))
      (my/journal-set-metrics))
    (let ((first (save-excursion
                   (my/journal--goto-metrics)
                   (org-entry-get (point) "METRICS_ADDED"))))
      (should first)
      (sleep-for 1)
      (my/jm-test--answering '(("WELLBEING" . "8")
                               ("ALCOHOL_U" . "2")
                               ("ILLNESS"   . "mild"))
        (my/journal-set-metrics))
      (save-excursion
        (my/journal--goto-metrics)
        (should (equal first (org-entry-get (point) "METRICS_ADDED")))
        (should (equal "8" (org-entry-get (point) "WELLBEING")))))))

(ert-deftest my/jm-test-nil-answer-deletes-property ()
  "\"-\" at the prompt removes the property rather than blanking it.
A blank value would be indistinguishable from an unmeasured one at
index time; an absent property is unambiguous."
  (my/jm-test--with-journal my/jm-test--metrics-only
    (my/jm-test--answering '(("WELLBEING" . nil)
                             ("ALCOHOL_U" . "0")
                             ("ILLNESS"   . "none"))
      (my/journal-set-metrics))
    (save-excursion
      (my/journal--goto-metrics)
      (should (null (org-entry-get (point) "WELLBEING"))))
    (goto-char (point-min))
    (should (null (re-search-forward "^:WELLBEING:[ \t]*$" nil t)))))

(ert-deftest my/jm-test-abort-leaves-file-untouched ()
  "C-g at a prompt must not half-migrate a note."
  (my/jm-test--with-journal my/jm-test--legacy
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'my/journal--ask)
                 (lambda (&rest _) (signal 'quit nil))))
        (ignore-errors (my/journal-set-metrics)))
      (should (equal before (buffer-string)))
      (should (equal "7" (my/journal--legacy-wellbeing))))))

;; ============================================================
;; JOURNAL DETECTION (21-dashboards.el)
;; ============================================================

(ert-deftest my/jm-test-dashboards-detects-schema1-journal ()
  "The regression this migration would otherwise have caused."
  (my/jm-test--with-journal my/jm-test--schema1
    (should (my/dashboards--journal-p file))))

(ert-deftest my/jm-test-dashboards-detects-legacy-journal ()
  (my/jm-test--with-journal my/jm-test--legacy
    (should (my/dashboards--journal-p file))))

(ert-deftest my/jm-test-dashboards-rejects-non-journal ()
  "A note with neither the keyword nor either content marker."
  (let ((file (make-temp-file "jmtest-" nil "--jakas-notatka__pks.org"
                              "#+title: Jakaś notatka\n#+filetags: :pks:\n\n* Treść\nCoś tam.\n")))
    (unwind-protect
        (should (null (my/dashboards--journal-p file)))
      (ignore-errors (delete-file file)))))

(ert-deftest my/jm-test-dashboards-content-fallback ()
  "A journal whose file name lost its keywords is still recognised."
  (let ((file (make-temp-file "jmtest-" nil "--2026-08-24-journal.org"
                              my/jm-test--metrics-only)))
    (unwind-protect
        (should (my/dashboards--journal-p file))
      (ignore-errors (delete-file file)))))

;; ============================================================
;; WIRING
;; ============================================================

(ert-deftest my/jm-test-core-variables-defined ()
  "The shared names live in 00-core.el, not in the optional module."
  (should (boundp 'my-journal-metrics-heading))
  (should (boundp 'my-journal-schema-version))
  (should (stringp my-journal-metrics-heading))
  (should (integerp my-journal-schema-version)))

(ert-deftest my/jm-test-commands-autoloadable ()
  (should (commandp 'my/journal-set-metrics))
  (should (commandp 'my/journal-set-metrics-for-date))
  (should (fboundp 'my/denote-journal--create-backdated)))

(ert-deftest my/jm-test-obsolete-command-gone ()
  (should-not (fboundp 'my/denote-set-wellbeing)))

(ert-deftest my/jm-test-transient-entries-present ()
  "Both metrics keys reached the Create menu, and nothing was displaced."
  (skip-unless (fboundp 'my/notes-create-menu))
  (should (transient-get-suffix 'my/notes-create-menu "w"))
  (should (transient-get-suffix 'my/notes-create-menu "W"))
  ;; The keys they were almost given are still doing their old jobs.
  (should (transient-get-suffix 'my/notes-create-menu "m"))
  (should (transient-get-suffix 'my/notes-create-menu "J")))

(provide 'test-journal-metrics)
;;; test-journal-metrics.el ends here
