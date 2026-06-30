;;; 12-transient.el --- Transient menu for notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Unified transient menu for all note-related operations.
;; Accessed with C-c n - shows all available note functions in one place.

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
    ("c" "Ideas capture"   my/capture-idea)
    ("C" "Capture menu"    org-capture)
    ("m" "Promote to note" my/capture-promote-to-note)]

   ["Search & Find"
    ("F" "Find file" denote-open-or-create)
    ("g" "Grep notes" consult-denote-grep)]

   ["Linking"
    ("i" "Insert link" denote-link)
    ("B" "Backlinks" denote-backlinks)
    ("L" "Linked note" my/denote-linked-note)]]

  ["File Management & Tools"
   ["File Management"
    ("r" "Rename file" denote-rename-file)
    ("t" "Add keywords" denote-rename-file-keywords)
    ("d" "Delete note" my/denote-delete-note)
    ("p" "Export to PDF" my/org-export-to-pdf)
    ("P" "Batch PDF — ANY keyword" my/org-export-pdf-by-keyword)
    ("Q" "Batch PDF — ALL keywords" my/org-export-pdf-by-all-keywords)]

   ["Insert"
    ("h" "Time (HH:MM)" insert-current-time)
    ("D" "Date (YYYY-MM-DD)" insert-current-date)
    ("w" "Well-being" my/denote-set-wellbeing)]

   ["Spelling"
    ("s" "Correct previous" my/spell-correct-previous :transient t)
    ("a" "Add to dict" my/spell-add-previous-to-dict :transient t)
    ("S" "Check visible" my/spell-check-visible)
    ("b" "Check full buffer" my/spell-check-buffer-full)
    ("T" "Toggle spellcheck" my/toggle-flyspell)]

   ["Toggle View"
    ("y" "Center text"      my/toggle-visual-fill-column-center)
    ("W" "Writing mode"     my/toggle-writeroom)
    ("I" "Indent headings"  my/toggle-org-indent)
    ("E" "Emphasis markers" my/toggle-emphasis-markers)]]

  ["Analytics & Navigation"
   ["Typing Analytics"
    ("k" "Command stats" keyfreq-show)
    ("K" "Keylog status" keylog-status :transient t)
    ("[" "Disable tracking" keylog-disable)
    ("]" "Enable tracking" keylog-enable)]

   ["Workspace"
    ("o" "Notes Dashboard" my/open-notes-dashboard)
    ("x" "Tag statistics" my/notes-explore)
    ("R" "Random note" denote-explore-random-note)
    ("u" "Zotero/Bib" my/zotero-menu)]

   ["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]])

;; ============================================================
;; KEYBINDING
;; ============================================================

(global-set-key (kbd "C-c n") 'my/notes-menu)

(provide '12-transient)
;;; 12-transient.el ends here
