;;; test-sentence-capitals.el --- ERT tests for 304-sentence-capitals -*- lexical-binding: t; -*-

;; Tests: 304-sentence-capitals 000-core

;;; Commentary:

;; 304-sentence-capitals gives the first word of a sentence its capital
;; letter while typing in Org, through the captain package.  It changes
;; the text being written, so these tests type through
;; `self-insert-command' with `post-self-insert-hook' as in a session
;; and read the buffer: where a sentence starts (paragraph, item, title,
;; after . ? !), where it does not (abbreviations, one letter, ordinals,
;; ellipsis), what is left alone (code, links, keywords, tables, a word
;; with a capital), the options, the owner's abbreviations file and the
;; switch.  Skipped without captain installed.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-sentence-capitals.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "304-sentence-capitals")

(defun my/sc-test-type (text)
  "Type TEXT character by character with self-inserting commands."
  (dolist (char (string-to-list text))
    (let ((last-command-event char))
      (self-insert-command 1))))

(defmacro my/sc-test-with-file (&rest body)
  "Run BODY with the abbreviations file in a new temporary folder."
  (declare (indent 0))
  `(let* ((folder (make-temp-file "mypks-sc-" t))
          (my/sentence-capitals-abbreviations-file
           (expand-file-name "dictionaries/sentence-abbreviations" folder))
          (my/sentence-capitals--cache nil))
     (unwind-protect
         (progn ,@body)
       (delete-directory folder t)
       (setq my/sentence-capitals--cache nil))))

(defun my/sc-test-typed (before text &optional after)
  "Return the buffer after typing TEXT between BEFORE and AFTER in Org.
Newlines shown as |, so that a failure prints on one line.  Skips the
test without captain."
  (unless (locate-library "captain")
    (ert-skip "captain is not installed"))
  (my/sc-test-with-file
    (with-temp-buffer
      (org-mode)
      (insert before (or after ""))
      (goto-char (1+ (length before)))
      (my/sc-test-type text)
      (replace-regexp-in-string "\n" "|" (buffer-string)))))

;; ============================================================
;; WHERE A SENTENCE STARTS
;; ============================================================

(ert-deftest my/sc-test-sentence-starts ()
  "The first word of a paragraph and the word after . ? ! get a capital."
  (should (equal (my/sc-test-typed "" "kot jest. pies jest? tak! no ")
                 "Kot jest. Pies jest? Tak! No "))
  (should (equal (my/sc-test-typed "Ala ma kota.\n\n" "nowy akapit ")
                 "Ala ma kota.||Nowy akapit "))
  ;; A line break inside a paragraph after a full stop.
  (should (equal (my/sc-test-typed "Ala ma kota.\n" "dalej ")
                 "Ala ma kota.|Dalej "))
  ;; An opening quotation mark before the word.
  (should (equal (my/sc-test-typed "" "„tak. „nie ")
                 "„Tak. „Nie ")))

(ert-deftest my/sc-test-word-with-a-capital-left-alone ()
  "A word that already holds a capital letter is not changed."
  (should (equal (my/sc-test-typed "Ala ma kota. " "iPhone ")
                 "Ala ma kota. iPhone ")))

(ert-deftest my/sc-test-no-sentence-end ()
  "After an abbreviation, one letter, a short ordinal, an ellipsis: as typed."
  (should (equal (my/sc-test-typed "" "to np. kot, m.in. pies ")
                 "To np. kot, m.in. pies "))
  ;; Case does not matter, and the abbreviation itself starts a sentence.
  (should (equal (my/sc-test-typed "Tak. " "np. kot ") "Tak. Np. kot "))
  (should (equal (my/sc-test-typed "" "e.g. this ") "E.g. this "))
  (should (equal (my/sc-test-typed "" "J. kowalski ") "J. kowalski "))
  (should (equal (my/sc-test-typed "" "w 2. rozdziale ") "W 2. rozdziale "))
  (should (equal (my/sc-test-typed "" "XX. wiek ") "XX. wiek "))
  (should (equal (my/sc-test-typed "" "tak... no ") "Tak... no "))
  (should (equal (my/sc-test-typed "" "tak… no ") "Tak… no "))
  (should (equal (my/sc-test-typed "" "(kot itd.) potem ") "(Kot itd.) potem ")))

(ert-deftest my/sc-test-year-ends-a-sentence ()
  "A number of four digits is no ordinal: the full stop after it ends a sentence."
  (should (equal (my/sc-test-typed "" "było w 2020. potem ")
                 "Było w 2020. Potem ")))

(ert-deftest my/sc-test-headings-and-items ()
  "The first word of a title and of an item, after a TODO keyword or a check box."
  (should (equal (my/sc-test-typed "* " "nagłówek. drugi ") "* Nagłówek. Drugi "))
  (should (equal (my/sc-test-typed "* TODO " "kupić mleko ") "* TODO Kupić mleko "))
  (should (equal (my/sc-test-typed "* Nagłówek\n" "tekst ") "* Nagłówek|Tekst "))
  (should (equal (my/sc-test-typed "- " "punkt ") "- Punkt "))
  (should (equal (my/sc-test-typed "- [ ] " "zadanie ") "- [ ] Zadanie "))
  (should (equal (my/sc-test-typed "- jeden\n- " "dwa ") "- jeden|- Dwa ")))

(ert-deftest my/sc-test-options ()
  "The options take items and titles out; sentences inside them stay."
  (let ((my/sentence-capitals-in-lists nil))
    (should (equal (my/sc-test-typed "- " "pierwszy. drugi ")
                   "- pierwszy. Drugi ")))
  (let ((my/sentence-capitals-in-headings nil))
    (should (equal (my/sc-test-typed "* " "tytuł. drugi ")
                   "* tytuł. drugi "))))

(ert-deftest my/sc-test-not-prose-left-alone ()
  "Code, keywords, drawers, comments, tables and links are not prose."
  (should (equal (my/sc-test-typed "#+title: " "tytuł ") "#+title: tytuł "))
  (should (equal (my/sc-test-typed "#+begin_src emacs-lisp\n" "kod. kod " "\n#+end_src\n")
                 "#+begin_src emacs-lisp|kod. kod |#+end_src|"))
  (should (equal (my/sc-test-typed "#+begin_example\n" "a. b " "\n#+end_example\n")
                 "#+begin_example|a. b |#+end_example|"))
  (should (equal (my/sc-test-typed ":PROPERTIES:\n:X: " "a. b " "\n:END:\n")
                 ":PROPERTIES:|:X: a. b |:END:|"))
  (should (equal (my/sc-test-typed "# " "uwaga. druga " "\n") "# uwaga. druga |"))
  (should (equal (my/sc-test-typed "| " "komórka " " |\n") "| komórka  ||"))
  (should (equal (my/sc-test-typed "Tekst [[https://x.pl][opis. " "inny " "]] dalej")
                 "Tekst [[https://x.pl][opis. inny ]] dalej"))
  (should (equal (my/sc-test-typed "Tekst =kod. " "inny" "= dalej")
                 "Tekst =kod. inny= dalej")))

(ert-deftest my/sc-test-org-buffers-only ()
  "captain is turned on in Org buffers, not in others."
  (skip-unless (locate-library "captain"))
  (with-temp-buffer
    (text-mode)
    (my/sc-test-type "kot. pies ")
    (should (equal (buffer-string) "kot. pies "))
    (should-not (bound-and-true-p captain-mode))))

;; ============================================================
;; THE OWNER'S ABBREVIATIONS
;; ============================================================

(defun my/sc-test-file-text ()
  "Return the abbreviations file's text without its comment lines."
  (with-temp-buffer
    (insert-file-contents (expand-file-name my/sentence-capitals-abbreviations-file))
    (flush-lines "^#" (point-min) (point-max))
    (buffer-string)))

(ert-deftest my/sc-test-continues-p ()
  "Which text before a full stop does not end a sentence."
  (my/sc-test-with-file
    (dolist (token '("np." "Np." "(np." "m.in." "itd.)" "a." "2." "123." "XIV." "tak..." "tak…"))
      (should (my/sentence-capitals--continues-p token)))
    (dolist (token '("kot." "2020." "kot?" "kot!" "kot.”"))
      (should-not (my/sentence-capitals--continues-p token)))))

(ert-deftest my/sc-test-add-abbreviation ()
  "An abbreviation added is written once, with the union line for git."
  (my/sc-test-with-file
    (my/sentence-capitals-add-abbreviation "Abc.")
    (should (equal (my/sc-test-file-text) "abc.\n"))
    (should (member "abc." (my/sentence-capitals-abbreviations)))
    (should (my/sentence-capitals--continues-p "abc."))
    ;; Once only.
    (my/sentence-capitals-add-abbreviation "abc.")
    (should (equal (my/sc-test-file-text) "abc.\n"))
    ;; A header for whoever opens the file.
    (with-temp-buffer
      (insert-file-contents my/sentence-capitals-abbreviations-file)
      (should (looking-at "# Abbreviations")))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name ".gitattributes"
                         (file-name-directory my/sentence-capitals-abbreviations-file)))
      (should (string-match-p "^sentence-abbreviations merge=union$" (buffer-string))))))

(ert-deftest my/sc-test-git-merge-by-union ()
  "000-core's `my/git-merge-by-union': the line once, also into an
existing .gitattributes; a new one starts with a comment naming the
writer; a file name with a space is left alone."
  (my/sc-test-with-file
    (let* ((folder (file-name-directory my/sentence-capitals-abbreviations-file))
           (attributes (expand-file-name ".gitattributes" folder))
           (read (lambda ()
                   (with-temp-buffer
                     (insert-file-contents attributes)
                     (buffer-string)))))
      (make-directory folder t)
      (with-temp-file attributes (insert "*.org diff"))
      (my/git-merge-by-union (expand-file-name "list" folder) "x.el")
      (my/git-merge-by-union (expand-file-name "list" folder) "x.el")
      (should (equal (funcall read) "*.org diff\nlist merge=union\n"))
      (my/git-merge-by-union (expand-file-name "a list" folder))
      (should (equal (funcall read) "*.org diff\nlist merge=union\n"))
      (delete-file attributes)
      (my/git-merge-by-union (expand-file-name "list" folder) "x.el")
      (should (equal (funcall read)
                     "# Written by x.el: lines added on two machines are both kept.\nlist merge=union\n")))))

