;;; test-notes-stats.el --- ERT tests for 836-notes-stats -*- lexical-binding: t; -*-

;; Tests: 836-notes-stats

;;; Commentary:

;; 836-notes-stats counts the collection from file names (counts, sizes,
;; keywords, months, journal coverage, sequenced notes) and, on `c',
;; from the files' contents (words, links, orphans), and exports all of
;; it to an Org file with `denote:' links.  These tests build a small
;; collection in a temporary notes folder and check the figures and the
;; export: journal notes named as 205-notes names them today, a
;; sequenced note without a title, titles with brackets and a bar in
;; the links and tables of the export, keyword figures with the inbox
;; left out, streaks, the content scan, the files on disk.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-notes-stats.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "204-denote" "205-notes" "227-denote-identifiers" "826-maintenance"
                      "836-notes-stats")

(defmacro my/ns2-test-with-notes (&rest body)
  "Run BODY in a fresh notes folder with journal/, pks/, inbox/.
Binds `root'.  Notes written by `my/ns2-test-note'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-stats-" t)))
          (my-notes-dir root)
          (my/notes-stats-keyword-exclude-dirs '("inbox"))
          (my/notes-stats-silos '("journal" "pks"))
          (inhibit-message t))
     (dolist (d '("journal" "pks" "inbox" ".snapshots/x")) (make-directory (expand-file-name d root) t))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/ns2-test-note (dir name &optional title body)
  "Write DIR/NAME.org with TITLE (default \"T\") and BODY; return the file."
  (let ((file (expand-file-name (concat name ".org") (expand-file-name dir my-notes-dir))))
    (with-temp-file file
      (insert "#+title:      " (or title "T") "\n\n" (or body "Body.\n")))
    file))

(defun my/ns2-test-org-export (data)
  "The Org text the export writes for DATA."
  (with-temp-buffer
    (my/notes-stats--render-org data)
    (buffer-string)))

(ert-deftest my/ns2-test-journal-notes-as-named-today ()
  "Journal notes named as 205-notes names them -- date as the title, the
`journal' keyword -- are the journal; the old pattern wanted
\"DATE-journal\" in the title and counted none of them."
  (my/ns2-test-with-notes
    (my/ns2-test-note "journal" "20261023T080000--2026-10-23__journal")
    (my/ns2-test-note "journal" "20261024T080000--2026-10-24__journal")
    (my/ns2-test-note "journal" "20240101T080000--2024-01-01-journal__journal")
    (my/ns2-test-note "pks" "20261024T090000--2026-10-24-plan__plan")
    (let ((journal (plist-get (my/notes-stats--collect) :journal)))
      (should (equal (sort (hash-table-keys journal) #'string<)
                     '("2024-01-01" "2026-10-23" "2026-10-24"))))))

(ert-deftest my/ns2-test-sequenced-note-without-title ()
  "A sequenced note is counted by its signature, also without a title;
the depth of 1a2 is three."
  (my/ns2-test-with-notes
    (my/ns2-test-note "pks" "20261025T100000==1a2__zettel")
    (my/ns2-test-note "pks" "20261025T110000==1--teza__zettel")
    (my/ns2-test-note "pks" "20261025T120000--zwykla__notatka")
    (let ((zettel (plist-get (my/notes-stats--collect) :zettel)))
      (should (equal (sort (mapcar #'cdr zettel) #'string<) '("1" "1a2")))
      (should (= (my/notes-stats--signature-depth "1a2") 3)))))

(ert-deftest my/ns2-test-counts-sizes-directories ()
  "Notes counted per top directory, dot folders left out; the largest
and smallest notes found."
  (my/ns2-test-with-notes
    (my/ns2-test-note "pks" "20261025T100000--duza__a" "Duża" (make-string 5000 ?x))
    (my/ns2-test-note "pks" "20261025T110000--mala__a" "Mała" "")
    (my/ns2-test-note "inbox" "20261025T120000--wejscie__a")
    (my/ns2-test-note ".snapshots/x" "20261025T130000--kopia__a")
    (let* ((data (my/notes-stats--collect))
           (dirs (plist-get data :dirs)))
      (should (= (plist-get data :total) 3))
      (should (equal (car (gethash "pks" dirs)) 2))
      (should (equal (car (gethash "inbox" dirs)) 1))
      (should-not (gethash ".snapshots" dirs))
      (should (string-match-p "duza" (plist-get data :largest)))
      (should (string-match-p "mala" (plist-get data :smallest))))))

(ert-deftest my/ns2-test-keywords-inbox-left-out ()
  "Keyword figures leave the inbox out; singletons and notes without
keywords are found."
  (my/ns2-test-with-notes
    (my/ns2-test-note "pks" "20261025T100000--a__filozofia_etyka")
    (my/ns2-test-note "pks" "20261025T110000--b__filozofia")
    (my/ns2-test-note "pks" "20261025T120000--bez-slow")
    (my/ns2-test-note "inbox" "20261025T130000--c__tymczasowe")
    (let ((data (my/notes-stats--collect)))
      (should (= (plist-get data :keyword-total) 3))
      (should (= (gethash "filozofia" (plist-get data :keywords)) 2))
      (should-not (gethash "tymczasowe" (plist-get data :keywords)))
      (should (equal (mapcar #'car (my/notes-stats--singletons data)) '("etyka")))
      (should (= (length (plist-get data :bare)) 1)))))

(ert-deftest my/ns2-test-export-links-survive-brackets-and-bars ()
  "In the exported Org file a title with brackets stays inside its link,
and a title with a bar does not split its table row."
  (my/ns2-test-with-notes
    (my/ns2-test-note "pks" "20261025T100000--plan__a" "Plan | wersja 2 [szkic]"
                      (make-string 3000 ?x))
    (my/ns2-test-note "pks" "20261025T110000--krotka__b" "Krótka" "")
    (with-temp-buffer
      (insert (my/ns2-test-org-export (my/notes-stats--collect)))
      (org-mode)
      (let ((links nil))
        (org-element-map (org-element-parse-buffer) 'link
          (lambda (link)
            (push (list (org-element-property :path link)
                        (buffer-substring-no-properties
                         (org-element-property :contents-begin link)
                         (org-element-property :contents-end link)))
                  links)))
        (should (member "20261025T100000" (mapcar #'car links)))
        ;; org-link-make-string puts a zero-width space after a closing
        ;; bracket that would otherwise run into the link's own "]]".
        (should (string-match-p "\\`Plan .* \\[szkic\\]\u200b?\\'"
                                (cadr (assoc "20261025T100000" links)))))
      ;; The row of the largest note: two cells, so three bars.
      (goto-char (point-min))
      (search-forward "| Largest note |")
      (let ((line (buffer-substring-no-properties (line-beginning-position)
                                                  (line-end-position))))
        (should (= 3 (cl-count ?| line)))
        (should (string-match-p "\\\\vert{}" line))))))

