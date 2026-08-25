;;; test-journal-metrics.el --- ERT tests for 05b-journal-metrics -*- lexical-binding: t; -*-
;;; Commentary:
;; Everything in 05b-journal-metrics.el and 21-dashboards.el that can be
;; exercised without a human at the minibuffer: keyword read/write, the two
;; older formats and their conversion, prose counting, and the end-to-end
;; paths through `my/journal-set-metrics' with the prompts stubbed.
;;
;;   emacs -Q --batch -l ~/.emacs.d/init.el \
;;     -l ~/.emacs.d/tests/test-journal-metrics.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; Nothing here touches ~/notes: every test builds a temp file and deletes
;; it afterwards.

;;; Code:

(require 'ert)
(require 'org)
(require 'cl-lib)

;; ============================================================
;; FIXTURES
;; ============================================================

(defconst my/jm-test--schema0
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
  "A journal as the pre-2026-08 template wrote them: a drawer Org ignores.")

(defconst my/jm-test--schema1
  "#+title:      2026-08-24 Journal
#+date:       [2026-08-24 pon 09:12]
#+filetags:   :journal:
#+identifier: 20260824T091200
#+language:   pl
#+schema:     1

* Metryki
:PROPERTIES:
:WELLBEING:  6
:ALCOHOL_U:  2
:ILLNESS:    none
:METRICS_ADDED: [2026-08-25 wto 02:43]
:END:

* 09:12
Dzisiaj było całkiem znośnie, mimo wszystko poszło lepiej niż wczoraj.
"
  "The short-lived headline format.")

(defconst my/jm-test--schema2
  "#+title:      2026-08-24 Journal
#+date:       [2026-08-24 pon 09:12]
#+filetags:   :journal:
#+identifier: 20260824T091200
#+language:   pl
#+schema:     2

* 09:12
Dzisiaj było całkiem znośnie, mimo wszystko poszło lepiej niż wczoraj.
"
  "Current format, metrics not yet recorded.")

(defconst my/jm-test--metrics-only
  "#+title:      2026-08-24 Journal
#+date:       [2026-08-24 pon]
#+filetags:   :journal:
#+identifier: 20260824T000000
#+language:   pl
#+schema:     2
#+wellbeing:  6

* Uzupełnienie
:PROPERTIES:
:ADDED_AT:   [2026-08-25 wto 10:00]
:EVENT_DATE: [2026-08-24]
:END:

"
  "A day that was rated but never written up.")

(defmacro my/jm-test--with-journal (content &rest body)
  "Run BODY in a buffer visiting a temp journal file holding CONTENT.
The name carries both markers real journal files have.  Bound to `file'."
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

