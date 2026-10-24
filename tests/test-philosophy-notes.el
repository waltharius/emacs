;;; test-philosophy-notes.el --- ERT tests for the philosophy notes of 19-philosophy-notes -*- lexical-binding: t; -*-

;; Tests: 19-philosophy-notes

;;; Commentary:

;; 19-philosophy-notes.el creates five types of philosophy note in the
;; pks silo, each with its type keyword, the epoch keywords chosen and a
;; scaffold of headings: TESTING.org, *Every module tested*, part 3.  On
;; real files in a temporary notes folder; Denote runs, the prompts of
;; the commands are answered.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-philosophy-notes.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "19-philosophy-notes")

(defvar denote-directory)

(defmacro my/phil-test--with-silos (&rest body)
  "Run BODY with a notes folder `notes' (the Denote folder) and its silo `pks'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-phil-" t)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (pks (file-name-as-directory (expand-file-name "pks" notes)))
          (my-notes-dir notes)
          (my-notes-pks pks)
          (denote-directory notes)
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

(defun my/phil-test--create (command title epochs)
  "Run COMMAND answering TITLE and the epoch keywords EPOCHS; return the
one note in the pks silo and its text."
  (cl-letf (((symbol-function 'read-string) (lambda (&rest _) title))
            ((symbol-function 'completing-read-multiple) (lambda (&rest _) epochs)))
    (funcall command)))

(defun my/phil-test--notes (dir)
  "Return the Org files in DIR."
  (directory-files dir t "\\.org\\'"))

(defun my/phil-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest my/phil-test-each-type ()
  "Each of the five commands makes one note in pks, never in the notes
folder itself, with its type keyword first, the chosen epoch, its
scaffold of headings, saved, and no line of spaces.  Keywords are in
Denote's order."
  (dolist (case '((my/philosophy-note-literatura "literatura" "* Streszczenie (moimi słowami)")
                  (my/philosophy-note-pojecie "pojęcie" "* Napięcia i krytyka")
                  (my/philosophy-note-mysliciel "myśliciel" "* Centralny projekt")
                  (my/philosophy-note-problem "problem" "* Pytania otwarte")
                  (my/philosophy-note-mapa "mapa" "* Wielkie pytania okresu")))
    (my/phil-test--with-silos
      (my/phil-test--create (nth 0 case) "Kant o wolności" '("nowożytność"))
      (let* ((files (my/phil-test--notes pks))
             (file (car files))
             (text (my/phil-test--read file)))
        (should (= (length files) 1))
        (should-not (my/phil-test--notes notes))
        ;; In Denote's order (`denote-sort-keywords'), not the order given.
        (should (equal (sort (denote-extract-keywords-from-path file) #'string<)
                       (sort (list (nth 1 case) "nowożytność") #'string<)))
        (should (string-search "#+title:      Kant o wolności" text))
        (should (string-search (concat "\n" (nth 2 case) "\n") text))
        (should-not (string-match-p "^[ \t]+$" text))
        (should-not (buffer-modified-p (find-buffer-visiting file)))))))

(ert-deftest my/phil-test-keywords-optional-and-new ()
  "No epoch keyword is fine (the type keyword alone); a new keyword not
in the list is accepted."
  (my/phil-test--with-silos
    (my/phil-test--create #'my/philosophy-note-problem "Wolna wola" '(""))
    (my/phil-test--create #'my/philosophy-note-problem "Determinizm" '("fenomenologia"))
    (should (equal (sort (mapcar #'denote-extract-keywords-from-path (my/phil-test--notes pks))
                         (lambda (a b) (< (length a) (length b))))
                   '(("problem") ("fenomenologia" "problem"))))))

(ert-deftest my/phil-test-keywords-known-to-denote ()
  "The type and epoch keywords are offered by Denote before any note
carries them."
  (dolist (keyword (append my/philosophy-type-keywords my/philosophy-epoch-keywords))
    (should (member keyword denote-known-keywords))))

(provide 'test-philosophy-notes)
;;; test-philosophy-notes.el ends here
