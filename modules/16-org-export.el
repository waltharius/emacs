;;; 16-org-export.el --- Org export and PDF settings -*- lexical-binding: t; -*-
;;; Commentary:
;; Global settings for org-mode export, primarily LaTeX/PDF output.
;;
;; Features:
;; - 2.5cm margins via geometry package
;; - No author, no date, no section numbers, no inline ToC in document body
;; - PDF bookmarks/ToC visible in PDF reader (via hyperref template)
;; - All PDFs saved to ~/notes/pdf/ (directory auto-created if missing)
;; - PDF filename taken from #+title: as-is (spaces preserved, safe chars only)
;; - Denote [[denote:ID][Description]] links stripped to plain Description text
;; - ALL build files isolated in /tmp and deleted after export
;; - Batch export: multiple keywords (space-separated), each file exported once
;;
;; Usage:
;;   C-c p                            - export current buffer to PDF
;;   M-x my/org-export-pdf-by-keyword - batch export by keyword(s)

;;; Code:

(require 'ox-latex)
(require 'ox)

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
;; DENOTE LINK FILTER
;; ============================================================
;; org-export-filter-link-functions is called by Org for every single
;; link element *after* it has been translated to the target format
;; (here: LaTeX).  At this point the link is already a LaTeX string
;; like \href{denote:20240101T120000}{Opis} or just the raw path.
;;
;; The right place to intercept it is *before* translation, using
;; org-export-filter-link-functions which receives the original Org
;; link object.  We check the link type; if it is "denote", we return
;; only the description (content) - already rendered to LaTeX by Org -
;; and discard the href wrapper entirely.
;;
;; If the link has no description we return an empty string so nothing
;; leaks into the output.

(defun my/--filter-denote-link (link-str link-obj _info)
  "Export filter for links: strip denote: links, keep only their description.
LINK-STR is the already-rendered LaTeX string for this link.
LINK-OBJ is the original Org element (a link parse-tree node).
Returns description text as plain LaTeX, or empty string if no description."
  (when (string= (org-element-property :type link-obj) "denote")
    ;; org-element-contents gives us the list of child elements (= description).
    ;; We render them back to LaTeX via org-export-data.
    (let ((contents (org-element-contents link-obj)))
      (if contents
          ;; Return the description as-is; Org already rendered it in link-str
          ;; but wrapped in \href{...}{DESC} - we want only DESC.
          ;; Simplest: extract from link-str with a regexp.
          (if (string-match "\\\\href{[^}]*}{\\(.*\\)}" link-str)
              (match-string 1 link-str)
            ;; fallback: use link-str as-is (shouldn't normally happen)
            link-str)
        "")))
  ;; For non-denote links, return nil = keep Org's default rendering
  )

(add-to-list 'org-export-filter-link-functions
             #'my/--filter-denote-link)

;; ============================================================
;; OUTPUT DIRECTORY
;; ============================================================

(defvar my-pdf-output-dir (expand-file-name "~/notes/pdf/")
  "Directory where all exported PDF files are saved.")

(defun my/ensure-pdf-dir ()
  "Create `my-pdf-output-dir' if it does not exist."
  (unless (file-exists-p my-pdf-output-dir)
    (make-directory my-pdf-output-dir t)
    (message "Created PDF output directory: %s" my-pdf-output-dir)))

;; ============================================================
;; INTERNAL HELPERS
;; ============================================================

(defun my/--org-title (org-file)
  "Return the #+title: value from ORG-FILE as a string, or nil.
Reads the file without activating org-mode to avoid triggering hooks."
  (with-temp-buffer
    (insert-file-contents org-file)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title:[ \t]*\\(.+\\)" nil t)
      (string-trim (match-string 1)))))

(defun my/--title-to-filename (title)
  "Convert TITLE to a safe filename, preserving spaces and capitalisation.
Only strips characters that are genuinely unsafe in filenames:
/ \\ : * ? \" < > | and control characters.
Everything else (Polish diacritics, dashes, spaces) is kept as-is.
Example: \"Nietzsche - notatki z kolokwium\" -> \"Nietzsche - notatki z kolokwium\""
  (replace-regexp-in-string "[/\\\\:*?\"<>|[:cntrl:]]" "" title))

;; ============================================================
;; INTERNAL: export one .org file to PDF
;; ============================================================

(defun my/--export-file-to-pdf (org-file)
  "Export ORG-FILE to PDF and place result in `my-pdf-output-dir'.

Filename is taken from #+title: (spaces and diacritics preserved).
Fallback to Denote base name if no #+title: is found.

All build files (.tex .aux .log .out .toc .fls .fdb_latexmk) are
created inside a /tmp directory and deleted after export.
The original .org file is never modified.

Returns the destination PDF path on success, nil on failure."
  (let* ((raw-title  (my/--org-title org-file))
         (pdf-name   (if raw-title
                         (my/--title-to-filename raw-title)
                       (file-name-base org-file)))
         (build-dir  (make-temp-file "org-latex-" t))
         (tex-file   (expand-file-name (concat pdf-name ".tex") build-dir))
         (pdf-src    (expand-file-name (concat pdf-name ".pdf") build-dir))
         (pdf-dest   (expand-file-name (concat pdf-name ".pdf") my-pdf-output-dir))
         (result     nil))
    (unwind-protect
        (progn
          ;; Step 1: .org -> .tex directly into build-dir
          (with-current-buffer (find-file-noselect org-file)
            (org-export-to-file 'latex tex-file))

          ;; Step 2: latexmk builds PDF entirely inside build-dir
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
      ;; unwind: always remove temp dir regardless of success or error
      (when (file-exists-p build-dir)
        (delete-directory build-dir t)))
    result))

;; ============================================================
;; SINGLE FILE EXPORT  (C-c p)
;; ============================================================

(defun my/org-export-to-pdf ()
  "Export the current Org buffer to PDF -> `my-pdf-output-dir'.
Filename comes from #+title:; build files go to /tmp and are deleted.
Denote links are stripped to their description text."
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
      (message "✗ Export failed - check *org-pdf-build-log* buffer"))))

;; ============================================================
;; BATCH EXPORT by keyword(s)  (M-x my/org-export-pdf-by-keyword)
;; ============================================================

(defun my/org-export-pdf-by-keyword (keywords-input)
  "Export .org files whose names match one or more keywords to PDF.

KEYWORDS-INPUT is a space-separated string of keywords, e.g.
\"kolokwium heidegger\".  A file is included if its name contains
ANY of the keywords.  Each matching file is exported at most once
regardless of how many keywords it matches.

Searches all directories in `my-tasks-agenda-dirs'.
Results are shown in *PDF Export Results*."
  (interactive "sKeyword(s) - space-separated: ")
  (when (string-empty-p (string-trim keywords-input))
    (user-error "Please provide at least one keyword"))
  (my/ensure-pdf-dir)
  (let* ((keywords    (split-string (string-trim keywords-input) "[ \t]+" t))
         (search-dirs (seq-filter #'file-directory-p my-tasks-agenda-dirs))
         (all-org-files
          (seq-mapcat
           (lambda (dir)
             (directory-files-recursively dir "\\.org$"))
           search-dirs))
         (matching
          (delete-dups
           (seq-filter
            (lambda (f)
              (let ((fname (file-name-nondirectory f)))
                (seq-some (lambda (kw)
                            (string-match-p (regexp-quote kw) fname))
                          keywords)))
            all-org-files)))
         (ok  '())
         (err '()))
    (if (null matching)
        (message "No .org files found matching: %s"
                 (mapconcat #'identity keywords ", "))
      (message "Found %d unique file(s). Exporting..." (length matching))
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
        (insert (format "PDF export — keyword(s): %s\n"
                        (mapconcat (lambda (k) (format "\"%s\"" k))
                                   keywords ", ")))
        (insert (make-string 50 ?-) "\n")
        (if ok
            (progn
              (insert (format "\n✓ OK (%d):\n" (length ok)))
              (dolist (f (nreverse ok)) (insert (format "  %s\n" f))))
          (insert "\nNo files exported successfully.\n"))
        (when err
          (insert (format "\n✗ Failed (%d):\n" (length err)))
          (dolist (f (nreverse err)) (insert (format "  %s\n" f))))
        (insert (format "\nOutput directory: %s\n" my-pdf-output-dir))
        (display-buffer (current-buffer))))))

(provide '16-org-export)
;;; 16-org-export.el ends here
