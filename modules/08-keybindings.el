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

;;; Code:

;; ============================================================
;; NOTE CREATION (C-c n ...)
;; ============================================================

(global-set-key (kbd "C-c n j") 'my/denote-journal)      ; Journal today
(global-set-key (kbd "C-c n d") 'my/denote-journal-date) ; Journal (date)
(global-set-key (kbd "C-c n n") 'my/denote-base)         ; New note
(global-set-key (kbd "C-c n e") 'my/denote-essay)        ; Essay project
(global-set-key (kbd "C-c n w") 'my/denote-set-wellbeing); Well-being
(global-set-key (kbd "C-c n D") 'my/denote-delete-note)  ; Delete note

;; Quick access files (already defined in 06-capture.el)
;; C-c n f = fleeting notes
;; C-c n c = journal captures

;; ============================================================
;; DENOTE BUILT-IN FUNCTIONS (C-c d ...)
;; ============================================================

(global-set-key (kbd "C-c d f") 'denote-find-file)           ; Find note
(global-set-key (kbd "C-c d l") 'denote-link)                ; Insert link
(global-set-key (kbd "C-c d b") 'denote-backlinks)           ; Show backlinks
(global-set-key (kbd "C-c d r") 'denote-rename-file)         ; Rename note
(global-set-key (kbd "C-c d t") 'denote-rename-file-keywords) ; Modify keywords (add/remove)

;; ============================================================
;; SILO SWITCHING (C-c s ...)
;; ============================================================

(defun my/switch-to-journal ()
  "Switch to journal silo."
  (interactive)
  (setq denote-directory my-notes-journal)
  (message "Denote: journal silo"))

(defun my/switch-to-pks ()
  "Switch to PKS silo."
  (interactive)
  (setq denote-directory my-notes-pks)
  (message "Denote: PKS silo"))

(defun my/switch-to-docu ()
  "Switch to documentation silo."
  (interactive)
  (setq denote-directory my-notes-docu)
  (message "Denote: docu silo"))

(global-set-key (kbd "C-c s j") 'my/switch-to-journal)
(global-set-key (kbd "C-c s p") 'my/switch-to-pks)
(global-set-key (kbd "C-c s d") 'my/switch-to-docu)

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
;; ORG APPEARANCE (defined in 11-org-appearance.el)
;; ============================================================
;; M-x my/toggle-org-indent = toggle indentation

;; ============================================================
;; HELPER KEYBINDINGS
;; ============================================================

;; Quick config access
(global-set-key (kbd "C-c o i") 'open-init-el-bottom-split)

;; Insert timestamp
(global-set-key (kbd "C-c i t") 'insert-current-time)

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

Note Creation (C-c n):
  C-c n j - Journal (today)
  C-c n d - Journal (specific date)
  C-c n n - New note
  C-c n e - Essay
  C-c n w - Set well-being
  C-c n D - Delete note
  C-c n f - Open fleeting notes
  C-c n c - Open journal captures

Denote Functions (C-c d):
  C-c d f - Find note
  C-c d l - Insert link
  C-c d b - Show backlinks
  C-c d r - Rename file
  C-c d t - Modify keywords (add/remove)
  C-c d s - Save desktop

Silo Switching (C-c s):
  C-c s j - Switch to journal
  C-c s p - Switch to PKS
  C-c s d - Switch to docu

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

Org Appearance:
  M-x my/toggle-org-indent - Toggle indentation

Magit:
  C-x g   - Magit status

Other:
  C-c o i - Open init.el
  C-c i t - Insert time
  C-c e b - Eval buffer
  C-c e r - Eval region
"))
    (with-output-to-temp-buffer "*Keybindings Help*"
      (princ help-text))))

(global-set-key (kbd "C-c h k") 'my/show-keybindings-help)

(provide '08-keybindings)
;;; 08-keybindings.el ends here
