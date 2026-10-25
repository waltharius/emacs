;;; 417-bibliography.el --- Citations with citar: the .bib files, CSL, references, the menu -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; Docs: ~/.emacs.d/function_helper.org::#citing-howto

;;; Commentary:
;; Citations and the bibliography with citar, from .bib files written by
;; any program: Zotero's Better BibTeX, JabRef, by hand.  Where they are
;; is an option, `my/bibliography-files' (C-c x ,), ~/notes/refs.bib by
;; default.  What only Zotero gives -- the folder of its attachments --
;; is 417c-zotero.el; the PDF and EPUB viewers are 117b-document-viewers.el
;; (both split off on 2026-10-25, as decided on the module map).
;;
;; The bibliography menu, C-c x (`my/bibliography-menu'), is here since
;; 2026-10-25zg; it was 18-zotero-transient.el, `my/zotero-menu'.
;;
;; Workflow:
;;   1. C-c x n  -- create a note from a reference, its file opens on the right
;;   2. C-c x f  -- reopen the file of the reference on the right
;;   3. C-c x R  -- insert the full reference at point, in the export style
;;   4. C-c x S  -- insert a short reference at point: Given Family, /Title/ (Year)

;;; Code:

(require 'cl-lib)

;; ============================================================
;; WHERE THE BIBLIOGRAPHY IS
;; ============================================================
;; The .bib file Zotero exports, and the folder holding Zotero's PDFs,
;; are options rather than paths written into the package settings:
;; some keep the export beside the notes, so that it travels with them,
;; others in Zotero's own folder or anywhere else.  A relative name is
;; relative to the notes folder and follows it; an absolute one stays.
;; Everything is applied at once (`my/bibliography-apply'), to citar and
;; to org-cite alike, so the two never read different files.

