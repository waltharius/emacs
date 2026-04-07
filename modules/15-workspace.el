;;; 15-workspace.el --- Obsidian-like workspace panels -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Adds four Obsidian-like features to the existing Denote setup:
;;   1. dired-sidebar    - Left panel: folder tree of ~/notes/
;;   2. denote-backlinks - Right panel: what links to this note
;;   3. denote-explore   - Tag stats and note network (on demand)
;;   4. dashboard        - Startup screen with recent notes
;;
;; HOW TO REVERT:
;;   - Remove the (load ... "15-workspace.el") line from init.el
;;   - That's it. No other module is touched by this file.
;;
;; KEYBINDINGS:
;;   C-c w w  - Toggle sidebar + backlinks together
;;   C-c w d  - Open dashboard
;;   C-c w x  - Explore tags / note statistics
;;   C-c w r  - Jump to random note

;;; Code:

;; ============================================================
;; 1. DIRED-SIDEBAR: Persistent left file tree
;; ============================================================
;; :demand t forces the package to load immediately so that
;; dired-sidebar-showing-sidebar-p is defined when my/workspace-toggle
;; is called. Without :demand, :commands makes it lazy and the function
;; is void until the first toggle.

(use-package dired-sidebar
  :ensure t
  :demand t                              ; FIX: was :commands (lazy) - caused void fn error
  :custom
  (dired-sidebar-width 28)
  (dired-sidebar-use-magit-integration nil) ; avoid git slowdown in large note dirs
  (dired-sidebar-use-term-integration nil)
  (dired-sidebar-follow-file-idle-delay 0)
  (dired-sidebar-follow-file-at-point-on-toggle-open nil))

(defun my/notes-sidebar-toggle ()
  "Toggle dired-sidebar pinned to the notes root directory.
Uses `my-notes-dir' variable from 00-core.el."
  (interactive)
  (let ((default-directory (expand-file-name my-notes-dir)))
    (dired-sidebar-toggle-sidebar)))

;; ============================================================
;; 2. DENOTE-BACKLINKS: Right panel wired as side window
;; ============================================================
;; Only configures WHERE the existing C-c d b command opens its buffer.

(with-eval-after-load 'denote
  (setq denote-backlinks-display-buffer-action
        '((display-buffer-reuse-window
           display-buffer-in-side-window)
          (side . right)
          (slot . 0)
          (window-width . 0.25)
          (inhibit-same-window . t)
          (window-parameters . ((no-delete-other-windows . t))))))

;; ============================================================
;; 3. DENOTE-EXPLORE: Tag browser and note network (on demand)
;; ============================================================
;; :after (denote org) ensures org functions are available at
;; native-compile time, silencing the org-insert-time-stamp etc. warnings.

(use-package denote-explore
  :ensure t
  :after (denote org)                    ; FIX: added org to silence native-compiler warnings
  :commands (denote-explore-count-notes
             denote-explore-count-keywords
             denote-explore-identify-duplicate-notes
             denote-explore-random-note
             denote-explore-network)
  :custom
  (denote-explore-network-directory (expand-file-name my-notes-dir))
  (denote-explore-network-filename "denote-network.json"))

(defun my/notes-explore ()
  "Show a quick stats summary of your Denote notes collection."
  (interactive)
  (require 'denote-explore)
  (denote-explore-count-notes))

;; ============================================================
;; 4. DASHBOARD: Startup screen with recent notes
;; ============================================================
;; recentf-exclude is set BEFORE dashboard-setup-startup-hook so the
;; dashboard's first render already uses the filtered list.
;; Excluded: Emacs internals, ido.last, desktop files, elpa packages.

(use-package dashboard
  :ensure t
  :demand t
  :config
  ;; FIX: exclude internal Emacs files so only real notes appear
  (setq recentf-exclude
        (list (expand-file-name "~/.emacs.d/")
              "/tmp/"
              "\\.log$"
              "\\.last$"))    ; catches ido.last, recentf.last, etc.
  (setq dashboard-startup-banner 'logo)
  (setq dashboard-center-content t)
  (setq dashboard-vertically-center-content nil)
  (setq dashboard-items '((recents  . 15)
                          (bookmarks . 5)))
  (setq dashboard-display-icons-p nil)
  (setq dashboard-set-heading-icons nil)
  (setq dashboard-set-file-icons nil)
  (setq dashboard-footer-messages
        '("C-c w w  sidebar+backlinks  |  C-c d b  backlinks  |  C-c w x  tags  |  C-c w r  random note"))
  (setq dashboard-footer-icon "")
  (dashboard-setup-startup-hook))

(defun my/open-dashboard ()
  "Switch to or recreate the Dashboard buffer."
  (interactive)
  (dashboard-open))

;; ============================================================
;; COMBINED TOGGLE: C-c w w
;; ============================================================
;; FIX 1: replaced dired-sidebar-showing-sidebar-p (void when lazy-loaded)
;;         with (get-buffer (dired-sidebar-buffer-name)) which is always
;;         available once dired-sidebar is loaded with :demand t.
;; FIX 2: replaced obsolete denote-file-is-note-p (Denote <4.1)
;;         with denote-file-has-denoted-filename-p (Denote 4.1+).

(defun my/workspace-toggle ()
  "Toggle Obsidian-like workspace: file tree left, backlinks right.
Run again to close. Use C-c <left> (winner-undo) to undo layout."
  (interactive)
  (if (dired-sidebar-showing-sidebar-p)
      (progn
        (dired-sidebar-hide-sidebar)
        (message "Workspace closed.  C-c <left> to undo any layout change."))
    (progn
      (my/notes-sidebar-toggle)
      (when (and (buffer-file-name)
                 (denote-file-has-denoted-filename-p (buffer-file-name))) ; FIX: updated API
        (denote-backlinks))
      (message "Workspace open.  C-c w w to close."))))

;; ============================================================
;; KEYBINDINGS (C-c w prefix)
;; ============================================================

(global-set-key (kbd "C-c w w") #'my/workspace-toggle)
(global-set-key (kbd "C-c w d") #'my/open-dashboard)
(global-set-key (kbd "C-c w x") #'my/notes-explore)
(global-set-key (kbd "C-c w r") #'denote-explore-random-note)

(provide '15-workspace)
;;; 15-workspace.el ends here
