;;; test-bold-marker.el --- ERT tests for 302b-bold-marker -*- lexical-binding: t; -*-

;; Tests: 302b-bold-marker

;;; Commentary:

;; 302b-bold-marker wraps the word or quoted phrase before point in Org
;; markers when *, ~ or = is typed right after it, and C-= moves the
;; opening marker one word left.  It changes the text being written, so
;; these tests type through `self-insert-command' with
;; `post-self-insert-hook' as in a session and read the buffer: words
;; and phrases wrapped, markup typed by hand left alone, nothing outside
;; Org or after a space, a stray quote, the expansion and its guards.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-bold-marker.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "302b-bold-marker")

(defun my/bm-test-type (text)
  "Type TEXT character by character with self-inserting commands."
  (dolist (char (string-to-list text))
    (let ((last-command-event char))
      (self-insert-command 1))))

(defmacro my/bm-test-in-org (initial &rest body)
  "Run BODY in an Org buffer holding INITIAL, point at its end."
  (declare (indent 1))
  `(with-temp-buffer
     (org-mode)
     (insert ,initial)
     (setq my/inline-marker-start nil my/inline-marker-end nil
           my/inline-marker-open-char nil)
     ,@body))

(ert-deftest my/bm-test-word-wrapped ()
  "word*, word~ and word= wrap the word; point after the closing marker."
  (my/bm-test-in-org "To jest "
    (my/bm-test-type "ważne*")
    (should (equal (buffer-string) "To jest *ważne*"))
    (should (eobp)))
  (my/bm-test-in-org "" (my/bm-test-type "kod~") (should (equal (buffer-string) "~kod~")))
  (my/bm-test-in-org "" (my/bm-test-type "stała=") (should (equal (buffer-string) "=stała="))))

(ert-deftest my/bm-test-markup-typed-by-hand-left-alone ()
  "*word* typed by hand stays *word*; it became **word**."
  (my/bm-test-in-org "To jest "
    (my/bm-test-type "*ważne*")
    (should (equal (buffer-string) "To jest *ważne*")))
  (my/bm-test-in-org ""
    (my/bm-test-type "~a~")
    (should (equal (buffer-string) "~a~"))))

(ert-deftest my/bm-test-quoted-phrase-wrapped ()
  "A trigger after a closing quote wraps the text between the quotes,
quotes outside, and point stays after the closing quote; a second press
does not wrap it again.  Until 2026-11-03 the quotes were inside."
  (my/bm-test-in-org "Powiedział "
    (my/bm-test-type "\"to jest fraza\"*")
    (should (equal (buffer-string) "Powiedział \"*to jest fraza*\""))
    (should (eobp)))
  (my/bm-test-in-org "Powiedział "
    (my/bm-test-type "\"fraza.\"=, dalej")
    (should (equal (buffer-string) "Powiedział \"=fraza.=\", dalej")))
  (my/bm-test-in-org "Powiedział \"*fraza*\""
    (my/bm-test-type "*")
    (should (equal (buffer-string) "Powiedział \"*fraza*\"*"))))

(ert-deftest my/bm-test-two-phrases-in-a-paragraph ()
  "A second phrase in the paragraph wraps only itself, and Org shows the
text between the two phrases as plain.  With the markers outside the
quotes, =\"a\"=, text =\"b\"= showed \", text \" as verbatim: Org's
highlighting read the first closing = (after a quote, before a comma)
as an opening one."
  (my/bm-test-in-org "Ala "
    (my/bm-test-type "\"pierwsze zdanie\"=, potem tekst \"drugie zdanie\"=")
    (should (equal (buffer-string)
                   "Ala \"=pierwsze zdanie=\", potem tekst \"=drugie zdanie=\""))
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward ", potem")
    (let ((face (get-text-property (1- (point)) 'face)))
      (should-not (memq 'org-verbatim (ensure-list face))))
    (goto-char (point-min))
    (search-forward "drugie")
    (should (memq 'org-verbatim
                  (ensure-list (get-text-property (1- (point)) 'face))))))

(ert-deftest my/bm-test-phrase-whitespace-and-empty-quotes ()
  "Whitespace after the opening quote stays outside the markers -- Org
renders no span that begins with it.  A quote after whitespace is an
opening one, and empty quotes hold nothing: in both cases nothing is
wrapped and the typed character stays."
  (my/bm-test-in-org "Ala \" dwa słowa\""
    (my/bm-test-type "*")
    (should (equal (buffer-string) "Ala \" *dwa słowa*\""))
    (should (eobp)))
  (my/bm-test-in-org "Ala \"dwa słowa \""
    (my/bm-test-type "*")
    (should (equal (buffer-string) "Ala \"dwa słowa \"*")))
  (my/bm-test-in-org "Ala \"\""
    (my/bm-test-type "*")
    (should (equal (buffer-string) "Ala \"\"*"))))

(ert-deftest my/bm-test-trigger-after-opening-quote-wraps-nothing ()
  "\"= typed by hand to begin markup inside quotes wraps nothing, even
with an earlier phrase in the paragraph; until 2026-11-03 the quote was
taken for a closing one and the text since the previous quote was
wrapped.  Electric pairing is on, as in the notes."
  (my/bm-test-in-org "Ala \"pierwsze\" i "
    (electric-pair-local-mode 1)
    (my/bm-test-type "\"=drugie=\"")
    (should (equal (buffer-string) "Ala \"pierwsze\" i \"=drugie=\""))))

(ert-deftest my/bm-test-expand-backward-from-phrase ()
  "C-= after a phrase moves the opening marker one word left of the
opening quote, so the span takes in the quote."
  (my/bm-test-in-org "jeden "
    (my/bm-test-type "\"dwa\"=")
    (should (equal (buffer-string) "jeden \"=dwa=\""))
    (my/inline-marker-expand-backward)
    (should (equal (buffer-string) "=jeden \"dwa=\""))
    (should (eobp))))

(ert-deftest my/bm-test-quote-in-an-earlier-paragraph-not-used ()
  "An opening quote only in an earlier paragraph wraps nothing; the
typed character stays."
  (my/bm-test-in-org "Akapit z \"cudzysłowem.\n\nNowy akapit zakończony\""
    (my/bm-test-type "*")
    (should (string-suffix-p "zakończony\"*" (buffer-string)))
    (should-not (string-match-p "\\*\"cudz" (buffer-string)))))

(ert-deftest my/bm-test-nothing-outside-org-or-after-space ()
  "Outside Org, after a space, and for / and _, nothing is wrapped."
  (with-temp-buffer
    (text-mode)
    (my/bm-test-type "słowo*")
    (should (equal (buffer-string) "słowo*")))
  (my/bm-test-in-org "" (my/bm-test-type "lista *") (should (equal (buffer-string) "lista *")))
  (my/bm-test-in-org "" (my/bm-test-type "and/or") (should (equal (buffer-string) "and/or")))
  (my/bm-test-in-org "" (my/bm-test-type "nazwa_pliku") (should (equal (buffer-string) "nazwa_pliku"))))

(ert-deftest my/bm-test-expand-backward ()
  "C-= moves the opening marker one word left each time."
  (my/bm-test-in-org ""
    (my/bm-test-type "jeden dwa trzy*")
    (should (equal (buffer-string) "jeden dwa *trzy*"))
    (my/inline-marker-expand-backward)
    (should (equal (buffer-string) "jeden *dwa trzy*"))
    (my/inline-marker-expand-backward)
    (should (equal (buffer-string) "*jeden dwa trzy*"))
    (should (eobp))))

(ert-deftest my/bm-test-expand-after-moving-cancels ()
  "C-= after point moved away changes nothing and forgets the span;
without a wrap first it changes nothing either."
  (my/bm-test-in-org ""
    (my/bm-test-type "jeden dwa*")
    (backward-char 3)
    (let ((inhibit-message t)) (my/inline-marker-expand-backward))
    (should (equal (buffer-string) "jeden *dwa*"))
    (should-not my/inline-marker-start))
  (my/bm-test-in-org "jeden dwa"
    (let ((inhibit-message t)) (my/inline-marker-expand-backward))
    (should (equal (buffer-string) "jeden dwa"))))

(ert-deftest my/bm-test-state-reset-when-point-leaves ()
  "After a command that leaves the wrapped span, the span is forgotten."
  (my/bm-test-in-org ""
    (my/bm-test-type "słowo*")
    (should my/inline-marker-start)
    (goto-char (point-min))
    (my/inline-marker-reset-state)
    (should-not my/inline-marker-start)))

(provide 'test-bold-marker)
;;; test-bold-marker.el ends here
