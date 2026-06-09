;;; 16-org-export.el --- Org export and PDF settings -*- lexical-binding: t; -*-
;;; Commentary:
;; Global settings for org-mode export, primarily LaTeX/PDF output.
;;
;; Features:
;; - 2.5cm margins via geometry package
;; - No author, no date, no inline table of contents in the document body
;; - PDF bookmarks/ToC visible in PDF reader (via hyperref)
;; - All PDFs saved to ~/notes/pdf/ (directory auto-created if missing)
;; - Temporary LaTeX build files cleaned up after export

;;; Code:

;; ============================================================
;; OUTPUT DIRECTORY
;; ============================================================

(defvar my-pdf-output-dir (expand-file-name "~/notes/pdf/")
  "Directory where all exported PDF files are saved.")

(defun my/ensure-pdf-dir ()
  "Create the PDF output directory if it does not exist."
  (unless (file-exists-p my-pdf-output-dir)
    (make-directory my-pdf-output-dir t)
    (message "Created PDF output directory: %s" my-pdf-output-dir)))

;; ============================================================
;; PDF EXPORT FUNCTION
;; ============================================================

(defun my/org-export-to-pdf ()
  "Export current Org buffer to PDF.

Steps:
1. Ensure ~/notes/pdf/ exists.
2. Export to PDF via LaTeX in the system temp directory.
3. Move the resulting PDF to ~/notes/pdf/.
4. Delete all temporary build files (.tex, .aux, .log, .out, .toc, etc.)."
  (interactive)
  (my/ensure-pdf-dir)
  (let* ((org-file (buffer-file-name))
         (base-name (file-name-base org-file))
         ;; Build in a dedicated temp dir to isolate all intermediate files
         (build-dir (make-temp-file "org-latex-" t))
         (pdf-src   (expand-file-name (concat base-name ".pdf") build-dir))
         (pdf-dest  (expand-file-name (concat base-name ".pdf") my-pdf-output-dir)))
    ;; Tell ox-latex to write output into the temp build directory
    (let ((org-latex-pdf-process
           (list (concat "lualatex -interaction nonstopmode"
                         " -output-directory " build-dir " %f")
                 (concat "lualatex -interaction nonstopmode"
                         " -output-directory " build-dir " %f"))))
      ;; Export .org -> .tex -> .pdf
      (org-latex-export-to-pdf nil nil nil nil
                               `(:output-file ,(expand-file-name
                                                (concat base-name ".tex")
                                                build-dir))))
    ;; Move PDF to final destination
    (if (file-exists-p pdf-src)
        (progn
          (rename-file pdf-src pdf-dest t)
          (message "PDF saved to: %s" pdf-dest))
      (message "ERROR: PDF not found at %s" pdf-src))
    ;; Remove the entire temp build directory (all intermediate files)
    (delete-directory build-dir t)
    (message "Build directory cleaned up.")))

;; ============================================================
;; LATEX / ORG EXPORT SETTINGS
;; ============================================================

(with-eval-after-load 'ox-latex
  ;; --- Margins ---
  (setq org-latex-packages-alist
        '(("margin=2.5cm" "geometry" t)))

  ;; --- Suppress author, date, and inline ToC in document body ---
  (setq org-export-with-author nil)
  (setq org-export-with-date   nil)
  (setq org-export-with-toc    nil)  ; No ToC rendered as body text

  ;; --- PDF bookmarks (ToC visible in PDF reader, not in body) ---
  ;; hyperref is already included by Org by default; this makes sure
  ;; bookmarks are enabled and the PDF outline is built from headings.
  (add-to-list 'org-latex-packages-alist
               '("bookmarks=true,bookmarksnumbered=true" "hyperref" t))

  ;; --- Default document class and compiler ---
  (setq org-latex-default-class "article")
  (setq org-latex-compiler      "lualatex"))

(provide '16-org-export)
;;; 16-org-export.el ends here
