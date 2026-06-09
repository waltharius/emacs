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
;;
;; Usage: M-x my/org-export-to-pdf  or  C-c p

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
2. Export .org -> .tex -> .pdf using latexmk in a temp directory.
3. Move the resulting PDF to ~/notes/pdf/.
4. Delete all temporary build files (.tex, .aux, .log, .out, .toc, etc.)."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Buffer is not visiting a file"))
  (my/ensure-pdf-dir)
  (let* ((org-file  (buffer-file-name))
         (base-name (file-name-base org-file))
         ;; Build in a dedicated temp dir - keeps all intermediate files away
         ;; from the notes directory
         (build-dir (make-temp-file "org-latex-" t))
         (pdf-src   (expand-file-name (concat base-name ".pdf") build-dir))
         (pdf-dest  (expand-file-name (concat base-name ".pdf") my-pdf-output-dir)))
    ;; Use latexmk: handles reruns automatically, respects org-latex-compiler
    (let ((org-latex-pdf-process
           (list (concat "latexmk -lualatex -interaction=nonstopmode"
                         " -output-directory=" build-dir
                         " -f %f"))))
      (org-latex-export-to-pdf nil nil nil nil
                               `(:output-file ,(expand-file-name
                                                (concat base-name ".tex")
                                                build-dir))))
    ;; Move PDF to final destination
    (if (file-exists-p pdf-src)
        (progn
          (rename-file pdf-src pdf-dest t)
          (message "PDF saved to: %s" pdf-dest))
      (message "ERROR: PDF not found at %s - check *org-export-latex* buffer" pdf-src))
    ;; Remove the entire temp build directory
    (delete-directory build-dir t)
    (message "Temp files cleaned up.")))

;; ============================================================
;; LATEX / ORG EXPORT SETTINGS
;; ============================================================

(with-eval-after-load 'ox-latex
  ;; --- Margins ---
  ;; geometry is loaded here; hyperref is handled separately below
  ;; to avoid the 'Option clash for package hyperref' error.
  (setq org-latex-packages-alist
        '(("margin=2.5cm" "geometry" t)))

  ;; --- Suppress author, date, section numbers, and inline ToC ---
  (setq org-export-with-author          nil)
  (setq org-export-with-date            nil)
  (setq org-export-with-toc             nil) ; No ToC in document body
  (setq org-export-with-section-numbers nil) ; No numbered headings

  ;; --- hyperref configuration via Org's dedicated template ---
  ;; Org inserts hyperref itself using org-latex-hyperref-template.
  ;; Setting options here avoids the double-\usepackage clash.
  ;; bookmarks=true     -> PDF reader shows outline panel
  ;; bookmarksnumbered  -> outline entries show section numbers (internal only)
  ;; colorlinks=false   -> no coloured links in print
  (setq org-latex-hyperref-template
        "\\hypersetup{\n  bookmarks=true,\n  bookmarksnumbered=true,\n  colorlinks=false,\n  pdfauthor={%a},\n  pdftitle={%t},\n  pdfkeywords={%k},\n  pdfsubject={%d},\n  pdfcreator={%c},\n  pdflang={%L}}\n")

  ;; --- Default document class and compiler ---
  (setq org-latex-default-class "article")
  (setq org-latex-compiler      "lualatex"))

(provide '16-org-export)
;;; 16-org-export.el ends here