(ert-deftest my/ns2-test-streaks ()
  "Longest and current streaks; today missing still keeps a streak that
reaches yesterday."
  ;; Calendar days (`my/test-date'): 86400-second steps from now failed
  ;; at 23:23 on the day summer time ended (2026-10-25).
  (let* ((day #'my/test-date)
         (days (list (funcall day -10) (funcall day -9) (funcall day -8) (funcall day -7)
                     (funcall day -3) (funcall day -2) (funcall day -1))))
    (should (equal (my/notes-stats--streaks days) '(4 . 3)))
    (should (equal (my/notes-stats--streaks (append days (list (funcall day 0)))) '(4 . 4)))
    (should (equal (my/notes-stats--streaks nil) '(0 . 0)))))

(ert-deftest my/ns2-test-deep-scan ()
  "Words, links, notes linking to nothing and notes nothing links to."
  (my/ns2-test-with-notes
    (let ((files (list (my/ns2-test-note "pks" "20261025T100000--a__x" "A"
                                         "jeden dwa [[denote:20261025T110000][B]]\n")
                       (my/ns2-test-note "pks" "20261025T110000--b__x" "B" "trzy\n")
                       (my/ns2-test-note "pks" "20261025T120000--c__x" "C" "cztery\n"))))
      (let ((deep (my/notes-stats--deep-scan files)))
        (should (= (plist-get deep :links) 1))
        (should (= (plist-get deep :no-links) 2))
        (should (= (plist-get deep :orphans) 2))
        (should (> (plist-get deep :words) 6))))))

(ert-deftest my/ns2-test-disk-rows ()
  "On disk: every file of each top folder, any extension, dot folders out."
  (my/ns2-test-with-notes
    (my/ns2-test-note "pks" "20261025T100000--a__x")
    (with-temp-file (expand-file-name "pks/obraz.png" root) (insert "png"))
    (my/ns2-test-note ".snapshots/x" "20261025T130000--kopia__a")
    (let ((rows (my/notes-stats--disk-rows)))
      (should (equal (nth 1 (assoc "pks" rows)) 2))
      (should-not (assoc ".snapshots" rows)))))

(ert-deftest my/ns2-test-export-writes-the-file ()
  "The export command writes the Org file asked for, with the Content
section when the content figures were computed in the report."
  (my/ns2-test-with-notes
    (my/ns2-test-note "pks" "20261025T100000--a__x" "A" "jeden dwa\n")
    (let ((target (expand-file-name "raport.org" root)))
      (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) target)))
        (with-temp-buffer
          (setq-local my/notes-stats--deep (my/notes-stats--deep-scan (my/denote-all-files)))
          (my/notes-stats-export)))
      (should (file-exists-p target))
      (with-temp-buffer
        (insert-file-contents target)
        (should (search-forward "* Content" nil t))
        (should (search-forward "| Words | " nil t))))))

(provide 'test-notes-stats)
;;; test-notes-stats.el ends here
