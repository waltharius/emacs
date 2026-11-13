;;; test-references.el --- ERT tests for references inserted as text by 417-bibliography -*- lexical-binding: t; -*-

;; Tests: 417-bibliography

;;; Commentary:

;; C-c x S and C-c x R insert a reference into a note as text.  Until
;; 2026-10-25 they glued the raw BibLaTeX fields together, giving
;; "Bałuk, Kamil and Krupiński, Wacław. /Wodecki: tak mi wyszło/ (2018).";
;; they now render through citeproc-el with a CSL style, as the export
;; does.  These tests check the text inserted for real entries of a
;; small .bib file -- names, "and" in the note's language, editors,
;; dates -- that the full reference is the entry the export prints, that
;; a changed .bib file is read again, and what the commands do when
;; nothing or something unknown is chosen.  Needs citeproc installed
;; (ci-packages.el installs it for the workflow); citar is stood in for.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-references.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "417-bibliography")

(defvar my/csl-bundled-styles-dir)
(defvar my/csl-bundled-locales-dir)
(defvar org-export-default-language)

(defconst my/ref-test-bib
  "@book{baluk2018,
  title = {Wodecki: tak mi wyszło},
  author = {Bałuk, Kamil and Krupiński, Wacław},
  date = {2018-05-01},
  publisher = {Wydawnictwo Agora},
  location = {Warszawa},
  langid = {polish}
}

@book{gogh1990,
  title = {Listy},
  author = {family=Gogh, given=Vincent, prefix=van, useprefix=false},
  date = {1990},
  publisher = {Penguin},
  langid = {polish}
}

@book{three2001,
  title = {Trzy},
  author = {Aa, Anna and Bb, Bogdan and Cc, Celina},
  year = {2001},
  langid = {polish}
}

@collection{edited2005,
  title = {Tom zbiorowy},
  editor = {Ed, Edyta},
  date = {2005},
  langid = {polish}
}

@book{block2020,
  title = {Karl Polanyi: krytyka wolnorynkowego fundamentalizmu},
  author = {Block, Fred L. and Somers, Margaret R.},
  translator = {Bednarek, Joanna and Kowalczyk, Agnieszka},
  date = {2020},
  publisher = {Heterodox},
  langid = {polish}
}

@book{brace2010,
  title = {{O} tytułach w klamrach},
  author = {{Instytut Badań}},
  date = {2010},
  langid = {polish}
}
"
  "A small bibliography in the shape Better BibLaTeX exports.")

(defmacro my/ref-test-with-bib (bib &rest body)
  "Run BODY with BIB as the only bibliography file, the bundled CSL files.
The caches of rendered entries start empty."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "mypks-ref-" t))
          (file (expand-file-name "refs.bib" dir))
          (my/bibliography-files (list file))
          (my/csl-styles-dir (file-name-as-directory (expand-file-name "styles" dir)))
          (my/csl-locales-dir (file-name-as-directory (expand-file-name "locales" dir)))
          (my/csl-bundled-styles-dir (expand-file-name "csl/styles/" my/test-repo))
          (my/csl-bundled-locales-dir (expand-file-name "csl/locales/" my/test-repo))
          (my/csl-default-style "chicago-notes-bibliography.csl")
          (my/reference-short-style "mypks-short-reference.csl")
          (my/bibliographic-note-fields-style "mypks-note-fields.csl")
          (my/reference-full-style nil)
          (my/reference--items nil)
          (my/reference--processors nil))
     (unwind-protect
         (progn
           (with-temp-file file (insert ,bib))
           ,@body)
       (delete-directory dir t))))

(defun my/ref-test-in-note (language thunk)
  "Call THUNK in an Org note whose #+language: is LANGUAGE (nil: none)."
  (with-temp-buffer
    (when language (insert "#+language: " language "\n\n"))
    (org-mode)
    (goto-char (point-max))
    (funcall thunk)))

(defun my/ref-test-short (key language)
  "The short reference to KEY rendered in an Org note in LANGUAGE."
  (my/ref-test-in-note
   language (lambda () (my/reference-render (list key) my/reference-short-style))))

(ert-deftest my/ref-test-short-reference-names-title-year ()
  "Given name first, \"i\" between two authors in a Polish note, the
year alone out of a full date, no full stop at the end -- not the raw
\"Bałuk, Kamil and Krupiński, Wacław. ... (2018-05-01).\"."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (should (equal (my/ref-test-short "baluk2018" "pl")
                   "Kamil Bałuk i Wacław Krupiński, /Wodecki: tak mi wyszło/ (2018)"))))

