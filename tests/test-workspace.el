;;; test-workspace.el --- ERT tests for the notes dashboard of 15-workspace -*- lexical-binding: t; -*-

;; Tests: 15-workspace

;;; Commentary:

;; 15-workspace draws the notes dashboard: recently modified notes, the
;; journal, the silos, hubs, sequenced notes and tags, in columns of
;; their own.  These tests build silos in a temporary folder and check
;; what the collectors return and what a column shows: titles and tags
;; from the front matter, signatures with or without a title, orders by
;; change and by creation, dot-files left out, the recent window, hubs
;; without 33-denote-hubs, tag counts, the "... and N more" line, tags
;; on lines only in a single column, hidden tags, an unknown section,
;; leftover column buffers.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-workspace.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "01-ui" "27-denote-identifiers" "15-workspace")

(defmacro my/ws-test-with-silos (&rest body)
  "Run BODY with silos journal/ and pks/ in a temporary folder.
Binds `root', `journal', `pks'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-ws-" t)))
          (journal (file-name-as-directory (expand-file-name "journal" root)))
          (pks (file-name-as-directory (expand-file-name "pks" root)))
          (my-notes-dir root)
          (my-notes-journal journal)
          (my-notes-pks pks)
          (my-tasks-agenda-dirs (list journal pks))
          (inhibit-message t))
     (make-directory journal t)
     (make-directory pks t)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (when (string-prefix-p "*Notes Dashboard" (buffer-name b))
           (kill-buffer b)))
       (delete-directory root t))))

(defun my/ws-test-note (dir name &optional title tags age)
  "Write DIR/NAME.org with TITLE and TAGS; changed AGE days ago.  Return it."
  (let ((file (expand-file-name (concat name ".org") dir)))
    (with-temp-file file
      (insert "#+title:      " (or title "") "\n"
              (if tags (format "#+filetags:   :%s:\n" (string-join tags ":")) "")
              "\nTekst.\n"))
    (when age
      (set-file-times file (time-subtract (current-time) (days-to-time age))))
    file))

