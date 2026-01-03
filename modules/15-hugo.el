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
                         "homelab" "server" "infrastructure" "hardware"
                         "proxmox" "vm" "lxc" "container" "virtualization"
                         "network" "networking" "dns" "dhcp" "vpn"
                         "pfsense" "firewall" "router" "routing" "vlan"
                         "freeipa" "ldap"
                         "ups" "dell" "raid" "disk" "storage"
                         ))
    
    ;; SYSTEMS - Operating systems, distributions, configurations
    ("systems" . (
                  "nixos" "nix" "flake" "flakes" "home-manager"
                  "configuration" "module" "modules" "iso"
                  "derivation" "channel" "generation"
                  "linux" "fedora" "ubuntu" "debian" "arch"
                  "gnome" "kde" "plasma" "xfce" "i3" "wayland" "x11"
                  "kernel" "systemd" "grub" "boot" "bootloader"
                  "driver" "nvidia" "graphics"
                  "btrfs" "ext4" "zfs" "filesystem"
                  "recovery" "backup" "restore" "snapshot"
                  ))
    
    ;; TOOLS - Development tools, editors, utilities
    ("tools" . (
                "emacs" "elisp" "vim" "neovim" "vscode"
                "denote" "org" "orgmode" "org-mode" "markdown"
                "hugo" "documentation" "docu"
                "tmux" "screen" "terminal" "alacritty" "atuin"
                "git" "github" "gitlab" "magit"
                "bash" "zsh" "fish" "shell" "script"
                "docker" "kubernetes" "ci" "cd"
                )))
  "Three-tier category mapping for documentation organization.")

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

