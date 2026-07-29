;;; 17-bibliography.el --- Zotero/Citar bibliography integration -*- lexical-binding: t; -*-
;;; Commentary:
;; Citation and bibliography management via Citar + Zotero Better BibTeX.
;;
;; Prerequisites (already satisfied in packages.nix):
;;   - ~/notes/refs.bib   — auto-exported by Better BibTeX in Zotero
;;   - poppler, poppler_utils, pkg-config, libpng in home.packages (for pdf-tools)
;;
;; Workflow:
;;   1. M-x my/zotero-menu (C-c x) → n  — create note from Zotero ref, PDF opens on the right
;;   2. M-x my/zotero-menu (C-c x) → f  — reopen PDF on the right for the current note
;;   3. M-x my/zotero-menu (C-c x) → R  — insert full bibliography at point
;;   4. M-x my/zotero-menu (C-c x) → S  — insert short reference (Author, Title, Year) at point

;;; Code:

;; ============================================================
;; CITAR — citation search and insertion
;; ============================================================

(use-package citar
  :ensure t
  :custom
  (citar-bibliography '("~/notes/refs.bib"))
  (citar-library-paths '("~/syncthing/Zotero/storage/"))
  (citar-notes-paths (list (expand-file-name "pks/" my-notes-dir)))
  :config
  (setq org-cite-global-bibliography '("~/notes/refs.bib"))
  (setq org-cite-insert-processor 'citar)
  (setq org-cite-follow-processor 'citar)
  (setq org-cite-activate-processor 'citar))

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

(defvar my/csl-styles-dir (expand-file-name "csl/" my-notes-dir)
  "Directory holding CSL style files (.csl).

Kept beside the notes rather than in .emacs.d because a style is part
of a document's requirements, not part of the editor: which style a
text uses is decided by the journal or publisher, and the file has to
travel with the writing.")

(defvar my/csl-default-style "chicago-note-bibliography.csl"
  "CSL style used when a document does not name its own.

A note style, since footnote citations are the default need here.
Override per document instead of changing this, because the style is a
property of the text rather than of the configuration:

  #+cite_export: csl apa.csl")

(with-eval-after-load 'oc
  ;; The styles directory is set unconditionally and first.  Loading
  ;; oc-csl can fail -- most plausibly because citeproc is not
  ;; installed yet -- and an error inside `with-eval-after-load' aborts
  ;; the remainder of the block silently.  With the require on top, a
  ;; missing citeproc therefore left `org-cite-export-processors'
  ;; unset, Org fell back to its built-in `basic' processor, and export
  ;; produced "(Author, Year)" with no bibliography and no visible
  ;; error anywhere.
  (setq org-cite-csl-styles-dir my/csl-styles-dir)
  (unless (require 'oc-csl nil t)
    (message "org-cite: oc-csl unavailable (is citeproc installed?) -- \
citations will export through the basic processor"))
  ;; NOTE the plural.  `org-cite-export-processors' is the global
  ;; setting: an alist keyed by export backend, where `t' is the
  ;; fallback for every backend without its own entry.  The SINGULAR
  ;; `org-cite-export-processor' is a buffer-local variable set by a
  ;; `#+cite_export:' keyword, so assigning it globally has no effect
  ;; -- Org then silently falls back to the `basic' processor, which
  ;; emits a plain "(Author, Year)" and no bibliography.
  ;;
  ;; Each entry is (BACKEND PROCESSOR BIBLIOGRAPHY-STYLE), mirroring
  ;; the argument order of the #+cite_export: keyword.
  (setq org-cite-export-processors
        `((t csl ,my/csl-default-style))))

(defun my/csl-check-setup ()
  "Report whether CSL export is ready, and what is missing if not.

Written because every failure here is silent: a missing style
directory or an unreadable .bib does not raise an error, it just
produces an export with no bibliography, which is easy not to notice
until the document is finished."
  (interactive)
  (let ((problems nil))
    (unless (featurep 'citeproc)
      (push "citeproc is not loaded (M-x package-install RET citeproc)" problems))
    (unless (featurep 'oc-csl)
      (push "oc-csl is not loaded -- export falls back to the basic processor"
            problems))
    (unless (assq t org-cite-export-processors)
      (push "org-cite-export-processors has no fallback entry -- citations will export via the basic processor"
            problems))
    (unless (file-directory-p my/csl-styles-dir)
      (push (format "no CSL styles directory: %s" my/csl-styles-dir) problems))
    (unless (file-directory-p my/csl-locales-dir)
      (push (format "no CSL locales directory: %s" my/csl-locales-dir) problems))
    (let ((locale (expand-file-name "locales-pl-PL.xml" my/csl-locales-dir)))
      (unless (file-readable-p locale)
        (push (format "Polish locale missing: %s" locale) problems)))
    (let ((style (expand-file-name my/csl-default-style my/csl-styles-dir)))
      (unless (file-readable-p style)
        (push (format "default style missing: %s" style) problems)))
    (dolist (bib (if (listp org-cite-global-bibliography)
                     org-cite-global-bibliography
                   (list org-cite-global-bibliography)))
      (unless (file-readable-p bib)
        (push (format "bibliography not readable: %s" bib) problems)))
    (if problems
        (message "CSL export NOT ready:\n- %s" (string-join (nreverse problems) "\n- "))
      (message "CSL export ready: %s via %S + %s"
               my/csl-default-style
               (cadr (assq t org-cite-export-processors))
               (string-join org-cite-global-bibliography ", ")))))

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
  (citar-denote-subdir "pks/")
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

(use-package pdf-tools
  :ensure t
  :magic ("%PDF" . pdf-view-mode)
  :config
  (pdf-tools-install :no-query)
  (add-hook 'pdf-view-mode-hook
            (lambda () (display-line-numbers-mode -1))))

;; ============================================================
;; NOV — ePub reader
;; ============================================================

(use-package nov
  :ensure t
  :mode ("\\.epub\\'" . nov-mode))

(provide '17-bibliography)
;;; 17-bibliography.el ends here
