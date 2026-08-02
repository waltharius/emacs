;;; 29-writing-export.el --- ODT and DOCX export -*- lexical-binding: t; -*-
;;; Commentary:
;; Office-format export for text that leaves Emacs: a chapter sent to a
;; supervisor, an article sent to an editor.
;;
;; WHY ORG'S EXPORTER AND NOT PANDOC.  Pandoc reads Org and writes DOCX
;; directly, in one step, and produces real Word footnotes from org-cite
;; citations.  It is the obvious choice and it is the wrong one here, for
;; two reasons:
;;
;;   Its Org reader is a reimplementation, not Org.  `#+INCLUDE:' with a
;;   heading target (`file.org::*Heading') is not supported: pandoc warns
;;   and omits the content.  `:only-contents t' is ignored, so the heading
;;   comes through anyway.  Both are how 20-transclusion.el writes INCLUDE
;;   pairs, so a manuscript assembled that way would export short without
;;   failing.
;;
;;   It renders citations with its own citeproc.  PDF goes through Org and
;;   citeproc-el; if DOCX went through pandoc, the same source could
;;   produce two different citation apparatus, and the difference would
;;   only appear in the copy already sent.
;;
;; So: Org exports to ODT, and LibreOffice converts ODT to DOCX.  Same
;; exporter as PDF, same INCLUDE handling, same citation renderer.  The
;; conversion step is mechanical.
;;
;; ODT IS ALSO A DELIVERABLE.  Word has opened ODT since 2007 and
;; OnlyOffice reads it natively, so `my/org-export-to-odt' is often
;; enough.  DOCX matters when the document comes back: a supervisor's
;; tracked changes and comments survive a DOCX round-trip through Word
;; more reliably than an ODT one.
;;
;; RELATION TO OTHER MODULES
;; - 16-org-export.el: reuses its filename, destination and overwrite
;;   helpers when present, and falls back to local equivalents when not.
;;   Also relies on its denote-link filter being backend-aware -- the
;;   LaTeX-only version deleted link descriptions from ODT output.
;; - 17-bibliography.el: citations come out through org-cite and CSL.
;;   A note style produces real footnotes in ODT.
;; - 28-writing-projects.el: optional.  When a file declares `#+project:',
;;   output goes to that project's directory instead of the notes tree.
;; - 12-transient.el: menu entries appended via `my/transient-append'.
;;
;; Docs: ~/.emacs.d/function_helper.org::#office-export

;;; Code:

(require 'ox)
(require 'cl-lib)

(defgroup my/writing-export nil
  "Export to office formats."
  :group 'org)

(defcustom my/office-output-dir (expand-file-name "~/notes/export/")
  "Root directory for exported office documents.

Used for notes that do not belong to a writing project.  Subdirectories
mirror the silo structure, as the PDF output does."
  :type 'directory
  :group 'my/writing-export)

(defcustom my/office-project-subdirectory "export"
  "Subdirectory of a project directory receiving its exports."
  :type 'string
  :group 'my/writing-export)

(defcustom my/office-convert-timeout 120
  "Seconds to wait for LibreOffice to convert a document.

Conversion runs synchronously because the result has to be moved into
place afterwards.  The first run of the session is much slower than the
rest, since LibreOffice starts a headless instance."
  :type 'integer
  :group 'my/writing-export)

;; ============================================================
;; ODT BACKEND
;; ============================================================
;; ox-odt ships with Org but is not loaded by default.

(with-eval-after-load 'org
  (require 'ox-odt nil t))

(with-eval-after-load 'ox-odt
  ;; Org can convert the ODT itself, but doing that through
  ;; `org-odt-preferred-output-format' would apply to every ODT export
  ;; including the ones that only want ODT.  Conversion is driven per
  ;; command here instead.
  (setq org-odt-preferred-output-format nil))

;; ============================================================
;; HELPERS
;; ============================================================
;; 16-org-export.el defines equivalents of the first three.  They are
;; reused when it is loaded and reimplemented when it is not, so that
;; this module works on its own without duplicating behaviour when both
;; are present.

(defun my/office--org-title (org-file)
  "Return the #+title: of ORG-FILE, or nil."
  (if (fboundp 'my/--org-title)
      (my/--org-title org-file)
    (with-temp-buffer
      (insert-file-contents org-file nil 0 2000)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+title:[ \t]*\\(.+\\)" nil t)
        (string-trim (match-string 1))))))

(defun my/office--safe-name (title)
  "Turn TITLE into a file name, keeping spaces and diacritics."
  (if (fboundp 'my/--title-to-filename)
      (my/--title-to-filename title)
    (replace-regexp-in-string "[/\\\\:*?\"<>|[:cntrl:]]" "" title)))

(defun my/office--resolve-dest (dest)
  "Prompt when DEST exists; return the path to use, or nil to cancel."
  (if (fboundp 'my/--resolve-pdf-dest)
      (my/--resolve-pdf-dest dest)
    (if (not (file-exists-p dest))
        dest
      (when (y-or-n-p (format "%s exists.  Overwrite? "
                              (file-name-nondirectory dest)))
        dest))))

(defun my/office--project-of (org-file)
  "Return the writing project ORG-FILE belongs to, or nil.
Nil whenever 28-writing-projects.el is absent, which makes the project
directory an enhancement rather than a requirement."
  (when (and (fboundp 'my/writing--file-projects)
             (fboundp 'my/writing--project-directory))
    (car (my/writing--file-projects org-file))))

(defun my/office--dest-dir (org-file)
  "Return the output directory for ORG-FILE, creating it if needed.

A file belonging to a writing project exports into that project, since
the document is a deliverable of the project rather than of the notes.
Everything else mirrors the silo structure under `my/office-output-dir'."
  (let* ((project (my/office--project-of org-file))
         (dir
          (if project
              (expand-file-name my/office-project-subdirectory
                                (my/writing--project-directory project))
            (let* ((root (expand-file-name my-notes-dir))
                   (here (expand-file-name (file-name-directory org-file)))
                   (rel (when (string-prefix-p root here)
                          (substring here (length root))))
                   (silo (when (and rel (not (string-empty-p rel)))
                           (car (split-string rel "/" t)))))
              (if silo
                  (expand-file-name (concat silo "/") my/office-output-dir)
                my/office-output-dir)))))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (file-name-as-directory dir)))

;; ============================================================
;; CONVERSION
;; ============================================================

(defun my/office--soffice ()
  "Return the LibreOffice binary, or nil."
  (or (executable-find "soffice") (executable-find "libreoffice")))

(defun my/office--convert (odt-file format)
  "Convert ODT-FILE to FORMAT with LibreOffice, in place.
Returns the produced file, or nil.  FORMAT is a LibreOffice filter name
such as \"docx\"."
  (let ((soffice (my/office--soffice))
        (dir (file-name-directory odt-file))
        (out (concat (file-name-sans-extension odt-file) "." format)))
    (unless soffice
      (user-error "LibreOffice not found -- install it, or export ODT only"))
    (with-timeout (my/office-convert-timeout
                   (progn (message "LibreOffice timed out after %ds"
                                   my/office-convert-timeout)
                          nil))
      (let ((exit (call-process soffice nil
                                (get-buffer-create "*office-convert-log*") nil
                                "--headless" "--convert-to" format
                                "--outdir" (directory-file-name dir)
                                odt-file)))
        (if (and (zerop exit) (file-exists-p out))
            out
          (message "Conversion failed (exit %s) -- see *office-convert-log*" exit)
          nil)))))

;; ============================================================
;; EXPORT
;; ============================================================

(defun my/office--export (org-file format)
  "Export ORG-FILE to FORMAT, which is either `odt' or `docx'.
Returns the destination path, or nil when cancelled or failed."
  (let* ((title (my/office--org-title org-file))
         (name (if title (my/office--safe-name title) (file-name-base org-file)))
         (dir (my/office--dest-dir org-file))
         (dest (my/office--resolve-dest
                (expand-file-name (format "%s.%s" name format) dir))))
    (when dest
      ;; Build in a temporary directory: ox-odt writes several
      ;; intermediate files, and LibreOffice adds its own, none of which
      ;; belong beside the finished document.
      (let ((build (make-temp-file "org-odt-" t))
            (result nil))
        (unwind-protect
            (let* ((odt (expand-file-name (concat name ".odt") build))
                   (produced
                    (with-current-buffer (find-file-noselect org-file)
                      (org-export-to-file 'odt odt))))
              (when (and produced (file-exists-p odt))
                (let ((final (if (equal format "odt")
                                 odt
                               (my/office--convert odt format))))
                  (when (and final (file-exists-p final))
                    (rename-file final dest t)
                    (setq result dest)))))
          (when (file-directory-p build)
            (delete-directory build t)))
        result))))

;;;###autoload
(defun my/org-export-to-odt ()
  "Export the current Org buffer to ODT.

Output goes to the project's export directory when the file declares
`#+project:', otherwise to `my/office-output-dir' mirroring the silo.
Citations are rendered by org-cite: with a CSL note style they become
real footnotes, with \"ibid.\" resolved from actual adjacency."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless (and file (string-suffix-p ".org" file))
      (user-error "Not visiting an Org file"))
    (when (buffer-modified-p) (save-buffer))
    (message "Exporting to ODT...")
    (let ((dest (my/office--export file "odt")))
      (if dest (message "✓ ODT saved to: %s" dest)
        (message "✗ Export cancelled or failed")))))

;;;###autoload
(defun my/org-export-to-docx ()
  "Export the current Org buffer to DOCX, via ODT and LibreOffice.

Use this when the document is going to come back edited: tracked changes
and comments made in Word survive a DOCX round-trip more reliably than
an ODT one.  For a document that is only read, ODT is enough and skips
the conversion."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless (and file (string-suffix-p ".org" file))
      (user-error "Not visiting an Org file"))
    (unless (my/office--soffice)
      (user-error "LibreOffice not found -- `my/org-export-to-odt' still works"))
    (when (buffer-modified-p) (save-buffer))
    (message "Exporting to DOCX (first conversion of the session is slow)...")
    (let ((dest (my/office--export file "docx")))
      (if dest (message "✓ DOCX saved to: %s" dest)
        (message "✗ Export cancelled or failed")))))

;;;###autoload
(defun my/office-check-setup ()
  "Report whether office export is ready, and what is missing if not.

Worth running before relying on it: every failure mode here is quiet.
A missing ox-odt exports nothing, a missing LibreOffice produces an ODT
where a DOCX was asked for, and a citation processor that is not CSL
produces a document with no bibliography at all."
  (interactive)
  (let (problems)
    (unless (featurep 'ox-odt)
      (push "ox-odt is not loaded -- ODT export unavailable" problems))
    (unless (my/office--soffice)
      (push "LibreOffice not found -- DOCX conversion unavailable" problems))
    (when (and (boundp 'org-cite-export-processors)
               (not (eq (cadr (assq t org-cite-export-processors)) 'csl)))
      (push "org-cite fallback processor is not csl -- citations will export unformatted"
            problems))
    (unless (fboundp 'my/--filter-denote-link)
      (push "denote link filter missing (16-org-export.el not loaded)" problems))
    (if problems
        (message "Office export NOT ready:\n- %s"
                 (string-join (nreverse problems) "\n- "))
      (message "Office export ready: ODT via ox-odt, DOCX via %s"
               (my/office--soffice)))))

;; ============================================================
;; MENU
;; ============================================================

;; Anchored on "Q", the last entry of the Export group in
;; `my/notes-export-menu'.  Appending each new key after the previous
;; one would chain the additions together, so a change to any single
;; anchor would silently drop everything after it.

(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-export-menu "Q"
                       '("O" "Export to ODT" my/org-export-to-odt))
  (my/transient-append 'my/notes-export-menu "Q"
                       '("W" "Export to DOCX" my/org-export-to-docx))
  (my/transient-append 'my/notes-export-menu "Q"
                       '("?" "Check office export setup" my/office-check-setup)))

(provide '29-writing-export)
;;; 29-writing-export.el ends here