(ert-deftest my/ref-test-language-name-read-as-code ()
  "A note whose #+language: is a name (\"polish\", as bibliographic notes
had it) or a region tag (\"pl-PL\") is rendered in Polish, not in
citeproc's fallback English."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (dolist (language '("polish" "pl-PL" "polski"))
      (should (equal (my/ref-test-short "baluk2018" language)
                     "Kamil Bałuk i Wacław Krupiński, /Wodecki: tak mi wyszło/ (2018)")))))

(ert-deftest my/ref-test-short-reference-english-and ()
  "In an English note the word is \"and\", not citeproc's \"&\"."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (should (equal (my/ref-test-short "baluk2018" "en")
                   "Kamil Bałuk and Wacław Krupiński, /Wodecki: tak mi wyszło/ (2018)"))))

(ert-deftest my/ref-test-language-from-export-default ()
  "A note without #+language: takes the export's default language."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (let ((org-export-default-language "pl"))
      (should (equal (my/ref-test-short "baluk2018" nil)
                     "Kamil Bałuk i Wacław Krupiński, /Wodecki: tak mi wyszło/ (2018)")))))

(ert-deftest my/ref-test-short-reference-name-forms ()
  "BibLaTeX's extended name format, three authors and more, an editor
without an author, a name in braces (an institution)."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (should (equal (my/ref-test-short "gogh1990" "pl")
                   "Vincent van Gogh, /Listy/ (1990)"))
    (should (equal (my/ref-test-short "three2001" "pl")
                   "Anna Aa et al., /Trzy/ (2001)"))
    (should (equal (my/ref-test-short "edited2005" "pl")
                   "Edyta Ed (red.), /Tom zbiorowy/ (2005)"))
    (should (equal (my/ref-test-short "brace2010" "pl")
                   "Instytut Badań, /O tytułach w klamrach/ (2010)"))))

