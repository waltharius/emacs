;;; 08-keybindings.el --- Keybindings -*- lexical-binding: t; -*-
;;; Commentary:
;; All custom keybindings in one place
;; THIS MODULE MUST BE LOADED LAST!
;;
;; Keybinding philosophy:
;; - C-c letter = user commands (your personal functions)
;; - C-c C-letter = mode-specific (org-mode, etc.)
;; - Keep frequently used commands short
;; - Group related commands with same prefix
;;
;; NOTE: C-c n is now handled by transient menu (12-transient.el)

;;; Code:

;; ============================================================
;; NOTE OPERATIONS - NOW IN TRANSIENT MENU (C-c n)
;; ============================================================
;;
;; All note-related operations are now accessible via:
;; C-c n - Opens transient menu with all functions
;;
;; Individual keybindings removed to avoid conflicts.
;; See modules/12-transient.el for the menu structure.

;; ============================================================
;; ORG-CAPTURE (already defined in 06-capture.el)
;; ============================================================
;; C-c c = org-capture menu

;; ============================================================
;; GIT OPERATIONS (already defined in 07-git.el)
;; ============================================================
;; C-c v s = notes git status
;; C-c v c = commit notes now
;; C-c v S = config git status
;; C-c v C = commit config now
;; C-c v d = diff current file
;; C-c v h = history current file

;; ============================================================
;; DESKTOP/SESSION (already defined in 01-ui.el)
;; ============================================================
;; C-c d s = save desktop now

;; ============================================================
;; TAB-BAR (already defined in 01-ui.el)
;; ============================================================
;; C-c t n = new tab
;; C-c t c = close tab
;; C-c t o = switch tab
;; C-c t r = rename tab

;; ============================================================
;; SPELLCHECK (already defined in 03-spelling.el)
;; ============================================================
;; C-c F m = Polish dictionary
;; C-c F e = English dictionary
;; C-c F n = next error
;; C-c F c = correct word
;; C-c F b = check buffer
;; C-c F a = add to dictionary

;; ============================================================
;; HELPER KEYBINDINGS
;; ============================================================

;; Quick config access
(global-set-key (kbd "C-c o i") 'open-init-el-bottom-split)

;; Evaluate elisp
(global-set-key (kbd "C-c e b") 'eval-buffer)
(global-set-key (kbd "C-c e r") 'eval-region)

;; ============================================================
;; DOCUMENTATION STRING
;; ============================================================

(defun my/show-keybindings-help ()
  "Show summary of custom keybindings."
  (interactive)
  (let ((help-text
         "Keybindings Summary

===================

Notes (C-c n):
  C-c n - Open notes transient menu
          (All note operations in one place!)

Denote Quick Access:
  C-c d f - Find note
  C-c d l - Insert link
  C-c d b - Show backlinks
  C-c d r - Rename file
  C-c d t - Modify keywords

Capture (C-c c):
  C-c c   - Org-capture menu

Git (C-c v):
  C-c v s - Notes status
  C-c v c - Commit notes
  C-c v S - Config status
  C-c v C - Commit config
  C-c v d - Diff file
  C-c v h - File history

Tabs (C-c t):
  C-c t n - New tab
  C-c t c - Close tab
  C-c t o - Switch tab
  C-c t r - Rename tab

Spelling (C-c F):
  C-c F m - Polish
  C-c F e - English
  C-c F n - Next error
  C-c F c - Correct
  C-c F b - Check buffer
  C-c F a - Add to dictionary

Magit:
  C-x g   - Magit status

Other:
  C-c o i - Open init.el
  C-c e b - Eval buffer
  C-c e r - Eval region
"))
    (with-output-to-temp-buffer "*Keybindings Help*"
      (princ help-text))))

(global-set-key (kbd "C-c h k") 'my/show-keybindings-help)

(provide '08-keybindings)
;;; 08-keybindings.el ends here