(defmacro my/jm-test--answering (answers &rest body)
  "Run BODY with `my/journal--ask' returning values from ANSWERS."
  (declare (indent 1) (debug t))
  `(cl-letf (((symbol-function 'my/journal--ask)
              (lambda (field &optional _existing)
                (cdr (assoc (plist-get field :key) ,answers))))
             ((symbol-function 'completing-read) (lambda (&rest _) ""))
             ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
     ,@body))

;; ============================================================
;; THE CENTRAL CLAIM
;; ============================================================

(ert-deftest my/jm-test-legacy-drawer-is-not-properties ()
  "The pre-2026-08 drawer position is invisible to Org's property API.
This is why the whole format changed; if it ever stops holding, the
premise was wrong."
  (my/jm-test--with-journal my/jm-test--schema0
    (goto-char (point-min))
    (should (search-forward ":well-being:  7" nil t))
    (save-excursion
      (goto-char (point-min))
      (re-search-forward "^\\* " nil t)
      (should (null (org-entry-get (point) "well-being"))))
    ;; ...but the module reads it anyway.
    (should (equal "7" (my/journal--legacy-wellbeing)))))

(ert-deftest my/jm-test-keyword-round-trip ()
  "A keyword written by the module is read back by the module."
  (my/jm-test--with-journal my/jm-test--schema2
    (my/journal--keyword-put "wellbeing" "6")
    (should (equal "6" (my/journal--keyword-get "wellbeing")))))

(ert-deftest my/jm-test-keyword-visible-to-org ()
  "Org's own keyword collector sees it too, so this is not a private format."
  (my/jm-test--with-journal my/jm-test--schema2
    (my/journal--keyword-put "wellbeing" "6")
    (should (member "6" (cdr (assoc "WELLBEING"
                                    (org-collect-keywords '("WELLBEING"))))))))

;; ============================================================
;; KEYWORD MECHANICS
;; ============================================================

(ert-deftest my/jm-test-keyword-absent-is-nil ()
  (my/jm-test--with-journal my/jm-test--schema2
    (should (null (my/journal--keyword-get "wellbeing")))))

(ert-deftest my/jm-test-keyword-empty-is-nil ()
  "A keyword with nothing after the colon is not a measurement."
  (my/jm-test--with-journal my/jm-test--schema2
    (goto-char (point-min))
    (forward-line 6)
    (insert "#+wellbeing:\n")
    (should (null (my/journal--keyword-get "wellbeing")))))

(ert-deftest my/jm-test-keyword-put-replaces-in-place ()
  "Re-setting a keyword edits its line: no duplicates, no reordering."
  (my/jm-test--with-journal my/jm-test--schema2
    (my/journal--keyword-put "wellbeing" "6")
    (my/journal--keyword-put "alcohol_u" "0")
    (my/journal--keyword-put "wellbeing" "8")
    (should (equal "8" (my/journal--keyword-get "wellbeing")))
    (goto-char (point-min))
    (let ((n 0))
      (while (re-search-forward "^#\\+wellbeing:" nil t) (setq n (1+ n)))
      (should (= 1 n)))
    ;; alcohol_u was added after wellbeing and stays there.
    (goto-char (point-min))
    (let ((wb (progn (re-search-forward "^#\\+wellbeing:" nil t) (point)))
          (al (progn (goto-char (point-min))
                     (re-search-forward "^#\\+alcohol_u:" nil t) (point))))
      (should (< wb al)))))

(ert-deftest my/jm-test-keyword-delete ()
  (my/jm-test--with-journal my/jm-test--metrics-only
    (should (my/journal--keyword-delete "wellbeing"))
    (should (null (my/journal--keyword-get "wellbeing")))
    (should (null (my/journal--keyword-delete "wellbeing")))))

(ert-deftest my/jm-test-keyword-stays-in-front-matter ()
  "Keywords are only looked for above the first headline.
A #+wellbeing: line inside the prose is not a metric."
  (my/jm-test--with-journal my/jm-test--schema2
    (goto-char (point-max))
    (insert "\n#+wellbeing:  9\n")
    (should (null (my/journal--keyword-get "wellbeing")))))

(ert-deftest my/jm-test-keyword-alignment ()
  "Values line up with Denote's front matter."
  (should (equal "#+wellbeing:  6\n"
                 (my/journal--keyword-line "wellbeing" "6")))
  ;; Longer than the alignment column: one space, not a negative pad.
  (should (equal "#+metrics_added: x\n"
                 (my/journal--keyword-line "metrics_added" "x"))))

;; ============================================================
;; SCHEMA AND LANGUAGE
;; ============================================================

(ert-deftest my/jm-test-schema-absent-is-zero ()
  (my/jm-test--with-journal my/jm-test--schema0
    (should (= 0 (my/journal--schema)))))

(ert-deftest my/jm-test-schema-present ()
  (my/jm-test--with-journal my/jm-test--schema2
    (should (= 2 (my/journal--schema)))))

(ert-deftest my/jm-test-ensure-language-adds-once ()
  (my/jm-test--with-journal my/jm-test--schema0
    (my/journal--ensure-language)
    (my/journal--ensure-language)
    (should (equal "pl" (my/journal--keyword-get "language")))
    (goto-char (point-min))
    (let ((n 0))
      (while (re-search-forward "^#\\+language:" nil t) (setq n (1+ n)))
      (should (= 1 n)))))

(ert-deftest my/jm-test-ensure-language-does-not-override ()
  (my/jm-test--with-journal my/jm-test--schema2
    (my/journal--keyword-put "language" "en")
    (my/journal--ensure-language)
    (should (equal "en" (my/journal--keyword-get "language")))))

;; ============================================================
;; OLDER FORMATS
;; ============================================================

(ert-deftest my/jm-test-schema1-values-read ()
  (my/jm-test--with-journal my/jm-test--schema1
    (should (equal "6" (my/journal--existing "wellbeing")))
    (should (equal "2" (my/journal--existing "alcohol_u")))
    (should (equal "none" (my/journal--existing "illness")))))

(ert-deftest my/jm-test-keywords-win-over-older-formats ()
  (my/jm-test--with-journal my/jm-test--schema1
    (my/journal--keyword-put "wellbeing" "9")
    (should (equal "9" (my/journal--existing "wellbeing")))))

(ert-deftest my/jm-test-purge-removes-both-old-formats ()
  (my/jm-test--with-journal my/jm-test--schema1
    (should (my/journal--purge-old-formats))
    (should (null (my/journal--metrics-heading-bounds)))
    (goto-char (point-min))
    (should (null (search-forward "Metryki" nil t)))
    ;; Prose and front matter survive.
    (goto-char (point-min))
    (should (search-forward "#+identifier: 20260824T091200" nil t))
    (goto-char (point-min))
    (should (search-forward "poszło lepiej niż wczoraj" nil t))))

(ert-deftest my/jm-test-purge-legacy-drawer ()
  (my/jm-test--with-journal my/jm-test--schema0
    (should (my/journal--purge-old-formats))
    (goto-char (point-min))
    (should (null (search-forward ":well-being:" nil t)))
    (should (null (my/journal--purge-old-formats)))))

(ert-deftest my/jm-test-uzupelnienie-drawer-untouched ()
  "The supplement drawer is not one of the old metrics formats.
Confusing the two is what produced a duplicated metrics block."
  (my/jm-test--with-journal my/jm-test--metrics-only
    (should (null (my/journal--metrics-heading-bounds)))
    (should (null (my/journal--legacy-drawer-bounds)))
    (should (null (my/journal--purge-old-formats)))
    (goto-char (point-min))
    (should (search-forward ":ADDED_AT:" nil t))))

;; ============================================================
;; BATCH CONVERSION
;; ============================================================

(ert-deftest my/jm-test-migrate-buffer-schema1 ()
  "Conversion is a pure translation: no value invented, changed or lost."
  (my/jm-test--with-journal my/jm-test--schema1
    (should (my/journal--migrate-buffer))
    (should (= 2 (my/journal--schema)))
    (should (equal "6" (my/journal--keyword-get "wellbeing")))
    (should (equal "2" (my/journal--keyword-get "alcohol_u")))
    (should (equal "none" (my/journal--keyword-get "illness")))
    (should (equal "[2026-08-25 wto 02:43]"
                   (my/journal--keyword-get "metrics_added")))
    (should (null (my/journal--metrics-heading-bounds)))))

(ert-deftest my/jm-test-migrate-buffer-schema0 ()
  (my/jm-test--with-journal my/jm-test--schema0
    (should (my/journal--migrate-buffer))
    (should (= 2 (my/journal--schema)))
    (should (equal "7" (my/journal--keyword-get "wellbeing")))
    (should (equal "pl" (my/journal--keyword-get "language")))
    ;; Nothing was invented for the fields that had no value.
    (should (null (my/journal--keyword-get "alcohol_u")))
    (should (null (my/journal--keyword-get "illness")))))

(ert-deftest my/jm-test-migrate-empty-legacy-drawer ()
  "An empty legacy drawer becomes no metrics, not empty metrics."
  (my/jm-test--with-journal
      "#+title:      2026-08-24 Journal
#+identifier: 20260824T091200
:PROPERTIES:
:well-being:
:END:

* 09:12
Coś tam.
"
    (should (my/journal--migrate-buffer))
    (should (null (my/journal--keyword-get "wellbeing")))
    (goto-char (point-min))
    (should (null (re-search-forward "^#\\+wellbeing:" nil t)))))

(ert-deftest my/jm-test-migrate-is-idempotent ()
  (my/jm-test--with-journal my/jm-test--schema1
    (should (my/journal--migrate-buffer))
    (let ((once (buffer-string)))
      (should (null (my/journal--migrate-buffer)))
      (should (equal once (buffer-string))))))

;; ============================================================
;; PROSE
;; ============================================================

(ert-deftest my/jm-test-prose-counted ()
  (my/jm-test--with-journal my/jm-test--schema2
    (should (>= (my/journal--prose-chars) my/journal-prose-threshold))))

(ert-deftest my/jm-test-prose-excludes-drawers-and-front-matter ()
  (my/jm-test--with-journal my/jm-test--metrics-only
    (should (< (my/journal--prose-chars) my/journal-prose-threshold))))

(ert-deftest my/jm-test-prose-excludes-metrics-subtree ()
  (my/jm-test--with-journal my/jm-test--schema1
    (goto-char (point-min))
    (re-search-forward "^:END:$" nil t)
    (forward-line 1)
    (insert "Notatka o metrykach, a nie opis dnia, i tak dalej.\n")
    (let ((with-note (my/journal--prose-chars)))
      (goto-char (point-min))
      (re-search-forward "^\\* 09:12" nil t)
      (should (> with-note 0))
      ;; The inserted line sits under * Metryki and must not be counted.
      (should (< with-note 100)))))

;; ============================================================
;; FILE DATE AND VALIDATION
;; ============================================================

(ert-deftest my/jm-test-file-date ()
  (my/jm-test--with-journal my/jm-test--schema2
    (should (equal "2026-08-24" (my/journal--file-date)))))

(ert-deftest my/jm-test-file-date-nil-outside-journal ()
  (with-temp-buffer (org-mode) (should (null (my/journal--file-date)))))

(ert-deftest my/jm-test-validation ()
  (let ((wb (car my/journal-metrics-fields))
        (alc (nth 1 my/journal-metrics-fields))
        (ill (nth 2 my/journal-metrics-fields)))
    (should (equal "wellbeing" (plist-get wb :key)))
    (should (my/journal--valid-p wb "7"))
    (should-not (my/journal--valid-p wb "11"))
    (should-not (my/journal--valid-p wb "0"))
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
;; END TO END
;; ============================================================

(ert-deftest my/jm-test-abort-leaves-file-untouched ()
  "C-g at a prompt must not modify the buffer at all.
The three-phase design exists for this; the previous version created the
metrics headline before prompting and failed here."
  (my/jm-test--with-journal my/jm-test--schema0
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'my/journal--ask)
                 (lambda (&rest _) (signal 'quit nil))))
        ;; `quit' is not a subtype of `error', so ignore-errors would let
        ;; the signal through and abort the test itself.
        (condition-case nil (my/journal-set-metrics) (quit nil)))
      (should (equal before (buffer-string)))
      (should (equal "7" (my/journal--legacy-wellbeing))))))

