;;; 17-bibliography.el --- Zotero/Citar bibliography integration -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; Docs: ~/.emacs.d/function_helper.org::#citing-howto

;;; Commentary:
;; Citation and bibliography management via Citar + Zotero Better BibTeX.
;;
;; Prerequisites (already satisfied in packages.nix):
;;   - a .bib file auto-exported by Better BibTeX in Zotero; where it is
;;     is an option, `my/bibliography-files' (C-c x ,), ~/notes/refs.bib
;;     by default
;;   - poppler, poppler_utils, pkg-config, libpng in home.packages (for pdf-tools)
;;
;; Workflow:
;;   1. M-x my/zotero-menu (C-c x) → n  — create note from Zotero ref, PDF opens on the right
;;   2. M-x my/zotero-menu (C-c x) → f  — reopen PDF on the right for the current note
;;   3. M-x my/zotero-menu (C-c x) → R  — insert full bibliography at point
;;   4. M-x my/zotero-menu (C-c x) → S  — insert short reference (Author, Title, Year) at point

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
  "Citations: the bibliography file, Zotero's attachments, CSL export."
  :tag "Bibliography and citations"
  :group 'mypks-writing)

(defcustom my/bibliography-files '("refs.bib")
  "The BibTeX files citations come from, usually exported by Zotero.
Better BibTeX keeps the export up to date.  A relative name is relative
to the notes folder (`my-notes-dir') and follows it; an absolute name,
such as ~/Zotero/refs.bib, stays where it is.  Several files are read
together.  Takes effect at once."
  :type '(repeat (file :tag "BibTeX file"))
  :tag "Bibliography files (.bib from Zotero)"
  :set (my/settings-apply-on-set #'my/bibliography-apply)
  :group 'my/bibliography)

(defcustom my/zotero-storage-directory "~/Zotero/storage/"
  "Folder holding the PDFs and other attachments Zotero stores.
The default is where Zotero keeps them unless told otherwise.
Where citar looks for the file of a reference (`C-c x f').  Nil for
none.  Takes effect at once."
  :type '(choice (directory :tag "Folder") (const :tag "None" nil))
  :tag "Zotero attachments folder (PDFs)"
  :set (my/settings-apply-on-set #'my/bibliography-apply)
  :group 'my/bibliography)

(defun my/bibliography-file-list ()
  "Return `my/bibliography-files' as absolute file names."
  (mapcar (lambda (file) (expand-file-name file my-notes-dir))
          my/bibliography-files))

(defvar citar-bibliography)
(defvar citar-library-paths)
(defvar citar-notes-paths)
(defvar org-cite-global-bibliography)

(defvar my/bibliography--told nil
  "Missing files already reported this session.")

(defun my/bibliography-apply ()
  "Point citar and org-cite at the bibliography files and Zotero's folder.
Also points citar's notes at the silo with role `notes'.  Says once per
session when a bibliography file does not exist."
  (let ((files (my/bibliography-file-list)))
    (setq org-cite-global-bibliography files)
    (with-eval-after-load 'citar
      (setq citar-bibliography files
            citar-library-paths (and my/zotero-storage-directory
                                     (list (expand-file-name my/zotero-storage-directory)))
            citar-notes-paths (list (my/silo-dir-by-role 'notes))))
    (dolist (file files)
      (unless (or (file-readable-p file) (member file my/bibliography--told))
        (push file my/bibliography--told)
        (message "Bibliography: %s not found; set the file in C-c x , (Bibliography files)"
                 (abbreviate-file-name file))))))

(defun my/bibliography-settings ()
  "Open the settings of the bibliography: files, Zotero folder, CSL."
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

(defun my/csl--default-style-file ()
  "Return the default style file to use, absolute, or nil if there is none.
The user's styles folder first, then the bundled copy."
  (seq-find (lambda (file) (my/csl--valid-file-p file "<style"))
            (list (expand-file-name my/csl-default-style my/csl-styles-dir)
                  (expand-file-name my/csl-default-style my/csl-bundled-styles-dir))))

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
;; HELPER: Insert full bibliography entry at point
;; ============================================================
;; Prompts to select a reference, then inserts a formatted
;; bibliography line at point, e.g.:
;; Cioran, Emil. /O niedogodności narodzin/. Warszawa: Aletheia, 2021.

(defun my/insert-full-reference ()
  "Select a reference and insert full bibliography at point."
  (interactive)
  (let* ((key (car (citar-select-refs)))
         (author   (citar-get-value "author" key))
         (title    (citar-get-value "title" key))
         (publisher (citar-get-value "publisher" key))
         (location  (citar-get-value "location" key))
         (year     (or (citar-get-value "year" key)
                       (citar-get-value "date" key)))
         (location-publisher
          (cond ((and location publisher) (concat location ": " publisher))
                (publisher publisher)
                (location location)
                (t nil)))
         (ref (concat author ". /" title "/."
                      (when location-publisher (concat " " location-publisher ","))
                      (when year (concat " " year))
                      ".")))
    (insert ref)))

;; ============================================================
;; HELPER: Insert short reference (Author, Title, Year) at point
;; ============================================================
;; Inserts a compact reference, e.g.:
;; Cioran, Emil. /O niedogodności narodzin/ (2021).

(defun my/insert-short-reference ()
  "Select a reference and insert short Author, Title (Year) at point."
  (interactive)
  (let* ((key (car (citar-select-refs)))
         (author (citar-get-value "author" key))
         (title  (citar-get-value "title" key))
         (year   (or (citar-get-value "year" key)
                     (citar-get-value "date" key)))
         (ref (concat author ". /" title "/"
                      (when year (concat " (" year ")"))
                      ".")))
    (insert ref)))

;; ============================================================
;; PDF-TOOLS — native PDF viewer
;; ============================================================

;; `pdf-loader-install', pdf-tools' own on-demand setup, not
;; `pdf-tools-install' in :config: that ran whenever pdf-tools was
;; loaded -- also by the byte compilation of its own files during the
;; first install -- and built the epdfinfo server then, unasked (the
;; build may ask for the sudo password to install libraries).  Now
;; the first PDF opened loads pdf-tools, which asks before building.

(defun my/bibliography--pdf-on-demand ()
  "Set PDF Tools up to load, and build its server, with the first PDF.
`pdf-loader-install' sets pdf-tools up at once when pdf-tools is loaded
already -- as it is in the session that installed it, by the byte
compilation of its own files -- and so asks about building the server
in the middle of the first start (and fails in batch, where nobody can
answer).  Told that pdf-tools is not loaded, it waits for a PDF, as in
every later session."
  ;; Loaded first, outside the binding below: a `provide' inside it
  ;; would be undone when the binding ends.
  (when (require 'pdf-loader nil t)
    ;; `cl-progv' binds `features' dynamically.  It has no `defvar' in
    ;; Lisp, so a plain `let' in this lexically bound file would bind a
    ;; local name `featurep' never reads; `dlet' would, but makes the
    ;; compiler ask for a prefix on a name that is Emacs's own.
    (cl-progv '(features) (list (remq 'pdf-tools features))
      (pdf-loader-install))))

(use-package pdf-tools
  :ensure t
  :defer t
  :init
  (my/bibliography--pdf-on-demand)
  :config
  (add-hook 'pdf-view-mode-hook
            (lambda () (display-line-numbers-mode -1))))

;; ============================================================
;; NOV — ePub reader
;; ============================================================

(use-package nov
  :ensure t
  :mode ("\\.epub\\'" . nov-mode))

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

(provide '17-bibliography)
;;; 17-bibliography.el ends here
