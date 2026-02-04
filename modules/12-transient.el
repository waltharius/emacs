;;; 12-transient.el --- Transient menu for notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Unified transient menu for all note-related operations.
;; Accessed with C-c n - shows all available note functions in one place.
;;
;; Menu sections:
;; - Create: Journal, base notes, essays
;; - Capture: Fleeting notes and journal captures
;; - Search: Find files and grep notes
;; - Linking: Insert links and view backlinks
;; - File Management: Rename, tag, delete
;; - Tools: Insert time/date, well-being, toggle view settings
;; - Spelling: Check, correct errors, toggle spell-checking

;;; Code:

(require 'transient)

;; ============================================================
;; MAIN NOTES MENU (C-c n)
;; ============================================================

(transient-define-prefix my/notes-menu ()
  "Unified menu for all note operations."
  ["Denote Notes - Main Menu"
   ["Create"
    ("n" "New note" my/denote-base)
    ("j" "Journal today" my/denote-journal)
    ("J" "Journal date" my/denote-journal-date)
    ("e" "Essay" my/denote-essay)]
   
   ["Capture"
    ("c" "Journal captures" my/open-journal-captures)
    ("f" "Fleeting notes" my/open-fleeting-notes)
    ("C" "Capture menu" org-capture)]
   
   ["Search & Find"
    ("F" "Find file" denote-open-or-create)
    ("g" "Grep notes" consult-denote-grep
     :if (lambda () (fboundp 'consult-denote-grep)))]
   
   ["Linking"
    ("i" "Insert link" denote-link)
    ("B" "Backlinks" denote-backlinks)]]
  
  ["File Management & Tools"
   ["File Management"
    ("r" "Rename file" denote-rename-file)
    ("t" "Add keywords" denote-rename-file-keywords)
    ("d" "Delete note" my/denote-delete-note)]
   
   ["Insert"
    ("h" "Time (HH:MM)" insert-current-time)
    ("D" "Date (YYYY-MM-DD)" insert-current-date)
    ("w" "Well-being" my/denote-set-wellbeing)]
   
   ["Spelling"
    ("s" "Correct previous" my/spell-correct-previous :transient t)
    ("S" "Check buffer" my/spell-check-buffer)
    ("T" "Toggle spellcheck" my/toggle-flyspell)]
   
   ["Toggle View"
    ("y" "Center text" my/toggle-visual-fill-column-center)
    ("I" "Indent headings" my/toggle-org-indent)]
   
   ["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]])

;; ============================================================
;; KEYBINDING
;; ============================================================

;; Replace existing C-c n keybindings with transient menu
(global-set-key (kbd "C-c n") 'my/notes-menu)

;; ============================================================
;; USAGE
;; ============================================================
;;
;; Press C-c n to open the notes menu
;;
;; All your note operations in one place:
;; - Create different types of notes
;; - Quick capture fleeting thoughts
;; - Search and link between notes
;; - Manage files (rename, tag, delete)
;; - Insert timestamps
;; - Toggle view settings
;; - Spell-checking with smart correction
;;
;; SPELL-CHECKING:
;; - Press 's' repeatedly to correct previous errors (stays in menu!)
;; - Press 'S' to force-check entire buffer
;; - Press 'T' to toggle flyspell on/off
;;
;; The menu stays open after most operations, so you can
;; perform multiple actions quickly. Press 'q' to quit.

(provide '12-transient)
;;; 12-transient.el ends here