(defgroup my/bibliography nil
  "Citations: the bibliography files, CSL export, Zotero's attachments."
  :tag "Bibliography and citations"
  :group 'mypks-writing)

(defcustom my/bibliography-files '("refs.bib")
  "The BibTeX files citations come from.
Written by any program: Zotero (Better BibTeX keeps the export up to
date), JabRef, or by hand.  A relative name is relative
to the notes folder (`my-notes-dir') and follows it; an absolute name,
such as ~/Zotero/refs.bib, stays where it is.  Several files are read
together.  Takes effect at once."
  :type '(repeat (file :tag "BibTeX file"))
  :tag "Bibliography files (.bib, from Zotero or any other program)"
  :set (my/settings-apply-on-set #'my/bibliography-apply)
  :group 'my/bibliography)

(defun my/bibliography-file-list ()
  "Return `my/bibliography-files' as absolute file names."
  (mapcar (lambda (file) (expand-file-name file my-notes-dir))
          my/bibliography-files))

(defvar citar-bibliography)
(defvar citar-notes-paths)
(defvar org-cite-global-bibliography)

(defvar my/bibliography--told nil
  "Missing files already reported this session.")

(defun my/bibliography-apply ()
  "Point citar and org-cite at the bibliography files.
Also points citar's notes at the silo with role `notes'.  Says once per
session when a bibliography file does not exist.  Where citar finds a
reference's file is the file field of its entry, and Zotero's folder
when 417c-zotero.el is loaded."
  (let ((files (my/bibliography-file-list)))
    (setq org-cite-global-bibliography files)
    (with-eval-after-load 'citar
      (setq citar-bibliography files
            citar-notes-paths (list (my/silo-dir-by-role 'notes))))
    (dolist (file files)
      (unless (or (file-readable-p file) (member file my/bibliography--told))
        (push file my/bibliography--told)
        (message "Bibliography: %s not found; set the file in C-c x , (Bibliography files)"
                 (abbreviate-file-name file))))))

(defun my/bibliography-settings ()
  "Open the settings of the bibliography: files, CSL, Zotero's folder."
  (interactive)
  (customize-group 'my/bibliography))

;; The notes silo can change while Emacs runs (`my/silos').
(add-hook 'my/silos-changed-hook #'my/bibliography-apply)

;; ============================================================
;; CITAR — citation search and insertion
;; ============================================================

(use-package citar
  :ensure t
  :config
  (my/bibliography-apply)
  (setq org-cite-insert-processor 'citar)
  (setq org-cite-follow-processor 'citar)
  (setq org-cite-activate-processor 'citar))

;; Before citar loads too: export reads `org-cite-global-bibliography'.
(my/bibliography-apply)

;; ============================================================
;; CITATION EXPORT — CSL
;; ============================================================
;; Citar above configures three of the four org-cite processors:
;; insert, follow and activate.  Those all work inside the editor.
;; The fourth, `org-cite-export-processor', decides what a citation
;; turns into when the document is exported -- and without it Org falls
;; back to the `basic' processor, which emits a plain-text key and no
;; real bibliography.  Citations therefore looked fine while writing
;; and came out wrong on export.
;;
;; CSL rather than biblatex, because biblatex only exists inside LaTeX
;; and the deliverables here include ODT and EPUB as well as PDF.  One
;; mechanism has to serve all three, and only CSL does.
;;
;; CSL handles note styles properly: the specification defines the
;; `ibid', `ibid-with-locator', `subsequent' and `near-note' positions,
;; and note styles such as chicago-note-bibliography implement them, so
;; repeated references shorten the way a humanities text expects.
;;
;; Known limitation, worth remembering before a deadline rather than
;; during one: a plain discursive footnote sitting between two
;; citations can confuse position tracking, so an "ibid." may appear
;; where "op. cit." belongs.  Proofread citation runs in a text with
;; dense commentary footnotes.

(use-package citeproc
  :ensure t
  :after oc)

;; WHERE THE STYLES COME FROM.  The user's folders beside the notes come
;; first: a style is a requirement of the text, decided by the journal
;; or publisher, and travels with the writing.  When they lack the
;; default style or the Polish locale -- a fresh installation, a new and
;; empty notes folder -- the copies bundled with this configuration in
;; csl/ are used instead, so export works from the first day; *Messages*
;; says so once per session.  Org's own fallback carries only en-US.
;; Everything is decided again before each export (`my/csl-apply'), so
;; a style dropped into the folder works without a restart.

(defconst my/csl-bundled-styles-dir (locate-user-emacs-file "csl/styles/")
  "CSL styles shipped with this configuration; see csl/README.md.")

(defconst my/csl-bundled-locales-dir (locate-user-emacs-file "csl/locales/")
  "CSL locales shipped with this configuration; see csl/README.md.")

(defcustom my/csl-styles-dir (expand-file-name "csl/" my-notes-dir)
  "Directory holding CSL style files (.csl).

Kept beside the notes rather than in .emacs.d because a style is part
of a document's requirements, not part of the editor: which style a
text uses is decided by the journal or publisher, and the file has to
travel with the writing.  The default style, when missing here, is
taken from `my/csl-bundled-styles-dir'.  Takes effect at once."
  :type 'directory
  :set (my/settings-apply-on-set #'my/csl-apply)
  :group 'my/bibliography)

(defcustom my/csl-locales-dir (expand-file-name "csl-locales/" my-notes-dir)
  "Directory holding CSL locale files (locales-*.xml).

Separate from the styles directory because citeproc looks the two up
independently: every style shares the same locale data for a given
language.  Without the Polish locale here, the folder
`my/csl-bundled-locales-dir' is used; Org's own carries only en-US, so
a Polish document would render English terms.  Takes effect at once."
  :type 'directory
  :set (my/settings-apply-on-set #'my/csl-apply)
  :group 'my/bibliography)

(defcustom my/csl-default-style "chicago-notes-bibliography.csl"
  "CSL style used when a document does not name its own.

A note style, since footnote citations are the default need here.
Override per document instead of changing this, because the style is a
property of the text rather than of the configuration:

  #+cite_export: csl apa.csl

Note the plural in \"notes\": the CSL styles repository renamed the
Chicago styles, and the old singular name now 404s.  Verify the
downloaded file is around 100 kB rather than the 14 bytes of an error
page -- `my/csl-check-setup\=' checks this.  Takes effect at once."
  :type 'string
  :set (my/settings-apply-on-set #'my/csl-apply)
  :group 'my/bibliography)

(defun my/csl--valid-file-p (file opening-tag)
  "Return non-nil when FILE looks like real XML containing OPENING-TAG.

Checking readability is not enough.  A failed download leaves a
perfectly readable file behind: `curl -O\=' writes the server\='s error
body, so a renamed or moved style arrives as a 14-byte file containing
\"404: Not Found\".  Citeproc then parses an empty style, produces no
layout parameters, and the export fails far away from the cause with
`Wrong type argument: numberp, nil\='."
  (and (file-readable-p file)
       (> (or (file-attribute-size (file-attributes file)) 0) 200)
       (with-temp-buffer
         (insert-file-contents file nil 0 2000)
         (goto-char (point-min))
         (search-forward opening-tag nil t))))

(defun my/csl--style-file (name)
  "Return the style file NAME to use, absolute, or nil if there is none.
The user's styles folder first, then the bundled copy."
  (seq-find (lambda (file) (my/csl--valid-file-p file "<style"))
            (list (expand-file-name name my/csl-styles-dir)
                  (expand-file-name name my/csl-bundled-styles-dir))))

(defun my/csl--default-style-file ()
  "Return the default style file to use, absolute, or nil if there is none.
The user's styles folder first, then the bundled copy."
  (my/csl--style-file my/csl-default-style))

(defun my/csl--locales-dir ()
  "Return the locales folder to use: the user's when it has the Polish locale."
  (if (my/csl--valid-file-p (expand-file-name "locales-pl-PL.xml" my/csl-locales-dir)
                            "<locale")
      my/csl-locales-dir
    my/csl-bundled-locales-dir))

(defvar my/csl--told nil
  "What `my/csl-apply' already said this session, so that it says it once.")

(defvar org-cite-csl-styles-dir)
(defvar org-cite-csl-locales-dir)
(defvar org-cite-export-processors)

(defun my/csl--bundled-p (file)
  "Non-nil when FILE is one of the CSL files bundled in csl/."
  (and file (string-prefix-p (expand-file-name (locate-user-emacs-file "csl/"))
                             (expand-file-name file))))

(defun my/csl-apply (&rest _)
  "Point org-cite at the CSL styles and locales to use; say what is missing.
Called when Org's citation library loads, when an option changes, and
before every export, so that a style added to the folder is used at the
next export.  Arguments, given by the export hook, are ignored."
  (with-eval-after-load 'oc
    (let* ((style (my/csl--default-style-file))
           (locales (my/csl--locales-dir))
           (bundled (delq nil (list (and (my/csl--bundled-p style) "the default style")
                                    (and (my/csl--bundled-p locales) "the locales"))))
           (note (cond
                  ((null style)
                   (format "no CSL style %s in %s nor in %s, so citations will not export.  Put the style file in the first folder (from https://github.com/citation-style-language/styles); M-x my/csl-check-setup lists what else is missing"
                           my/csl-default-style my/csl-styles-dir my/csl-bundled-styles-dir))
                  (bundled
                   (format "%s from the CSL files bundled with the configuration (csl/); put your own in %s and %s to use them instead"
                           (string-join bundled " and ")
                           my/csl-styles-dir my/csl-locales-dir)))))
      ;; Styles a document names by file are looked up here; the default
      ;; style is given by its full name, so it may come from either.
      (setq org-cite-csl-styles-dir
            (if (file-directory-p my/csl-styles-dir)
                my/csl-styles-dir
              my/csl-bundled-styles-dir))
      (setq org-cite-csl-locales-dir locales)
      ;; NOTE the plural.  `org-cite-export-processors' is the global
      ;; setting: an alist keyed by export backend, where `t' is the
      ;; fallback for every backend without its own entry.  The SINGULAR
      ;; `org-cite-export-processor' is a buffer-local variable set by a
      ;; `#+cite_export:' keyword, so assigning it globally has no
      ;; effect -- Org then silently falls back to the `basic' processor,
      ;; which emits a plain "(Author, Year)" and no bibliography.
      ;;
      ;; Each entry is (BACKEND PROCESSOR BIBLIOGRAPHY-STYLE), mirroring
      ;; the argument order of the #+cite_export: keyword.
      (setq org-cite-export-processors
            `((t csl ,(or style my/csl-default-style))))
      (when (and note (not (member note my/csl--told)))
        (push note my/csl--told)
        (if style
            (message "Citations: %s" note)
          (display-warning 'citations note :warning))))))

;; Set before oc-csl is required, and in a form of its own: loading
;; oc-csl can fail -- most plausibly because citeproc is not installed
;; yet -- and an error inside `with-eval-after-load' aborts the
;; remainder of the block silently.  When the settings shared a block
;; with the require, a missing citeproc left `org-cite-export-processors'
;; unset, Org fell back to its built-in `basic' processor, and export
;; produced "(Author, Year)" with no bibliography and no visible error.
(my/csl-apply)

(with-eval-after-load 'oc
  (unless (require 'oc-csl nil t)
    (message "org-cite: oc-csl unavailable (is citeproc installed?) -- \
citations will export through the basic processor")))

(add-hook (if (boundp 'org-export-before-processing-functions)
              'org-export-before-processing-functions
            'org-export-before-processing-hook)
          #'my/csl-apply)

(defun my/csl-check-setup ()
  "Report whether CSL export is ready, and what is missing if not.

Written because every failure here is silent: a missing style
directory or an unreadable .bib does not raise an error, it just
produces an export with no bibliography, which is easy not to notice
until the document is finished.  Files bundled in csl/ count as
present, and the report says when they are the ones in use."
  (interactive)
  (my/csl-apply)
  (let ((problems nil)
        (notes nil)
        (style (my/csl--default-style-file))
        (locales (my/csl--locales-dir)))
    (unless (featurep 'citeproc)
      (push "citeproc is not loaded (M-x package-install RET citeproc)" problems))
    (unless (featurep 'oc-csl)
      (push "oc-csl is not loaded -- export falls back to the basic processor"
            problems))
    (unless (assq t org-cite-export-processors)
      (push "org-cite-export-processors has no fallback entry -- citations will export via the basic processor"
            problems))
    (unless (equal (and (boundp 'org-cite-csl-locales-dir) org-cite-csl-locales-dir)
                   locales)
      (push (format "org-cite-csl-locales-dir is %S, expected %S -- the setting did not take effect"
                    (and (boundp 'org-cite-csl-locales-dir) org-cite-csl-locales-dir)
                    locales)
            problems))
    (let ((own (expand-file-name "locales-pl-PL.xml" my/csl-locales-dir)))
      (cond
       ((not (file-readable-p own))
        (push (format "Polish locale: bundled copy in use (none in %s)" my/csl-locales-dir)
              notes))
       ((not (my/csl--valid-file-p own "<locale"))
        (push (format "not a CSL locale (%d bytes): %s -- bundled copy in use"
                      (file-attribute-size (file-attributes own)) own)
              problems))))
    (let ((own (expand-file-name my/csl-default-style my/csl-styles-dir)))
      (cond
       ((null style)
        (push (format "default style %s found neither in %s nor bundled"
                      my/csl-default-style my/csl-styles-dir)
              problems))
       ((and (file-readable-p own) (not (my/csl--valid-file-p own "<style")))
        (push (format "not a CSL style (%d bytes): %s -- bundled copy in use"
                      (file-attribute-size (file-attributes own)) own)
              problems))
       ((my/csl--bundled-p style)
        (push (format "default style: bundled copy in use (none in %s)" my/csl-styles-dir)
              notes))))
    (dolist (bib (if (listp org-cite-global-bibliography)
                     org-cite-global-bibliography
                   (list org-cite-global-bibliography)))
      (unless (file-readable-p bib)
        (push (format "bibliography not readable: %s" bib) problems)))
    (if problems
        (message "CSL export NOT ready:\n- %s%s"
                 (string-join (nreverse problems) "\n- ")
                 (if notes (concat "\nAlso: " (string-join notes "; ")) ""))
      (message "CSL export ready: %s via %S + %s%s"
               (abbreviate-file-name style)
               (cadr (assq t org-cite-export-processors))
               (string-join org-cite-global-bibliography ", ")
               (if notes (concat "\n" (string-join notes "; ")) "")))))

;; ============================================================
;; DENOTE TEMPLATE: Bibliographic note front matter
;; ============================================================
;; Note: #+reference is added automatically by citar-denote — do not duplicate it here.
;; Fields that do not expand (origdate, pagetotal) are omitted — add manually if needed.

(with-eval-after-load 'denote
  (add-to-list 'denote-templates
               '(biblio . "#+entry-type:  %^{=type=}
#+authors:     %^{author}
#+translator:  %^{translator}
#+publisher:   %^{publisher}
#+year:        %^{year}
#+language:    %^{langid}

* Problem, na który odpowiada tekst

* Teza / główny ruch autora

* Werdykt (udało się?) + standardowa krytyka

* Nowe problemy, które otwiera

* Powiązania
# denote-link: pojęcia / problemy / myśliciele

")))

;; ============================================================
;; CITAR-DENOTE — bridge citar into Denote
;; ============================================================

(use-package citar-denote
  :ensure t
  :after (citar denote)
  :custom
  ;; The folder of the notes silo, relative to `denote-directory';
  ;; "pks/" when that silo lies outside the notes folder.
  (citar-denote-subdir (let ((name (my/silo-folder-name (or (my/silo-by-role 'notes) 'pks))))
                         (if name (concat name "/") "pks/")))
  (citar-denote-use-bib-keywords t)
  (citar-denote-title-format "author-year-title")
  (citar-denote-title-format-authors 1)
  (citar-denote-template 'biblio)
  :config
  (citar-denote-mode 1))

;; ============================================================
;; HELPER: Reopen PDF for current bibliographic note on the right
;; ============================================================

(defun my/open-bib-pdf-right ()
  "Open PDF for the current bibliographic note in a right window split."
  (interactive)
  (if-let* ((file (buffer-file-name))
             (keys (citar-denote--retrieve-references file))
             (key (car keys)))
      (progn
        (when (one-window-p) (split-window-right))
        (other-window 1)
        (citar-open-files key))
    (message "No #+reference found in this note")))

;; ============================================================
;; REFERENCES AS TEXT, rendered by CSL
;; ============================================================
;; C-c x S and C-c x R put a reference into a note as text, for notes
;; that stay plain text; a citation to be exported is [cite:@key]
;; (C-c x i).  Both go through citeproc-el with a CSL style -- the
;; machinery that renders citations on export -- rather than through
;; fields glued together here: names come out as "Kamil Bałuk i Wacław
;; Krupiński" (BibLaTeX stores "Bałuk, Kamil and Krupiński, Wacław"),
;; "and" in the language of the note, braces and dates handled, editors
;; named when there is no author.  Until 2026-10-25 the fields were
;; inserted raw: "Bałuk, Kamil and Krupiński, Wacław. /Title/ (2018).".
;;
;; The short reference has a style of its own, bundled in csl/styles/
;; (Given Family, /Title/ (Year)); the full one uses the export style,
;; so it reads as the entry of the exported bibliography does.  Either
;; can be another CSL style, put in `my/csl-styles-dir'.
;;
;; The entries are read from the bibliography files as the export reads
;; them (`citeproc-hash-itemgetter-from-any'), not from citar's cache:
;; citar keeps only the fields its own templates name, so a place of
;; publication, a translator or a language would be missing.  Read once,
;; and again when a file changes.

(defcustom my/reference-short-style "mypks-short-reference.csl"
  "CSL style of the short reference `my/insert-short-reference' inserts.
A file in `my/csl-styles-dir', or bundled in csl/styles/ as the default
is.  The default gives \"Given Family i Given Family, /Title/ (Year)\",
\"and\" in the language of the note.  Takes effect at once."
  :type 'string
  :tag "Style of the short reference (C-c x S)"
  :group 'my/bibliography)

(defcustom my/reference-full-style nil
  "CSL style of the full reference `my/insert-full-reference' inserts.
Nil: the export style, `my/csl-default-style', so that the reference
reads as the entry of an exported bibliography.  Otherwise a file in
`my/csl-styles-dir' or bundled in csl/styles/.  Takes effect at once."
  :type '(choice (const :tag "The export style" nil)
                 (string :tag "CSL style file"))
  :tag "Style of the full reference (C-c x R)"
  :group 'my/bibliography)

(declare-function citeproc-create "ext:citeproc")
(declare-function citeproc-clear "ext:citeproc")
(declare-function citeproc-append-citations "ext:citeproc")
(declare-function citeproc-citation-create "ext:citeproc-cite")
(declare-function citeproc-render-bib "ext:citeproc")
(declare-function citeproc-render-citations "ext:citeproc")
(declare-function citeproc-hash-itemgetter-from-any "ext:citeproc-itemgetters")
(declare-function citeproc-locale-getter-from-dir "ext:citeproc-locale")
(declare-function citar-select-refs "ext:citar")
(declare-function org-collect-keywords "org")
(defvar org-cite-csl-bibtex-titles-to-sentence-case)
(defvar org-export-default-language)

(defvar my/reference--items nil
  "(STAMP . GETTER): the entries of the bibliography files, read once.
STAMP names the files with their size and time of change; a different
stamp reads them again.")

(defvar my/reference--processors nil
  "Alist of ((STYLE STAMP LOCALE GETTER) . PROCESSOR) already built.")

(defun my/reference--file-stamp (files)
  "Return FILES with their time of change and size, to notice an edit."
  (mapcar (lambda (file)
            (let ((attrs (file-attributes file)))
              (list file
                    (file-attribute-modification-time attrs)
                    (file-attribute-size attrs))))
          files))

(defun my/reference--itemgetter ()
  "Return a citeproc item getter for the bibliography files.
Read as the export reads them, and kept until a file changes."
  (let ((files (seq-filter #'file-readable-p (my/bibliography-file-list))))
    (unless files
      (user-error "No bibliography file to read: %s (C-c x , to set one)"
                  (mapconcat #'abbreviate-file-name (my/bibliography-file-list) ", ")))
    (let ((stamp (my/reference--file-stamp files)))
      (unless (equal stamp (car my/reference--items))
        (setq my/reference--processors nil
              my/reference--items
              (cons stamp
                    ;; The second argument as the export passes it
                    ;; (Org 9.7 and later have the option).
                    (citeproc-hash-itemgetter-from-any
                     files
                     (and (boundp 'org-cite-csl-bibtex-titles-to-sentence-case)
                          (not org-cite-csl-bibtex-titles-to-sentence-case))))))
      (cdr my/reference--items))))

(defun my/reference--locale ()
  "Return the language references are rendered in, as the export does.
The note's #+language: keyword in an Org buffer, else the default
language of the export, else English."
  (or (and (derived-mode-p 'org-mode)
           (let ((value (cadar (org-collect-keywords '("LANGUAGE")))))
             (and value (not (string-empty-p (string-trim value)))
                  (string-trim value))))
      (and (boundp 'org-export-default-language) org-export-default-language)
      "en"))

(defun my/reference--processor (style-name locale)
  "Return a citeproc processor for the CSL style STYLE-NAME in LOCALE."
  (unless (require 'citeproc nil t)
    (user-error "citeproc is not installed (M-x package-install RET citeproc)"))
  (let* ((style (or (my/csl--style-file style-name)
                    (user-error "No CSL style %s in %s nor in %s"
                                style-name my/csl-styles-dir my/csl-bundled-styles-dir)))
         (getter (my/reference--itemgetter))
         (key (list style (my/reference--file-stamp (list style)) locale getter)))
    (or (cdr (assoc key my/reference--processors))
        (let ((processor (citeproc-create
                          style getter
                          (citeproc-locale-getter-from-dir (my/csl--locales-dir))
                          locale)))
          (push (cons key processor) my/reference--processors)
          processor))))

(defun my/reference-missing (keys)
  "Return the keys among KEYS that no bibliography file holds."
  (let ((getter (my/reference--itemgetter)))
    ;; The getter answers (KEY . nil) for a key it does not hold.
    (seq-remove (lambda (key) (cdar (funcall getter (list key)))) keys)))

(defun my/reference-render (keys style-name &optional format separator)
  "Return the references to KEYS, a list of citation keys, as text.
Rendered in the CSL style STYLE-NAME as entries of a bibliography, in
the language of the current buffer (`my/reference--locale').  FORMAT is
a citeproc output format, `org' by default; SEPARATOR joins several
references, a new line by default.  An unknown key is an error naming
it."
  (let ((missing (my/reference-missing keys))
        (processor (my/reference--processor style-name (my/reference--locale))))
    (when missing
      (user-error "Not in the bibliography: %s" (string-join missing ", ")))
    ;; Cited rather than added as uncited: `citeproc-clear' empties
    ;; the citations but keeps uncited keys, so a reused processor would
    ;; print every key asked for before.
    (citeproc-clear processor)
    (citeproc-append-citations
     (list (citeproc-citation-create
            :cites (mapcar (lambda (key) (list (cons 'id key))) keys)))
     processor)
    (car (citeproc-render-bib processor (or format 'org) 'no-links t
                              (lambda (items _params)
                                (string-join items (or separator "\n")))))))

(defun my/reference-render-citation (citation style-name &optional format)
  "Return CITATION, a `citeproc-citation' structure, as text.
Rendered in the CSL style STYLE-NAME as a citation -- the note of a note
style, the parenthesis of an author-date one -- in the language of the
current buffer, as the first citation of the work in a document.
FORMAT is a citeproc output format, `plain' by default.  The keys are
not checked: `my/reference-missing' does that."
  (let ((processor (my/reference--processor style-name (my/reference--locale))))
    (citeproc-clear processor)
    (citeproc-append-citations (list citation) processor)
    (car (citeproc-render-citations processor (or format 'plain) 'no-links))))

(defun my/reference--select ()
  "Ask for references with citar; return their keys."
  (unless (fboundp 'citar-select-refs)
    (user-error "citar is not installed"))
  (or (citar-select-refs)
      (user-error "No reference chosen")))

(defun my/reference--insert (keys style-name separator)
  "Insert the references to KEYS in STYLE-NAME, joined by SEPARATOR.
Org markup (/italic/) in Org buffers, plain text elsewhere."
  (insert (my/reference-render keys style-name
                               (if (derived-mode-p 'org-mode) 'org 'plain)
                               separator)))

(defun my/insert-short-reference (keys)
  "Insert a short reference to each of KEYS at point.
Interactively, KEYS are chosen with citar.  In the style
`my/reference-short-style': Given Family i Given Family, /Title/ (Year),
several joined by \"; \"."
  (interactive (list (my/reference--select)))
  (my/reference--insert keys my/reference-short-style "; "))

(defun my/insert-full-reference (keys)
  "Insert the full reference to each of KEYS at point, one per line.
Interactively, KEYS are chosen with citar.  In `my/reference-full-style',
by default the export style, as an exported bibliography lists it."
  (interactive (list (my/reference--select)))
  (my/reference--insert keys (or my/reference-full-style my/csl-default-style) "\n"))

;; PDF and EPUB viewers (pdf-tools, nov): 117b-document-viewers.el, since
;; 2026-10-25zd.  `my/open-bib-pdf-right' above opens the attachment in
;; whatever mode Emacs has for it.

;; ============================================================
;; CITATION KEY CHECKER
;; ============================================================
;; Citation keys are generated from metadata by Better BibTeX, so
;; correcting a year or an author can rewrite the key of an item
;; already cited in finished text.  Turning off "regenerate citation
;; key when item changes" prevents that going forward, but says
;; nothing about what has already drifted, or about items added before
;; the setting was changed.
;;
;; The failure is loud rather than silent -- a stale key exports as
;; NO_ITEM_DATA -- but only at export time, which may be long after the
;; writing.  This scans for it on demand instead.

(defvar my/cite-check-directories nil
  "Directories scanned by `my/cite-check-keys'.
Nil means the whole notes tree.")

(defconst my/cite--citation-re "\\[cite[^]]*\\]"
  "Match a whole Org citation, from `[cite' to its closing bracket.")

(defconst my/cite--key-re "@\\([^]&;, \t\n]+\\)"
  "Match one key inside a citation, capturing the key itself.
Deliberately permissive: Better BibTeX keys may contain characters
this configuration has no reason to enumerate, so the pattern excludes
the delimiters instead of listing what is allowed.")

(defun my/cite--bibliography-keys ()
  "Return a hash table of every key defined in the global bibliography."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (bib (if (listp org-cite-global-bibliography)
                     org-cite-global-bibliography
                   (list org-cite-global-bibliography)))
      (when (file-readable-p bib)
        (with-temp-buffer
          (insert-file-contents bib)
          (goto-char (point-min))
          (while (re-search-forward "^[ \t]*@[a-zA-Z]+[{(]\\([^,\n]+\\)," nil t)
            (puthash (string-trim (match-string 1)) bib table)))))
    table))

(defun my/cite--org-files ()
  "Return the Org files to scan."
  (let ((dirs (or my/cite-check-directories (list my-notes-dir))))
    (seq-mapcat (lambda (dir)
                  (when (file-directory-p dir)
                    (directory-files-recursively dir "\\.org\\'")))
                dirs)))

(defun my/cite--collect-uses ()
  "Return (KEY FILE LINE) for every citation key used in the scanned files."
  (let (uses)
    (dolist (file (my/cite--org-files))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward my/cite--citation-re nil t)
          (let ((citation (match-string 0))
                (line (line-number-at-pos (match-beginning 0)))
                (start 0))
            ;; One citation may hold several keys: [cite:@a; @b].
            (while (string-match my/cite--key-re citation start)
              (push (list (match-string 1 citation) file line) uses)
              (setq start (match-end 0)))))))
    (nreverse uses)))

(defun my/cite-check-keys ()
  "Report citation keys used in notes that are absent from the bibliography.

Run this before submitting a text, or occasionally over the whole
collection.  A key that no longer resolves exports as NO_ITEM_DATA,
which is visible but only once the document has been produced."
  (interactive)
  (let* ((defined (my/cite--bibliography-keys))
         (uses (my/cite--collect-uses))
         (missing (seq-remove (lambda (use) (gethash (car use) defined)) uses))
         (grouped (make-hash-table :test #'equal)))
    (dolist (use missing)
      (push (cdr use) (gethash (car use) grouped)))
    (if (null missing)
        (message "All %d citation key use(s) resolve against %d bibliography entr(ies)"
                 (length uses) (hash-table-count defined))
      (with-current-buffer (get-buffer-create "*Citation Keys*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (special-mode)
          (insert (format "Unresolved citation keys: %d\n"
                          (hash-table-count grouped))
                  (format "Checked %d use(s) against %d entr(ies) in %s\n\n"
                          (length uses) (hash-table-count defined)
                          (string-join org-cite-global-bibliography ", "))
                  "RET on a location opens it.\n\n")
          (maphash
           (lambda (key places)
             (insert (format "  %s\n" key))
             (dolist (place (nreverse places))
               (let ((file (car place)) (line (cadr place)))
                 (insert "      ")
                 (insert-text-button
                  (format "%s:%d" (file-name-nondirectory file) line)
                  'follow-link t
                  'help-echo file
                  'action (lambda (_b)
                            (find-file file)
                            (goto-char (point-min))
                            (forward-line (1- line))))
                 (insert "\n")))
             (insert "\n"))
           grouped)
          (goto-char (point-min))))
      (display-buffer "*Citation Keys*")
      (message "%d unresolved key(s) -- see *Citation Keys*"
               (hash-table-count grouped)))))

(defun my/cite-rename-key (old new)
  "Replace citation key OLD with NEW across the scanned Org files.

Offered because the usual cause of an unresolved key is a rename in
Zotero rather than a mistake in the text, and the same stale key is
then likely to appear in several places.

Only occurrences inside a citation are touched: the same string in
ordinary prose is left alone, which matters because keys often look
like ordinary words."
  (interactive
   (let ((old (read-string "Replace key: ")))
     (list old (read-string (format "Replace %s with: " old)))))
  (let ((changed 0)
        (files 0))
    (dolist (file (my/cite--org-files))
      (let ((hits 0))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward my/cite--citation-re nil t)
            (let* ((start (match-beginning 0))
                   (end (match-end 0))
                   (citation (match-string 0))
                   (replaced (replace-regexp-in-string
                              (concat "@" (regexp-quote old) "\\b")
                              (concat "@" new) citation t t)))
              (unless (equal citation replaced)
                (delete-region start end)
                (goto-char start)
                (insert replaced)
                (setq hits (1+ hits)))))
          (when (> hits 0)
            (write-region (point-min) (point-max) file nil 'silent)))
        (when (> hits 0)
          (setq changed (+ changed hits))
          (setq files (1+ files)))))
    (message "Replaced %d occurrence(s) of %s in %d file(s)" changed old files)))

(global-set-key (kbd "C-c b c") #'my/cite-check-keys)

;; ============================================================
;; THE BIBLIOGRAPHY MENU (C-c x)
;; ============================================================
;; Every entry runs a command of citar, citar-denote or this file, so the
;; menu is this module's: it works with a .bib from any program.  Until
;; 2026-10-25zg it was 18-zotero-transient.el, a module of its own, off
;; on a new machine; `my/zotero-menu' is kept as an obsolete name.
;; Zotero's attachments folder (417c-zotero.el) is set in `,' with the
;; other settings of the bibliography.

(require 'transient)

(transient-define-prefix my/bibliography-menu ()
  "Bibliography & reading (C-c x)"

  ["Notes"
   [("n" "New note from reference"        citar-create-note)
    ("o" "Open existing bib note"         citar-denote-open-note)]]

  ["Open"
   [("f" "Open PDF for this note"         my/open-bib-pdf-right)
    ("e" "Open BibTeX entry"              citar-open-entry)
    ("u" "Open URL / DOI"                 citar-open-links)
    ("i" "Insert citation [cite:@key]"    citar-insert-citation)]]

  ["Insert reference at point"
   [("R" "Full bibliography"              my/insert-full-reference)
    ("S" "Short: Author, Title (Year)"    my/insert-short-reference)]]

  ["Maintenance"
   [("c" "Check keys in notes"            my/cite-check-keys)
    ("C" "Rename a citation key"          my/cite-rename-key)
    ("?" "Check CSL export setup"         my/csl-check-setup)
    ("," "Settings: .bib files, CSL, Zotero" my/bibliography-settings)]]

  [("q" "Quit" transient-quit-one)])

(define-obsolete-function-alias 'my/zotero-menu #'my/bibliography-menu "2026-10-25")

;; The key, and the entry in the Integrations column of the Tools menu
;; (C-c n t z), which this module inserts so that turning it off takes
;; the entry out and leaves the menu whole.
(my/module-keys t '(("C-c x" . my/bibliography-menu)))
(with-eval-after-load '212-transient
  (when (fboundp 'my/transient-entries)
    (my/transient-entries
     t '((insert my/notes-tools-menu "q" ("z" "Bibliography →" my/bibliography-menu))))))

(provide '417-bibliography)
;;; 417-bibliography.el ends here
