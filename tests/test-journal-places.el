;;; test-journal-places.el --- ERT tests for 405c-journal-places -*- lexical-binding: t; -*-

;; Tests: 405c-journal-places

;;; Commentary:
;; Everything in 405c-journal-places.el that can be exercised without a
;; human at the minibuffer: the value format, the scan of the journal
;; silo and the order it produces, the numbered candidates, and the
;; paths through `my/journal-set-place' with the prompt stubbed.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-journal-places.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.  The modules are loaded by
;; tests/helper.el, in a sandbox: nothing here touches ~/notes or the
;; settings, and every test builds its own temp silo and deletes it.

;;; Code:

(require 'ert)
(require 'org)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "204-denote" "205-notes" "405c-journal-places" "212-transient")

;; ============================================================
;; FIXTURES
;; ============================================================

(defun my/jp-test--note (day &optional place)
  "Return the text of a journal note for DAY, carrying PLACE."
  (concat "#+title:      " day " Journal\n"
          "#+date:       [" day " nie 09:12]\n"
          "#+filetags:   :journal:\n"
          "#+identifier: " (replace-regexp-in-string "-" "" day) "T091200\n"
          "#+language:   pl\n"
          (if place (concat "#+place:      " place "\n") "")
          "\n* 09:12\nProse.\n"))

(defun my/jp-test--file (dir day &optional place)
  "Write a journal note for DAY with PLACE into DIR.  Return its name."
  (let ((file (expand-file-name
               (format "%sT091200--%s-journal__journal.org"
                       (replace-regexp-in-string "-" "" day) day)
               dir)))
    (with-temp-file file (insert (my/jp-test--note day place)))
    file))

(defmacro my/jp-test--with-silo (files &rest body)
  "Run BODY with a temp journal silo holding FILES, a list of (DAY PLACE).
`my-notes-journal' points at it and the cache starts empty."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "mypks-places-" t))
          (my-notes-journal dir)
          (my/journal-places--cache nil)
          (my/journal-places--scanned nil))
     (unwind-protect
         (progn
           (dolist (spec ,files)
             (my/jp-test--file dir (car spec) (cadr spec)))
           ,@body)
       (delete-directory dir t))))