(ert-deftest my/ws-test-title-and-tags-from-front-matter ()
  "Title and tags come from the front matter; an empty title gives the
file's base name."
  (my/ws-test-with-silos
    (let ((a (my/ws-test-note pks "20261025T100000--a__x" "Tytuł" '("filozofia" "etyka")))
          (b (my/ws-test-note pks "20261025T110000--b__x" "")))
      (should (equal (my/denote-file-metadata a) '("Tytuł" "filozofia" "etyka")))
      (should (equal (my/denote-file-title b) "20261025T110000--b__x")))))

(ert-deftest my/ws-test-signature-with-and-without-title ()
  "A signature is read with a title after it, keywords only, or nothing."
  (should (equal (my/denote-file-signature "/n/20261025T100000==1a--teza__z.org") "1a"))
  (should (equal (my/denote-file-signature "/n/20261025T100000==2b3__z.org") "2b3"))
  (should (equal (my/denote-file-signature "/n/20261025T100000==4.org") "4"))
  (should-not (my/denote-file-signature "/n/20261025T100000--zwykla__z.org")))

(ert-deftest my/ws-test-orders ()
  "Silo lists by last change, the journal by creation with undated last."
  (my/ws-test-with-silos
    (let ((old (my/ws-test-note pks "20261020T100000--stara__x" "Stara" nil 5))
          (new (my/ws-test-note pks "20261010T100000--nowa__x" "Nowa" nil 1)))
      (should (equal (my/denote-org-files-in pks) (list new old))))
    (let ((first (my/ws-test-note journal "20261020T000000--2026-10-20__journal" "a" nil 1))
          (second (my/ws-test-note journal "20261022T000000--2026-10-22__journal" "b" nil 5))
          (captures (my/ws-test-note journal "captures" "c")))
      (should (equal (my/denote-org-files-in-by-id journal)
                     (list second first captures))))))

(ert-deftest my/ws-test-dot-files-left-out ()
  "A dot-file ending in .org -- an Emacs lock file, a link to nowhere --
is not listed."
  (my/ws-test-with-silos
    (let ((note (my/ws-test-note pks "20261025T100000--a__x" "A")))
      (make-symbolic-link "user@host.12345:1" (expand-file-name ".#20261025T100000--a__x.org" pks))
      (should (equal (my/denote-org-files-in pks) (list note)))
      (should (equal (my/denote-org-files-in-by-id pks) (list note)))
      (should (equal (my/denote--all-silo-files) (list note))))))

(ert-deftest my/ws-test-recently-modified ()
  "Recently modified: across the silos, inside the window, newest first."
  (my/ws-test-with-silos
    (let ((a (my/ws-test-note pks "20261025T100000--a__x" "A" nil 2))
          (b (my/ws-test-note journal "20261025T000000--2026-10-25__journal" "B" nil 1)))
      (my/ws-test-note pks "20261001T100000--c__x" "C" nil 20)
      (should (equal (my/denote-recently-modified 10) (list b a))))))

(ert-deftest my/ws-test-hubs-without-the-hubs-module ()
  "Without 33-denote-hubs, hubs are the notes with the hub keyword."
  (skip-unless (not (fboundp 'my/denote-hub-files)))
  (my/ws-test-with-silos
    (let ((hub (my/ws-test-note pks "20261025T100000--mapa__hub" "Mapa")))
      (my/ws-test-note pks "20261025T110000--hubert__osoby" "Hubert")
      (should (equal (my/denote-hub-notes) (list hub))))))

(ert-deftest my/ws-test-tags-counted ()
  "Tags with their notes, the most used first."
  (my/ws-test-with-silos
    (my/ws-test-note pks "20261025T100000--a__x" "A" '("filozofia" "etyka"))
    (my/ws-test-note pks "20261025T110000--b__x" "B" '("filozofia"))
    (let ((tags (my/denote-all-tags)))
      (should (equal (car (car tags)) "filozofia"))
      (should (= (length (cdr (assoc "filozofia" tags))) 2))
      (should (= (length (cdr (assoc "etyka" tags))) 1)))))

(ert-deftest my/ws-test-column-shows-what-is-left-out ()
  "A capped list says how many notes it leaves out; hidden tags are not
shown; tags appear on lines only in a single column; an unknown section
is named, not an error."
  (my/ws-test-with-silos
    (dotimes (i 4)
      (my/ws-test-note pks (format "20261025T10000%d--n%d__x" i i) (format "Nota %d" i)
                       '("journal" "widoczny")))
    (let ((my/dashboard-silo-limit 3)
          (my/dashboard-sections (append my/dashboard-sections nil)))
      (with-current-buffer (my/dashboard--render-column '(pks nosuch) 1 1)
        (let ((text (buffer-string)))
          (should (string-match-p "\\.\\.\\. and 1 more" text))
          (should (string-match-p ":widoczny:" text))
          (should-not (string-match-p ":journal" text))
          (should (string-match-p "Unknown section: nosuch" text))))
      (with-current-buffer (my/dashboard--render-column '(pks) 1 2)
        (should-not (string-match-p ":widoczny:" (buffer-string)))))))

(ert-deftest my/ws-test-stale-columns-killed ()
  "Column buffers beyond the current number of columns are killed."
  (my/ws-test-with-silos
    (get-buffer-create "*Notes Dashboard 3*")
    (let ((my/dashboard-columns '((pks) (journal))))
      (my/render-notes-dashboard))
    (should (get-buffer "*Notes Dashboard 2*"))
    (should-not (get-buffer "*Notes Dashboard 3*"))))

(ert-deftest my/ws-test-tag-list-by-creation ()
  "The notes of a tag are listed newest created first, with their dates."
  (my/ws-test-with-silos
    (let ((older (my/ws-test-note pks "20261001T100000--a__x" "Starsza" nil 1))
          (newer (my/ws-test-note pks "20261020T100000--b__x" "Nowsza" nil 9)))
      (my/dashboard-show-tag-notes "x" (list older newer))
      (with-current-buffer "*Tag: x*"
        (let ((text (buffer-string)))
          (should (< (string-search "Nowsza" text) (string-search "Starsza" text)))
          (should (string-match-p "2026-10-20 .*Nowsza" text))))
      (kill-buffer "*Tag: x*"))))

(provide 'test-workspace)
;;; test-workspace.el ends here
