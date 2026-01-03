;;; 15-hugo.el --- Hugo documentation workflow integration -*- lexical-binding: t -*-

;;; Commentary:
;; Integration between Denote notes and Hugo static site generator.
;; Notes tagged with :hugosync: are automatically copied to Hugo content directory.

;;; Code:

(require 'denote)

;; ============================================================
;; INSTALL OX-HUGO
;; ============================================================

;; Ensure ox-hugo is installed from MELPA
(use-package ox-hugo
  :ensure t  ; Auto-install from MELPA if missing
  :after ox  ; Load after org export backend
  :config
  (message "✅ ox-hugo loaded for Hugo export"))

;; Alternative: if you use straight.el instead of use-package:
;; (straight-use-package 'ox-hugo)
;; (require 'ox-hugo)

;;;; Configuration Variables

(defvar hugo-base-dir (expand-file-name "~/syncthing/hugo/")
  "Base directory for Hugo site.")

(require 'ox-hugo)

;;;; Configuration Variables

(defvar hugo-base-dir "~/syncthing/hugo/"
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

(defun hugo--copy-note-to-hugo (file)
  "Copy Denote note FILE to Hugo content directory with Hugo front-matter."
  (hugo--ensure-directories)
  (let* ((file-name (file-name-nondirectory file))
         ;; Use denote identifier or timestamp from filename
         (identifier (if (string-match "^\\([0-9T]+\\)--" file-name)
                        (match-string 1 file-name)
                      (format-time-string "%Y%m%dT%H%M%S")))
         ;; Extract title from denote filename format
         (title (if (string-match "--\\(.+?\\)\\(__\\|.org\\)" file-name)
                   (replace-regexp-in-string "-" " " 
                     (match-string 1 file-name))
                 (file-name-base file-name)))
         (hugo-file (expand-file-name 
                    (format "%s.org" identifier)
                    hugo-content-dir)))
    
    (with-temp-buffer
      (insert-file-contents file)
      
      ;; Add/update Hugo front-matter at the top
      (goto-char (point-min))
      
      ;; Remove existing hugo directives if present
      (while (re-search-forward "^#\\+hugo_.*$" nil t)
        (replace-match ""))
      
      ;; Insert Hugo configuration after title
      (goto-char (point-min))
      (if (re-search-forward "^#\\+title:" nil t)
          (forward-line 1)
        (goto-char (point-min)))
      
      (insert (format "#+hugo_base_dir: %s\n" hugo-base-dir))
      (insert "#+hugo_section: docs\n")
      (insert "#+hugo_auto_set_lastmod: t\n")
      (insert (format "#+hugo_custom_front_matter: :identifier %s\n" identifier))
      (insert "#+export_file_name: " (file-name-base file-name) "\n\n")
      
      ;; Write to hugo content directory
      (write-region (point-min) (point-max) hugo-file)
      (message "Copied to Hugo: %s" (file-name-nondirectory hugo-file)))
    
    hugo-file))

(defun hugo--export-to-markdown (org-file)
  "Export ORG-FILE to Hugo markdown format."
  (with-current-buffer (find-file-noselect org-file)
    (org-hugo-export-to-md)
    (message "Exported to markdown: %s" (buffer-name))))

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
  "Process current note if it has docu tag: copy to Hugo and export."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  
  (let ((file (buffer-file-name)))
    (if (hugo--file-has-hugosync-tag-p file)
        (progn
          (save-buffer)  ; Save first
          (let ((hugo-file (hugo--copy-note-to-hugo file)))
            (hugo--export-to-markdown hugo-file)
            (message "✓ Processed for Hugo: %s" (file-name-nondirectory file))))
      (message "Note doesn't have :%s: tag, skipping" hugo-sync-tag))))

(defun hugo-process-all-documentation-notes ()
  "Process all Denote notes tagged with :hugosync:."
  (interactive)
  (let ((processed 0)
        (skipped 0))
    (dolist (file (denote-directory-files))
      (if (hugo--file-has-hugosync-tag-p file)
          (progn
            (let ((hugo-file (hugo--copy-note-to-hugo file)))
              (hugo--export-to-markdown hugo-file))
            (setq processed (1+ processed)))
        (setq skipped (1+ skipped))))
    (message "Hugo export complete: %d processed, %d skipped" 
             processed skipped)))

(defun hugo-remove-note-from-hugo ()
  "Remove current note from Hugo content directory."
  (interactive)
  (let* ((file (buffer-file-name))
         (file-name (file-name-nondirectory file))
         (identifier (when (string-match "^\\([0-9T]+\\)--" file-name)
                      (match-string 1 file-name)))
         (hugo-org (expand-file-name (format "%s.org" identifier) 
                                    hugo-content-dir))
         (hugo-md (expand-file-name (format "%s.md" identifier)
                                   hugo-content-dir)))
    
    (when (and identifier
               (or (file-exists-p hugo-org)
                   (file-exists-p hugo-md)))
      (when (yes-or-no-p "Remove this note from Hugo documentation? ")
        (when (file-exists-p hugo-org)
          (delete-file hugo-org))
        (when (file-exists-p hugo-md)
          (delete-file hugo-md))
        (message "Removed from Hugo: %s" file-name)))))

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

;; Enable auto-processing (optional, can be disabled)
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

;; Bind to C-c h
(global-set-key (kbd "C-c x") hugo-command-map)

(provide 'hugo)
;;; 15-hugo.el ends here