(defmacro my/jp-test--answering (answers &rest body)
  "Run BODY with the place prompt answering ANSWERS in turn.
An answer past the end of the list is the empty string, which ends the
loop -- so a test cannot hang on a prompt it forgot to answer."
  (declare (indent 1))
  `(let ((remaining ,answers))
     (cl-letf (((symbol-function 'my/journal-places--read)
                (lambda (&rest _) (or (pop remaining) ""))))
       ,@body)))

;; ============================================================
;; THE VALUE
;; ============================================================

(ert-deftest my/jp-test-split ()
  (should (equal (my/journal-places--split "Kraków; Roma, Włochy")
                 '("Kraków" "Roma, Włochy")))
  (should (equal (my/journal-places--split "Kraków") '("Kraków")))
  (should-not (my/journal-places--split nil))
  (should-not (my/journal-places--split "")))

(ert-deftest my/jp-test-join-round-trip ()
  (let ((places '("Kraków" "Roma, Włochy")))
    (should (equal (my/journal-places--split (my/journal-places--join places))
                   places))))

(ert-deftest my/jp-test-normalize-trims-and-collapses ()
  (should (equal (my/journal-places--normalize "  Nowy   Sącz ") "Nowy Sącz")))

(ert-deftest my/jp-test-normalize-strips-the-home-country ()
  "One town must not sit in the list twice, bare and with the country."
  (should (equal (my/journal-places--normalize "Kraków, Polska") "Kraków"))
  (should (equal (my/journal-places--normalize "Kraków ,  Polska  ") "Kraków")))

(ert-deftest my/jp-test-normalize-keeps-a-foreign-country ()
  (should (equal (my/journal-places--normalize "Roma, Włochy") "Roma, Włochy")))

(ert-deftest my/jp-test-normalize-keeps-spelling ()
  "Case and diacritics are the name of a town, not a key."
  (should (equal (my/journal-places--normalize "Łódź") "Łódź")))

;; ============================================================
;; THE SCAN
;; ============================================================

(ert-deftest my/jp-test-scan-collects-places ()
  (my/jp-test--with-silo '(("2026-07-14" "Kraków") ("2026-08-02" "Roma, Włochy"))
    (should (equal (sort (my/journal-places) #'string<)
                   '("Kraków" "Roma, Włochy")))))

(ert-deftest my/jp-test-scan-orders-by-last-visit ()
  "The place of the latest day comes first; the list is the order of use."
  (my/jp-test--with-silo '(("2026-07-14" "Kraków")
                           ("2026-08-02" "Zakopane")
                           ("2026-09-20" "Gdańsk"))
    (should (equal (my/journal-places) '("Gdańsk" "Zakopane" "Kraków")))))

(ert-deftest my/jp-test-scan-takes-the-newest-day-of-a-place ()
  "A place used twice is ranked by its later day, not its first."
  (my/jp-test--with-silo '(("2026-01-05" "Kraków")
                           ("2026-08-02" "Zakopane")
                           ("2026-09-20" "Kraków"))
    (should (equal (my/journal-places) '("Kraków" "Zakopane")))))

(ert-deftest my/jp-test-scan-reads-several-places-of-one-day ()
  (my/jp-test--with-silo '(("2026-09-20" "Kraków; Zakopane"))
    (should (equal (sort (my/journal-places) #'string<) '("Kraków" "Zakopane")))))

(ert-deftest my/jp-test-scan-is-cached-until-asked ()
  "The silo is read once a session: the second call does not go to disk."
  (my/jp-test--with-silo '(("2026-09-20" "Kraków"))
    (should (equal (my/journal-places) '("Kraków")))
    (my/jp-test--file my-notes-journal "2026-09-21" "Gdańsk")
    (should (equal (my/journal-places) '("Kraków")))
    (should (equal (my/journal-places t) '("Gdańsk" "Kraków")))))

(ert-deftest my/jp-test-scan-empty-silo ()
  "No notes yet is an empty list, not an error."
  (my/jp-test--with-silo '()
    (should-not (my/journal-places))))

;; ============================================================
;; NUMBERED CANDIDATES
;; ============================================================

(ert-deftest my/jp-test-displays-number-the-first-ones ()
  (let* ((places (mapcar #'number-to-string (number-sequence 1 12)))
         (displays (my/journal-places--displays places)))
    (should (equal (car (nth 0 displays)) "1 1"))
    (should (equal (car (nth 8 displays)) "9 9"))
    ;; Past nine there is no digit left to type.
    (should (equal (car (nth 9 displays)) "10"))))

(ert-deftest my/jp-test-displays-honour-the-count ()
  (let* ((my/journal-place-quick-count 2)
         (displays (my/journal-places--displays '("Kraków" "Zakopane" "Gdańsk"))))
    (should (equal (car (nth 1 displays)) "2 Zakopane"))
    (should (equal (car (nth 2 displays)) "Gdańsk"))))

(ert-deftest my/jp-test-quick-selects-by-index ()
  (let ((displays (my/journal-places--displays '("Kraków" "Zakopane" "Gdańsk"))))
    (should (equal (my/journal-places--quick "2" displays) "Zakopane"))
    (should-not (my/journal-places--quick "4" displays))
    ;; Anything but a bare digit is text being typed.
    (should-not (my/journal-places--quick "2 Z" displays))
    (should-not (my/journal-places--quick "Kra" displays))
    (should-not (my/journal-places--quick "" displays))))

(ert-deftest my/jp-test-quick-ignores-unnumbered-candidates ()
  "Past the numbered ones a digit is a digit, not an index."
  (let* ((my/journal-place-quick-count 1)
         (displays (my/journal-places--displays '("Kraków" "Zakopane"))))
    (should (equal (my/journal-places--quick "1" displays) "Kraków"))
    (should-not (my/journal-places--quick "2" displays))))

;; ============================================================
;; THE COMMAND
;; ============================================================

(defmacro my/jp-test--in-note (day place &rest body)
  "Visit a journal note for DAY carrying PLACE in a temp silo, run BODY."
  (declare (indent 2))
  `(my/jp-test--with-silo (list (list ,day ,place))
     (let ((file (expand-file-name
                  (format "%sT091200--%s-journal__journal.org"
                          (replace-regexp-in-string "-" "" ,day) ,day)
                  my-notes-journal)))
       (unwind-protect
           (with-current-buffer (find-file-noselect file)
             (org-mode)
             ,@body)
         (when (get-file-buffer file)
           (kill-buffer (get-file-buffer file)))))))

(ert-deftest my/jp-test-writes-the-keyword ()
  (my/jp-test--in-note "2026-11-15" nil
    (my/jp-test--answering '("Kraków")
      (my/journal-set-place))
    (should (equal (my/note-keyword "place") "Kraków"))
    (goto-char (point-min))
    ;; Aligned with the rest of the front matter.
    (should (re-search-forward "^#\\+place:\\( +\\)Kraków$" nil t))
    (should (= (- (match-end 1) (line-beginning-position))
               my/note-front-matter-column))))

