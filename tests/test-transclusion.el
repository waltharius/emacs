;;; test-transclusion.el --- ERT tests for the transclusion wizard of 420-transclusion -*- lexical-binding: t; -*-

;; Tests: 420-transclusion

;;; Commentary:

;; 420-transclusion.el inserts a `#+transclude:' and `#+INCLUDE:' pair
;; for a whole note, a heading or a paragraph of another note, and for
;; the last two writes an anchor into that note (a CUSTOM_ID, a
;; <<target>>) and saves it: TESTING.org, *Every module tested*, part 3.
;; On real files in a temporary folder; org-transclusion itself runs
;; (it expands the inserted keyword).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-transclusion.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "420-transclusion")
(require 'org-transclusion)

;; ============================================================
;; FIXTURE
;; ============================================================

(defmacro my/tr-test--with-folder (&rest body)
  "Run BODY with a fresh folder `dir'."
  (declare (indent 0))
  `(let* ((dir (file-name-as-directory (make-temp-file "mypks-transclusion-" t)))
          (inhibit-message t))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p dir f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory dir t))))

(defun my/tr-test--write (file text)
  "Write TEXT to FILE; return FILE."
  (with-temp-file file (insert text))
  file)

(defun my/tr-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defconst my/tr-test--source
  (concat "#+title: Source\n\n"
          "* First\n** Notes\nFirst notes.\n\n"
          "#+begin_src org\n,* Not a heading\n#+end_src\n\n"
          "* Second\n** Notes\nSecond notes.\n")
  "A source note: two subheadings named Notes, an escaped heading in a block.")

(defun my/tr-test--wizard (file choice &rest keys)
  "Run the wizard in a new Org buffer for FILE choosing CHOICE; KEYS
answer the paragraph browser.  Return the buffer's text."
  (with-temp-buffer
    (org-mode)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt &rest _)
                 (if (string-prefix-p "Source" prompt) "Any file on disk" choice)))
              ((symbol-function 'read-file-name) (lambda (&rest _) file))
              ((symbol-function 'read-key) (lambda (&rest _) (pop keys))))
      (my/denote-transclude-insert))
    ;; org-transclusion shows the source in place of the keyword line;
    ;; collapsed again, the line as it is saved.
    (org-transclusion-remove-all)
    (buffer-substring-no-properties (point-min) (point-max))))

;; ============================================================
;; HEADINGS
;; ============================================================

(ert-deftest my/tr-test-headings ()
  "Headings are read by Org: an escaped line in a block is not one, and
two headings with the same title can each be chosen."
  (my/tr-test--with-folder
    (let* ((file (my/tr-test--write (expand-file-name "s.org" dir) my/tr-test--source))
           (displays (mapcar #'car (my/--org-file-headings file))))
      (should (equal displays '("* First" "** Notes  (line 4)" "* Second" "** Notes  (line 12)"))))))

(ert-deftest my/tr-test-heading-anchor ()
  "Choosing a heading gives it a CUSTOM_ID, saves the source and inserts
the pair; a second heading of the same title gets an id of its own; an
existing id is reused and the file not touched."
  (my/tr-test--with-folder
    (let ((file (my/tr-test--write (expand-file-name "s.org" dir) my/tr-test--source)))
      (let ((text (my/tr-test--wizard file "** Notes  (line 4)")))
        (should (string-search (format "#+transclude: [[file:%s::#notes][Source — Notes]]" file) text))
        (should (string-search (format "#+INCLUDE: \"%s::#notes\" :only-contents t" file) text)))
      ;; Three lines further down now: the drawer written above.
      (my/tr-test--wizard file "** Notes  (line 15)")
      (let ((saved (my/tr-test--read file)))
        (should (string-match-p "\\* First\n\\*\\* Notes\n:PROPERTIES:\n:CUSTOM_ID: notes\n" saved))
        (should (string-match-p "\\* Second\n\\*\\* Notes\n:PROPERTIES:\n:CUSTOM_ID: notes-2\n" saved))
        (should (string-search ",* Not a heading\n#+end_src" saved))
        (my/tr-test--wizard file "** Notes  (line 4)")
        (should (equal (my/tr-test--read file) saved))))))

(ert-deftest my/tr-test-unsaved-source-refused ()
  "A source open with unsaved changes is refused before anything is
written: the anchor would go to the wrong place and the edits be saved."
  (my/tr-test--with-folder
    (let ((file (my/tr-test--write (expand-file-name "s.org" dir) my/tr-test--source)))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (insert "#+filetags: :draft:\nAn unsaved line.\n"))
      (should-error (my/tr-test--wizard file "* Second") :type 'user-error)
      (should-error (my/tr-test--wizard file "Paragraph" ?\r) :type 'user-error)
      (should (equal (my/tr-test--read file) my/tr-test--source))
      (should (buffer-modified-p (find-buffer-visiting file))))))

;; ============================================================
;; PARAGRAPHS AND THE WHOLE NOTE
;; ============================================================

(ert-deftest my/tr-test-paragraph-anchor ()
  "Choosing a paragraph puts a <<target>> at its end and saves the
source; choosing it again reuses the target."
  (my/tr-test--with-folder
    (let ((file (my/tr-test--write (expand-file-name "p.org" dir)
                                   "#+title: Para\n\nOne paragraph.\n\nTwo paragraph.\n")))
      (let* ((text (my/tr-test--wizard file "Paragraph" ?n ?\r))
             (saved (my/tr-test--read file)))
        (should (string-match "Two paragraph\\. <<\\([a-z0-9]\\{7\\}\\)>>\n" saved))
        (let ((target (match-string 1 saved)))
          (should (string-search (format "[[file:%s::%s][Para — paragraph]]" file target) text))
          (should (string-search "One paragraph.\n" saved))
          (my/tr-test--wizard file "Paragraph" ?n ?\r)
          (should (equal (my/tr-test--read file) saved)))))))

(ert-deftest my/tr-test-whole-note-title-with-brackets ()
  "The whole note: the pair is inserted, the source untouched; a title
ending in `]' gives a link Org reads whole."
  (my/tr-test--with-folder
    (let* ((source "#+title: Draft [v2]\n\nBody.\n")
           (file (my/tr-test--write (expand-file-name "w.org" dir) source))
           (text (my/tr-test--wizard file "Whole note")))
      (should (string-search (concat "#+transclude: "
                                     (org-link-make-string (concat "file:" file) "Draft [v2]"))
                             text))
      (should (string-search (format "#+INCLUDE: \"%s\" :only-contents t" file) text))
      (should (equal (my/tr-test--read file) source)))))

(ert-deftest my/tr-test-slugify ()
  "Slugs keep letters and digits, Polish ones too, and join words by one
hyphen; nothing usable gives a generated id."
  (should (equal (my/--transclusion-slugify "  Zażółć  gęślą: jaźń! ") "zażółć-gęślą-jaźń"))
  (should (string-match-p "\\`note-[0-9]+\\'" (my/--transclusion-slugify "?!"))))

(provide 'test-transclusion)
;;; test-transclusion.el ends here