(ert-deftest my/jm-test-migration-preserves-unchanged-value ()
  "Carrying a value across a format change does not make it a memory."
  (my/jm-test--with-journal my/jm-test--schema0
    (my/jm-test--answering '(("wellbeing" . "7")
                             ("alcohol_u" . "0")
                             ("illness"   . "none"))
      (my/journal-set-metrics))
    (should (equal "7" (my/journal--keyword-get "wellbeing")))
    (should (equal "0" (my/journal--keyword-get "alcohol_u")))
    (should (equal "none" (my/journal--keyword-get "illness")))
    (should (my/journal--keyword-get "metrics_added"))
    (should (null (my/journal--keyword-get "recalled")))
    (should (null (my/journal--legacy-wellbeing)))
    (should (= my-journal-schema-version (my/journal--schema)))))

(ert-deftest my/jm-test-changed-value-is-recalled ()
  (my/jm-test--with-journal my/jm-test--schema0
    (my/jm-test--answering '(("wellbeing" . "5")
                             ("alcohol_u" . "4")
                             ("illness"   . "none"))
      (my/journal-set-metrics))
    (should (equal "5" (my/journal--keyword-get "wellbeing")))
    (should (equal "t" (my/journal--keyword-get "recalled")))))

(ert-deftest my/jm-test-new-value-on-past-day-is-recalled ()
  (my/jm-test--with-journal my/jm-test--schema2
    (my/jm-test--answering '(("wellbeing" . "6")
                             ("alcohol_u" . "0")
                             ("illness"   . "none"))
      (my/journal-set-metrics))
    (should (equal "t" (my/journal--keyword-get "recalled")))))