(ert-deftest my/jp-test-writes-several-places ()
  (my/jp-test--in-note "2026-11-15" nil
    (my/jp-test--answering '("Kraków" "Roma, Włochy")
      (my/journal-set-place))
    (should (equal (my/note-keyword "place") "Kraków; Roma, Włochy"))))

(ert-deftest my/jp-test-normalizes-what-was-typed ()
  (my/jp-test--in-note "2026-11-15" nil
    (my/jp-test--answering '("  Kraków ,  Polska ")
      (my/journal-set-place))
    (should (equal (my/note-keyword "place") "Kraków"))))

(ert-deftest my/jp-test-refuses-a-repeated-place ()
  (my/jp-test--in-note "2026-11-15" nil
    (my/jp-test--answering '("Kraków" "kraków" "Zakopane")
      (my/journal-set-place))
    (should (equal (my/note-keyword "place") "Kraków; Zakopane"))))

(ert-deftest my/jp-test-replaces-the-previous-value ()
  (my/jp-test--in-note "2026-11-15" "Gdańsk"
    (my/jp-test--answering '("Kraków")
      (my/journal-set-place))
    (should (equal (my/note-keyword "place") "Kraków"))
    (goto-char (point-min))
    (should (= 1 (count-matches "^#\\+place:")))))

(ert-deftest my/jp-test-empty-answer-changes-nothing ()
  "RET at the first prompt is not an empty value and not a removal."
  (my/jp-test--in-note "2026-11-15" "Gdańsk"
    (let ((before (buffer-string)))
      (my/jp-test--answering '()
        (my/journal-set-place))
      (should (equal (buffer-string) before))
      (should-not (buffer-modified-p)))))

(ert-deftest my/jp-test-marker-removes-the-keyword ()
  (my/jp-test--in-note "2026-11-15" "Gdańsk"
    (my/jp-test--answering (list my/journal-place-remove-marker)
      (my/journal-set-place))
    (should-not (my/note-keyword "place"))
    (goto-char (point-min))
    (should-not (re-search-forward "^#\\+place" nil t))))

(ert-deftest my/jp-test-keeps-the-other-front-matter ()
  "The metrics and Denote's own keywords are not touched."
  (my/jp-test--in-note "2026-11-15" nil
    (my/note-keyword-set "wellbeing" "7" my/note-front-matter-column)
    (my/jp-test--answering '("Kraków")
      (my/journal-set-place))
    (should (equal (my/note-keyword "wellbeing") "7"))
    (should (equal (my/note-keyword "identifier") "20261115T091200"))
    (should (equal (my/note-keyword "language") "pl"))))

(ert-deftest my/jp-test-quit-leaves-the-file-alone ()
  "C-g at a prompt writes nothing: read, prompt, write, in that order."
  (my/jp-test--in-note "2026-11-15" "Gdańsk"
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'my/journal-places--read)
                 (lambda (&rest _) (signal 'quit nil))))
        (condition-case nil
            (my/journal-set-place)
          (quit nil)))
      (should (equal (buffer-string) before))
      (should-not (buffer-modified-p)))))

(ert-deftest my/jp-test-refuses-outside-a-journal-note ()
  (my/jp-test--with-silo '()
    (let ((file (expand-file-name "20261115T091200--a-note__pks.org" my-notes-journal)))
      (with-temp-file file (insert "#+title: A note\n"))
      (unwind-protect
          (with-current-buffer (find-file-noselect file)
            (org-mode)
            (should-error (my/journal-set-place) :type 'user-error))
        (when (get-file-buffer file)
          (kill-buffer (get-file-buffer file)))))))

(ert-deftest my/jp-test-new-place-reaches-the-list ()
  "A place just written is in the list without the silo being read again.
The scan is replaced afterwards, so a list rebuilt from disk instead of
from the cache fails here rather than passing by accident."
  (my/jp-test--in-note "2026-11-15" nil
    (should-not (my/journal-places))
    (my/jp-test--answering '("Kraków")
      (my/journal-set-place))
    (cl-letf (((symbol-function 'my/journal-places--scan)
               (lambda () (error "The silo was scanned again"))))
      (should (equal (my/journal-places) '("Kraków"))))))

(ert-deftest my/jp-test-transient-entry-present ()
  "The place key reached the Insert menu."
  (skip-unless (fboundp 'my/notes-insert-menu))
  (should (transient-get-suffix 'my/notes-insert-menu "g")))

(provide 'test-journal-places)
;;; test-journal-places.el ends here
