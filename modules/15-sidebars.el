;;; 15-sidebars.el --- Persistent sidebars (Obsidian-style) -*- lexical-binding: t; -*-
;;; Commentary:
;; Description: Persistent left/right sidebars for file tree, backlinks,
;;              calendar, and quick notes.  Always visible, toggleable.
;;
;;; Code:

(require 'neotree)  ; File tree
(require 'dired-sidebar)  ; Better file sidebar
(require 'org-sidebar)  ; Org-mode specific sidebar

;; ============================================================
;; CONFIGURATION
;; ============================================================

(defvar my/sidebar-left-visible t
  "Whether left sidebar is currently visible.")

(defvar my/sidebar-right-visible t
  "Whether right sidebar is currently visible.")

(defvar my/sidebar-left-width 30
  "Width of left sidebar in characters.")

(defvar my/sidebar-right-width 35
  "Width of right sidebar in characters.")

(defvar my/sidebar-left-buffer-name "*Sidebar-Left*"
  "Name of left sidebar buffer.")

(defvar my/sidebar-right-buffer-name "*Sidebar-Right*"
  "Name of right sidebar buffer.")

;; ============================================================
;; LEFT SIDEBAR: File Tree + Recent Files
;; ============================================================

(defun my/sidebar-left-create ()
  "Create persistent left sidebar with file tree."
  (interactive)
  (let ((buf (get-buffer-create my/sidebar-left-buffer-name)))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      
      ;; Header
      (insert (propertize "📁 FILES\n" 'face '(:weight bold :height 1.2)))
      (insert (propertize "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n" 'face 'shadow))
      
      ;; Quick actions
      (insert-text-button "[+] New Note"
                         'action (lambda (_) (call-interactively 'denote))
                         'follow-link t
                         'face '(:foreground "#51afef"))
      (insert "  ")
      (insert-text-button "[↻] Refresh"
                         'action (lambda (_) (my/sidebar-left-refresh))
                         'follow-link t
                         'face '(:foreground "#98be65"))
      (insert "\n\n")
      
      ;; Recent files (last 10)
      (insert (propertize "Recent Files:\n" 'face '(:weight bold)))
      (let ((recent-files (seq-take recentf-list 10)))
        (dolist (file recent-files)
          (when (string-match-p my/notes-dir file)
            (let ((display-name (file-name-nondirectory file)))
              (insert "  ")
              (insert-text-button display-name
                                 'action `(lambda (_) (find-file ,file))
                                 'follow-link t
                                 'face 'link)
              (insert "\n")))))
      
      (insert "\n")
      (insert (propertize "All Notes:\n" 'face '(:weight bold)))
      
      ;; All notes by category
      (let ((files (directory-files my/notes-dir t "\\.org$"))
            (journal-files '())
            (zettel-files '())
            (other-files '()))
        
        ;; Categorize files
        (dolist (file files)
          (let ((name (file-name-nondirectory file)))
            (cond
             ((string-match-p "journal" name) (push file journal-files))
             ((string-match-p "==" name) (push file zettel-files))
             (t (push file other-files)))))
        
        ;; Display categories
        (when journal-files
          (insert "\n  📓 Journals:\n")
          (dolist (file (seq-take (sort journal-files #'string>) 5))
            (let ((name (file-name-nondirectory file)))
              (insert "    ")
              (insert-text-button name
                                 'action `(lambda (_) (find-file ,file))
                                 'follow-link t
                                 'face 'link)
              (insert "\n"))))
        
        (when zettel-files
          (insert "\n  🗂️  Zettelkasten:\n")
          (dolist (file (seq-take (sort zettel-files #'string>) 5))
            (let ((name (file-name-nondirectory file)))
              (insert "    ")
              (insert-text-button name
                                 'action `(lambda (_) (find-file ,file))
                                 'follow-link t
                                 'face 'link)
              (insert "\n")))))
      
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "q") 'my/sidebar-left-toggle)
      (local-set-key (kbd "r") 'my/sidebar-left-refresh))
    buf))

(defun my/sidebar-left-show ()
  "Show left sidebar in dedicated window."
  (interactive)
  (let ((win (split-window (frame-root-window) my/sidebar-left-width 'left t)))
    (with-selected-window win
      (switch-to-buffer (my/sidebar-left-create))
      (set-window-dedicated-p win t)
      (set-window-parameter win 'no-delete-other-windows t))
    (setq my/sidebar-left-visible t)))

(defun my/sidebar-left-hide ()
  "Hide left sidebar."
  (interactive)
  (when-let ((win (get-buffer-window my/sidebar-left-buffer-name)))
    (delete-window win)
    (setq my/sidebar-left-visible nil)))

(defun my/sidebar-left-toggle ()
  "Toggle left sidebar visibility."
  (interactive)
  (if my/sidebar-left-visible
      (my/sidebar-left-hide)
    (my/sidebar-left-show)))

(defun my/sidebar-left-refresh ()
  "Refresh left sidebar content."
  (interactive)
  (when-let ((win (get-buffer-window my/sidebar-left-buffer-name)))
    (with-selected-window win
      (my/sidebar-left-create)
      (switch-to-buffer my/sidebar-left-buffer-name))))

;; ============================================================
;; RIGHT SIDEBAR: Backlinks + Quick Stats + Calendar
;; ============================================================

(defun my/sidebar-right-create ()
  "Create persistent right sidebar with backlinks and stats."
  (interactive)
  (let ((buf (get-buffer-create my/sidebar-right-buffer-name))
        (current-file (buffer-file-name)))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      
      ;; Header
      (insert (propertize "📊 CONTEXT\n" 'face '(:weight bold :height 1.2)))
      (insert (propertize "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n" 'face 'shadow))
      
      ;; Quick actions
      (insert-text-button "[w] Well-being"
                         'action (lambda (_) (call-interactively 'my/denote-wellbeing-entry))
                         'follow-link t
                         'face '(:foreground "#c678dd"))
      (insert "  ")
      (insert-text-button "[s] Stats"
                         'action (lambda (_) (call-interactively 'my/denote-dashboard))
                         'follow-link t
                         'face '(:foreground "#da8548"))
      (insert "\n\n")
      
      ;; Today's stats
      (insert (propertize "Today's Progress:\n" 'face '(:weight bold)))
      (let* ((today (format-time-string "%Y-%m-%d"))
             (words-today 0)
             (notes-today 0))
        (dolist (file (directory-files my/notes-dir t "\\.org$"))
          (when (string-match-p today file)
            (setq notes-today (1+ notes-today))
            (with-temp-buffer
              (insert-file-contents file)
              (setq words-today (+ words-today (count-words (point-min) (point-max)))))))
        
        (insert (format "  📝 Notes: %d\n" notes-today))
        (insert (format "  ✍️  Words: %s\n\n" (my/format-number words-today))))
      
      ;; Backlinks (if current file is a note)
      (when (and current-file (string-match-p my/notes-dir current-file))
        (insert (propertize "Backlinks:\n" 'face '(:weight bold)))
        (let ((backlinks (my/sidebar-find-backlinks current-file)))
          (if backlinks
              (dolist (link backlinks)
                (insert "  → ")
                (insert-text-button link
                                   'action `(lambda (_) (find-file ,link))
                                   'follow-link t
                                   'face 'link)
                (insert "\n"))
            (insert "  (no backlinks)\n")))
        (insert "\n"))
      
      ;; Calendar (mini)
      (insert (propertize "Calendar:\n" 'face '(:weight bold)))
      (let ((calendar-str (with-temp-buffer
                           (calendar)
                           (buffer-string))))
        (insert (substring calendar-str 0 (min 300 (length calendar-str)))))
      
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "q") 'my/sidebar-right-toggle)
      (local-set-key (kbd "r") 'my/sidebar-right-refresh))
    buf))

(defun my/sidebar-find-backlinks (file)
  "Find all files linking to FILE."
  (let ((file-id (my/folge-get-id-from-file file))
        (backlinks '()))
    (when file-id
      (dolist (f (directory-files my/notes-dir t "\\.org$"))
        (with-temp-buffer
          (insert-file-contents f)
          (goto-char (point-min))
          (when (search-forward file-id nil t)
            (push (file-name-nondirectory f) backlinks)))))
    backlinks))

(defun my/sidebar-right-show ()
  "Show right sidebar in dedicated window."
  (interactive)
  (let ((win (split-window (frame-root-window) (- my/sidebar-right-width) 'right t)))
    (with-selected-window win
      (switch-to-buffer (my/sidebar-right-create))
      (set-window-dedicated-p win t)
      (set-window-parameter win 'no-delete-other-windows t))
    (setq my/sidebar-right-visible t)))

(defun my/sidebar-right-hide ()
  "Hide right sidebar."
  (interactive)
  (when-let ((win (get-buffer-window my/sidebar-right-buffer-name)))
    (delete-window win)
    (setq my/sidebar-right-visible nil)))

(defun my/sidebar-right-toggle ()
  "Toggle right sidebar visibility."
  (interactive)
  (if my/sidebar-right-visible
      (my/sidebar-right-hide)
    (my/sidebar-right-show)))

(defun my/sidebar-right-refresh ()
  "Refresh right sidebar content."
  (interactive)
  (when-let ((win (get-buffer-window my/sidebar-right-buffer-name)))
    (with-selected-window win
      (my/sidebar-right-create)
      (switch-to-buffer my/sidebar-right-buffer-name))))

;; ============================================================
;; AUTO-REFRESH ON FILE CHANGE
;; ============================================================

(defun my/sidebar-auto-refresh ()
  "Auto-refresh sidebars when switching files."
  (when my/sidebar-left-visible
    (my/sidebar-left-refresh))
  (when my/sidebar-right-visible
    (my/sidebar-right-refresh)))

(add-hook 'buffer-list-update-hook #'my/sidebar-auto-refresh)

;; ============================================================
;; INIT: Show sidebars on startup
;; ============================================================

(defun my/sidebars-init ()
  "Initialize sidebars on Emacs startup."
  (when my/sidebar-left-visible
    (my/sidebar-left-show))
  (when my/sidebar-right-visible
    (my/sidebar-right-show)))

(add-hook 'emacs-startup-hook #'my/sidebars-init)

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c [") 'my/sidebar-left-toggle)
(global-set-key (kbd "C-c ]") 'my/sidebar-right-toggle)
(global-set-key (kbd "C-c {") 'my/sidebar-left-refresh)
(global-set-key (kbd "C-c }") 'my/sidebar-right-refresh)

(provide '15-sidebars)
;;; 15-sidebars.el ends here
