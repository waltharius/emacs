;;; 15-workspace.el --- Notes dashboard and workspace tools -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Custom notes dashboard and workspace features for Denote.
;; Replaces dired-sidebar (which conflicted with transient menus).
;;
;; FEATURES:
;;   1. Custom notes dashboard  - Full buffer with clickable titles,
;;                                grouped by silo, recency, and tags.
;;                                Opens in its own named tab on startup.
;;   2. Denote backlinks panel  - Right side window (C-c d b, already in 08-keybindings)
;;   3. Denote-explore          - Tag stats and network (on demand)
;;
;; KEYBINDINGS:
;;   C-c w d  - Open/refresh notes dashboard (also in transient menu)
;;   C-c w x  - Show tag statistics
;;   C-c w r  - Jump to random note
;;   C-c d b  - Show backlinks (defined in 08-keybindings.el)
;;
;; HOW TO REVERT:
;;   Remove (load ... "15-workspace.el") from init.el. Nothing else changes.

;;; Code:

;; ============================================================
;; HELPERS: Read org frontmatter from Denote files
;; ============================================================

(defun my/denote-file-title (file)
  "Return the #+title value from FILE, or the bare filename if not found.
Reads only the first 20 lines to stay fast on large files."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file nil 0 800) ; read first 800 bytes only
        (goto-char (point-min))
        (if (re-search-forward "^#\\+title:\\s-*\\(.+\\)$" nil t)
            (string-trim (match-string 1))
          (file-name-base file)))
    (error (file-name-base file))))

(defun my/denote-file-tags (file)
  "Return list of tags from #+filetags in FILE."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file nil 0 800)
        (goto-char (point-min))
        (if (re-search-forward "^#\\+filetags:\\s-*\\(.+\\)$" nil t)
            (split-string (match-string 1) ":" t " ")
          nil))
    (error nil)))

(defun my/denote-org-files-in (directory)
  "Return list of .org files in DIRECTORY sorted by modification time (newest first)."
  (let ((files (directory-files directory t "\\.org$" t)))
    (sort files
          (lambda (a b)
            (time-less-p
             (nth 5 (file-attributes b))
             (nth 5 (file-attributes a)))))))

