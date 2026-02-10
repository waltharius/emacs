;;; 12-transient.el --- Transient menu for notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Unified transient menu for all note-related operations.
;; Accessed with C-c n - shows all available note functions in one place.
;;
;; Menu sections:
;; - Create: Journal, base notes, essays
;; - Capture: Fleeting notes and journal captures
;; - Search: Find files and grep notes (SEARCHES ALL ~/notes/!)
;; - Linking: Insert links and view backlinks
;; - File Management: Rename, tag, delete
;; - Tools: Insert time/date, well-being, toggle view settings
;; - Spelling: Check, correct errors, add to dictionary, toggle spell-checking
;; - Analytics: Typing statistics for ergonomic keyboard research

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
    ("g" "Grep notes" consult-denote-grep)]
   
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
    ("a" "Add to dict" my/spell-add-previous-to-dict :transient t)
    ("S" "Check visible" my/spell-check-visible)
    ("b" "Check full buffer" my/spell-check-buffer-full)
    ("T" "Toggle spellcheck" my/toggle-flyspell)]
   
   ["Toggle View"
    ("y" "Center text" my/toggle-visual-fill-column-center)
    ("W" "Writing mode" my/toggle-writeroom)
    ("I" "Indent headings" my/toggle-org-indent)]]
  
  ["Analytics & Navigation"
   ["Typing Analytics"
    ("k" "Command stats" keyfreq-show)
    ("K" "Keylog status" keylog-status :transient t)
    ("[" "Disable tracking" keylog-disable)
    ("]" "Enable tracking" keylog-enable)]
   
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
;; - Typing analytics for keyboard ergonomics research
;;
;; SEARCH:
;; - 'F' (Find) - Fuzzy search for files across all silos
;; - 'g' (Grep) - Text search across ALL ~/notes/ (journal, pks, docu)
;;   Since denote-directory is set to ~/notes/ root, grep automatically
;;   searches all subdirectories including journal, pks, and docu!
;;
;; SPELL-CHECKING:
;; - Press 's' repeatedly to correct previous errors (menu stays open!)
;; - Press 'a' to add word to dictionary (skip correction menu)
;; - Press 'S' to check visible region (fast, safe)
;; - Press 'b' to check entire buffer (thorough, may take a moment)
;; - Press 'T' to toggle flyspell on/off
;;
;; AUTO-CHECKING:
;; - Small files (< 7000 words) → Auto-checked after 3 seconds
;; - Large files (>= 7000 words) → Only visible region auto-checked
;; - You can manually check anytime with 'S' (visible) or 'b' (full)
;;
;; Both 's' and 'a' return you to original cursor position automatically!
;;
;; FILE LINKING:
;; - Use C-c n i for denote-link (fuzzy matching across all silos)
;; - Use C-c n F for find file (search all directories)
;; - Both now work beautifully across journal, pks, and docu!
;;
;; INDENT TOGGLE:
;; - 'I' toggles org-indent-mode
;; - Default: OFF (better for older notes)
;; - Enable for new notes when you want visual hierarchy
;;
;; WRITING MODE:
;; - 'W' toggles writeroom-mode (centered cursor for writing)
;; - Keeps cursor vertically centered while typing
;; - Non-disruptive: doesn't jump when clicking or navigating
;; - Perfect for distraction-free journal and essay writing
;;
;; TYPING ANALYTICS:
;; - 'k' shows command frequency statistics (which commands you use most)
;; - 'K' shows keylog status (keystrokes buffered, file size) - menu stays open
;; - '[' temporarily disables character tracking (privacy/performance)
;; - ']' re-enables character tracking
;; 
;; Data collection for ergonomic keyboard selection:
;; - Commands tracked in ~/.emacs.keyfreq
;; - Keystrokes tracked in ~/.emacs.d/keys
;; - All data stays local (in .gitignore)
;; - Recommended: collect 2-4 weeks of data before analyzing
;;
;; The menu stays open after most operations, so you can
;; perform multiple actions quickly. Press 'q' to quit.

(provide '12-transient)
;;; 12-transient.el ends here
