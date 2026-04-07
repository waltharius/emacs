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
;;   2. Denote backlinks panel  - Right side window (C-c d b)
;;   3. Denote-explore          - Tag stats and network (on demand)
;;
;; KEYBINDINGS:
;;   C-c w d  - Open/refresh notes dashboard (also C-c n o in transient)
;;   C-c w x  - Show tag statistics
;;   C-c w r  - Jump to random note
;;   g        - Refresh dashboard (inside dashboard buffer)
;;   q        - Bury dashboard
;;
;; HOW TO REVERT:
;;   Remove (load ... "15-workspace.el") from init.el. Nothing else changes.

;;; Code:

;; ============================================================
;; HELPERS: Read org frontmatter from Denote files
;; ============================================================

(defun my/denote-file-title (file)
  "Return #+title from FILE (first 800 bytes only, for speed)."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file nil 0 800)
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
  "Return .org files in DIRECTORY sorted newest-modified first."
  (when (file-directory-p directory)
    (sort (directory-files directory t "\\.org$" t)
          (lambda (a b)
            (time-less-p (nth 5 (file-attributes b))
                         (nth 5 (file-attributes a)))))))

(defun my/denote-recently-modified (days)
  "Return .org files across all silos modified within DAYS, newest first."
  (let ((cutoff (time-subtract (current-time) (days-to-time days)))
        (result '()))
    (dolist (dir (list my-notes-journal my-notes-pks my-notes-docu))
      (when (file-directory-p dir)
        (dolist (f (directory-files dir t "\.org$" t))
          (when (time-less-p cutoff (nth 5 (file-attributes f)))
            (push f result)))))
    (sort result
          (lambda (a b)
            (time-less-p (nth 5 (file-attributes b))
                         (nth 5 (file-attributes a)))))))

(defun my/denote-all-tags ()
  "Return alist of (tag . files) sorted by usage count descending."
  (let ((tag-map (make-hash-table :test 'equal)))
    (dolist (dir (list my-notes-journal my-notes-pks my-notes-docu))
      (when (file-directory-p dir)
        (dolist (f (directory-files dir t "\.org$" t))
          (dolist (tag (my/denote-file-tags f))
            (puthash tag (cons f (gethash tag tag-map '())) tag-map)))))
    (let ((pairs '()))
      (maphash (lambda (tag files) (push (cons tag files) pairs)) tag-map)
      (sort pairs (lambda (a b) (> (length (cdr a)) (length (cdr b))))))))

;; ============================================================
;; DASHBOARD: Rendering helpers
;; ============================================================

(defconst my/dashboard-buffer-name "*Notes Dashboard*")

(defun my/dashboard-open-in-new-tab (file)
  "Open FILE in a new named tab (browser middle-click behaviour)."
  (tab-bar-new-tab)
  (find-file file)
  (tab-bar-rename-tab (my/denote-file-title file)))

(defun my/dashboard-insert-section-header (title)
  "Insert a styled section TITLE line."
  (insert "\n")
  (insert (propertize (concat "  " title "\n")
                      'face '(:weight bold :underline t)))
  (insert "\n"))

(defun my/dashboard-insert-file-link (file)
  "Insert a clickable line showing date + org title for FILE."
  (let* ((title   (my/denote-file-title file))
         (mtime   (format-time-string "%Y-%m-%d" (nth 5 (file-attributes file))))
         (display (format "  %s  %s" mtime title))
         (start   (point)))
    (insert display)
    (make-text-button start (point)
                      'action (let ((f file))
                                (lambda (_b) (my/dashboard-open-in-new-tab f)))
                      'follow-link t
                      'help-echo file
                      'mouse-face 'highlight
                      'face '(:foreground "#2aa198"))
    (insert "\n")))

(defun my/dashboard-insert-tag-line (tag files)
  "Insert a clickable TAG line showing note count."
  (let* ((display (format "  %-24s  %d notes" tag (length files)))
         (start   (point)))
    (insert display)
    (make-text-button start (point)
                      'action (let ((tg tag) (fl files))
                                (lambda (_b)
                                  (my/dashboard-show-tag-notes tg fl)))
                      'follow-link t
                      'help-echo (format "Show notes tagged :%s:" tag)
                      'mouse-face 'highlight
                      'face '(:foreground "#859900"))
    (insert "\n")))

(defun my/dashboard-show-tag-notes (tag files)
  "Pop up a clickable list of FILES tagged TAG."
  (let ((buf (get-buffer-create (format "*Tag: %s*" tag))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "Notes tagged :%s: (%d)\n\n" tag (length files))
                            'face '(:weight bold)))
        (dolist (f (sort (copy-sequence files)
                         (lambda (a b)
                           (time-less-p (nth 5 (file-attributes b))
                                        (nth 5 (file-attributes a))))))
          (my/dashboard-insert-file-link f))
        (insert "\n")
        (insert (propertize "  q = close" 'face '(:foreground "#888888")))
        (read-only-mode 1)
        (local-set-key (kbd "q") #'kill-buffer-and-window)))
    (display-buffer buf '(display-buffer-below-selected (window-height . 0.4)))))

;; ============================================================
;; DASHBOARD: Main render function
;; ============================================================

(defun my/render-notes-dashboard ()
  "Render the notes dashboard into `my/dashboard-buffer-name'. Returns buffer."
  (let ((buf (get-buffer-create my/dashboard-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)

        ;; Header
        (insert "\n")
        (insert (propertize "  Notes Dashboard\n"
                            'face '(:weight bold :height 1.3)))
        (insert (propertize (format "  %s\n"
                                   (format-time-string "Refreshed: %Y-%m-%d %H:%M"))
                            'face '(:foreground "#888888")))

        ;; Section: Recently Modified
        (my/dashboard-insert-section-header
         (format "Recently Modified  (last 10 days)"))
        (let ((recent (my/denote-recently-modified 10)))
          (if recent
              (dolist (f recent) (my/dashboard-insert-file-link f))
            (insert "  (no files modified in the last 10 days)\n")))

        ;; Section: Journal
        (my/dashboard-insert-section-header
         (format "Journal  [%s]" (abbreviate-file-name my-notes-journal)))
        (dolist (f (seq-take (my/denote-org-files-in my-notes-journal) 20))
          (my/dashboard-insert-file-link f))

        ;; Section: PKS
        (my/dashboard-insert-section-header
         (format "PKS -- Personal Knowledge  [%s]" (abbreviate-file-name my-notes-pks)))
        (dolist (f (seq-take (my/denote-org-files-in my-notes-pks) 20))
          (my/dashboard-insert-file-link f))

        ;; Section: Documentation
        (my/dashboard-insert-section-header
         (format "Documentation  [%s]" (abbreviate-file-name my-notes-docu)))
        (dolist (f (seq-take (my/denote-org-files-in my-notes-docu) 20))
          (my/dashboard-insert-file-link f))

        ;; Section: Tags
        (my/dashboard-insert-section-header "Tags  (click to list notes)")
        (dolist (pair (seq-take (my/denote-all-tags) 30))
          (my/dashboard-insert-tag-line (car pair) (cdr pair)))

        ;; Footer
        (insert "\n")
        (insert (propertize
                 "  g = refresh  |  C-c d b = backlinks  |  C-c w r = random note  |  q = bury\n"
                 'face '(:foreground "#888888")))

        (read-only-mode 1)
        (local-set-key (kbd "g") #'my/open-notes-dashboard)
        (local-set-key (kbd "q") #'bury-buffer)
        (goto-char (point-min))))
    buf))

;; ============================================================
;; DASHBOARD: Open in named tab
;; ============================================================

(defun my/open-notes-dashboard ()
  "Open or refresh the Notes Dashboard in its own named tab."
  (interactive)
  (let* ((tabs (tab-bar-tabs))
         (dash-tab (seq-find (lambda (tab)
                               (equal (alist-get 'name tab) "Dashboard"))
                             tabs)))
    (if dash-tab
        (tab-bar-switch-to-tab "Dashboard")
      (tab-bar-new-tab 1)
      (tab-bar-rename-tab "Dashboard"))
    (switch-to-buffer (my/render-notes-dashboard))))

;; ============================================================
;; STARTUP: Open Dashboard tab after desktop restore
;; ============================================================

(defun my/startup-open-dashboard ()
  "Open Dashboard tab at startup, after desktop restore settles."
  (run-with-timer
   0.5 nil
   (lambda ()
     (unless (seq-find (lambda (tab)
                         (equal (alist-get 'name tab) "Dashboard"))
                       (tab-bar-tabs))
       (my/open-notes-dashboard)))))

(add-hook 'emacs-startup-hook #'my/startup-open-dashboard)

;; ============================================================
;; BACKLINKS: Right side-window
;; ============================================================

(with-eval-after-load 'denote
  (setq denote-backlinks-display-buffer-action
        '((display-buffer-reuse-window
           display-buffer-in-side-window)
          (side . right)
          (slot . 0)
          (window-width . 0.25)
          (inhibit-same-window . t))))

;; ============================================================
;; DENOTE-EXPLORE: Tag stats (lazy loaded)
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

(provide '15-workspace)
;;; 15-workspace.el ends here
