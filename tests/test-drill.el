;;; test-drill.el --- ERT tests for flashcards of 43-drill -*- lexical-binding: t; -*-

;; Tests: 43-drill

;;; Commentary:

;; 43-drill.el finds card decks by their Denote keyword, inserts cards in
;; org-drill's format, and saves the decks a review session touched, also
;; when the session is quit: TESTING.org, *Every module tested*, part 3.
;; On real files in a temporary notes folder.  org-drill's own review
;; (keys read at each card) is not run; a session is played by a function
;; that changes the deck and then quits or fails.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-drill.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "43-drill")
(require 'denote)

(defvar denote-directory)

(defmacro my/drill-test--with-notes (&rest body)
  "Run BODY in a fresh notes folder `notes' (the Denote folder)."
  (declare (indent 0))
  `(let* ((notes (file-name-as-directory (make-temp-file "mypks-drill-" t)))
          (my-notes-dir notes)
          (denote-directory notes)
          (inhibit-message t))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p notes f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory notes t))))

(defun my/drill-test--write (file text)
  "Write TEXT to FILE; return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  file)

(defun my/drill-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/drill-test--insert (text search question)
  "In an Org buffer holding TEXT, put point after SEARCH (or at the top
when nil), insert a card with QUESTION, and return the buffer's text
and the line point is on."
  (with-temp-buffer
    (insert text)
    (org-mode)
    (goto-char (point-min))
    (when search (search-forward search))
    (my/drill-insert-card question)
    (list (buffer-string)
          (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))

;; ============================================================
;; DECKS
;; ============================================================

(ert-deftest my/drill-test-card-files ()
  "Decks are the Org notes with the deck keyword in their file name, in
any silo; a Markdown note with it and a note without it are not."
  (my/drill-test--with-notes
    (let ((a (my/drill-test--write (expand-file-name "pks/20261001T100000--kant__karty.org" notes) "* A\n"))
          (b (my/drill-test--write (expand-file-name "docu/20261002T100000--emacs__karty_emacs.org" notes) "* B\n")))
      (my/drill-test--write (expand-file-name "pks/20261003T100000--md__karty.md" notes) "# C\n")
      (my/drill-test--write (expand-file-name "pks/20261004T100000--kartoteka__kartoteka.org" notes) "* D\n")
      (should (equal (sort (my/drill-card-files) #'string<) (sort (list a b) #'string<))))))

(ert-deftest my/drill-test-no-decks ()
  "Reviewing all decks with none refuses, saying which keyword is missing."
  (my/drill-test--with-notes
    (let ((err (should-error (my/drill-all) :type 'user-error)))
      (should (string-search "karty" (cadr err))))))

;; ============================================================
;; WRITING CARDS
;; ============================================================

(ert-deftest my/drill-test-insert-under-heading ()
  "Under an ordinary heading a card becomes its last child, tagged, with
the answer heading one level deeper; point is in the answer."
  (pcase-let ((`(,text ,line)
               (my/drill-test--insert "* Kant\nIntro.\n** Older card :drill:\nQ\n" "Intro." "Co to jest imperatyw?")))
    (should (string-match-p
             "\\*\\* Older card :drill:\nQ\n\\*\\* Karta +:drill:\nCo to jest imperatyw\\?\n\n\\*\\*\\* Odpowiedź\n\\'"
             text))
    (should (equal line ""))))

(ert-deftest my/drill-test-insert-inside-card ()
  "From inside a card, its answer included, the new card is a sibling
after it, not a child of the answer."
  (pcase-let ((`(,text ,_)
               (my/drill-test--insert "* Deck\n** Karta :drill:\nQ1\n*** Odpowiedź\nA1\n** Other\n"
                                      "A1" "Q2")))
    (should (string-search "*** Odpowiedź\nA1\n** Karta" text))
    (should (string-search "Q2\n\n*** Odpowiedź\n** Other\n" text))))

(ert-deftest my/drill-test-insert-before-first-heading ()
  "Before the first heading the card is a top-level heading at the end."
  (pcase-let ((`(,text ,_) (my/drill-test--insert "#+title: Deck\n* Kant\nText." nil "Q")))
    (should (string-suffix-p "* Kant\nText.\n* Karta :drill:\nQ\n\n** Odpowiedź\n"
                             (replace-regexp-in-string "Karta +:" "Karta :" text)))))

(ert-deftest my/drill-test-insert-refuses-and-warns ()
  "An empty question is refused; brackets in a question are mentioned,
since org-drill hides them as a cloze."
  (with-temp-buffer
    (org-mode)
    (should-error (my/drill-insert-card "  ") :type 'user-error)
    (should (equal (buffer-string) ""))
    (let ((shown nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (format &rest args) (push (apply #'format format args) shown))))
        (my/drill-insert-card "Stolica [Francji]"))
      (should (string-search "cloze" (car shown))))))

;; ============================================================
;; SAVING AFTER A SESSION
;; ============================================================

(ert-deftest my/drill-test-run-saves-even-when-quit ()
  "A session that changed a deck and was then quit (C-g) or failed still
leaves the deck saved; decks it did not touch are not written."
  (my/drill-test--with-notes
    (let* ((a (my/drill-test--write (expand-file-name "a__karty.org" notes) "* Karta :drill:\nQ\n"))
           (b (my/drill-test--write (expand-file-name "b__karty.org" notes) "* Karta :drill:\nQ\n"))
           (b-time (file-attribute-modification-time (file-attributes b))))
      (find-file-noselect b)
      (dolist (ending (list (lambda () (signal 'quit nil)) (lambda () (error "Failed"))))
        (cl-letf (((symbol-function 'my/drill--ensure-package) #'ignore))
          (ignore-errors
            (condition-case nil
                (my/drill--run (lambda ()
                                 (with-current-buffer (find-file-noselect a)
                                   (goto-char (point-max))
                                   (insert ":PROPERTIES:\n:ID: x\n:END:\n"))
                                 (funcall ending))
                               (list a b))
              (quit nil))))
        (should-not (buffer-modified-p (find-buffer-visiting a))))
      (should (string-search ":ID: x" (my/drill-test--read a)))
      (should (equal (file-attribute-modification-time (file-attributes b)) b-time)))))

(ert-deftest my/drill-test-save-buffers-count ()
  "Only modified buffers are saved, and they are counted."
  (my/drill-test--with-notes
    (let ((a (my/drill-test--write (expand-file-name "a.org" notes) "x\n"))
          (b (my/drill-test--write (expand-file-name "b.org" notes) "y\n")))
      (with-current-buffer (find-file-noselect a) (insert "z"))
      (find-file-noselect b)
      (should (= (my/drill--save-buffers (list a b (expand-file-name "c.org" notes))) 1))
      (should (equal (my/drill-test--read a) "zx\n")))))

;; ============================================================
;; THE KEYWORD AND THE SWITCH
;; ============================================================

(ert-deftest my/drill-test-keyword-registration ()
  "On, the deck keyword is offered by Denote; off, the module takes back
only a keyword it added itself."
  (let ((denote-known-keywords (remove "karty" denote-known-keywords))
        (my/drill--registered-keyword nil))
    (unwind-protect
        (progn
          (my/drill-mode 1)
          (should (member "karty" denote-known-keywords))
          (my/drill-mode -1)
          (should-not (member "karty" denote-known-keywords))
          (push "karty" denote-known-keywords)
          (my/drill-mode 1)
          (my/drill-mode -1)
          (should (member "karty" denote-known-keywords)))
      (my/drill-mode 1))))

(provide 'test-drill)
;;; test-drill.el ends here
