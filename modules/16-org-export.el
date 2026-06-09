;;; 16-org-export.el --- Org export and PDF settings -*- lexical-binding: t; -*-
;;; Commentary:
;; Global settings for org-mode export, primarily LaTeX/PDF output.
;;
;; Features:
;; - 2.5cm margins via geometry package
;; - No author, no date, no section numbers, no inline ToC in document body
;; - PDF bookmarks/ToC visible in PDF reader (via hyperref template)
;; - All PDFs saved to ~/notes/pdf/ (directory auto-created if missing)
;; - PDF filename taken from #+title: (not the Denote filename)
;; - ALL intermediate build files isolated in /tmp and deleted after export
;; - Batch export: export all .org files matching a keyword
;;
;; Usage:
;;   C-c p                            - export current buffer to PDF
;;   M-x my/org-export-pdf-by-keyword - batch export by keyword

;;; Code:

(require 'ox-latex)
(require 'ox)

;; ============================================================
;; LATEX / ORG EXPORT SETTINGS
;; ============================================================

;; --- Margins ---
(setq org-latex-packages-alist
      '(("margin=2.5cm" "geometry" t)))

;; --- Suppress author, date, section numbers, and inline ToC ---
(setq org-export-with-author          nil)
(setq org-export-with-date            nil)
(setq org-export-with-toc             nil)
(setq org-export-with-section-numbers nil)

;; --- hyperref via Org's own template (avoids double-\usepackage clash) ---
(setq org-latex-hyperref-template
      "\\hypersetup{\n  bookmarks=true,\n  bookmarksnumbered=true,\n  colorlinks=false,\n  pdfauthor={%a},\n  pdftitle={%t},\n  pdfkeywords={%k},\n  pdfsubject={%d},\n  pdfcreator={%c},\n  pdflang={%L}}\n")

;; --- Document class and compiler ---
(setq org-latex-default-class "article")
(setq org-latex-compiler      "lualatex")

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
  "Return the #+title: value from ORG-FILE, or nil if not found.
Reads the file in a temporary buffer without activating org-mode
to avoid triggering hooks."
  (with-temp-buffer
    (insert-file-contents org-file)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title:[ \t]*\\(.+\\)" nil t)
      (string-trim (match-string 1)))))

(defun my/--title-to-filename (title)
  "Convert TITLE string to a safe, lowercase filename without spaces.
Example: \"Szkoła Frankfurcka\" -> \"szkola-frankfurcka\"
Handles Polish diacritics by transliterating them."
  (let* ((tr '((?ą . "a") (?ć . "c") (?ę . "e") (?ł . "l") (?ń . "n")
               (?ó . "o") (?ś . "s") (?ź . "z") (?ż . "z")
               (?Ą . "a") (?Ć . "c") (?Ę . "e") (?Ł . "l") (?Ń . "n")
               (?Ó . "o") (?Ś . "s") (?Ź . "z") (?Ż . "z")))
         (result (mapconcat
                  (lambda (ch)
                    (or (cdr (assq ch tr)) (string ch)))
                  title "")))
    (thread-last result
                 downcase
                 (replace-regexp-in-string "[^a-z0-9]+" "-")
                 (replace-regexp-in-string "^-+\\|-+$" ""))))

;; ============================================================
;; INTERNAL: export one .org file to PDF
;; ============================================================

(defun my/--export-file-to-pdf (org-file)
  "Export ORG-FILE to PDF and place result in `my-pdf-output-dir'.

The PDF filename is derived from the file's #+title: value.
If no #+title: is found, the Denote base filename is used as fallback.

All build files (.tex .aux .log .out .toc .fls .fdb_latexmk) are
created inside a temporary directory under /tmp and deleted afterwards.
The original .org file is never touched.

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
          ;; Step 1: export .org -> .tex directly into build-dir
          (with-current-buffer (find-file-noselect org-file)
            (org-export-to-file 'latex tex-file))

          ;; Step 2: run latexmk inside build-dir
          ;; We call the process directly so we control CWD and output dir.
          ;; Running twice is not needed - latexmk decides reruns itself.
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
      ;; unwind: always delete the temp directory
      (when (file-exists-p build-dir)
        (delete-directory build-dir t)))
    result))

;; ============================================================
;; SINGLE FILE EXPORT  (C-c p)
;; ============================================================

(defun my/org-export-to-pdf ()
  "Export the current Org buffer to PDF -> `my-pdf-output-dir'.
Filename is taken from #+title:; build files go to /tmp and are deleted."
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
;; BATCH EXPORT by keyword  (M-x my/org-export-pdf-by-keyword)
;; ============================================================

(defun my/org-export-pdf-by-keyword (keyword)
  "Export all .org files whose name contains KEYWORD to PDF.
Searches all note directories defined in `my-tasks-agenda-dirs'.
Filenames in ~/notes/pdf/ are derived from each file's #+title:.
Shows a summary in *PDF Export Results* when done."
  (interactive "sKeyword (substring of filename): ")
  (when (string-empty-p keyword)
    (user-error "Keyword must not be empty"))
  (my/ensure-pdf-dir)
  (let* ((search-dirs (seq-filter #'file-directory-p my-tasks-agenda-dirs))
         (all-org-files
          (seq-mapcat
           (lambda (dir)
             (directory-files-recursively dir "\\.org$"))
           search-dirs))
         (matching
          (seq-filter
           (lambda (f)
             (string-match-p (regexp-quote keyword)
                             (file-name-nondirectory f)))
           all-org-files))
         (ok  '())
         (err '()))
    (if (null matching)
        (message "No .org files found with '%s' in their name." keyword)
      (message "Found %d matching file(s). Exporting..." (length matching))
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
        (insert (format "PDF export — keyword: \"%s\"\n" keyword))
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