(ert-deftest my/sc-test-add-abbreviation-refused ()
  "Not one word with a full stop: refused, nothing written."
  (my/sc-test-with-file
    (dolist (bad '("abc" "a b." "." "12."))
      (should-error (my/sentence-capitals-add-abbreviation bad) :type 'user-error))
    (should-not (file-exists-p my/sentence-capitals-abbreviations-file))))

(ert-deftest my/sc-test-remove-abbreviation ()
  "The owner's own is deleted; a built-in one is taken out by a line; adding
that one back deletes the line."
  (my/sc-test-with-file
    (my/sentence-capitals-add-abbreviation "abc.")
    (my/sentence-capitals-remove-abbreviation "abc.")
    (should (equal (my/sc-test-file-text) ""))
    (should-not (member "abc." (my/sentence-capitals-abbreviations)))
    (my/sentence-capitals-remove-abbreviation "np.")
    (should (equal (my/sc-test-file-text) "-np.\n"))
    (should-not (my/sentence-capitals--continues-p "np."))
    (my/sentence-capitals-add-abbreviation "np.")
    (should (equal (my/sc-test-file-text) ""))
    (should (my/sentence-capitals--continues-p "np."))
    (should-error (my/sentence-capitals-remove-abbreviation "xyz.") :type 'user-error)))

(ert-deftest my/sc-test-file-read-again-when-changed ()
  "A change made on disk (by hand, by a pull) is seen at the next check."
  (my/sc-test-with-file
    (should-not (my/sentence-capitals--continues-p "qq."))
    (make-directory (file-name-directory my/sentence-capitals-abbreviations-file) t)
    (with-temp-file my/sentence-capitals-abbreviations-file
      (insert "# hand\nqq.\n-np.\n\n"))
    ;; A modification time other than the one cached.
    (set-file-times my/sentence-capitals-abbreviations-file (time-add nil 10))
    (should (my/sentence-capitals--continues-p "qq."))
    (should-not (my/sentence-capitals--continues-p "np."))))

(ert-deftest my/sc-test-typing-after-new-abbreviation ()
  "After adding one, the word after it keeps its small letter."
  (skip-unless (locate-library "captain"))
  (my/sc-test-with-file
    (my/sentence-capitals-add-abbreviation "wzgl.")
    (with-temp-buffer
      (org-mode)
      (my/sc-test-type "to wzgl. proste ")
      (should (equal (buffer-string) "To wzgl. proste ")))))

(ert-deftest my/sc-test-default-before-point ()
  "The word before point is offered when it ends in a full stop."
  (with-temp-buffer
    (insert "To (Tzw. ")
    (should (equal (my/sentence-capitals--default-before-point) "tzw.")))
  (with-temp-buffer
    (insert "To kot ")
    (should-not (my/sentence-capitals--default-before-point))))

;; ============================================================
;; THE SWITCH
;; ============================================================

(ert-deftest my/sc-test-switch-and-buffer-toggle ()
  "Off: no hook, captain off in Org buffers; on again: both back.  One
buffer alone with the toggle."
  (skip-unless (locate-library "captain"))
  (with-temp-buffer
    (org-mode)
    (should captain-mode)
    (unwind-protect
        (progn
          (my/sentence-capitals-mode -1)
          (should-not (memq #'my/sentence-capitals--setup org-mode-hook))
          (should-not captain-mode)
          (my/sentence-capitals-mode 1)
          (should (memq #'my/sentence-capitals--setup org-mode-hook))
          (should captain-mode)
          (my/sentence-capitals-toggle-buffer)
          (should-not captain-mode)
          (my/sc-test-type "kot. pies ")
          (should (equal (buffer-string) "kot. pies "))
          (my/sentence-capitals-toggle-buffer)
          (should captain-mode))
      (my/sentence-capitals-mode 1))))

(ert-deftest my/sc-test-buffer-toggle-org-only ()
  "Outside Org the toggle says so."
  (with-temp-buffer
    (fundamental-mode)
    (should-error (my/sentence-capitals-toggle-buffer) :type 'user-error)))

;;; test-sentence-capitals.el ends here
