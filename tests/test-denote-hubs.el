;;; test-denote-hubs.el --- ERT tests for hub notes of 33-denote-hubs -*- lexical-binding: t; -*-

;; Tests: 33-denote-hubs

;;; Commentary:

;; 33-denote-hubs.el keeps hub notes: Denote notes with the `hub'
;; keyword whose body is a list of links with descriptions.  It reads
;; which hubs list a note, adds an entry in identifier order (sorting the
;; hub first when needed), edits an entry in place, and creates hubs:
;; TESTING.org, *Every module tested*, part 3.  On real files in a
;; temporary notes folder that is also the Denote folder.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-denote-hubs.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "33-denote-hubs")

(defvar denote-directory)

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/hub-test--with-notes (&rest body)
  "Run BODY in a fresh notes folder `notes' with the silo `pks'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-hubs-" t)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (pks (file-name-as-directory (expand-file-name "pks" notes)))
          (my-notes-dir notes)
          (denote-directory notes)
          (my/denote-hub-directory pks)
          (inhibit-message t))
     (make-directory pks t)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/hub-test--write (file text)
  "Write TEXT to FILE, creating its folder; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/hub-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/hub-test--note (dir id title &optional keywords body)
  "Write the Denote note ID titled TITLE with KEYWORDS and BODY in DIR."
  (my/hub-test--write
   (expand-file-name (format "%s--%s%s.org" id
                             (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase title))
                             (if keywords (concat "__" (string-join keywords "_")) ""))
                     dir)
   (format "#+title:      %s\n#+identifier: %s\n\n%s" title id (or body ""))))

