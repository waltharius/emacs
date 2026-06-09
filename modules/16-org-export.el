;;; 16-org-export.el --- Org export and PDF settings -*- lexical-binding: t; -*-
;;; Commentary:
;; Global settings for org-mode export, primarily LaTeX/PDF output.
;;
;; Features:
;; - 2.5cm margins via geometry package
;; - No author, no date, no section numbers, no inline ToC in document body
;; - PDF bookmarks/ToC visible in PDF reader (via hyperref template)
;; - All PDFs saved to ~/notes/pdf/ (directory auto-created if missing)
;; - Temporary LaTeX build files cleaned up after export
;; - Batch export: export all .org files matching a keyword
;;
;; Usage:
;;   C-c p          - export current buffer to PDF
;;   M-x my/org-export-pdf-by-keyword  - batch export by keyword

;;; Code:

;; ox-latex must be loaded before we configure or call any of its functions.
;; Using require here (not with-eval-after-load) so the backend is available
;; immediately when this module is loaded at startup.
(require 'ox-latex)

;; ============================================================
;; LATEX / ORG EXPORT SETTINGS
;; ============================================================

;; --- Margins ---
;; geometry handles page layout; hyperref is configured separately below
;; via org-latex-hyperref-template to avoid 'Option clash for package hyperref'.
(setq org-latex-packages-alist
      '(("margin=2.5cm" "geometry" t)))

;; --- Suppress author, date, section numbers, and inline ToC ---
(setq org-export-with-author          nil)
(setq org-export-with-date            nil)
(setq org-export-with-toc             nil) ; No ToC rendered as body text
(setq org-export-with-section-numbers nil) ; No numbered headings

;; --- hyperref via Org's own template (avoids double-\usepackage clash) ---
;; bookmarks=true        -> PDF reader shows outline/bookmark panel
;; bookmarksnumbered     -> bookmark entries carry section numbers
;; colorlinks=false      -> no coloured link boxes in printed output
(setq org-latex-hyperref-template
      "\\hypersetup{\n  bookmarks=true,\n  bookmarksnumbered=true,\n  colorlinks=false,\n  pdfauthor={%a},\n  pdftitle={%t},\n  pdfkeywords={%k},\n  pdfsubject={%d},\n  pdfcreator={%c},\n  pdflang={%L}}\n")

;; --- Document class and compiler ---
(setq org-latex-default-class "article")
(setq org-latex-compiler      "lualatex")

;; --- latexmk as the PDF build process ---
;; latexmk handles the number of required compiler reruns automatically.
;; %o = output directory, %f = input .tex file.
(setq org-latex-pdf-process
      '("latexmk -lualatex -interaction=nonstopmode -output-directory=%o -f %f"))

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
;; INTERNAL: export one .org file to PDF
;; ============================================================

(defun my/--export-file-to-pdf (org-file)
  "Export ORG-FILE to PDF and place result in `my-pdf-output-dir'.
All intermediate build files are written to a temp directory and
deleted afterwards.  Returns the destination path on success, nil
on failure."
  (let* ((base-name (file-name-base org-file))
         (build-dir (make-temp-file "org-latex-" t))
         (pdf-src   (expand-file-name (concat base-name ".pdf") build-dir))
         (pdf-dest  (expand-file-name (concat base-name ".pdf") my-pdf-output-dir))
         (result    nil))
    (unwind-protect
        (with-current-buffer (find-file-noselect org-file)
          (org-latex-export-to-pdf
           nil nil nil nil `(:output-file
                             ,(expand-file-name (concat base-name ".tex")
                                               build-dir)))
          (if (file-exists-p pdf-src)
              (progn
                (rename-file pdf-src pdf-dest t)
                (setq result pdf-dest))
            (message "ERROR: PDF not produced for %s" org-file)))
      ;; Always clean up the temp build dir
      (when (file-exists-p build-dir)
        (delete-directory build-dir t)))
    result))

;; ============================================================
;; SINGLE FILE EXPORT  (C-c p)
;; ============================================================

(defun my/org-export-to-pdf ()
  "Export the current Org buffer to PDF -> `my-pdf-output-dir'.
Build files are isolated in a temp directory and removed after export."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Buffer is not visiting a file"))
  (unless (string-suffix-p ".org" (buffer-file-name))
    (user-error "Current buffer is not an .org file"))
  (my/ensure-pdf-dir)
  (let ((dest (my/--export-file-to-pdf (buffer-file-name))))
    (if dest
        (message "PDF saved to: %s" dest)
      (message "Export failed - check *org-export-latex* buffer for details"))))

;; ============================================================
;; BATCH EXPORT by keyword  (M-x my/org-export-pdf-by-keyword)
;; ============================================================

(defun my/org-export-pdf-by-keyword (keyword)
  "Export all .org files whose name contains KEYWORD to PDF.
Searches all note directories defined in `my-tasks-agenda-dirs'.
Each matching file is exported to `my-pdf-output-dir'.
Shows a summary buffer with results when done."
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
           (push (format "%s (%s)" (file-name-nondirectory f) (error-message-string e))
                 err))))
      ;; Show results summary
      (with-current-buffer (get-buffer-create "*PDF Export Results*")
        (erase-buffer)
        (insert (format "PDF export — keyword: \"%s\"\n" keyword))
        (insert (make-string 50 ?-) "\n")
        (if ok
            (progn
              (insert (format "\nOK (%d):\n" (length ok)))
              (dolist (f (nreverse ok)) (insert (format "  + %s\n" f))))
          (insert "\nNo files exported successfully.\n"))
        (when err
          (insert (format "\nFailed (%d):\n" (length err)))
          (dolist (f (nreverse err)) (insert (format "  ! %s\n" f))))
        (insert (format "\nOutput directory: %s\n" my-pdf-output-dir))
        (display-buffer (current-buffer))))))

(provide '16-org-export)
;;; 16-org-export.el ends here
