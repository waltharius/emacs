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
;; - Denote [[denote:ID][Description]] links stripped to plain Description text
;; - Overwrite prompt when PDF already exists (overwrite / rename with index)
;; - ALL build files isolated in /tmp and deleted after export
;; - Batch export: multiple Denote keywords with completion, each file once
;;
;; Usage:
;;   C-c p                            - export current buffer to PDF
;;   M-x my/org-export-pdf-by-keyword - batch export, keyword completion

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
;; Uses org-export-filter-link-functions - called per-link during export,
;; receives both the rendered LaTeX string and the original parse-tree node.
;; For denote: links we extract only the description from \href{...}{DESC}.

(defun my/--filter-denote-link (link-str link-obj _info)
  "Strip denote: links to their description text only.
Returns description string for denote links, nil for all others
(nil = keep Org's default rendering)."
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
Subfolders are created automatically to mirror the notes structure:
  ~/notes/pks/note.org  ->  ~/notes/pdf/pks/Title.pdf
  ~/notes/journal/note.org  ->  ~/notes/pdf/journal/Title.pdf")

(defun my/--pdf-dest-dir (org-file)
  "Return the PDF output subdirectory for ORG-FILE.
Mirrors the silo subfolder under `my-pdf-output-dir'.
Example: ~/notes/pks/foo.org -> ~/notes/pdf/pks/
If the file is not under `my-notes-dir', returns `my-pdf-output-dir' directly."
  (let* ((notes-root (expand-file-name my-notes-dir))
         (file-dir   (expand-file-name (file-name-directory org-file)))
         ;; relative path from notes root, e.g. "pks/" or "journal/"
         (rel        (when (string-prefix-p notes-root file-dir)
                       (substring file-dir (length notes-root))))
         ;; take only the first path component (the silo name)
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
  "If PATH does not exist, return it as-is.
Otherwise append (2), (3), ... before the extension until a free name is found.
Example: if \"Nietzsche.pdf\" exists, returns \"Nietzsche (2).pdf\"."
  (if (not (file-exists-p path))
      path
    (let* ((dir  (file-name-directory path))
           (base (file-name-base path))
           (ext  (file-name-extension path t)) ; includes the dot
           (n    2)
           candidate)
      (while (progn
               (setq candidate
                     (expand-file-name (format "%s (%d)%s" base n ext) dir))
               (file-exists-p candidate))
        (cl-incf n))
      candidate)))

(defun my/--resolve-pdf-dest (pdf-dest)
  "Ask what to do if PDF-DEST already exists.
Offers three choices:
  o - Overwrite the existing file
  r - Rename the new file (appends index)
  q - Quit / cancel this export
Returns the resolved destination path, or nil if the user chose to cancel."
  (if (not (file-exists-p pdf-dest))
      pdf-dest
    (let* ((fname    (file-name-nondirectory pdf-dest))
           (renamed  (my/--next-available-path pdf-dest))
           (choice   (read-char-choice
                      (format "'%s' already exists.  [o]verwrite  [r]ename to '%s'  [q]uit: "
                              fname
                              (file-name-nondirectory renamed))
                      '(?o ?r ?q))))
      (pcase choice
        (?o pdf-dest)
        (?r renamed)
        (?q nil)))))

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
  "Convert TITLE to a safe filename preserving spaces and capitalisation.
Strips only genuinely unsafe chars: / \\ : * ? \" < > | and control chars.
Polish diacritics, dashes, and spaces are kept as written in #+title:."
  (replace-regexp-in-string "[/\\\\:*?\"<>|[:cntrl:]]" "" title))

;; ============================================================
;; INTERNAL: collect Denote keywords from all notes
;; ============================================================

(defun my/--denote-all-keywords ()
  "Return a sorted, deduplicated list of all Denote keywords in use.
Scans #+filetags: lines in all .org files under `my-notes-dir'.
This is the same pool that Denote itself uses for completion."
  (let ((keywords '()))
    (dolist (f (directory-files-recursively
                (expand-file-name my-notes-dir) "\\.org$"))
      (with-temp-buffer
        (insert-file-contents f nil 0 2000) ; read only first 2kb (headers)
        (goto-char (point-min))
        (when (re-search-forward "^#\\+filetags:[ \t]*\\(.+\\)" nil t)
          (let ((tags-str (match-string 1)))
            ;; filetags format: :tag1:tag2:tag3:
            (dolist (tag (split-string tags-str ":" t " \t"))
              (push tag keywords))))))
    (sort (delete-dups keywords) #'string<)))

;; ============================================================
;; INTERNAL: export one .org file to PDF
;; ============================================================

(defun my/--export-file-to-pdf (org-file)
  "Export ORG-FILE to PDF.

Output goes to a subfolder of `my-pdf-output-dir' that mirrors the
notes silo (pks/, journal/, docu/, etc.).

Filename is taken from #+title: (spaces and diacritics preserved).
Fallback to Denote base name if no #+title: is found.

If the destination PDF already exists, the user is prompted:
overwrite, rename with index, or cancel.

All build files are created in /tmp and deleted after export.
The original .org file is never modified.

Returns the destination PDF path on success, nil on failure or cancel."
  (let* ((raw-title  (my/--org-title org-file))
         (pdf-name   (if raw-title
                         (my/--title-to-filename raw-title)
                       (file-name-base org-file)))
         (dest-dir   (my/--pdf-dest-dir org-file))
         (pdf-dest   (expand-file-name (concat pdf-name ".pdf") dest-dir))
         ;; Resolve overwrite before starting the (slow) build
         (pdf-dest   (my/--resolve-pdf-dest pdf-dest)))
    (unless pdf-dest
      (message "Export cancelled for: %s" (file-name-nondirectory org-file))
      (cl-return-from my/--export-file-to-pdf nil))
    (let* ((build-dir  (make-temp-file "org-latex-" t))
           (tex-file   (expand-file-name (concat pdf-name ".tex") build-dir))
           (pdf-src    (expand-file-name (concat pdf-name ".pdf") build-dir))
           (result     nil))
      (unwind-protect
          (progn
            (with-current-buffer (find-file-noselect org-file)
              (org-export-to-file 'latex tex-file))
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
  "Export the current Org buffer to PDF.
Output goes to ~/notes/pdf/<silo>/ mirroring the notes structure.
Filename comes from #+title:; build files go to /tmp and are deleted.
Denote links are stripped to their description text.
If the PDF already exists you are asked whether to overwrite or rename."
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
      (message "✗ Export cancelled or failed - check *org-pdf-build-log* if unexpected"))))

;; ============================================================
;; BATCH EXPORT by Denote keyword(s)
;; ============================================================

(defun my/org-export-pdf-by-keyword (keywords-input)
  "Export .org files whose filenames match one or more Denote keywords.

Keywords are selected interactively with completion drawn from all
keywords actually in use across your notes (same pool as Denote itself).
Type a keyword and press RET; separate multiple keywords with commas
(completing-read-multiple behaviour).

A file is included if its name contains ANY of the selected keywords.
Each matching file is exported at most once.
Subfolder structure under ~/notes/pdf/ mirrors the notes silos.

Results are shown in *PDF Export Results* when done."
  (interactive
   (list
    (mapconcat #'identity
               (completing-read-multiple
                "Keyword(s) [comma-separated, TAB to complete]: "
                (my/--denote-all-keywords)
                nil nil)
               " ")))
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
          (insert (format "\n✗ Failed / cancelled (%d):\n" (length err)))
          (dolist (f (nreverse err)) (insert (format "  %s\n" f))))
        (insert (format "\nOutput directory: %s\n" my-pdf-output-dir))
        (display-buffer (current-buffer))))))

(provide '16-org-export)
;;; 16-org-export.el ends here
