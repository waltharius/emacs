;;; 15-hugo.el --- Hugo documentation workflow with categories -*- lexical-binding: t -*-

;;; Commentary:
;; Integration between Denote notes and Hugo with category support.
;; Notes tagged with :hugosync: are exported to Hugo in categorized folders.

;;; Code:

(require 'denote)

;; Ensure ox-hugo is installed
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

(defvar hugo-sync-tag "hugosync"
  "Tag that marks notes for Hugo export.")

;; ============================================================
;; CATEGORY MAPPING - Three main documentation buckets
;; ============================================================

(defvar hugo-category-keywords
  '(;; INFRASTRUCTURE - Servers, networking, homelab
    ("infrastructure" . (
                         ;; Homelab and servers
                         "homelab" "server" "infrastructure" "hardware"
                         ;; Virtualization
                         "proxmox" "vm" "lxc" "container" "virtualization"
                         ;; Networking
                         "network" "networking" "dns" "dhcp" "vpn"
                         "pfsense" "firewall" "router" "routing" "vlan"
                         "freeipa" "ldap"
                         ;; Hardware and power
                         "ups" "dell" "raid" "disk" "storage"
                         ))
    
    ;; SYSTEMS - Operating systems, distributions, configurations
    ("systems" . (
                  ;; NixOS (priority over generic Linux)
                  "nixos" "nix" "flake" "flakes" "home-manager"
                  "configuration" "module" "modules" "iso"
                  "derivation" "channel" "generation"
                  ;; Other Linux distributions
                  "linux" "fedora" "ubuntu" "debian" "arch"
                  ;; Desktop environments
                  "gnome" "kde" "plasma" "xfce" "i3" "wayland" "x11"
                  ;; System components
                  "kernel" "systemd" "grub" "boot" "bootloader"
                  "driver" "nvidia" "graphics"
                  ;; Filesystems
                  "btrfs" "ext4" "zfs" "filesystem"
                  ;; Recovery and maintenance
                  "recovery" "backup" "restore" "snapshot"
                  ))
    
    ;; TOOLS - Development tools, editors, utilities
    ("tools" . (
                ;; Editors
                "emacs" "elisp" "vim" "neovim" "vscode"
                ;; Note-taking and documentation
                "denote" "org" "orgmode" "org-mode" "markdown"
                "hugo" "documentation" "docu"
                ;; Terminal and multiplexers
                "tmux" "screen" "terminal" "alacritty" "atuin"
                ;; Version control
                "git" "github" "gitlab" "magit"
                ;; Shell and scripting
                "bash" "zsh" "fish" "shell" "script"
                ;; Development tools
                "docker" "kubernetes" "ci" "cd"
                )))
  "Three-tier category mapping for documentation organization.
Notes are automatically categorized based on keyword matching.")
;;;; Helper Functions

(defun hugo--ensure-directories ()
  "Ensure Hugo directory structure exists."
  (unless (file-directory-p hugo-content-dir)
    (make-directory hugo-content-dir t))
  ;; Create category directories
  (dolist (category hugo-category-keywords)
    (let ((cat-dir (expand-file-name (car category) hugo-content-dir)))
      (unless (file-directory-p cat-dir)
        (make-directory cat-dir t)))))

(defun hugo--file-has-hugosync-tag-p (file)
  "Check if FILE has the hugosync tag."
  (when (and (file-exists-p file)
             (string-match-p "\\.org\\'" file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (or (re-search-forward (format "\\b%s\\b" hugo-sync-tag) 
                            (+ (point-min) 500) t)
          (re-search-forward (format "^#\\+filetags:.*:%s:" hugo-sync-tag)
                            (+ (point-min) 500) t)))))

(defun hugo--determine-category (file)
  "Determine category for FILE based on its tags/keywords.
Returns category name or 'general' if no match."
  (let ((file-name (file-name-nondirectory file))
        (file-content "")
        (matched-category "general"))
    
    ;; Get file tags from filename and content
    (with-temp-buffer
      (insert-file-contents file)
      (setq file-content (buffer-string)))
    
    ;; Check each category's keywords
    (catch 'found
      (dolist (cat-entry hugo-category-keywords)
        (let ((category (car cat-entry))
              (keywords (cdr cat-entry)))
          (dolist (keyword keywords)
            (when (or (string-match-p (regexp-quote keyword) file-name)
                      (string-match-p (format "\\b%s\\b" keyword) file-content))
              (setq matched-category category)
              (throw 'found category))))))
    
    matched-category))

(defun hugo--extract-note-metadata (file)
  "Extract metadata from Denote note FILE.
Returns a plist with :date, :title, :tags, :identifier, :category."
  (let ((file-name (file-name-nondirectory file))
        date title tags identifier category)
    
    ;; Extract identifier (timestamp)
    (when (string-match "^\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)" file-name)
      (setq identifier (match-string 1 file-name))
      ;; Convert 20260103T120502 to 2026-01-03
      (setq date (format "%s-%s-%s"
                        (substring identifier 0 4)
                        (substring identifier 4 6)
                        (substring identifier 6 8))))
    
    ;; Extract title
    (when (string-match "--\\(.+?\\)__" file-name)
      (setq title (replace-regexp-in-string 
                   "-" " "
                   (match-string 1 file-name))))
    
    ;; Extract tags
    (when (string-match "__\\(.+\\)\\.org$" file-name)
      (setq tags (split-string (match-string 1 file-name) "_")))
    
    ;; Remove hugosync from tags
    (setq tags (delete hugo-sync-tag tags))
    
    ;; Determine category
    (setq category (hugo--determine-category file))
    
    (list :date date
          :title title
          :tags tags
          :identifier identifier
          :category category)))

(defun hugo--get-org-file-content (file)
  "Get the main content of org FILE, excluding frontmatter."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    
    ;; Skip past all #+PROPERTY lines
    (while (re-search-forward "^#\\+[A-Z_]+:.*$" nil t))
    
    (buffer-substring-no-properties (point) (point-max))))

(defun hugo--create-temp-org-file (file metadata)
  "Create temporary org file with Hugo frontmatter for export."
  (let* ((temp-file (make-temp-file "hugo-export" nil ".org"))
         (title (plist-get metadata :title))
         (date (plist-get metadata :date))
         (tags (plist-get metadata :tags))
         (identifier (plist-get metadata :identifier))
         (category (plist-get metadata :category))
         (content (hugo--get-org-file-content file)))
    
    (with-temp-file temp-file
      ;; Hugo-specific org properties
      (insert "#+TITLE: " title "\n")
      (insert "#+DATE: " date "\n")
      (insert "#+HUGO_BASE_DIR: " hugo-base-dir "\n")
      (insert "#+HUGO_SECTION: docs/" category "\n")  ;; Category folder!
      (insert "#+HUGO_AUTO_SET_LASTMOD: t\n")
      
      ;; Add tags and category
      (when tags
        (insert "#+HUGO_TAGS: " (mapconcat 'identity tags " ") "\n"))
      (insert "#+HUGO_CATEGORIES: " category "\n")
      
      (insert "#+HUGO_CUSTOM_FRONT_MATTER: :identifier " identifier "\n")
      
      ;; Clean filename
      (insert "#+EXPORT_FILE_NAME: " date "-" 
              (replace-regexp-in-string " " "-" (downcase title)) "\n")
      
      (insert "\n")
      (insert content))
    
    temp-file))

(defun hugo--export-note-to-hugo (file)
  "Export Denote note FILE to Hugo markdown in correct category folder."
  (hugo--ensure-directories)
  
  (let* ((metadata (hugo--extract-note-metadata file))
         (temp-file (hugo--create-temp-org-file file metadata))
         (category (plist-get metadata :category)))
    
    ;; Export using ox-hugo
    (with-current-buffer (find-file-noselect temp-file)
      (org-hugo-export-to-md)
      (kill-buffer))
    
    ;; Clean up temp file
    (delete-file temp-file)
    
    (message "✓ Exported to Hugo [%s]: %s" 
             category
             (plist-get metadata :title))))

(defun hugo--clean-old-exports (current-file)
  "Remove old Hugo exports when note changes."
  (let* ((metadata (hugo--extract-note-metadata current-file))
         (current-title (plist-get metadata :title))
         (current-date (plist-get metadata :date))
         (current-export-base (format "%s-%s" 
                                     current-date
                                     (replace-regexp-in-string 
                                      " " "-" 
                                      (downcase current-title)))))
    
    ;; Search all category directories
    (dolist (cat-entry hugo-category-keywords)
      (let* ((category (car cat-entry))
             (cat-dir (expand-file-name category hugo-content-dir)))
        (when (file-directory-p cat-dir)
          (dolist (hugo-file (directory-files cat-dir t "\\.md$"))
            (let ((base (file-name-sans-extension 
                        (file-name-nondirectory hugo-file))))
              ;; Remove if same title but different date/identifier
              (when (and (string-match-p (regexp-quote (downcase current-title)) base)
                        (not (string= base current-export-base)))
                (delete-file hugo-file)
                (message "🗑 Removed old export: %s" 
                        (file-name-nondirectory hugo-file))))))))))

;;;; Interactive Commands

(defun hugo-create-documentation-note ()
  "Create a new Denote note tagged for Hugo documentation."
  (interactive)
  (let* ((categories (mapcar 'car hugo-category-keywords))
         (category (completing-read "Category: " categories))
         (title (read-string "Documentation title: "))
         (keywords (completing-read-multiple 
                   "Additional keywords (comma-separated): "
                   denote-known-keywords))
         ;; Add category keyword + hugosync
         (all-keywords (cons hugo-sync-tag (cons category keywords))))
    (denote title all-keywords)
    (message "Created [%s] note: %s" category title)))

(defun hugo-process-current-note ()
  "Process current note for Hugo export."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  
  (let ((file (buffer-file-name)))
    (if (hugo--file-has-hugosync-tag-p file)
        (progn
          (save-buffer)
          (hugo--clean-old-exports file)
          (hugo--export-note-to-hugo file))
      (message "Note doesn't have :%s: tag, skipping" hugo-sync-tag))))

(defun hugo-process-all-documentation-notes ()
  "Process all Denote notes tagged with :hugosync:."
  (interactive)
  (let ((processed 0)
        (by-category (make-hash-table :test 'equal)))
    
    ;; Optional: clean all
    (when (yes-or-no-p "Clean all Hugo exports and regenerate? ")
      (dolist (cat-entry hugo-category-keywords)
        (let ((cat-dir (expand-file-name (car cat-entry) hugo-content-dir)))
          (when (file-directory-p cat-dir)
            (dolist (file (directory-files cat-dir t "\\.md$"))
              (unless (string-match-p "_index\\.md$" file)
                (delete-file file))))))
      (message "🗑 Cleaned all Hugo exports"))
    
    ;; Process all notes
    (dolist (file (denote-directory-files))
      (when (hugo--file-has-hugosync-tag-p file)
        (let* ((metadata (hugo--extract-note-metadata file))
               (category (plist-get metadata :category)))
          (hugo--export-note-to-hugo file)
          (puthash category (1+ (gethash category by-category 0)) by-category)
          (setq processed (1+ processed)))))
    
    ;; Show summary
    (message "Hugo export complete: %d notes processed" processed)
    (maphash (lambda (cat count)
              (message "  [%s]: %d notes" cat count))
            by-category)))

(defun hugo-create-category-index ()
  "Create _index.md files for all categories with descriptions."
  (interactive)
  
  ;; Category descriptions
  (let ((category-info
         '(("infrastructure" 
            "Infrastructure & Homelab"
            "Server infrastructure, virtualization, networking, and homelab setup documentation.")
           ("systems"
            "Operating Systems"
            "Linux distributions, NixOS configurations, system administration, and OS-level configurations.")
           ("tools"
            "Development Tools"
            "Editors, terminal tools, version control, and development environment configurations."))))
    
    (dolist (cat-entry hugo-category-keywords)
      (let* ((category (car cat-entry))
             (info (assoc category category-info))
             (display-name (if info (nth 1 info) (capitalize category)))
             (description (if info (nth 2 info) "Documentation"))
             (cat-dir (expand-file-name category hugo-content-dir))
             (index-file (expand-file-name "_index.md" cat-dir)))
        
        (unless (file-directory-p cat-dir)
          (make-directory cat-dir t))
        
        (with-temp-file index-file
          (insert "---\n")
          (insert "title: \"" display-name "\"\n")
          (insert "weight: 10\n")
          (insert "bookFlatSection: false\n")
          (insert "bookCollapseSection: false\n")
          (insert "bookToc: true\n")
          (insert "---\n\n")
          (insert "# " display-name "\n\n")
          (insert description "\n"))
        
        (message "✓ Created category index: %s" category)))))

;;;; Auto-process on save

(defun hugo--maybe-process-on-save ()
  "Automatically process note for Hugo on save if it has hugosync tag."
  (when (and (derived-mode-p 'org-mode)
             (buffer-file-name)
             (hugo--file-has-hugosync-tag-p (buffer-file-name)))
    (hugo-process-current-note)))

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
    (define-key map (kbd "i") #'hugo-create-category-index)
    (define-key map (kbd "s") #'hugo-serve)
    (define-key map (kbd "b") #'hugo-build)
    (define-key map (kbd "o") #'hugo-open-in-browser)
    map)
  "Keymap for Hugo documentation commands.")

(global-set-key (kbd "C-c x") hugo-command-map)

(provide 'hugo)
;;; 15-hugo.el ends here

