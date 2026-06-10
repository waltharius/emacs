;;; 16-org-export.el --- Org export and PDF settings -*- lexical-binding: t; -*-
;;; Commentary:
;; Global settings for org-mode export, primarily LaTeX/PDF output.
;;
;; Features:
;; - 2.5cm margins via geometry package
;; - No author, no date, no section numbers, no inline ToC in document body
;; - PDF bookmarks/ToC visible in PDF reader (via hyperref template)
;; - Output structure mirrors notes: ~/notes/pdf/pks/, ~/notes/pdf/journal/ etc.
;; - PDF filename taken from #+title: as-is (spaces preserved, safe chars only)
;; - Denote links stripped to their description text
;; - Overwrite prompt when PDF already exists (overwrite / rename with index)
;; - ALL build files isolated in /tmp and deleted after export
;; - Language auto-detected from #+filetags:: :en: -> English, default -> Polish
;; - Journal files (#+filetags: :journal:) use Playpen Sans Hebrew font in PDF
;; - polyglossia: correct hyphenation for detected language
;; - csquotes: quotation marks matching detected language
;; - setspace 1.2: line spacing matching Emacs visual appearance
;; - verbatim/code blocks wrap correctly (no overflow past margins)
;; - Batch ANY-mode: files matching any of the given keywords
;; - Batch ALL-mode: files matching ALL of the given keywords simultaneously
;;
;; Usage:
;;   C-c p                             - export current buffer to PDF
;;   M-x my/org-export-pdf-by-keyword  - batch, ANY keyword matches
;;   M-x my/org-export-pdf-by-all-keywords - batch, ALL keywords must match

;;; Code:

(require 'ox-latex)
(require 'ox)
(require 'cl-lib)

;; ============================================================
;; LATEX / ORG EXPORT SETTINGS
;; ============================================================

(setq org-latex-packages-alist
      '(("margin=2.5cm" "geometry" t)))

(setq org-export-with-author          nil)
(setq org-export-with-date            nil)
(setq org-export-with-toc             nil)
(setq org-export-with-section-numbers nil)

;; hyperref via Org's own template - avoids double-\usepackage clash
(setq org-latex-hyperref-template
      "\\hypersetup{\n  bookmarks=true,\n  bookmarksnumbered=true,\n  colorlinks=false,\n  pdfauthor={%a},\n  pdftitle={%t},\n  pdfkeywords={%k},\n  pdfsubject={%d},\n  pdfcreator={%c},\n  pdflang={%L}}\n")

(setq org-latex-default-class "article")
(setq org-latex-compiler      "lualatex")

;; ============================================================
;; LATEX DOCUMENT CLASSES
;; ============================================================
;; Language is detected per-file from #+filetags::
;;   :en: tag present -> English (hyphenation, csquotes style)
;;   no :en: tag      -> Polish (default)
;;
;; Class selection:
;;   :journal: tag  -> journal-article  (Playpen Sans Hebrew)
;;   otherwise      -> article          (default system font)
;;
;; Shared preamble for both classes:
;;   polyglossia  - hyphenation patterns for detected language
;;   csquotes     - quotation marks matching detected language
;;   setspace     - line spacing 1.2 (matches Emacs line-spacing 0.2)
;;   microtype    - better paragraph justification (lualatex-native)
;;   emergencystretch - last-resort stretch to avoid verbatim overflow
;;
;; journal-article additionally:
;;   fontspec     - must come BEFORE polyglossia with lualatex
;;   Playpen Sans Hebrew - handwriting-style font

(defun my/--latex-preamble (language journal-p)
  "Build the LaTeX document preamble string.
LANGUAGE is a polyglossia language name string (\"polish\" or \"english\").
JOURNAL-P non-nil adds fontspec + Playpen Sans Hebrew before the rest."
  (concat
   (when journal-p
     "\\usepackage{fontspec}\n\\setmainfont{Playpen Sans Hebrew}\n")
   "\\usepackage{polyglossia}\n"
   (format "\\setmainlanguage{%s}\n" language)
   ;; csquotes autostyle picks quote style from polyglossia language
   "\\usepackage[autostyle]{csquotes}\n"
   "\\usepackage{setspace}\n"
   "\\setstretch{1.2}\n"
   "\\usepackage{microtype}\n"
   "\\setlength{\\emergencystretch}{3em}"))

(defconst my/--latex-section-levels
  '(("\\section{%s}"       . "\\section*{%s}")
    ("\\subsection{%s}"    . "\\subsection*{%s}")
    ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
    ("\\paragraph{%s}"     . "\\paragraph*{%s}")
    ("\\subparagraph{%s}"  . "\\subparagraph*{%s}"))
  "Standard LaTeX section hierarchy used by all export classes.")

;; Register both base classes once at startup.
;; Language variants are handled dynamically per-file via
;; my/--org-latex-class, which temporarily overrides
;; org-latex-default-class during export.
(with-eval-after-load 'ox-latex

  ;; Standard class - language placeholder, replaced at export time
  (add-to-list 'org-latex-classes
               `("article"
                 ,(concat "\\documentclass[11pt,a4paper]{article}\n"
                          (my/--latex-preamble "polish" nil))
                 ,@my/--latex-section-levels))

  ;; Journal class - language placeholder, replaced at export time
  (add-to-list 'org-latex-classes
               `("journal-article"
                 ,(concat "\\documentclass[11pt,a4paper]{article}\n"
                          (my/--latex-preamble "polish" t))
                 ,@my/--latex-section-levels))

  ;; English variants - same structure, English polyglossia
  (add-to-list 'org-latex-classes
               `("article-en"
                 ,(concat "\\documentclass[11pt,a4paper]{article}\n"
                          (my/--latex-preamble "english" nil))
                 ,@my/--latex-section-levels))

  (add-to-list 'org-latex-classes
               `("journal-article-en"
                 ,(concat "\\documentclass[11pt,a4paper]{article}\n"
                          (my/--latex-preamble "english" t))
                 ,@my/--latex-section-levels)))

;; ============================================================
;; DENOTE LINK FILTER
;; ============================================================

(defun my/--filter-denote-link (link-str link-obj _info)
  "Strip denote: links to their description text only.
Returns description string for denote links, nil for all others."
  (when (string= (org-element-property :type link-obj) "denote")
    (if (string-match "\\\\href{[^}]*}{\\(.*\\)}" link-str)
        (match-string 1 link-str)
      "")))

(add-to-list 'org-export-filter-link-functions
             #'my/--filter-denote-link)

;; ============================================================
;; OUTPUT DIRECTORY
;; ============================================================

(defvar my-pdf-output-dir (expand-file-name "~/notes/pdf/")
  "Root directory for exported PDFs.
Subfolders mirror the notes silo structure automatically.")

(defun my/--pdf-dest-dir (org-file)
  "Return the PDF output subdirectory for ORG-FILE.
Mirrors the silo subfolder under `my-pdf-output-dir'.
Example: ~/notes/pks/foo.org -> ~/notes/pdf/pks/"
  (let* ((notes-root (expand-file-name my-notes-dir))
         (file-dir   (expand-file-name (file-name-directory org-file)))
         (rel        (when (string-prefix-p notes-root file-dir)
                       (substring file-dir (length notes-root))))
         (silo       (when (and rel (not (string-empty-p rel)))
                       (car (split-string rel "/" t))))
         (dest-dir   (if silo
                         (expand-file-name (concat silo "/") my-pdf-output-dir)
                       my-pdf-output-dir)))
    (unless (file-exists-p dest-dir)
      (make-directory dest-dir t))
    dest-dir))

(defun my/ensure-pdf-dir ()
  "Create `my-pdf-output-dir' root if it does not exist."
  (unless (file-exists-p my-pdf-output-dir)
    (make-directory my-pdf-output-dir t)))

;; ============================================================
;; OVERWRITE HANDLING
;; ============================================================

(defun my/--next-available-path (path)
  "Return PATH if it does not exist, else append (2), (3)... until free."
  (if (not (file-exists-p path))
      path
    (let* ((dir  (file-name-directory path))
           (base (file-name-base path))
           (ext  (file-name-extension path t))
           (n    2)
           candidate)
      (while (progn
               (setq candidate
                     (expand-file-name (format "%s (%d)%s" base n ext) dir))
               (file-exists-p candidate))
        (cl-incf n))
      candidate)))

(defun my/--resolve-pdf-dest (pdf-dest)
  "Prompt if PDF-DEST exists: overwrite, rename with index, or cancel.
Returns resolved path or nil if cancelled."
  (if (not (file-exists-p pdf-dest))
      pdf-dest
    (let* ((fname   (file-name-nondirectory pdf-dest))
           (renamed (my/--next-available-path pdf-dest))
           (choice  (read-char-choice
                     (format "'%s' exists.  [o]verwrite  [r]ename -> '%s'  [q]uit: "
                             fname (file-name-nondirectory renamed))
                     '(?o ?r ?q))))
      (pcase choice
        (?o pdf-dest)
        (?r renamed)
        (?q nil)))))

;; ============================================================
;; INTERNAL HELPERS
;; ============================================================

(defun my/--org-title (org-file)
  "Return #+title: value from ORG-FILE, or nil."
  (with-temp-buffer
    (insert-file-contents org-file)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title:[ \t]*\\(.+\\)" nil t)
      (string-trim (match-string 1)))))

(defun my/--title-to-filename (title)
  "Convert TITLE to a safe filename; keep spaces, diacritics, capitalisation.
Strips only: / \\ : * ? \" < > | and control characters."
  (replace-regexp-in-string "[/\\\\:*?\"<>|[:cntrl:]]" "" title))

(defun my/--org-has-tag-p (org-file tag)
  "Return non-nil if ORG-FILE has TAG in its #+filetags: line."
  (with-temp-buffer
    (insert-file-contents org-file nil 0 2000)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+filetags:[ \t]*\\(.+\\)" nil t)
      (member tag (split-string (match-string 1) ":" t " \t")))))

(defun my/--org-latex-class (org-file)
  "Return the LaTeX class name to use when exporting ORG-FILE.

Decision matrix:
  journal + en tag -> journal-article-en  (Playpen Sans + English)
  journal, no en   -> journal-article     (Playpen Sans + Polish)
  no journal + en  -> article-en          (default font + English)
  no journal, no en -> article            (default font + Polish)"
  (let ((journal-p (my/--org-has-tag-p org-file "journal"))
        (english-p (my/--org-has-tag-p org-file "en")))
    (cond
     ((and journal-p english-p) "journal-article-en")
     (journal-p                 "journal-article")
     (english-p                 "article-en")
     (t                         "article"))))

(defun my/--denote-all-keywords ()
  "Sorted, deduplicated list of all Denote keywords in use across notes."
  (let ((keywords '()))
    (dolist (f (directory-files-recursively
                (expand-file-name my-notes-dir) "\\.org$"))
      (with-temp-buffer
        (insert-file-contents f nil 0 2000)
        (goto-char (point-min))
        (when (re-search-forward "^#\\+filetags:[ \t]*\\(.+\\)" nil t)
          (dolist (tag (split-string (match-string 1) ":" t " \t"))
            (push tag keywords)))))
    (sort (delete-dups keywords) #'string<)))

;; ============================================================
;; INTERNAL: export one .org file to PDF
;; ============================================================

(defun my/--export-file-to-pdf (org-file)
  "Export ORG-FILE to PDF in the appropriate ~/notes/pdf/<silo>/ subfolder.

Class and language are chosen automatically from #+filetags::
  :journal: -> Playpen Sans Hebrew font
  :en:       -> English hyphenation and quotation marks
  (both can be combined; absence of :en: defaults to Polish)

Filename from #+title:; fallback to Denote base name.
Prompts on overwrite.  All build files go to /tmp and are deleted.
Returns destination path on success, nil on failure or cancel."
  (let* ((raw-title   (my/--org-title org-file))
         (pdf-name    (if raw-title
                          (my/--title-to-filename raw-title)
                        (file-name-base org-file)))
         (dest-dir    (my/--pdf-dest-dir org-file))
         (pdf-dest    (expand-file-name (concat pdf-name ".pdf") dest-dir))
         (pdf-dest    (my/--resolve-pdf-dest pdf-dest)))
    (unless pdf-dest
      (message "Export cancelled: %s" (file-name-nondirectory org-file))
      (cl-return-from my/--export-file-to-pdf nil))
    (let* ((latex-class (my/--org-latex-class org-file))
           (build-dir   (make-temp-file "org-latex-" t))
           (tex-file    (expand-file-name (concat pdf-name ".tex") build-dir))
           (pdf-src     (expand-file-name (concat pdf-name ".pdf") build-dir))
           (result      nil))
      (unwind-protect
          (progn
            (with-current-buffer (find-file-noselect org-file)
              (let ((org-latex-default-class latex-class))
                (org-export-to-file 'latex tex-file)))
            (let ((exit-code
                   (call-process
                    "latexmk" nil
                    (get-buffer-create "*org-pdf-build-log*")
                    nil
                    "-lualatex"
                    "-interaction=nonstopmode"
                    (concat "-output-directory=" build-dir)
                    "-f"
                    tex-file)))
              (if (and (zerop exit-code) (file-exists-p pdf-src))
                  (progn
                    (rename-file pdf-src pdf-dest t)
                    (setq result pdf-dest))
                (message "Build failed for %s (exit %s) - see *org-pdf-build-log*"
                         (file-name-nondirectory org-file) exit-code))))
        (when (file-exists-p build-dir)
          (delete-directory build-dir t)))
      result)))

;; ============================================================
;; SINGLE FILE EXPORT  (C-c p)
;; ============================================================

(defun my/org-export-to-pdf ()
  "Export current Org buffer to PDF -> ~/notes/pdf/<silo>/.
Language detected from #+filetags:: :en: -> English, default -> Polish.
Journal files use Playpen Sans Hebrew; others use default font.
Filename from #+title:. Prompts if PDF already exists."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Buffer is not visiting a file"))
  (unless (string-suffix-p ".org" (buffer-file-name))
    (user-error "Current buffer is not an .org file"))
  (my/ensure-pdf-dir)
  (message "Exporting to PDF...")
  (let ((dest (my/--export-file-to-pdf (buffer-file-name))))
    (if dest
        (message "✓ PDF saved to: %s" dest)
      (message "✗ Export cancelled or failed"))))

;; ============================================================
;; INTERNAL: batch export helper
;; ============================================================

(defun my/--batch-export-and-report (matching label)
  "Export all files in MATCHING list to PDF, then show results buffer.
LABEL is a string describing the search (shown in results header)."
  (let ((ok '()) (err '()))
    (message "Found %d file(s). Exporting..." (length matching))
    (dolist (f matching)
      (message "  Exporting: %s" (file-name-nondirectory f))
      (condition-case e
          (let ((dest (my/--export-file-to-pdf f)))
            (if dest
                (push (file-name-nondirectory dest) ok)
              (push (file-name-nondirectory f) err)))
        (error
         (push (format "%s  [%s]" (file-name-nondirectory f)
                       (error-message-string e))
               err))))
    (with-current-buffer (get-buffer-create "*PDF Export Results*")
      (erase-buffer)
      (insert (format "PDF export — %s\n" label))
      (insert (make-string 50 ?-) "\n")
      (if ok
          (progn
            (insert (format "\n✓ OK (%d):\n" (length ok)))
            (dolist (f (nreverse ok)) (insert (format "  %s\n" f))))
        (insert "\nNo files exported successfully.\n"))
      (when err
        (insert (format "\n✗ Failed/cancelled (%d):\n" (length err)))
        (dolist (f (nreverse err)) (insert (format "  %s\n" f))))
      (insert (format "\nOutput directory: %s\n" my-pdf-output-dir))
      (display-buffer (current-buffer)))))

(defun my/--all-notes-org-files ()
  "Return list of all .org files under note directories."
  (seq-mapcat
   (lambda (dir)
     (when (file-directory-p dir)
       (directory-files-recursively dir "\\.org$")))
   my-tasks-agenda-dirs))

;; ============================================================
;; BATCH EXPORT - ANY mode  (files with ANY of the keywords)
;; ============================================================

(defun my/org-export-pdf-by-keyword (keywords-input)
  "Batch export: files whose names contain ANY of the given keywords.

Keywords selected with completion (TAB) from all Denote tags in use.
Separate multiple keywords with commas. Each file exported at most once.
Output mirrors notes structure: ~/notes/pdf/pks/, ~/notes/pdf/journal/ etc."
  (interactive
   (list
    (mapconcat #'identity
               (completing-read-multiple
                "ANY keyword(s) [comma-sep, TAB]: "
                (my/--denote-all-keywords)
                nil nil)
               " ")))
  (when (string-empty-p (string-trim keywords-input))
    (user-error "Please provide at least one keyword"))
  (my/ensure-pdf-dir)
  (let* ((keywords (split-string (string-trim keywords-input) "[ \t]+" t))
         (matching
          (delete-dups
           (seq-filter
            (lambda (f)
              (let ((fname (file-name-nondirectory f)))
                (seq-some (lambda (kw)
                            (string-match-p (regexp-quote kw) fname))
                          keywords)))
            (my/--all-notes-org-files)))))
    (if (null matching)
        (message "No files found matching ANY of: %s" (string-join keywords ", "))
      (my/--batch-export-and-report
       matching
       (format "ANY of: %s"
               (mapconcat (lambda (k) (format "\"%s\"" k)) keywords ", "))))))

;; ============================================================
;; BATCH EXPORT - ALL mode  (files with ALL keywords simultaneously)
;; ============================================================

(defun my/org-export-pdf-by-all-keywords (keywords-input)
  "Batch export: files whose names contain ALL of the given keywords.

A file is included only if EVERY keyword appears in its filename.
Keywords selected with completion (TAB) from all Denote tags in use.
Separate multiple keywords with commas.
Output mirrors notes structure: ~/notes/pdf/pks/, ~/notes/pdf/journal/ etc."
  (interactive
   (list
    (mapconcat #'identity
               (completing-read-multiple
                "ALL keyword(s) [comma-sep, TAB]: "
                (my/--denote-all-keywords)
                nil nil)
               " ")))
  (when (string-empty-p (string-trim keywords-input))
    (user-error "Please provide at least one keyword"))
  (my/ensure-pdf-dir)
  (let* ((keywords (split-string (string-trim keywords-input) "[ \t]+" t))
         (matching
          (delete-dups
           (seq-filter
            (lambda (f)
              (let ((fname (file-name-nondirectory f)))
                (seq-every-p (lambda (kw)
                               (string-match-p (regexp-quote kw) fname))
                             keywords)))
            (my/--all-notes-org-files)))))
    (if (null matching)
        (message "No files found matching ALL of: %s" (string-join keywords ", "))
      (my/--batch-export-and-report
       matching
       (format "ALL of: %s"
               (mapconcat (lambda (k) (format "\"%s\"" k)) keywords ", "))))))

(provide '16-org-export)
;;; 16-org-export.el ends here
