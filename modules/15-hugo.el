;;; 15-hugo.el --- Hugo documentation workflow integration -*- lexical-binding: t -*-

;;; Commentary:
;; Integration between Denote notes and Hugo static site generator.
;; Notes tagged with :hugosync: are automatically exported to Hugo.

;;; Code:

(require 'denote)

;; Ensure ox-hugo is installed from MELPA
(use-package ox-hugo
  :ensure t
  :after ox
  :config
  (message "✅ ox-hugo loaded for Hugo export"))

;;;; Configuration Variables

(defvar hugo-base-dir (expand-file-name "~/syncthing/hugo/")
  "Base directory for Hugo site.")

(defvar hugo-content-dir (expand-file-name "content/docs/" hugo-base-dir)
  "Hugo content directory for documentation.")

(defvar hugo-notes-source-dir "~/notes/"
  "Source directory containing Denote notes.")

(defvar hugo-sync-tag "hugosync"
  "Tag that marks notes for Hugo export.")

;;;; Helper Functions

(defun hugo--ensure-directories ()
  "Ensure Hugo directory structure exists."
  (unless (file-directory-p hugo-content-dir)
    (make-directory hugo-content-dir t))
  (unless (file-directory-p (expand-file-name "static" hugo-base-dir))
    (make-directory (expand-file-name "static" hugo-base-dir) t)))

(defun hugo--file-has-hugosync-tag-p (file)
  "Check if FILE has the hugosync tag."
  (when (and (file-exists-p file)
             (string-match-p "\\.org\\'" file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      ;; Check both denote tags and org tags
      (or (re-search-forward (format "\\b%s\\b" hugo-sync-tag) 
                            (+ (point-min) 500) t)
          (re-search-forward (format "^#\\+filetags:.*:%s:" hugo-sync-tag)
                            (+ (point-min) 500) t)))))

(defun hugo--extract-note-metadata (file)
  "Extract metadata from Denote note FILE.
Returns a plist with :date, :title, :tags, and :identifier."
  (let ((file-name (file-name-nondirectory file))
        date title tags identifier)
    
    ;; Extract identifier (timestamp)
    (when (string-match "^\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)" file-name)
      (setq identifier (match-string 1 file-name))
      ;; Convert 20260103T102502 to 2026-01-03
      (setq date (format "%s-%s-%s"
                        (substring identifier 0 4)
                        (substring identifier 4 6)
                        (substring identifier 6 8))))
    
    ;; Extract title (between -- and __)
    (when (string-match "--\\(.+?\\)__" file-name)
      (setq title (replace-regexp-in-string 
                   "-" " "
                   (match-string 1 file-name))))
    
    ;; Extract tags from filename (after __)
    (when (string-match "__\\(.+\\)\\.org$" file-name)
      (setq tags (split-string (match-string 1 file-name) "_")))
    
    ;; Remove hugosync from tags list (it's metadata, not content)
    (setq tags (delete hugo-sync-tag tags))
    
    (list :date date
          :title title
          :tags tags
          :identifier identifier)))

(defun hugo--get-org-file-content (file)
  "Get the main content of org FILE, excluding frontmatter."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    
    ;; Skip past all #+PROPERTY lines
    (while (re-search-forward "^#\\+[A-Z_]+:.*$" nil t))
    
    ;; Return everything after frontmatter
    (buffer-substring-no-properties (point) (point-max))))

(defun hugo--create-temp-org-file (file metadata)
  "Create temporary org file with Hugo frontmatter for export.
FILE is source, METADATA is from hugo--extract-note-metadata."
  (let* ((temp-file (make-temp-file "hugo-export" nil ".org"))
         (title (plist-get metadata :title))
         (date (plist-get metadata :date))
         (tags (plist-get metadata :tags))
         (identifier (plist-get metadata :identifier))
         (content (hugo--get-org-file-content file)))
    
    (with-temp-file temp-file
      ;; Insert Hugo-specific org properties
      (insert "#+TITLE: " title "\n")
      (insert "#+DATE: " date "\n")
      (insert "#+HUGO_BASE_DIR: " hugo-base-dir "\n")
      (insert "#+HUGO_SECTION: docs\n")
      (insert "#+HUGO_AUTO_SET_LASTMOD: t\n")
      
      ;; Add custom frontmatter
      (when tags
        (insert "#+HUGO_TAGS: " (mapconcat 'identity tags " ") "\n"))
      
      (insert "#+HUGO_CUSTOM_FRONT_MATTER: :identifier " identifier "\n")
      
      ;; Export filename: date-title (clean, readable)
      (insert "#+EXPORT_FILE_NAME: " date "-" 
              (replace-regexp-in-string " " "-" (downcase title)) "\n")
      
      (insert "\n")
      
      ;; Add the actual content
      (insert content))
    
    temp-file))

(defun hugo--export-note-to-hugo (file)
  "Export Denote note FILE to Hugo markdown.
Uses clean filenames and proper frontmatter."
  (hugo--ensure-directories)
  
  (let* ((metadata (hugo--extract-note-metadata file))
         (temp-file (hugo--create-temp-org-file file metadata)))
    
    ;; Export using ox-hugo
    (with-current-buffer (find-file-noselect temp-file)
      (org-hugo-export-to-md)
      (kill-buffer))
    
    ;; Clean up temp file
    (delete-file temp-file)
    
    (message "✓ Exported to Hugo: %s" 
             (plist-get metadata :title))))

(defun hugo--clean-old-exports (current-file)
  "Remove old Hugo exports when note identifier changes.
Keeps only the export from CURRENT-FILE."
  (let* ((metadata (hugo--extract-note-metadata current-file))
         (current-title (plist-get metadata :title))
         (current-date (plist-get metadata :date))
         (current-export-base (format "%s-%s" 
                                     current-date
                                     (replace-regexp-in-string 
                                      " " "-" 
                                      (downcase current-title)))))
    
    ;; Find all .md files in hugo content dir
    (dolist (hugo-file (directory-files hugo-content-dir t "\\.md$"))
      (let ((base (file-name-sans-extension 
                   (file-name-nondirectory hugo-file))))
        ;; If file has same title but different date/identifier, remove it
        (when (and (string-match-p (regexp-quote (downcase current-title)) base)
                   (not (string= base current-export-base)))
          (delete-file hugo-file)
          (message "🗑 Removed old export: %s" (file-name-nondirectory hugo-file)))))))

;;;; Interactive Commands

(defun hugo-create-documentation-note ()
  "Create a new Denote note tagged for Hugo documentation."
  (interactive)
  (let* ((title (read-string "Documentation title: "))
         (keywords (completing-read-multiple 
                   "Additional keywords (comma-separated): "
                   denote-known-keywords))
         (all-keywords (cons hugo-sync-tag keywords)))
    (denote title all-keywords)
    (message "Created documentation note: %s" title)))

(defun hugo-process-current-note ()
  "Process current note if it has hugosync tag: export to Hugo."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  
  (let ((file (buffer-file-name)))
    (if (hugo--file-has-hugosync-tag-p file)
        (progn
          (save-buffer)
          (hugo--clean-old-exports file)
          (hugo--export-note-to-hugo file)
          (message "✓ Processed for Hugo: %s" (file-name-nondirectory file)))
      (message "Note doesn't have :%s: tag, skipping" hugo-sync-tag))))

(defun hugo-process-all-documentation-notes ()
  "Process all Denote notes tagged with :hugosync:."
  (interactive)
  (let ((processed 0)
        (skipped 0))
    
    ;; First, clean hugo content dir completely
    (when (yes-or-no-p "Clean all Hugo exports and regenerate? ")
      (dolist (file (directory-files hugo-content-dir t "\\.md$"))
        (unless (string-match-p "_index\\.md$" file)
          (delete-file file)))
      (message "🗑 Cleaned all Hugo exports"))
    
    ;; Process all notes
    (dolist (file (denote-directory-files))
      (if (hugo--file-has-hugosync-tag-p file)
          (progn
            (hugo--export-note-to-hugo file)
            (setq processed (1+ processed)))
        (setq skipped (1+ skipped))))
    
    (message "Hugo export complete: %d processed, %d skipped" 
             processed skipped)))

(defun hugo-remove-note-from-hugo ()
  "Remove current note from Hugo content directory."
  (interactive)
  (let* ((file (buffer-file-name))
         (metadata (hugo--extract-note-metadata file))
         (title (plist-get metadata :title)))
    
    (when (yes-or-no-p (format "Remove '%s' from Hugo? " title))
      ;; Find and delete all exports matching this title
      (dolist (hugo-file (directory-files hugo-content-dir t "\\.md$"))
        (when (string-match-p (regexp-quote (downcase title)) 
                            (file-name-nondirectory hugo-file))
          (delete-file hugo-file)
          (message "🗑 Removed: %s" (file-name-nondirectory hugo-file)))))))

(defun hugo-serve ()
  "Start Hugo development server."
  (interactive)
  (hugo--ensure-directories)
  (let ((default-directory hugo-base-dir))
    (async-shell-command "hugo server --bind 127.0.0.1 --port 1313 --buildDrafts"
                        "*Hugo Server*"))
  (message "Hugo server starting at http://localhost:1313"))

(defun hugo-build ()
  "Build Hugo site."
  (interactive)
  (hugo--ensure-directories)
  (let ((default-directory hugo-base-dir))
    (shell-command "hugo --cleanDestinationDir")
    (message "Hugo site built to %spublic/" hugo-base-dir)))

(defun hugo-open-in-browser ()
  "Open Hugo documentation site in browser."
  (interactive)
  (browse-url "http://localhost:1313"))

;;;; Auto-process on save

(defun hugo--maybe-process-on-save ()
  "Automatically process note for Hugo on save if it has hugosync tag."
  (when (and (derived-mode-p 'org-mode)
             (buffer-file-name)
             (string-prefix-p (expand-file-name hugo-notes-source-dir)
                            (expand-file-name (buffer-file-name)))
             (hugo--file-has-hugosync-tag-p (buffer-file-name)))
    (hugo-process-current-note)))

;; Enable auto-processing
(defvar hugo-auto-process-on-save t
  "When non-nil, automatically process notes with :hugosync: tag on save.")

(when hugo-auto-process-on-save
  (add-hook 'after-save-hook #'hugo--maybe-process-on-save))

;;;; Keybindings

(defvar hugo-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'hugo-create-documentation-note)
    (define-key map (kbd "p") #'hugo-process-current-note)
    (define-key map (kbd "P") #'hugo-process-all-documentation-notes)
    (define-key map (kbd "r") #'hugo-remove-note-from-hugo)
    (define-key map (kbd "s") #'hugo-serve)
    (define-key map (kbd "b") #'hugo-build)
    (define-key map (kbd "o") #'hugo-open-in-browser)
    map)
  "Keymap for Hugo documentation commands.")

;; Bind to C-c x
(global-set-key (kbd "C-c x") hugo-command-map)

(provide 'hugo)
;;; 15-hugo.el ends here