(ert-deftest my/ref-test-reused-processor-renders-only-the-keys-asked ()
  "A second reference rendered with the same style shows that entry
alone, not the first one again: the processor is reused, and citeproc's
`citeproc-clear' keeps keys added as uncited."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (my/ref-test-short "gogh1990" "pl")
    (should (equal (my/ref-test-short "three2001" "pl")
                   "Anna Aa et al., /Trzy/ (2001)"))))

(ert-deftest my/ref-test-full-reference-is-the-export-entry ()
  "The full reference is the entry the export style prints."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (should (equal (my/ref-test-in-note
                    "pl" (lambda () (my/reference-render
                                     '("baluk2018") my/csl-default-style)))
                   "Bałuk, Kamil, i Wacław Krupiński. /Wodecki: tak mi wyszło/. Wydawnictwo Agora, 2018."))))

(ert-deftest my/ref-test-full-reference-matches-an-export ()
  "The text of C-c x R is the line Org's own CSL export writes for the
same entry, style and language (exported to ASCII, which marks italics
with slashes as Org does)."
  (skip-unless (and (locate-library "citeproc") (require 'oc-csl nil t)))
  (require 'ox-ascii)
  (my/ref-test-with-bib my/ref-test-bib
    (my/csl-apply)
    (let* ((ours (my/ref-test-in-note
                  "pl" (lambda () (my/reference-render
                                   '("baluk2018") my/csl-default-style))))
           (org-cite-global-bibliography (my/bibliography-file-list))
           (exported
            (with-temp-buffer
              (insert "#+language: pl\n\nTekst [cite:@baluk2018].\n\n#+print_bibliography:\n")
              (org-mode)
              (org-export-as 'ascii nil nil t '(:ascii-charset utf-8)))))
      (should (string-match-p (regexp-quote ours)
                              (replace-regexp-in-string "[ \t\n]+" " " exported))))))

(ert-deftest my/ref-test-several-keys-joined ()
  "Several references: \"; \" between short ones, each between = signs,
one full one per line, the full ones in the export style and without."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (cl-letf (((symbol-function 'citar-select-refs)
               (lambda (&rest _) '("baluk2018" "gogh1990"))))
      (my/ref-test-in-note
       "pl" (lambda ()
              (let ((my/reference-short-verbatim t))
                (call-interactively #'my/insert-short-reference))
              (should (string-suffix-p
                       "\n\n=Kamil Bałuk i Wacław Krupiński, /Wodecki: tak mi wyszło/ (2018)=; =Vincent van Gogh, /Listy/ (1990)="
                       (buffer-string)))))
      (my/ref-test-in-note
       "pl" (lambda ()
              (call-interactively #'my/insert-full-reference)
              (should (string-suffix-p
                       "\n\nBałuk, Kamil, i Wacław Krupiński. /Wodecki: tak mi wyszło/. Wydawnictwo Agora, 2018.\nGogh, Vincent van. /Listy/. Penguin, 1990."
                       (buffer-string))))))))

(ert-deftest my/ref-test-short-reference-verbatim-option ()
  "In Org the short reference is between = signs while the option is
on, the title in /italic/ inside; with it off, as before.  Org reads
the result as one verbatim object."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (my/ref-test-in-note
     "pl" (lambda ()
            (insert "Czytam ")
            (let ((my/reference-short-verbatim t))
              (my/insert-short-reference '("gogh1990")))
            (insert ".")
            (should (string-suffix-p "Czytam =Vincent van Gogh, /Listy/ (1990)=."
                                     (buffer-string)))
            (should (equal (org-element-property
                            :value (car (org-element-map (org-element-parse-buffer)
                                            'verbatim #'identity)))
                           "Vincent van Gogh, /Listy/ (1990)"))))
    (my/ref-test-in-note
     "pl" (lambda ()
            (let ((my/reference-short-verbatim nil))
              (my/insert-short-reference '("gogh1990")))
            (should (string-suffix-p "\n\nVincent van Gogh, /Listy/ (1990)"
                                     (buffer-string)))))))

(ert-deftest my/ref-test-plain-text-outside-org ()
  "Outside Org the title is not wrapped in Org's /italic/ markers, nor
the reference in = signs."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (with-temp-buffer
      (text-mode)
      (let ((org-export-default-language "pl")
            (my/reference-short-verbatim t))
        (my/insert-short-reference '("baluk2018")))
      (should (equal (buffer-string)
                     "Kamil Bałuk i Wacław Krupiński, Wodecki: tak mi wyszło (2018)")))))

(ert-deftest my/ref-test-changed-bib-read-again ()
  "An entry changed in the .bib file -- Zotero's export rewriting it --
is seen at the next insertion, without a restart."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (should (string-match-p "/Listy/" (my/ref-test-short "gogh1990" "pl")))
    (let ((file (car my/bibliography-files)))
      (with-temp-file file
        (insert (replace-regexp-in-string "{Listy}" "{Listy do brata}" my/ref-test-bib)))
      ;; Another time of change, also where the clock is coarse.
      (set-file-times file (time-add (current-time) 10)))
    (should (string-match-p "/Listy do brata/" (my/ref-test-short "gogh1990" "pl")))))

(ert-deftest my/ref-test-own-style-wins ()
  "A style of the same name in the user's styles folder is used instead
of the bundled one."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (make-directory my/csl-styles-dir t)
    (with-temp-file (expand-file-name "mypks-short-reference.csl" my/csl-styles-dir)
      (insert-file-contents (expand-file-name "mypks-short-reference.csl"
                                              my/csl-bundled-styles-dir))
      (goto-char (point-min))
      (search-forward "prefix=\" (\" suffix=\")\">\n      <date-part")
      (replace-match "prefix=\" [\" suffix=\"]\">\n      <date-part" t t))
    (should (equal (my/ref-test-short "gogh1990" "pl")
                   "Vincent van Gogh, /Listy/ [1990]"))))

(ert-deftest my/ref-test-unknown-key-inserts-nothing ()
  "A key the bibliography lacks is named in an error; nothing is inserted."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (my/ref-test-in-note
     "pl" (lambda ()
            (let ((before (buffer-string))
                  (err (should-error (my/insert-short-reference '("baluk2018" "nosuch"))
                                     :type 'user-error)))
              (should (string-match-p "nosuch" (cadr err)))
              (should (equal (buffer-string) before)))))))

(ert-deftest my/ref-test-nothing-chosen-inserts-nothing ()
  "Leaving citar's prompt without a choice inserts nothing."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (cl-letf (((symbol-function 'citar-select-refs) (lambda (&rest _) nil)))
      (my/ref-test-in-note
       "pl" (lambda ()
              (let ((before (buffer-string)))
                (should-error (call-interactively #'my/insert-short-reference)
                              :type 'user-error)
                (should (equal (buffer-string) before))))))))

(defconst my/ref-test-note-front
  "#+title:       Block 2020
#+entry-type:  book
#+authors:     %^{mypks:authors}
#+translator:  %^{mypks:translators}
#+publisher:   %^{publisher}
#+year:        %^{mypks:year}
#+language:    %^{mypks:language}

* Problem, na który odpowiada tekst
"
  "The front matter of the biblio template as citar-denote leaves it,
the entry's publisher not yet filled (to see an empty field emptied).")

(defun my/ref-test-filled-note (key language)
  "The front matter of `my/ref-test-note-front' filled for KEY in LANGUAGE.
The default language of the export is English, as in the configuration,
which does not set it: the note's language must not come from there,
nor from its #+language: polish."
  (with-temp-buffer
    (insert my/ref-test-note-front)
    (org-mode)
    (let ((org-export-default-language "en")
          (my/bibliographic-note-language language))
      (my/bibliographic-note-fill key))
    (buffer-string)))

