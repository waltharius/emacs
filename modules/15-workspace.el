;;; 15-workspace.el --- Notes dashboard and workspace tools -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Custom notes dashboard and workspace features for Denote.
;;
;; LAYOUT (3 columns, width calculated from window at render time):
;;
;;   LEFT (33%)          MIDDLE (33%)         RIGHT (33%)
;;   -----------------   ------------------   ---------------------
;;   Recently Modified   PKS -- Personal      Documentation
;;   Journal             Knowledge            Tags
;;
;; KEYBINDINGS:
;;   C-c w d  - Open/refresh notes dashboard (also C-c n o in transient)
;;   C-c w x  - Show tag statistics
;;   C-c w r  - Jump to random note
;;   C-c d b  - Show backlinks (defined in 08-keybindings.el)
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
        (dolist (f (directory-files dir t "\\.org$" t))
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
        (dolist (f (directory-files dir t "\\.org$" t))
          (dolist (tag (my/denote-file-tags f))
            (puthash tag (cons f (gethash tag tag-map '())) tag-map)))))
    (let ((pairs '()))
      (maphash (lambda (tag files) (push (cons tag files) pairs)) tag-map)
      (sort pairs (lambda (a b) (> (length (cdr a)) (length (cdr b))))))))

;; ============================================================
;; COLUMN LAYOUT ENGINE
;; ============================================================
;; Each column is built as a list of (display-string . payload) pairs.
;; display-string is pre-padded to col-width chars.
;; payload is: nil (plain text), a file path string, or (tag . files).
;; The render loop zips all three lists row-by-row, inserting text
;; and attaching buttons based on payload type.

(defun my/col-pad (str width)
  "Truncate or right-pad STR to exactly WIDTH characters."
  (let ((len (length str)))
    (cond
     ((= len width) str)
     ((> len width) (concat (substring str 0 (- width 1)) "~"))
     (t (concat str (make-string (- width len) ?\ ))))))

(defun my/col-header (title width)
  "Return list of two strings: bold title line + separator, each WIDTH chars."
  (list
   (my/col-pad (concat " " title) width)
   (make-string width ?-)))

(defun my/col-file-line (file width)
  "Return (display-string . file-path) truncated to WIDTH."
  (let* ((mtime (format-time-string "%m-%d" (nth 5 (file-attributes file))))
         (title (my/denote-file-title file))
         (text  (my/col-pad (format " %s %s" mtime title) width)))
    (cons text file)))

(defun my/col-tag-line (tag files width)
  "Return (display-string . (tag . files)) truncated to WIDTH."
  (cons (my/col-pad (format " %-18s %2d" tag (length files)) width)
        (cons tag files)))

(defun my/col-blank (width)
  "Return blank string of WIDTH spaces."
  (make-string width ?\ ))

;; ============================================================
;; DASHBOARD: Build column data
;; ============================================================

(defun my/dashboard-build-left (col-width)
  "Build left column: Recently Modified + Journal."
  (let ((lines '()))
    (dolist (s (my/col-header "Recently Modified (10d)" col-width))
      (push (cons s nil) lines))
    (let ((recent (my/denote-recently-modified 10)))
      (if recent
          (dolist (f (seq-take recent 12))
            (push (my/col-file-line f col-width) lines))
        (push (cons (my/col-pad " (none in 10 days)" col-width) nil) lines)))
    (push (cons (my/col-pad "" col-width) nil) lines)
    (dolist (s (my/col-header "Journal" col-width))
      (push (cons s nil) lines))
    (dolist (f (seq-take (my/denote-org-files-in my-notes-journal) 20))
      (push (my/col-file-line f col-width) lines))
    (nreverse lines)))

(defun my/dashboard-build-middle (col-width)
  "Build middle column: PKS."
  (let ((lines '()))
    (dolist (s (my/col-header "PKS -- Personal Knowledge" col-width))
      (push (cons s nil) lines))
    (dolist (f (seq-take (my/denote-org-files-in my-notes-pks) 35))
      (push (my/col-file-line f col-width) lines))
    (nreverse lines)))

(defun my/dashboard-build-right (col-width)
  "Build right column: Documentation + Tags."
  (let ((lines '()))
    (dolist (s (my/col-header "Documentation" col-width))
      (push (cons s nil) lines))
    (dolist (f (seq-take (my/denote-org-files-in my-notes-docu) 15))
      (push (my/col-file-line f col-width) lines))
    (push (cons (my/col-pad "" col-width) nil) lines)
    (dolist (s (my/col-header "Tags" col-width))
      (push (cons s nil) lines))
    (dolist (pair (seq-take (my/denote-all-tags) 25))
      (push (my/col-tag-line (car pair) (cdr pair) col-width) lines))
    (nreverse lines)))

;; ============================================================
;; DASHBOARD: Actions
;; ============================================================

(defconst my/dashboard-buffer-name "*Notes Dashboard*")

(defun my/dashboard-open-in-new-tab (file)
  "Open FILE in a new named tab (browser middle-click behaviour)."
  (tab-bar-new-tab)
  (find-file file)
  (tab-bar-rename-tab (my/denote-file-title file)))

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
          (let* ((title   (my/denote-file-title f))
                 (mtime   (format-time-string "%Y-%m-%d" (nth 5 (file-attributes f))))
                 (display (format "  %s  %s\n" mtime title))
                 (start   (point)))
            (insert display)
            (make-text-button start (1- (point))
                              'action (let ((ff f))
                                        (lambda (_b)
                                          (my/dashboard-open-in-new-tab ff)))
                              'follow-link t
                              'mouse-face 'highlight
                              'face '(:foreground "#2aa198"))))
        (insert "\n")
        (insert (propertize "  q = close" 'face '(:foreground "#888888")))
        (read-only-mode 1)
        (local-set-key (kbd "q") #'kill-buffer-and-window)))
    (display-buffer buf '(display-buffer-below-selected (window-height . 0.4)))))

;; ============================================================
;; DASHBOARD: Render 3-column layout
;; ============================================================

(defun my/dashboard-insert-cell (text payload face-file face-tag)
  "Insert TEXT as a button if PAYLOAD is non-nil, else as plain text.
PAYLOAD is a file path string or a (tag . files) cons."
  (let ((start (point)))
    (insert text)
    (cond
     ((stringp payload)
      (make-text-button start (point)
                        'action (let ((f payload))
                                  (lambda (_b) (my/dashboard-open-in-new-tab f)))
                        'follow-link t
                        'mouse-face 'highlight
                        'face face-file))
     ((consp payload)
      (make-text-button start (point)
                        'action (let ((tag (car payload))
                                      (files (cdr payload)))
                                  (lambda (_b)
                                    (my/dashboard-show-tag-notes tag files)))
                        'follow-link t
                        'mouse-face 'highlight
                        'face face-tag)))))

(defun my/render-notes-dashboard ()
  "Render the 3-column notes dashboard. Returns the buffer."
  (let* ((buf    (get-buffer-create my/dashboard-buffer-name))
         (total  (- (window-total-width) 2))
         (col-w  (/ total 3))
         (left   (my/dashboard-build-left   col-w))
         (middle (my/dashboard-build-middle col-w))
         (right  (my/dashboard-build-right  col-w))
         (blank  (my/col-blank col-w))
         (face-file '(:foreground "#2aa198"))
         (face-tag  '(:foreground "#859900")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)

        ;; Header
        (insert (propertize "  Notes Dashboard"
                            'face '(:weight bold :height 1.2)))
        (insert (propertize (format "   --   %s\n"
                                   (format-time-string "%Y-%m-%d %H:%M"))
                            'face '(:foreground "#888888")))
        (insert (make-string (- (window-total-width) 1) ?=))
        (insert "\n")

        ;; 3-column body
        (let ((max-rows (max (length left) (length middle) (length right))))
          (dotimes (i max-rows)
            (let* ((lp (or (nth i left)   (cons blank nil)))
                   (mp (or (nth i middle) (cons blank nil)))
                   (rp (or (nth i right)  (cons blank nil))))
              (my/dashboard-insert-cell (car lp) (cdr lp) face-file face-tag)
              (insert " ")
              (my/dashboard-insert-cell (car mp) (cdr mp) face-file face-tag)
              (insert " ")
              (my/dashboard-insert-cell (car rp) (cdr rp) face-file face-tag)
              (insert "\n"))))

        ;; Footer
        (insert (make-string (- (window-total-width) 1) ?-))
        (insert "\n")
        (insert (propertize
                 "  g refresh   C-c d b backlinks   C-c w r random note   q bury\n"
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
;; STARTUP: Open Dashboard tab automatically
;; ============================================================

(defun my/startup-open-dashboard ()
  "Open Dashboard tab at startup after desktop restore settles."
  (run-with-timer
   0.5 nil
   (lambda ()
     (unless (seq-find (lambda (tab)
                         (equal (alist-get 'name tab) "Dashboard"))
                       (tab-bar-tabs))
       (my/open-notes-dashboard)))))

(add-hook 'emacs-startup-hook #'my/startup-open-dashboard)

;; ============================================================
;; BACKLINKS: Right side-window (non-conflicting with transient)
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
