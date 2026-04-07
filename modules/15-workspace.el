;;; 15-workspace.el --- Obsidian-like workspace panels -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Adds four Obsidian-like features to the existing Denote setup:
;;   1. dired-sidebar  - Left panel: folder tree of ~/notes/
;;   2. denote-backlinks - Right panel: what links to this note
;;   3. denote-explore - Tag stats and note network (on demand)
;;   4. dashboard      - Startup screen with recent notes
;;
;; HOW TO REVERT:
;;   - Remove the (load ... "15-workspace.el") line from init.el
;;   - That's it. No other module is touched by this file.
;;
;; TOGGLE:
;;   C-c w w  - Toggle sidebar + backlinks together
;;   C-c w d  - Open dashboard
;;   C-c w x  - Explore tags / note statistics
;;
;; KNOWN RISKS:
;;   - dired-sidebar may conflict with visual-fill-column centering.
;;     If text centering breaks, run (visual-fill-column--adjust-window)
;;     or close the sidebar and reopen the note.
;;   - denote-backlinks hook fires on every find-file; disabled by default.
;;     Enable manually via C-c d b (already in 08-keybindings.el).

;;; Code:

;; ============================================================
;; 1. DIRED-SIDEBAR: Persistent left file tree
;; ============================================================

(use-package dired-sidebar
  :ensure t
  :commands (dired-sidebar-toggle-sidebar)
  :custom
  (dired-sidebar-width 28)
  ;; Disable git integration - avoids slowdown in large note directories
  (dired-sidebar-use-magit-integration nil)
  (dired-sidebar-use-term-integration nil)
  ;; Don't follow currently open file (less visual noise)
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
;; Backlinks command already keyed to C-c d b in 08-keybindings.el.
;; Here we only configure WHERE it appears (right side window),
;; so the existing keybinding now opens it in a persistent panel.

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

(use-package denote-explore
  :ensure t
  :after denote
  :commands (denote-explore-count-notes
             denote-explore-count-keywords
             denote-explore-identify-duplicate-notes
             denote-explore-random-note
             denote-explore-network)
  :custom
  ;; Output graph JSON to notes root so it's version-controlled
  (denote-explore-network-directory (expand-file-name my-notes-dir))
  (denote-explore-network-filename "denote-network.json"))

(defun my/notes-explore ()
  "Show a quick stats summary of your Denote notes collection."
  (interactive)
  (denote-explore-count-notes))

;; ============================================================
;; 4. DASHBOARD: Startup screen with recent notes
;; ============================================================

(use-package dashboard
  :ensure t
  :demand t
  :custom
  (dashboard-startup-banner 'logo)
  (dashboard-center-content t)
  (dashboard-vertically-center-content nil)
  ;; Show recent files and bookmarks only - no agenda (keep it fast)
  (dashboard-items '((recents  . 12)
                     (bookmarks . 5)))
  (dashboard-display-icons-p nil)      ; Avoid icon font dependency
  (dashboard-set-heading-icons nil)
  (dashboard-set-file-icons nil)
  ;; Footer message
  (dashboard-footer-messages
   '("C-c w w  toggle sidebar + backlinks | C-c d b  backlinks | C-c w x  explore tags"))
  (dashboard-footer-icon "")
  :config
  ;; Exclude Emacs internals from recent files - show only notes + config
  (setq recentf-exclude
        (list (expand-file-name "~/.emacs.d/elpa/")
              (expand-file-name "~/.emacs.d/desktop/")
              "/tmp/"
              "\\.log$"))
  (dashboard-setup-startup-hook))

(defun my/open-dashboard ()
  "Switch to or recreate the Dashboard buffer."
  (interactive)
  (dashboard-open))

;; ============================================================
;; COMBINED TOGGLE: C-c w w opens sidebar + backlinks together
;; ============================================================

(defun my/workspace-toggle ()
  "Toggle Obsidian-like workspace: file tree on left, backlinks on right.
Run again to close both panels. Use winner-undo (C-c <left>) to revert
any accidental layout change."
  (interactive)
  (if (dired-sidebar-showing-sidebar-p)
      (progn
        (dired-sidebar-hide-sidebar)
        (message "Workspace panels closed. C-c <left> to undo layout."))
    (progn
      (my/notes-sidebar-toggle)
      (when (and (buffer-file-name)
                 (denote-file-is-note-p (buffer-file-name)))
        (denote-backlinks))
      (message "Workspace open. C-c w w to close."))))

;; ============================================================
;; KEYBINDINGS (C-c w prefix - unused in 08-keybindings.el)
;; ============================================================

(global-set-key (kbd "C-c w w") #'my/workspace-toggle)
(global-set-key (kbd "C-c w d") #'my/open-dashboard)
(global-set-key (kbd "C-c w x") #'my/notes-explore)
;; Also expose random note jump - useful for review/serendipitous discovery
(global-set-key (kbd "C-c w r") #'denote-explore-random-note)

(provide '15-workspace)
;;; 15-workspace.el ends here