(ert-deftest my/ref-test-bibliographic-note-names-as-in-text ()
  "A new bibliographic note names authors and translators as C-c x S
does, given name first, joined by \"i\" -- not \"Block, Fred L. and
Somers, Margaret R.\" -- and has the year of a date; a placeholder of a
field the entry lacks is emptied, the rest of the note untouched."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (let ((note (my/ref-test-filled-note "block2020" "pl")))
      (should (string-match-p "^#\\+authors:     Fred L\\. Block i Margaret R\\. Somers$" note))
      (should (string-match-p "^#\\+translator:  Joanna Bednarek i Agnieszka Kowalczyk$" note))
      (should (string-match-p "^#\\+year:        2020$" note))
      (should (string-match-p "^#\\+publisher:$" note))
      (should (string-match-p "^#\\+language:    pl$" note))
      (should-not (string-match-p "%\\^{" note))
      (should (string-suffix-p "\n\n* Problem, na który odpowiada tekst\n" note)))))

(ert-deftest my/ref-test-bibliographic-note-language-option ()
  "In English the names are joined by \"and\"."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (should (string-match-p "^#\\+authors:     Fred L\\. Block and Margaret R\\. Somers$"
                            (my/ref-test-filled-note "block2020" "en")))))

(ert-deftest my/ref-test-bibliographic-note-editors-no-translator ()
  "An edited volume names its editors with \"(red.)\"; three authors
are all named; an entry without translators leaves the line empty."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (let ((note (my/ref-test-filled-note "edited2005" "pl")))
      (should (string-match-p "^#\\+authors:     Edyta Ed (red\\.)$" note))
      (should (string-match-p "^#\\+translator:$" note))
      (should (string-match-p "^#\\+year:        2005$" note)))
    (should (string-match-p "^#\\+authors:     Anna Aa, Bogdan Bb i Celina Cc$"
                            (my/ref-test-filled-note "three2001" "pl")))))

(ert-deftest my/ref-test-bibliographic-note-falls-back-to-raw ()
  "A key not in the bibliography files (Zotero's export behind citar):
the raw fields citar has, no error, the note still made."
  (skip-unless (locate-library "citeproc"))
  (my/ref-test-with-bib my/ref-test-bib
    (cl-letf (((symbol-function 'citar-get-value)
               (lambda (field _key)
                 (cdr (assoc field '(("author" . "Nowy, Jan") ("date" . "2026-03-01")))))))
      (let ((note (my/ref-test-filled-note "notyet2026" "pl")))
        (should (string-match-p "^#\\+authors:     Nowy, Jan$" note))
        (should (string-match-p "^#\\+translator:$" note))
        (should (string-match-p "^#\\+year:        2026$" note))))))

(ert-deftest my/ref-test-bibliographic-note-after-citar-denote ()
  "Through citar-denote's own expansion: it fills the fields it knows,
leaves the %^{mypks:...} ones alone, and the advice fills those after.
Fails when citar-denote renames the function the advice is on."
  (skip-unless (and (locate-library "citeproc") (locate-library "citar-denote")))
  (require 'citar-denote)
  (should (fboundp 'citar-denote--expand-citation-macros))
  (should (advice-member-p #'my/bibliographic-note--after-expand
                           'citar-denote--expand-citation-macros))
  (my/ref-test-with-bib my/ref-test-bib
    (cl-letf (((symbol-function 'citar-denote--format-author-editor) (lambda (_) "raw"))
              ((symbol-function 'citar-get-value) (lambda (&rest _) nil))
              ((symbol-function 'citar-format-reference) (lambda (&rest _) "ref"))
              ((symbol-function 'citar-get-entry)
               (lambda (_) '(("=type=" . "book") ("publisher" . "Heterodox")
                             ("author" . "Block, Fred L. and Somers, Margaret R.")))))
      (with-temp-buffer
        (insert (replace-regexp-in-string "#\\+entry-type:  book"
                                          "#+entry-type:  %^{=type=}"
                                          my/ref-test-note-front))
        (org-mode)
        (let ((org-export-default-language "en")
              (my/bibliographic-note-language "pl"))
          (citar-denote--expand-citation-macros "block2020"))
        (let ((note (buffer-string)))
          (should (string-match-p "^#\\+entry-type:  book$" note))
          (should (string-match-p "^#\\+publisher:   Heterodox$" note))
          (should (string-match-p "^#\\+authors:     Fred L\\. Block i Margaret R\\. Somers$" note)))))))

(provide 'test-references)
;;; test-references.el ends here
