;;; test-maintenance.el --- ERT tests for keyword renaming and the checks of 826-maintenance -*- lexical-binding: t; -*-

;; Tests: 826-maintenance 826b-maintenance-repairs

;;; Commentary:

;; 826-maintenance.el renames or removes a keyword across the collection
;; -- the front matter and the file name of every note using it -- and
;; reports broken `denote:' links: the fifth module of TESTING.org,
;; *Every module tested*, part 3.  On real files in a temporary notes
;; folder; the review list is driven with its own keys (y, n).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-maintenance.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "205-notes" "212-transient" "227-denote-identifiers" "826-maintenance"
                      "826b-maintenance-repairs")

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/maint-test--with-notes (&rest body)
  "Run BODY in a fresh notes folder with silos pks and docu.
Binds `root', `pks', `docu'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-maint-" t)))
          (pks (file-name-as-directory (expand-file-name "pks" root)))
          (docu (file-name-as-directory (expand-file-name "docu" root)))
          (my-notes-dir root)
          (my/denote-silo-directories (list pks docu))
          (inhibit-message t))
     (dolist (d (list pks docu)) (make-directory d t))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (when (get-buffer my/maintenance--keyword-buffer)
         (kill-buffer my/maintenance--keyword-buffer))
       (delete-directory root t))))

(defun my/maint-test--note (dir name keywords &optional body)
  "Write the note NAME.org in DIR with #+filetags: KEYWORDS and BODY."
  (let ((file (expand-file-name (concat name ".org") dir)))
    (with-temp-file file
      (insert "#+title:      A title\n"
              (if keywords (format "#+filetags:   :%s:\n" (string-join keywords ":")) "")
              "#+identifier: " (substring name 0 15) "\n\n"
              (or body "Body text.\n")))
    file))

(defun my/maint-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

;; ============================================================
;; FILE NAMES AND FRONT MATTER
;; ============================================================

(ert-deftest my/maint-test-keywords-from-file-name ()
  "Keywords are read after the first double underscore, nothing else."
  (should (equal (my/maintenance-file-keywords "/n/20261023T100000--a-title__kant_ethics.org")
                 '("kant" "ethics")))
  (should (null (my/maintenance-file-keywords "/n/20261023T100000--a-title.org")))
  (should (equal (my/maintenance-file-keywords "/n/20261023T100000==1a2--a_title__k.org")
                 '("k"))))

(ert-deftest my/maint-test-new-name-rebuilds-only-keywords ()
  "Identifier, signature, title and extension are carried across as they
are; only the keyword field changes, and goes when no keyword is left."
  (should (equal (my/maintenance--new-file-name
                  "/n/pks/20261023T100000==1a2--a-title__kant.org" '("ethics" "kant"))
                 "/n/pks/20261023T100000==1a2--a-title__ethics_kant.org"))
  (should (equal (my/maintenance--new-file-name "/n/pks/20261023T100000--a-title__kant.org" nil)
                 "/n/pks/20261023T100000--a-title.org"))
  ;; A single underscore in the title (a name not made by Denote) stays
  ;; part of the title: the keyword field begins at the double one.
  (should (equal (my/maintenance--new-file-name "/n/pks/20261023T100000--a_b__kant.org" '("x"))
                 "/n/pks/20261023T100000--a_b__x.org")))

(ert-deftest my/maint-test-normalize-and-sort ()
  "A keyword takes the shape a file name can hold; the list is sorted."
  (should (equal (my/maintenance--normalize-keyword " Kant Ethics_x ") "kant-ethics-x"))
  (should (null (my/maintenance--normalize-keyword "  ")))
  (let ((denote-sort-keywords t))
    (should (equal (my/maintenance--sort-keywords '("zeta" "alfa")) '("alfa" "zeta")))))

(ert-deftest my/maint-test-set-keywords-writes-both-places ()
  "The keywords go into #+filetags: and the file name; the rest of the
note is byte for byte the same."
  (my/maint-test--with-notes
    (let* ((file (my/maint-test--note pks "20261023T100000--a-title__kant" '("kant")
                                      "Line one.\n\n* Heading\n#+filetags: :inside:\n"))
           (new (my/maintenance--set-keywords file '("ethics" "kant"))))
      (should (equal new (expand-file-name "20261023T100000--a-title__ethics_kant.org" pks)))
      (should-not (file-exists-p file))
      (should (equal (my/maint-test--read new)
                     (concat "#+title:      A title\n#+filetags:   :ethics:kant:\n"
                             "#+identifier: 20261023T100000\n\n"
                             "Line one.\n\n* Heading\n#+filetags: :inside:\n"))))))

(ert-deftest my/maint-test-filetags-added-and-removed ()
  "A note without #+filetags: gets one above #+identifier:, even with a
#+filetags: line far down in its body, which is left alone; removing the
last keyword removes the line."
  (my/maint-test--with-notes
    (let* ((file (my/maint-test--note pks "20261023T100000--a-title" nil
                                      (concat (make-string 5000 ?x) "\n#+filetags: :deep:\n")))
           (tagged (my/maintenance--set-keywords file '("kant"))))
      (should (string-match-p "#\\+filetags:  :kant:\n#\\+identifier:" (my/maint-test--read tagged)))
      (should (string-match-p "#\\+filetags: :deep:" (my/maint-test--read tagged)))
      (let ((bare (my/maintenance--set-keywords tagged nil)))
        (should (equal bare file))
        (should (string-prefix-p "#+title:      A title\n#+identifier:" (my/maint-test--read bare)))
        (should (string-match-p "#\\+filetags: :deep:" (my/maint-test--read bare)))))))

(ert-deftest my/maint-test-filetags-example-early-in-body ()
  "A short note without its own #+filetags: but with one in an example
right below the front matter: the keywords go into the front matter,
the example is left exactly as it was.  (Until 2026-10-24 the search
reached 4096 characters and rewrote the example.)"
  (my/maint-test--with-notes
    (let* ((example "#+begin_src org\n#+filetags: :przyklad:\n#+end_src\n")
           (file (my/maint-test--note pks "20261023T100000--a-title" nil example))
           (tagged (my/maintenance--set-keywords file '("kant")))
           (text (my/maint-test--read tagged)))
      (should (string-match-p "#\\+filetags:  :kant:\n#\\+identifier:" text))
      (should (string-search example text)))))

(ert-deftest my/maint-test-set-keywords-refuses-unsaved-buffer ()
  "Unsaved changes in the note's buffer: refused, nothing written."
  (my/maint-test--with-notes
    (let* ((file (my/maint-test--note pks "20261023T100000--a-title__kant" '("kant")))
           (text (my/maint-test--read file)))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (insert "unsaved"))
      (should-error (my/maintenance--set-keywords file '("ethics")) :type 'user-error)
      (should (equal (my/maint-test--read file) text)))))

(ert-deftest my/maint-test-set-keywords-refuses-taken-name ()
  "The new name taken by another note: refused, both notes unchanged."
  (my/maint-test--with-notes
    (let* ((file (my/maint-test--note pks "20261023T100000--a-title__kant" '("kant")))
           (other (my/maint-test--note pks "20261023T100000--a-title__ethics" '("ethics")
                                       "Other note.\n"))
           (text (my/maint-test--read file)))
      (should-error (my/maintenance--set-keywords file '("ethics")) :type 'user-error)
      (should (equal (my/maint-test--read file) text))
      (should (string-match-p "Other note" (my/maint-test--read other))))))

(ert-deftest my/maint-test-read-only-buffer-follows ()
  "A note open read-only (the preview's view-mode): renamed all the
same, and its buffer follows it, still read-only, showing the new tags."
  (my/maint-test--with-notes
    (let* ((file (my/maint-test--note pks "20261023T100000--a-title__kant" '("kant")))
           (buffer (find-file-noselect file)))
      (with-current-buffer buffer (view-mode 1))
      (let ((new (my/maintenance--set-keywords file '("ethics"))))
        (with-current-buffer buffer
          (should (equal buffer-file-name new))
          (should buffer-read-only)
          (should (string-match-p ":ethics:" (buffer-string))))))))

;; ============================================================
;; RENAMING A KEYWORD ACROSS THE COLLECTION
;; ============================================================

(defun my/maint-test--decide (keys)
  "In the review list, press KEYS (a list of \"y\" and \"n\") from the top."
  (with-current-buffer my/maintenance--keyword-buffer
    (goto-char (point-min))
    (dolist (key keys)
      (if (equal key "y") (my/keyword-rename-apply) (my/keyword-rename-skip)))))

(ert-deftest my/maint-test-rename-only-what-is-confirmed ()
  "y renames the note at point, n leaves it; nothing else is written."
  (my/maint-test--with-notes
    (let* ((a (my/maint-test--note pks "20261023T100000--a__kant" '("kant")))
           (b (my/maint-test--note docu "20261023T110000--b__kant" '("kant")))
           (c (my/maint-test--note pks "20261023T120000--c__hegel" '("hegel")))
           (a-text (my/maint-test--read a))
           (c-text (my/maint-test--read c)))
      (my/maintenance-rename-keyword "kant" "kant-ethics")
      ;; Rows sorted by path: docu/b first, then pks/a.
      (my/maint-test--decide '("y" "n"))
      (should (file-exists-p (expand-file-name "20261023T110000--b__kant-ethics.org" docu)))
      (should-not (file-exists-p b))
      (should (equal (my/maint-test--read a) a-text))
      (should (equal (my/maint-test--read c) c-text)))))

(ert-deftest my/maint-test-rename-merges-into-existing ()
  "A note with both spellings keeps one, not two."
  (my/maint-test--with-notes
    (my/maint-test--note pks "20261023T100000--a__ethic_ethics" '("ethic" "ethics"))
    (my/maintenance-rename-keyword "ethic" "ethics")
    (my/maint-test--decide '("y"))
    (should (file-exists-p (expand-file-name "20261023T100000--a__ethics.org" pks)))))

(ert-deftest my/maint-test-remove-keyword ()
  "An empty replacement removes the keyword from name and front matter."
  (my/maint-test--with-notes
    (my/maint-test--note pks "20261023T100000--a__kant_temp" '("kant" "temp"))
    (my/maintenance-rename-keyword "temp" "")
    (my/maint-test--decide '("y"))
    (let ((new (expand-file-name "20261023T100000--a__kant.org" pks)))
      (should (file-exists-p new))
      (should (string-match-p "#\\+filetags:   :kant:\n" (my/maint-test--read new))))))

;; ============================================================
;; BROKEN LINKS
;; ============================================================

(ert-deftest my/maint-test-broken-links-found ()
  "A link to an identifier no file has is reported, a link with a heading
suffix to an existing note is not."
  (my/maint-test--with-notes
    (my/maint-test--note pks "20261023T100000--a" nil
                         "[[denote:20261023T110000::*Heading][ok]] [[denote:20991231T000000][gone]]\n")
    (my/maint-test--note pks "20261023T110000--b" nil)
    (let (groups)
      (cl-letf (((symbol-function 'my/maintenance--report)
                 (lambda (_name _intro g) (setq groups g) t)))
        (my/denote-check-broken-links))
      (should (= 1 (length groups)))
      (should (string-prefix-p "20991231T000000" (car (car groups)))))))

(ert-deftest my/maint-test-menu-columns-and-switch ()
  "The Maintenance menu has its reports and its repairs; K, the keyword
repair, follows the switch of 826b-maintenance-repairs, the reports stay."
  (should (eq (my/transient--layout-command (transient-get-suffix 'my/notes-maintenance-menu "k"))
              #'my/maintenance-keyword-inventory))
  (should (eq (my/transient--layout-command (transient-get-suffix 'my/notes-maintenance-menu "K"))
              #'my/maintenance-rename-keyword))
  (unwind-protect
      (progn
        (my/maintenance-repairs-mode -1)
        (should-not (ignore-errors (transient-get-suffix 'my/notes-maintenance-menu "K")))
        (should (transient-get-suffix 'my/notes-maintenance-menu "k")))
    (my/maintenance-repairs-mode 1))
  (should (transient-get-suffix 'my/notes-maintenance-menu "K")))

(ert-deftest my/maint-test-inventory-buttons-need-the-repairs ()
  "In the keyword inventory a keyword is a button starting its rename
only while the renaming command exists."
  (my/maint-test--with-notes
    (my/maint-test--note pks "20261025T100000--a__filozofia" '("filozofia"))
    (cl-flet ((buttons ()
                (my/maintenance-keyword-inventory)
                (with-current-buffer "*Denote Keyword Inventory*"
                  (prog1 (let ((n 0)) (goto-char (point-min))
                              (while (forward-button 1 nil nil t) (setq n (1+ n)))
                              n)
                    (kill-buffer)))))
      (should (= (buttons) 1))
      (let ((def (symbol-function 'my/maintenance-rename-keyword)))
        (unwind-protect
            (progn (fmakunbound 'my/maintenance-rename-keyword)
                   (should (= (buttons) 0)))
          (fset 'my/maintenance-rename-keyword def))))))

(provide 'test-maintenance)
;;; test-maintenance.el ends here