(defun my/hub-test--hub (dir id title body)
  "Write the hub note ID titled TITLE with BODY in DIR."
  (my/hub-test--note dir id title '("hub") body))

(defun my/hub-test--label (hub)
  "Return the prompt label of HUB, as the hub prompt shows it."
  (format "%s (%s)" (my/denote-hub--title hub) (denote-retrieve-filename-identifier hub)))

(defun my/hub-test--add (note choice &rest answers)
  "Run the add-to-hub command in NOTE choosing CHOICE; ANSWERS answer the
text prompts in order (descriptions, a new hub's title and description)."
  (with-current-buffer (find-file-noselect note)
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) choice))
              ((symbol-function 'read-from-minibuffer) (lambda (&rest _) (pop answers)))
              ((symbol-function 'read-string) (lambda (&rest _) (pop answers))))
      (my/denote-add-to-hub))))

;; ============================================================
;; FINDING HUBS AND MEMBERSHIP
;; ============================================================

(ert-deftest my/hub-test-hub-files ()
  "Hubs are the notes with the hub keyword in their file name."
  (my/hub-test--with-notes
    (let ((hub (my/hub-test--hub pks "20261001T100000" "Ethics" ""))
          (_note (my/hub-test--note pks "20261002T100000" "Plain" '("ethics"))))
      (should (equal (my/denote-hub-files) (list hub))))))

(ert-deftest my/hub-test-membership ()
  "A hub lists a note when one of its entries links to it first; the
entry comes back whole, continuation lines included."
  (my/hub-test--with-notes
    (let* ((note (my/hub-test--note pks "20261002T100000" "Kant"))
           (hub (my/hub-test--hub pks "20261001T100000" "Ethics"
                                  (concat "- [[denote:20261002T100000][Kant]] — duty\n"
                                          "  and the law\n\n"
                                          "- [[denote:20261003T100000][Hume]]\n"))))
      (should (equal (my/denote-hub-membership note)
                     (list (cons hub (list "- [[denote:20261002T100000][Kant]] — duty\n  and the law")))))
      (should (equal (my/denote-hub--entry-description
                      (car (cdr (car (my/denote-hub-membership note)))))
                     "duty\nand the law")))))

(ert-deftest my/hub-test-link-in-description-not-an-entry ()
  "A link to the note inside another entry's description does not make
the note listed: it is added as an entry of its own, and the other
entry stays exactly as it was."
  (my/hub-test--with-notes
    (let* ((note (my/hub-test--note pks "20261003T100000" "Hume"))
           (other "- [[denote:20261002T100000][Kant]] — read with [[denote:20261003T100000][Hume]]")
           (hub (my/hub-test--hub pks "20261001T100000" "Ethics" (concat other "\n"))))
      (should-not (my/denote-hub-membership note))
      (my/hub-test--add note (my/hub-test--label hub) "custom")
      (let ((text (my/hub-test--read hub)))
        (should (string-search (concat other "\n") text))
        (should (string-search "- [[denote:20261003T100000][Hume]] — custom" text))))))

;; ============================================================
;; ADDING AND ORDER
;; ============================================================

(ert-deftest my/hub-test-add-entry-in-order ()
  "An entry goes before the first newer one in a hub already in order,
which is otherwise not rewritten."
  (my/hub-test--with-notes
    (let ((hub (my/hub-test--hub pks "20261001T100000" "Ethics"
                                 (concat "- [[denote:20261002T100000][A]] — a\n\n"
                                         "- [[denote:20261004T100000][C]] — c\n"))))
      (should (eq (my/denote-hub-add-entry hub "- [[denote:20261003T100000][B]] — b" "20261003T100000")
                  'inserted))
      (should (string-suffix-p (concat "- [[denote:20261002T100000][A]] — a\n\n"
                                       "- [[denote:20261003T100000][B]] — b\n\n"
                                       "- [[denote:20261004T100000][C]] — c\n")
                               (my/hub-test--read hub))))))

(ert-deftest my/hub-test-add-entry-sorts-first ()
  "A hub out of order is sorted, multi-line entries kept whole, before
the entry goes in; with prose between entries it is appended instead."
  (my/hub-test--with-notes
    (let ((hub (my/hub-test--hub pks "20261001T100000" "Ethics"
                                 (concat "- [[denote:20261004T100000][C]] — c\n  more c\n\n"
                                         "- [[denote:20261002T100000][A]] — a\n"))))
      (should (eq (my/denote-hub-add-entry hub "- [[denote:20261003T100000][B]]" "20261003T100000")
                  'sorted))
      (should (string-suffix-p (concat "- [[denote:20261002T100000][A]] — a\n\n"
                                       "- [[denote:20261003T100000][B]]\n\n"
                                       "- [[denote:20261004T100000][C]] — c\n  more c\n")
                               (my/hub-test--read hub))))
    (let ((hub (my/hub-test--hub pks "20261001T110000" "Logic"
                                 (concat "- [[denote:20261004T100000][C]]\n\nA remark.\n\n"
                                         "- [[denote:20261002T100000][A]]\n"))))
      (should (eq (my/denote-hub-add-entry hub "- [[denote:20261003T100000][B]]" "20261003T100000")
                  'appended))
      (should (string-suffix-p "- [[denote:20261002T100000][A]]\n\n- [[denote:20261003T100000][B]]\n"
                               (my/hub-test--read hub))))))

(ert-deftest my/hub-test-sort-command ()
  "Sorting by hand refuses prose between entries, naming its line, and
leaves a hub in order untouched."
  (my/hub-test--with-notes
    (let* ((body (concat "- [[denote:20261004T100000][C]]\n\nA remark.\n\n"
                         "- [[denote:20261002T100000][A]]\n"))
           (hub (my/hub-test--hub pks "20261001T100000" "Ethics" body)))
      (should-error (my/denote-hub-sort-entries hub) :type 'user-error)
      (should (string-suffix-p body (my/hub-test--read hub))))
    (let* ((body "- [[denote:20261002T100000][A]]\n\n- [[denote:20261004T100000][C]]\n")
           (hub (my/hub-test--hub pks "20261001T110000" "Logic" body)))
      (my/denote-hub-sort-entries hub)
      (should (string-suffix-p body (my/hub-test--read hub))))))

;; ============================================================
;; THE COMMAND
;; ============================================================

(ert-deftest my/hub-test-command-adds-entry ()
  "Adding a note to a hub that does not list it: its title, the
description with continuation lines indented, in order."
  (my/hub-test--with-notes
    (let ((note (my/hub-test--note pks "20261003T100000" "Hume"))
          (hub (my/hub-test--hub pks "20261001T100000" "Ethics"
                                 "- [[denote:20261002T100000][Kant]]\n")))
      (my/hub-test--add note (my/hub-test--label hub) "custom\nand habit")
      (should (string-suffix-p (concat "- [[denote:20261002T100000][Kant]]\n\n"
                                       "- [[denote:20261003T100000][Hume]] — custom\n  and habit\n")
                               (my/hub-test--read hub))))))

(ert-deftest my/hub-test-command-edits-in-place ()
  "Choosing a hub that lists the note rewrites its entry where it stands,
continuation lines and all; the other entries are untouched, also one
whose description links to the note above its entry."
  (my/hub-test--with-notes
    (let ((note (my/hub-test--note pks "20261003T100000" "Hume"))
          (hub (my/hub-test--hub pks "20261001T100000" "Ethics"
                                 (concat "- [[denote:20261002T100000][Kant]] — vs [[denote:20261003T100000][Hume]]\n\n"
                                         "- [[denote:20261003T100000][Hume]] — old\n  old tail\n\n"
                                         "- [[denote:20261004T100000][Mill]] — use\n"))))
      (my/hub-test--add note (my/hub-test--label hub) "new")
      (should (string-suffix-p (concat "- [[denote:20261002T100000][Kant]] — vs [[denote:20261003T100000][Hume]]\n\n"
                                       "- [[denote:20261003T100000][Hume]] — new\n\n"
                                       "- [[denote:20261004T100000][Mill]] — use\n")
                               (my/hub-test--read hub))))))

(ert-deftest my/hub-test-command-refuses-duplicates ()
  "A hub listing the note twice is refused for editing; nothing changes."
  (my/hub-test--with-notes
    (let* ((note (my/hub-test--note pks "20261003T100000" "Hume"))
           (body "- [[denote:20261003T100000][Hume]] — a\n\n- [[denote:20261003T100000][Hume]] — b\n")
           (hub (my/hub-test--hub pks "20261001T100000" "Ethics" body)))
      (should-error (my/hub-test--add note (my/hub-test--label hub) "x") :type 'user-error)
      (should (string-suffix-p body (my/hub-test--read hub))))))

(ert-deftest my/hub-test-command-new-hub ()
  "A new hub: a Denote note in the hub folder with the hub keyword, its
description in bold, the entry one blank line below."
  (my/hub-test--with-notes
    (let ((note (my/hub-test--note pks "20261003T100000" "Hume")))
      (my/hub-test--add note my/denote-hub-new-label "Empiricism" "British empiricists" "")
      (let ((hubs (my/denote-hub-files)))
        (should (= (length hubs) 1))
        (should (string-prefix-p pks (car hubs)))
        (should (string-suffix-p "\n*British empiricists*\n\n- [[denote:20261003T100000][Hume]]\n"
                                 (my/hub-test--read (car hubs))))))))

(ert-deftest my/hub-test-title-with-brackets ()
  "A note title ending in `]' gives an entry Org reads as one link, and
its description is still found."
  (my/hub-test--with-notes
    (let ((note (my/hub-test--note pks "20261003T100000" "Hume [draft]"))
          (hub (my/hub-test--hub pks "20261001T100000" "Ethics" "")))
      (my/hub-test--add note (my/hub-test--label hub) "custom")
      (let ((entry (car (cdr (car (my/denote-hub-membership note))))))
        (should (string-prefix-p (concat "- " (org-link-make-string "denote:20261003T100000" "Hume [draft]"))
                                 entry))
        (should (equal (my/denote-hub--entry-description entry) "custom"))))))

(provide 'test-denote-hubs)
;;; test-denote-hubs.el ends here