(defun hugo--format-title (raw-title)
  "Format RAW-TITLE with proper capitalization and special cases.
Handles acronyms and proper names like NixOS, SSH, UPS, etc."
  (let ((special-words '(("nixos" . "NixOS")
                         ("tmux" . "Tmux")
                         ("emacs" . "Emacs")
                         ("dns" . "DNS")
                         ("ssh" . "SSH")
                         ("ups" . "UPS")
                         ("iso" . "ISO")
                         ("lxc" . "LXC")
                         ("vm" . "VM")
                         ("vpn" . "VPN")
                         ("ssl" . "SSL")
                         ("tls" . "TLS")
                         ("dhcp" . "DHCP")
                         ("btrfs" . "Btrfs")
                         ("zfs" . "ZFS")
                         ("usb" . "USB")
                         ("api" . "API")
                         ("cli" . "CLI")
                         ("gui" . "GUI")
                         ("pfsense" . "pfSense")
                         ("freeipa" . "FreeIPA")
                         ("nvidia" . "NVIDIA")
                         ("fedora" . "Fedora")
                         ("proxmox" . "Proxmox")
                         ("gnome" . "GNOME")
                         ("kde" . "KDE")
                         ("xfce" . "XFCE")
                         ("github" . "GitHub")
                         ("gitlab" . "GitLab")
                         ("quadro" . "Quadro")
                         ("atuin" . "Atuin")
                         ("run-or-rise" . "Run-or-Rise")
                         ))
        (title-words (split-string raw-title " " t)))
    
    ;; Capitalize each word
    (setq title-words (mapcar #'capitalize title-words))
    
    ;; Replace special words with proper forms
    (setq title-words
          (mapcar (lambda (word)
                    (let ((lower-word (downcase word)))
                      (or (cdr (assoc lower-word special-words))
                          word)))
                  title-words))
    
    ;; Join back together
    (mapconcat #'identity title-words " ")))


(defun hugo--file-has-hugosync-tag-p (file)
  "Check if FILE has the hugosync tag in filename or file content.
Checks filename first (fast), then searches entire file header (thorough)."
  (when (and (file-exists-p file)
             (string-match-p "\\.org\\'" file))
    (let ((file-name (file-name-nondirectory file)))
      ;; Method 1: Check filename (Denote standard: __tag1_tag2.org)
      (or (string-match-p (format "\\b%s\\b" hugo-sync-tag) file-name)
          ;; Method 2: Check file content (search entire header, not just 500 chars)
          (with-temp-buffer
            (insert-file-contents file nil nil 2000)  ; Read first 2000 chars
            (goto-char (point-min))
            ;; Look for #+filetags: :tag1:hugosync:tag2:
            (re-search-forward (format "^#\\+filetags:.*:%s:" hugo-sync-tag)
                              nil t))))))

(defun hugo--determine-category (file)
  "Determine category for FILE based on its tags/keywords.
Uses weighted scoring: tool-specific keywords > infrastructure-specific > generic."
  (let ((file-name (file-name-nondirectory file))
        (file-content "")
        (category-scores (make-hash-table :test 'equal)))
    
    ;; Read file content
    (with-temp-buffer
      (insert-file-contents file nil nil 2000)
      (setq file-content (buffer-string)))
    
    ;; Score each category based on keyword matches
    (dolist (cat-entry hugo-category-keywords)
      (let ((category (car cat-entry))
            (keywords (cdr cat-entry))
            (score 0))
        
        (dolist (keyword keywords)
          (let ((weight 1))  ; Default weight
            
            ;; Assign higher weights to specific keywords
            (cond
             ;; Tool-specific keywords (highest priority)
             ((member keyword '("tmux" "emacs" "denote" "vim" "neovim" "atuin" "git"))
              (setq weight 10))
             
             ;; Infrastructure-specific keywords
             ((member keyword '("proxmox" "pfsense" "freeipa" "ups"))
              (setq weight 8))
             
             ;; NixOS-specific keywords  
             ((member keyword '("nixos" "nix" "flake" "flakes"))
              (setq weight 7))
             
             ;; Generic keywords (lowest priority)
             ((member keyword '("linux" "docu" "documentation"))
              (setq weight 1)))
            
            ;; Check filename and content for keyword
            (when (or (string-match-p (regexp-quote keyword) file-name)
                      (string-match-p (format "\\b%s\\b" keyword) file-content))
              (setq score (+ score weight))))
          
          (puthash category score category-scores))))
    
    ;; Return category with highest score
    (let ((best-category "tools")  ; Default
          (best-score 0))
      (maphash (lambda (cat score)
                 (when (> score best-score)
                   (setq best-category cat
                         best-score score)))
               category-scores)
      best-category)))


(defun hugo--extract-note-metadata (file)
  "Extract metadata from Denote note FILE."
  (let ((file-name (file-name-nondirectory file))
        date title tags identifier category)
    
    (when (string-match "^\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)" file-name)
      (setq identifier (match-string 1 file-name))
      (setq date (format "%s-%s-%s"
                        (substring identifier 0 4)
                        (substring identifier 4 6)
                        (substring identifier 6 8))))

    (when (string-match "--\\(.+?\\)__" file-name)
      (let ((raw-title (replace-regexp-in-string
                    "-" " "
                    (match-string 1 file-name))))
        (setq title (hugo--format-title raw-title))))
    
    (when (string-match "__\\(.+\\)\\.org$" file-name)
      (setq tags (split-string (match-string 1 file-name) "_")))
    
    (setq tags (delete hugo-sync-tag tags))
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
      (insert "#+TITLE: " title "\n")
      (insert "#+DATE: " date "\n")
      (insert "#+HUGO_BASE_DIR: " hugo-base-dir "\n")
      (insert "#+HUGO_SECTION: docs/" category "\n")
      (insert "#+HUGO_AUTO_SET_LASTMOD: t\n")
      
      (when tags
        (insert "#+HUGO_TAGS: " (mapconcat 'identity tags " ") "\n"))
      (insert "#+HUGO_CATEGORIES: " category "\n")
      
      (insert "#+HUGO_CUSTOM_FRONT_MATTER: :identifier " identifier "\n")
      
      (insert "#+EXPORT_FILE_NAME: " date "-" 
              (replace-regexp-in-string " " "-" (downcase title)) "\n")
      
      (insert "\n")
      (insert content))
    
    temp-file))

(defun hugo--export-note-to-hugo (file)
  "Export Denote note FILE to Hugo markdown."
  (hugo--ensure-directories)
  
  (let* ((metadata (hugo--extract-note-metadata file))
         (temp-file (hugo--create-temp-org-file file metadata))
         (category (plist-get metadata :category)))
    
    (with-current-buffer (find-file-noselect temp-file)
      (org-hugo-export-to-md)
      (kill-buffer))
    
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
    
    (dolist (cat-entry hugo-category-keywords)
      (let* ((category (car cat-entry))
             (cat-dir (expand-file-name category hugo-content-dir)))
        (when (file-directory-p cat-dir)
          (dolist (hugo-file (directory-files cat-dir t "\\.md$"))
            (let ((base (file-name-sans-extension 
                        (file-name-nondirectory hugo-file))))
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
    
    (when (yes-or-no-p "Clean all Hugo exports and regenerate? ")
      (dolist (cat-entry hugo-category-keywords)
        (let ((cat-dir (expand-file-name (car cat-entry) hugo-content-dir)))
          (when (file-directory-p cat-dir)
            (dolist (file (directory-files cat-dir t "\\.md$"))
              (unless (string-match-p "_index\\.md$" file)
                (delete-file file))))))
      (message "🗑 Cleaned all Hugo exports"))
    
    (dolist (file (denote-directory-files))
      (when (hugo--file-has-hugosync-tag-p file)
        (let* ((metadata (hugo--extract-note-metadata file))
               (category (plist-get metadata :category)))
          (hugo--export-note-to-hugo file)
          (puthash category (1+ (gethash category by-category 0)) by-category)
          (setq processed (1+ processed)))))
    
    (message "Hugo export complete: %d notes processed" processed)
    (maphash (lambda (cat count)
              (message "  [%s]: %d notes" cat count))
            by-category)))

(defun hugo-create-category-index ()
  "Create _index.md files for all categories."
  (interactive)
  
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

(defun hugo-add-sync-tag-to-documented-notes ()
  "Add :hugosync: tag to all notes with :docu: tag by renaming files."
  (interactive)
  
  (let ((notes-to-process '())
        (notes-already-synced '()))
    
    ;; Scan all notes
    (dolist (file (denote-directory-files))
      (when (string-match-p "\\.org\\'" file)
        (let ((name (file-name-nondirectory file)))
          (cond
           ((and (string-match-p "\\bdocu\\b" name)
                 (not (string-match-p "\\bhugosync\\b" name)))
            (push file notes-to-process))
           ((and (string-match-p "\\bdocu\\b" name)
                 (string-match-p "\\bhugosync\\b" name))
            (push file notes-already-synced))))))
    
    (if (null notes-to-process)
        (message "No notes found with :docu: tag missing :hugosync:")
      
      (let ((preview-buffer (get-buffer-create "*Hugo Sync Preview*")))
        (with-current-buffer preview-buffer
          (erase-buffer)
          (insert "Notes that will get :hugosync: tag:\n\n")
          (dolist (file (reverse notes-to-process))
            (insert "  • " (file-name-nondirectory file) "\n"))
          (insert (format "\nTotal: %d notes\n" (length notes-to-process)))
          (when notes-already-synced
            (insert (format "Already synced: %d notes\n" 
                           (length notes-already-synced))))
          (goto-char (point-min))
          (special-mode))
        
        (pop-to-buffer preview-buffer)
        
        (when (yes-or-no-p (format "Add :hugosync: to %d notes? " 
                                   (length notes-to-process)))
          (let ((success 0)
                (errors 0))
            
            (dolist (file notes-to-process)
              (condition-case err
                  (let* ((dir (file-name-directory file))
                         (name (file-name-nondirectory file))
                         (parsed (string-match 
                                 "^\\([0-9T]+\\)--\\([^_]+\\)__\\(.+\\)\\.org$" 
                                 name))
                         new-name)
                    
                    (when parsed
                      (let* ((timestamp (match-string 1 name))
                             (title (match-string 2 name))
                             (tags (match-string 3 name))
                             (tag-list (split-string tags "_"))
                             (new-tag-list (sort (cons "hugosync" tag-list) 'string<))
                             (new-tags (mapconcat 'identity new-tag-list "_")))
                        
                        (setq new-name (format "%s--%s__%s.org" 
                                              timestamp title new-tags))
                        
                        (rename-file file (concat dir new-name))
                        (message "✓ Renamed: %s" name)
                        (setq success (1+ success)))))
                
                (error
                 (message "✗ Error processing %s: %s" 
                         (file-name-nondirectory file) err)
                 (setq errors (1+ errors)))))
            
            (message "✓ Added :hugosync: to %d notes (%d errors)" 
                     success errors)
            (kill-buffer preview-buffer)
            
            (dolist (buf (buffer-list))
              (with-current-buffer buf
                (when (eq major-mode 'dired-mode)
                  (revert-buffer))))))))))

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

;; Create keymap BEFORE trying to use it
(defvar hugo-command-map (make-sparse-keymap)
  "Keymap for Hugo documentation commands.")

;; Now define keys on the keymap
(define-key hugo-command-map (kbd "n") #'hugo-create-documentation-note)
(define-key hugo-command-map (kbd "p") #'hugo-process-current-note)
(define-key hugo-command-map (kbd "P") #'hugo-process-all-documentation-notes)
(define-key hugo-command-map (kbd "i") #'hugo-create-category-index)
(define-key hugo-command-map (kbd "a") #'hugo-add-sync-tag-to-documented-notes)
(define-key hugo-command-map (kbd "o") #'hugo-open-in-browser)

;; Helper functions for serving
(defun hugo-serve ()
  "Start Hugo development server."
  (interactive)
  (let ((default-directory hugo-base-dir))
    (async-shell-command "hugo server --bind 127.0.0.1 --port 1313"
                        "*Hugo Server*"))
  (message "Hugo server starting at http://localhost:1313"))

(defun hugo-open-in-browser ()
  "Open Hugo documentation site in browser."
  (interactive)
  (browse-url "http://localhost:1313"))

;; Bind to C-c x
(global-set-key (kbd "C-c x") hugo-command-map)

(provide 'hugo)
;;; 15-hugo.el ends here