(defun my/denote-recently-modified (days)
  "Return .org files modified within DAYS across all three note silos.
Sorted newest first."
  (let ((cutoff (time-subtract (current-time) (days-to-time days)))
        (all-files '()))
    (dolist (dir (list my-notes-journal my-notes-pks my-notes-docu))
      (when (file-directory-p dir)
        (dolist (f (directory-files dir t "\\.org$" t))
          (let ((mtime (nth 5 (file-attributes f))))
            (when (time-less-p cutoff mtime)
              (push f all-files))))))
    (sort all-files
          (lambda (a b)
            (time-less-p
             (nth 5 (file-attributes b))
             (nth 5 (file-attributes a)))))))

(defun my/denote-all-tags ()
  "Return alist of (tag . (file1 file2 ...)) across all silos."
  (let ((tag-map (make-hash-table :test 'equal)))
    (dolist (dir (list my-notes-journal my-notes-pks my-notes-docu))
      (when (file-directory-p dir)
        (dolist (f (directory-files dir t "\\.org$" t))
          (dolist (tag (my/denote-file-tags f))
            (puthash tag (cons f (gethash tag tag-map '())) tag-map)))))
    ;; Convert to sorted alist (most-used tags first)
    (let ((pairs '()))
      (maphash (lambda (tag files) (push (cons tag files) pairs)) tag-map)
      (sort pairs (lambda (a b) (> (length (cdr a)) (length (cdr b))))))))

;; ============================================================
;; DASHBOARD: Buffer rendering
;; ============================================================

(defconst my/dashboard-buffer-name "*Notes Dashboard*"
  "Name of the notes dashboard buffer.")

(defun my/dashboard-insert-section-header (title)
  "Insert a styled section header TITLE."
  (insert "\n")
  (insert (propertize (concat "  " title "\n")
                      'face '(:weight bold :height 1.1 :foreground "#4a90d9")))
  (insert (propertize (concat "  " (make-string (- (window-width) 4) ?─) "\n")
                      'face '(:foreground "#cccccc"))))

(defun my/dashboard-insert-file-link (file &optional prefix)
  "Insert a clickable line for FILE showing its org title.
PREFIX is an optional string prepended (e.g. modification date)."
  (let* ((title (my/denote-file-title file))
         (mtime (format-time-string "%Y-%m-%d"
                                    (nth 5 (file-attributes file))))
         (display (if prefix
                      (format "  %s  %s" prefix title)
                    (format "  %s  %s" mtime title)))
         (start (point)))
    (insert display)
    (make-text-button start (point)
                      'action (lambda (_btn) (my/dashboard-open-in-new-tab file))
                      'follow-link t
                      'help-echo file
                      'mouse-face 'highlight
                      'face '(:foreground "#2aa198"))
    (insert "\n")))

(defun my/dashboard-open-in-new-tab (file)
  "Open FILE in a new tab, like middle-click in a browser."
  (tab-bar-new-tab)
  (find-file file)
  ;; Name the tab after the note title
  (tab-bar-rename-tab (my/denote-file-title file)))

(defun my/dashboard-insert-tag-line (tag files)
  "Insert a clickable TAG line showing how many notes use it."
  (let* ((count (length files))
         (display (format "  %-20s %d notes" tag count))
         (start (point)))
    (insert display)
    (make-text-button start (point)
                      'action (lambda (_btn) (my/dashboard-show-tag-notes tag files))
                      'follow-link t
                      'help-echo (format "Show notes tagged :%s:" tag)
                      'mouse-face 'highlight
                      'face '(:foreground "#859900"))
    (insert "\n")))

(defun my/dashboard-show-tag-notes (tag files)
  "Open a temporary buffer listing all FILES tagged TAG, clickable."
  (let ((buf (get-buffer-create (format "*Tag: %s*" tag))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "Notes tagged :%s: (%d)\n\n" tag (length files))
                            'face '(:weight bold)))
        (dolist (f files)
          (my/dashboard-insert-file-link f))
        (insert "\n")
        (insert (propertize "[press q to close]" 'face '(:foreground "#888888")))
        (read-only-mode 1)
        (local-set-key (kbd "q") #'kill-buffer-and-window)))
    (display-buffer buf '(display-buffer-below-selected
                          (window-height . 0.35)))))

(defun my/render-notes-dashboard ()
  "Render the full notes dashboard into `my/dashboard-buffer-name'."
  (let ((buf (get-buffer-create my/dashboard-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)

        ;; Header
        (insert "\n")
        (insert (propertize "  📓 Notes Dashboard\n"
                            'face '(:weight bold :height 1.3)))
        (insert (propertize (format "  Refreshed: %s\n"
                                   (format-time-string "%Y-%m-%d %H:%M"))
                            'face '(:foreground "#888888")))

        ;; ── Section 1: Recently modified (last 10 days) ──────────────────
        (my/dashboard-insert-section-header "Recently Modified  (last 10 days)")
        (let ((recent (my/denote-recently-modified 10)))
          (if recent
              (dolist (f recent) (my/dashboard-insert-file-link f))
            (insert "  (no files modified in the last 10 days)\n")))

        ;; ── Section 2: Journal ───────────────────────────────────────────
        (my/dashboard-insert-section-header
         (format "Journal  (%s)"
                 (abbreviate-file-name my-notes-journal)))
        (dolist (f (seq-take (my/denote-org-files-in my-notes-journal) 20))
          (my/dashboard-insert-file-link f))

        ;; ── Section 3: PKS ───────────────────────────────────────────────
        (my/dashboard-insert-section-header
         (format "PKS — Personal Knowledge  (%s)"
                 (abbreviate-file-name my-notes-pks)))
        (dolist (f (seq-take (my/denote-org-files-in my-notes-pks) 20))
          (my/dashboard-insert-file-link f))

        ;; ── Section 4: Docu ──────────────────────────────────────────────
        (my/dashboard-insert-section-header
         (format "Documentation  (%s)"
                 (abbreviate-file-name my-notes-docu)))
        (dolist (f (seq-take (my/denote-org-files-in my-notes-docu) 20))
          (my/dashboard-insert-file-link f))

        ;; ── Section 5: Tags ──────────────────────────────────────────────
        (my/dashboard-insert-section-header "Tags  (click to list notes)")
        (dolist (pair (seq-take (my/denote-all-tags) 30))
          (my/dashboard-insert-tag-line (car pair) (cdr pair)))

        ;; Footer
        (insert "\n")
        (insert (propertize
                 "  g = refresh  |  C-c d b = backlinks  |  C-c w r = random note  |  q = bury\n"
                 'face '(:foreground "#888888")))

        ;; Make buffer read-only and set up local keys
        (read-only-mode 1)
        (local-set-key (kbd "g") #'my/open-notes-dashboard)
        (local-set-key (kbd "q") #'bury-buffer)
        (goto-char (point-min))))
    buf))

;; ============================================================
;; DASHBOARD: Open in named tab
;; ============================================================

(defun my/open-notes-dashboard ()
  "Open (or refresh) the Notes Dashboard in its own named tab.
If a tab named 'Dashboard' already exists, switch to it and refresh.
Otherwise create a new tab named 'Dashboard'."
  (interactive)
  ;; Find existing Dashboard tab or create one
  (let* ((tabs (tab-bar-tabs))
         (dash-tab (seq-find
                    (lambda (tab)
                      (equal (alist-get 'name tab) "Dashboard"))
                    tabs)))
    (if dash-tab
        ;; Switch to existing tab
        (tab-bar-switch-to-tab "Dashboard")
      ;; Create new tab named Dashboard at position 1 (front)
      (tab-bar-new-tab 1)
      (tab-bar-rename-tab "Dashboard"))
    ;; Render dashboard into buffer and display it
    (switch-to-buffer (my/render-notes-dashboard))))

;; ============================================================
;; STARTUP: Open Dashboard tab automatically
;; ============================================================
;; Runs after desktop-save-mode has restored all buffers/tabs,
;; so the Dashboard tab is added on top of the restored session.
;; Uses a timer to run after all startup hooks settle.

(defun my/startup-open-dashboard ()
  "Open Dashboard tab at startup, after desktop restore completes."
  (run-with-timer
   0.5 nil
   (lambda ()
     ;; Only open if not already present
     (unless (seq-find (lambda (tab)
                         (equal (alist-get 'name tab) "Dashboard"))
                       (tab-bar-tabs))
       (my/open-notes-dashboard)))))

(add-hook 'emacs-startup-hook #'my/startup-open-dashboard)

;; ============================================================
;; BACKLINKS: Configure display as right side-window
;; ============================================================
;; This only sets WHERE denote-backlinks opens - the C-c d b
;; keybinding is already defined in 08-keybindings.el.
;; Side window for backlinks does NOT conflict with transient
;; because it is opened explicitly by the user, not auto-attached.

(with-eval-after-load 'denote
  (setq denote-backlinks-display-buffer-action
        '((display-buffer-reuse-window
           display-buffer-in-side-window)
          (side . right)
          (slot . 0)
          (window-width . 0.25)
          (inhibit-same-window . t))))

;; ============================================================
;; DENOTE-EXPLORE: Tag stats and network (on demand)
;; ============================================================

(use-package denote-explore
  :ensure t
  :after (denote org)
  :commands (denote-explore-count-notes
             denote-explore-count-keywords
             denote-explore-identify-duplicate-notes
             denote-explore-random-note
             denote-explore-network)
  :custom
  (denote-explore-network-directory (expand-file-name my-notes-dir))
  (denote-explore-network-filename "denote-network.json"))

(defun my/notes-explore ()
  "Show tag and note statistics."
  (interactive)
  (require 'denote-explore)
  (denote-explore-count-notes))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c w d") #'my/open-notes-dashboard)
(global-set-key (kbd "C-c w x") #'my/notes-explore)
(global-set-key (kbd "C-c w r") #'denote-explore-random-note)

;; C-c w w no longer used (dired-sidebar removed) - freed up

(provide '15-workspace)
;;; 15-workspace.el ends here
