;;; test-zettelkasten.el --- ERT tests for the pks-only Folgezettel of 22-zettelkasten -*- lexical-binding: t; -*-

;; Tests: 22-zettelkasten

;;; Commentary:

;; 22-zettelkasten.el wraps denote-sequence so that sequences are found
;; and created in the pks silo only (`denote-directory' bound to it),
;; with the alphanumeric scheme (1, 1a, 1b, 2), and works around stale
;; Dired listings: TESTING.org, *Every module tested*, part 3.  On real
;; files in a temporary notes folder; denote-sequence and Denote run,
;; only their prompts are answered.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-zettelkasten.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "22-zettelkasten")
(require 'denote)
(require 'denote-sequence)

(defvar denote-directory)

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/zk-test--with-silos (&rest body)
  "Run BODY with a notes folder `notes' (the Denote folder) holding the
silos `pks' and `journal'.  Denote asks only for a title, answered by
`my/zk-test--title'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-zk-" t)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (pks (file-name-as-directory (expand-file-name "pks" notes)))
          (journal (file-name-as-directory (expand-file-name "journal" notes)))
          (my-notes-dir notes)
          (my-notes-pks pks)
          (denote-directory notes)
          (denote-prompts '(title))
          (denote-rename-confirmations nil)
          (denote-save-buffers t)
          (inhibit-message t))
     (make-directory pks t)
     (make-directory journal t)
     (advice-add 'denote-title-prompt :override #'my/zk-test--title)
     (unwind-protect
         (progn ,@body)
       (advice-remove 'denote-title-prompt #'my/zk-test--title)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defvar my/zk-test--next-title "Thought"
  "The title Denote is given for the next note.")

(defun my/zk-test--title (&rest _)
  "Answer Denote's title prompt with `my/zk-test--next-title'."
  my/zk-test--next-title)

(defun my/zk-test--write (file text)
  "Write TEXT to FILE; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/zk-test--signatures (dir)
  "Return the signatures of the notes in DIR, sorted."
  (sort (delq nil (mapcar #'denote-retrieve-filename-signature
                          (directory-files dir t "\\.org\\'")))
        #'string<))

(defun my/zk-test--file-with (dir signature)
  "Return the note in DIR with SIGNATURE."
  (seq-find (lambda (f) (equal (denote-retrieve-filename-signature f) signature))
            (directory-files dir t "\\.org\\'")))

;; ============================================================
;; CREATING IN THE PKS SILO
;; ============================================================

(ert-deftest my/zk-test-new-parents-in-pks ()
  "New threads are notes in pks numbered 1, 2; a journal note with a
signature neither counts nor gets a sibling."
  (my/zk-test--with-silos
    (my/zk-test--write (expand-file-name "20261001T100000==5--day__journal.org" journal)
                       "#+title: day\n")
    (my/zettel-new-parent)
    (my/zettel-new-parent)
    (should (equal (my/zk-test--signatures pks) '("1" "2")))
    (should (equal (my/zk-test--signatures journal) '("5")))
    (should-not (directory-files notes nil "\\.org\\'"))))

(ert-deftest my/zk-test-child-and-sibling-of-current ()
  "From a note's buffer: a child gets the alphanumeric next level (1a),
a sibling of that the next letter (1b), both in pks."
  (my/zk-test--with-silos
    (my/zettel-new-parent)
    (with-current-buffer (find-file-noselect (my/zk-test--file-with pks "1"))
      (my/zettel-new-child-of-current))
    (with-current-buffer (find-file-noselect (my/zk-test--file-with pks "1a"))
      (my/zettel-new-sibling-of-current))
    (should (equal (my/zk-test--signatures pks) '("1" "1a" "1b")))))

(ert-deftest my/zk-test-adopt ()
  "Adopting an ordinary pks note gives it the next parent number in its
place; a note that has a sequence is refused and keeps its name."
  (my/zk-test--with-silos
    (my/zettel-new-parent)
    (let ((plain (my/zk-test--write (expand-file-name "20261002T100000--plain.org" pks)
                                    "#+title:      plain\n#+date:       [2026-10-02 Fri 10:00]\n#+identifier: 20261002T100000\n")))
      (with-current-buffer (find-file-noselect plain)
        (my/zettel-adopt))
      (should (equal (my/zk-test--signatures pks) '("1" "2")))
      (should (string-match-p "\\`20261002T100000==2--plain"
                              (file-name-nondirectory (my/zk-test--file-with pks "2")))))
    (let ((one (my/zk-test--file-with pks "1")))
      (with-current-buffer (find-file-noselect one)
        (should-error (my/zettel-adopt) :type 'user-error))
      (should (file-exists-p one)))))

(ert-deftest my/zk-test-reparent ()
  "Reparenting the current note makes it a child of the chosen thread,
in pks: 2 under 1 becomes 1a; only pks notes are offered."
  (my/zk-test--with-silos
    (my/zettel-new-parent)
    (my/zettel-new-parent)
    (my/zk-test--write (expand-file-name "20261001T100000==9--day__journal.org" journal)
                       "#+title: day\n")
    (let ((offered nil))
      (with-current-buffer (find-file-noselect (my/zk-test--file-with pks "2"))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt collection &rest _)
                     (setq offered (all-completions "" collection))
                     (seq-find (lambda (c) (string-match-p "==1--" c)) offered))))
          (my/zettel-reparent)))
      (should (equal (my/zk-test--signatures pks) '("1" "1a")))
      (should-not (seq-some (lambda (c) (string-search "journal" c)) offered)))))

;; ============================================================
;; STALE DIRED LISTINGS
;; ============================================================

(ert-deftest my/zk-test-kill-stale-dired-buffers ()
  "Only Dired buffers named by `denote-sequence-dired' are killed; other
Dired buffers and ordinary buffers with such a name stay."
  (my/zk-test--with-silos
    (let ((listing (dired-noselect pks))
          (plain-dired (dired-noselect journal))
          (text (generate-new-buffer "notes prefix ‘1’; depth ‘2’ (a text)")))
      (with-current-buffer listing (rename-buffer "Denote sequences at prefix ‘1’; depth ‘2’"))
      (with-current-buffer text (fundamental-mode))
      (my/zettel--kill-stale-dired-buffers)
      (should-not (buffer-live-p listing))
      (should (buffer-live-p plain-dired))
      (should (buffer-live-p text))
      (kill-buffer plain-dired)
      (kill-buffer text))))

(provide 'test-zettelkasten)
;;; test-zettelkasten.el ends here
