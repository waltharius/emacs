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
;; SORTING STRATEGY:
;;   - Recently Modified section : by mtime (what you edited last)
;;   - Journal section           : by creation date from identifier, last 10
;;   - PKS / Docu sections       : by mtime (what you edited last)
;;   - Tag popup                 : by creation date from identifier, newest first
;;                                 Files without identifier (captures.org) sort last.
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

(defun my/denote-file-identifier (file)
  "Return the Denote identifier string from FILE basename, or nil."
  (let ((base (file-name-base file)))
    (when (string-match "^\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)" base)
      (match-string 1 base))))

(defun my/denote-identifier< (file-a file-b)
  "Return t if FILE-A was created before FILE-B by Denote identifier."
  (let ((id-a (my/denote-file-identifier file-a))
        (id-b (my/denote-file-identifier file-b)))
    (cond
     ((and id-a id-b) (string< id-a id-b))
     (id-a            t)
     (t               nil))))

(defun my/denote-org-files-in (directory)
  "Return .org files in DIRECTORY sorted newest-modified first."
  (when (file-directory-p directory)
    (sort (directory-files directory t "\\.org$" t)
          (lambda (a b)
            (time-less-p (nth 5 (file-attributes b))
                         (nth 5 (file-attributes a)))))))

(defun my/denote-org-files-in-by-id (directory)
  "Return .org files in DIRECTORY sorted newest-created first (by identifier)."
  (when (file-directory-p directory)
    (let* ((all     (directory-files directory t "\\.org$" t))
           (dated   (seq-filter  #'my/denote-file-identifier all))
           (undated (seq-remove  #'my/denote-file-identifier all)))
      (append
       (sort dated (lambda (a b) (my/denote-identifier< b a)))
       undated))))

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
  "Open FILE in a new named tab."
  (tab-bar-new-tab)
  (find-file file)
  (tab-bar-rename-tab (my/denote-file-title file)))

(defun my/dashboard-insert-section-header (title)
  "Insert a styled section TITLE line."
  (insert "\n")
  (insert (propertize (concat "  " title "\n")
                      'face '(:weight bold :underline t)))
  (insert "\n"))

(defun my/dashboard-insert-file-link (file &optional date-source)
  "Insert a clickable line for FILE with date and org title.

DATE-SOURCE controls which date is shown:
  \='mtime (default) — file modification time; used for Recently Modified,
                       PKS, and Docu sections where \"what changed last\"
                       is the relevant signal.
  \='id             — creation date parsed from the Denote identifier
                       (YYYYMMDDTHHMMSS prefix); used for Journal and tag
                       popups where chronological creation order matters.
                       Falls back to mtime when the file has no identifier
                       (e.g. captures.org)."
  (let* ((title   (my/denote-file-title file))
         (date    (pcase date-source
                    ('id
                     (let ((id (my/denote-file-identifier file)))
                       (if id
                           (concat (substring id 0 4) "-"
                                   (substring id 4 6) "-"
                                   (substring id 6 8))
                         (format-time-string "%Y-%m-%d"
                                             (nth 5 (file-attributes file))))))
                    (_
                     (format-time-string "%Y-%m-%d"
                                         (nth 5 (file-attributes file))))))
         (display (format "  %s  %s" date title))
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
  "Pop up a clickable list of FILES tagged TAG, sorted by creation date."
  (let* ((dated   (seq-filter #'my/denote-file-identifier files))
         (undated (seq-remove #'my/denote-file-identifier files))
         (sorted  (append
                   (sort dated (lambda (a b) (my/denote-identifier< b a)))
                   undated))
         (buf (get-buffer-create (format "*Tag: %s*" tag))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize
                 (format "Notes tagged :%s: (%d)  --  sorted by creation date\n\n"
                         tag (length files))
                 'face '(:weight bold)))
        (dolist (f sorted)
          (my/dashboard-insert-file-link f 'id))
        (insert "\n")
        (insert (propertize "  q = close" 'face '(:foreground "#888888")))
        (read-only-mode 1)
        (local-set-key (kbd "q") #'kill-buffer-and-window)))
    (display-buffer buf '(display-buffer-below-selected (window-height . 0.4)))))

;; ============================================================
;; DASHBOARD: Main render function
;; ============================================================

(defun my/render-notes-dashboard ()
  "Render the notes dashboard into `my/dashboard-buffer-name'."
  (let ((buf (get-buffer-create my/dashboard-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "\n")
        (insert (propertize "  Notes Dashboard\n"
                            'face '(:weight bold :height 1.3)))
        (insert (propertize (format "  %s\n"
                                   (format-time-string "Refreshed: %Y-%m-%d %H:%M"))
                            'face '(:foreground "#888888")))
        (my/dashboard-insert-section-header "Recently Modified  (last 10 days)")
        (let ((recent (my/denote-recently-modified 10)))
          (if recent
              (dolist (f recent) (my/dashboard-insert-file-link f))
            (insert "  (no files modified in the last 10 days)\n")))
        (my/dashboard-insert-section-header
         (format "Journal  [%s]" (abbreviate-file-name my-notes-journal)))
        (dolist (f (seq-take (my/denote-org-files-in-by-id my-notes-journal) 10))
          (my/dashboard-insert-file-link f 'id))
        (my/dashboard-insert-section-header
         (format "PKS -- Personal Knowledge  [%s]" (abbreviate-file-name my-notes-pks)))
        (dolist (f (seq-take (my/denote-org-files-in my-notes-pks) 20))
          (my/dashboard-insert-file-link f))
        (my/dashboard-insert-section-header
         (format "Documentation  [%s]" (abbreviate-file-name my-notes-docu)))
        (dolist (f (seq-take (my/denote-org-files-in my-notes-docu) 20))
          (my/dashboard-insert-file-link f))
        (my/dashboard-insert-section-header "Tags  (click to list notes)")
        (dolist (pair (seq-take (my/denote-all-tags) 30))
          (my/dashboard-insert-tag-line (car pair) (cdr pair)))
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
;; STARTUP: Unblock Hunspell after desktop restore, then open Dashboard
;; ============================================================
;; `desktop-after-read-hook' fires after all buffers have been restored.
;; We use it to:
;;   1. Clear the flyspell desktop-restore guard (allows Hunspell to start).
;;   2. Re-run flyspell-mode-on on all restored buffers so errors show up.
;;   3. Open the Dashboard tab.
;;
;; The two actions are separated by a small timer so the dashboard
;; does not block the flyspell recheck loop.

(defun my/after-desktop-restore ()
  "Run once after desktop-restore: unblock Hunspell and open Dashboard."
  ;; Step 1: allow Hunspell to start and check all restored buffers.
  ;; This fires Hunspell exactly once for the first buffer that needs it.
  (when (fboundp 'my/flyspell--recheck-all-buffers)
    (run-with-timer 0.1 nil #'my/flyspell--recheck-all-buffers))
  ;; Step 2: open the Dashboard tab after flyspell has settled.
  (run-with-timer
   0.5 nil
   (lambda ()
     (unless (seq-find (lambda (tab)
                         (equal (alist-get 'name tab) "Dashboard"))
                       (tab-bar-tabs))
       (my/open-notes-dashboard)))))

(add-hook 'desktop-after-read-hook #'my/after-desktop-restore)
;; Keep emacs-startup-hook as fallback for first launch (no desktop yet).
(add-hook 'emacs-startup-hook      #'my/startup-open-dashboard)

(defun my/startup-open-dashboard ()
  "Open Dashboard tab at startup (fallback for first launch without desktop)."
  (run-with-timer
   0.5 nil
   (lambda ()
     (unless (seq-find (lambda (tab)
                         (equal (alist-get 'name tab) "Dashboard"))
                       (tab-bar-tabs))
       (my/open-notes-dashboard)))))

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