(ert-deftest my/jm-test-metrics-added-not-refreshed ()
  (my/jm-test--with-journal my/jm-test--schema2
    (my/jm-test--answering '(("wellbeing" . "6")
                             ("alcohol_u" . "0")
                             ("illness"   . "none"))
      (my/journal-set-metrics))
    (let ((first (my/journal--keyword-get "metrics_added")))
      (should first)
      (sleep-for 1)
      (my/jm-test--answering '(("wellbeing" . "8")
                               ("alcohol_u" . "2")
                               ("illness"   . "mild"))
        (my/journal-set-metrics))
      (should (equal first (my/journal--keyword-get "metrics_added")))
      (should (equal "8" (my/journal--keyword-get "wellbeing"))))))

(ert-deftest my/jm-test-nil-answer-removes-keyword ()
  "\"-\" removes the keyword rather than blanking it: an absent keyword is
unambiguous at index time, an empty one is not."
  (my/jm-test--with-journal my/jm-test--metrics-only
    (my/jm-test--answering '(("wellbeing" . nil)
                             ("alcohol_u" . "0")
                             ("illness"   . "none"))
      (my/journal-set-metrics))
    (should (null (my/journal--keyword-get "wellbeing")))
    (goto-char (point-min))
    (should (null (re-search-forward "^#\\+wellbeing:" nil t)))))

(ert-deftest my/jm-test-set-metrics-leaves-no-headline ()
  "Running the command must not reintroduce a metrics headline."
  (my/jm-test--with-journal my/jm-test--schema2
    (my/jm-test--answering '(("wellbeing" . "6")
                             ("alcohol_u" . "0")
                             ("illness"   . "none"))
      (my/journal-set-metrics))
    (goto-char (point-min))
    (should (null (search-forward "* Metryki" nil t)))))

;; ============================================================
;; JOURNAL DETECTION
;; ============================================================

(ert-deftest my/jm-test-dashboards-detects-schema2-journal ()
  (my/jm-test--with-journal my/jm-test--schema2
    (should (my/dashboards--journal-p file))))

(ert-deftest my/jm-test-dashboards-detects-legacy-journal ()
  (my/jm-test--with-journal my/jm-test--schema0
    (should (my/dashboards--journal-p file))))

(ert-deftest my/jm-test-dashboards-rejects-non-journal ()
  (let ((file (make-temp-file "jmtest-" nil "--jakas-notatka__pks.org"
                              "#+title: Jakaś notatka\n#+filetags: :pks:\n\n* Treść\nCoś tam.\n")))
    (unwind-protect (should (null (my/dashboards--journal-p file)))
      (ignore-errors (delete-file file)))))

(ert-deftest my/jm-test-dashboards-content-fallback ()
  "A journal whose file name lost its keywords is still recognised."
  (let ((file (make-temp-file "jmtest-" nil "--2026-08-24-journal.org"
                              my/jm-test--metrics-only)))
    (unwind-protect (should (my/dashboards--journal-p file))
      (ignore-errors (delete-file file)))))

;; ============================================================
;; WIRING
;; ============================================================

(ert-deftest my/jm-test-core-variables-defined ()
  (should (boundp 'my-journal-metrics-heading))
  (should (boundp 'my-journal-schema-version))
  (should (= 2 my-journal-schema-version)))

(ert-deftest my/jm-test-commands-autoloadable ()
  (should (commandp 'my/journal-set-metrics))
  (should (commandp 'my/journal-set-metrics-for-date))
  (should (commandp 'my/journal-migrate-metrics-format))
  (should (fboundp 'my/denote-journal--create-backdated))
  (should (fboundp 'my/note-add-front-matter-extras)))

(ert-deftest my/jm-test-obsolete-command-gone ()
  (should-not (fboundp 'my/denote-set-wellbeing)))

(ert-deftest my/jm-test-auto-commit-config-disabled ()
  "Config commits are deliberate; the exit hook must not make them."
  (should (boundp 'my/auto-commit-config-enabled))
  (should (null my/auto-commit-config-enabled)))

(ert-deftest my/jm-test-transient-entries-present ()
  "Both metrics keys reached the Create menu, and the Insert chain that
used to hang off the removed \"w\" entry is intact."
  (skip-unless (fboundp 'my/notes-create-menu))
  (should (transient-get-suffix 'my/notes-create-menu "w"))
  (should (transient-get-suffix 'my/notes-create-menu "W"))
  (should (transient-get-suffix 'my/notes-create-menu "m"))
  (should (transient-get-suffix 'my/notes-insert-menu "d"))
  (should (transient-get-suffix 'my/notes-insert-menu "i"))
  (should (transient-get-suffix 'my/notes-insert-menu "I"))
  (should (transient-get-suffix 'my/notes-insert-menu "t"))
  (should (transient-get-suffix 'my/notes-insert-menu "u")))

(provide 'test-journal-metrics)
;;; test-journal-metrics.el ends here
