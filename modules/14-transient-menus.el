;;; 14-transient-menus.el --- Additional Transient menus -*- lexical-binding: t; -*-
;;
;; Description: Help, Well-being, Statistics, Spelling, Grammar menus
;;              Provides unified Transient interface for all workflows
;;
;;; Commentary:
;;
;; This module defines Transient menus for:
;; - Help & Cheatsheet (C-c h) - master menu with guide
;; - Well-being tracking (C-c w)
;; - Statistics & dashboards (C-c s)
;; - Flyspell & spelling (C-c F)
;; - Grammar checking (C-c G)
;; - Org-transclusion (C-c T)
;; - Bookmarks (C-c B)
;;
;;; Code:

(require 'transient)

;; ============================================================
;; MASTER HELP MENU - Central hub for all menus + cheatsheet
;; ============================================================

(transient-define-prefix my/help-master-menu ()
  "Master menu - all system functions and menus"
  [:description
   (lambda ()
     (concat
      (propertize "📘 PKM SYSTEM GUIDE\n" 'face 'bold)
      (propertize "════════════════════════════════════════\n\n" 'face 'shadow)
      (propertize "MAIN MENUS:\n" 'face 'warning)
      "  C-c n → Notes (denote, journal, zettel)\n"
      "  C-c p → Projects (agenda, kanban, time)\n"
      "  C-c w → Well-being tracking\n"
      "  C-c s → Statistics & dashboards\n"
      "  C-c W → Windows (navigate, swap, layout)\n"
      "  C-c h → This help menu\n\n"
      (propertize "QUICK ACCESS:\n" 'face 'warning)
      "  C-c f → Spelling (Flyspell)\n"
      "  C-c g → Grammar (LanguageTool)\n"
      "  C-c t → Transclusion (embed)\n"
      "  C-c b → Bookmarks\n"
      "  C-c a → Agenda\n\n"
      (propertize "QUICK SHORTCUTS:\n" 'face 'warning)
      "  C-s-<arrow>  → Swap windows\n"                   ; ← NEW!
      "  C-S-<arrow>  → Navigate windows\n"               ; ← NEW!
      "  C-c <left>   → Undo layout (winner-mode)\n\n"    ; ← NEW!
      (propertize "Press key to open submenu or scroll for reference\n" 'face 'shadow)))
   
   ["Main Menus"
    ("n" "Notes" my/notes-transient-menu)
    ("p" "Projects" my/project-transient-menu)
    ("w" "Well-being" my/wellbeing-transient-menu)
    ("s" "Statistics" my/statistics-transient-menu)
    ("W" "Windows" my/window-transient-menu)
    ("q" "Quote from selection" my/insert-quote-block)
    ("Q" "Smart quote (clipboard)" my/smart-quote-from-clipboard)]
   
   ["Quick Tools"
    ("F" "Spelling" my/spelling-transient-menu)
    ("G" "Grammar" my/grammar-transient-menu)
    ("T" "Transclusion" my/transclusion-transient-menu)
    ("B" "Bookmarks" my/bookmarks-transient-menu)]]
  
  ["Org-mode Reference"
   ["Structure"
    ("*" "New heading" org-insert-heading)
    ("TAB" "Fold/unfold" org-cycle)
    ("S-TAB" "Global fold" org-global-cycle)]
   
   ["Editing"
    ("M-RET" "New item" org-meta-return)
    ("M-↑" "Move up" org-metaup)
    ("M-↓" "Move down" org-metadown)]
   
   ["Links"
    ("l" "Insert link" org-insert-link)
    ("L" "Store link" org-store-link)
    ("o" "Open link" org-open-at-point)]]
  
  ["Denote Quick Ref"
   ["Create"
    ("N" "New note" denote)
    ("J" "Journal" my/denote-journal)
    ("Z" "Zettel" my/denote-zettel)]
   
   ["Search"
    ("F" "Find" consult-denote-find)
    ("G" "Grep" consult-denote-grep)]
   
   ["Link"
    ("i" "Insert link" denote-link)
    ("B" "Backlinks" denote-backlinks)]]
  
  ["Emacs Essentials"
   ["Files"
    ("C-x C-f" "Find file" find-file)
    ("C-x C-s" "Save" save-buffer)
    ("C-x b" "Switch buf" switch-to-buffer)]
   
   ["Search"
    ("C-s" "Search fwd" isearch-forward)
    ("C-r" "Search back" isearch-backward)
    ("M-%" "Replace" query-replace)]
   
   ["Help System"
    ("h f" "Describe func" describe-function)
    ("h v" "Describe var" describe-variable)
    ("h k" "Describe key" describe-key)]]
  
  [["Exit"
    ("q" "Quit" transient-quit-one)
    ("?" "Help system" describe-mode)]])

;; ============================================================
;; WELL-BEING TRACKING MENU
;; ============================================================

(transient-define-prefix my/wellbeing-transient-menu ()
  "Well-being tracking and visualization."
  ["Well-being Tracking"
   ("e" "Add entry (1-10)" my/denote-wellbeing-entry)
   ("s" "Statistics" my/denote-wellbeing-stats)
   ("j" "Filter journal" my/denote-wellbeing-journal)]
  ["Navigation"
   ("q" "Quit" transient-quit-one)
   ("?" "Help" describe-mode)])

;; ============================================================
;; STATISTICS & DASHBOARDS MENU
;; ============================================================

(transient-define-prefix my/statistics-transient-menu ()
  "Writing statistics and dashboards"
  ["Statistics & Dashboards"
   ["Word Count"
    ("s" "Today" my/denote-count-words-today)
    ("S" "All notes" my/denote-count-words-all)
    ("w" "Current buffer" count-words)]
   
   ["Dashboards"
    ("d" "Main dashboard" my/denote-dashboard)
    ("c" "Cockpit" my/denote-cockpit)
    ("D" "Refresh" dashboard-refresh-buffer)]
   
   ["Projects"
    ("p" "Project stats" my/denote-project-stats)
    ("P" "Project goal" my/denote-project-goal)
    ("m" "Projects menu" my/denote-projects-menu)]
   
   ["Goals"
    ("g" "Set goal" my/denote-writing-goal)
    ("G" "Check progress" (lambda () (interactive)
                            (message "Progress: %d words today"
                                   (my/denote-count-words-today))))]]
  
  [["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]])

;; ============================================================
;; SPELLING (FLYSPELL) MENU
;; ============================================================

(transient-define-prefix my/spelling-transient-menu ()
  "Flyspell spell checking"
  ["Flyspell Spelling"
   ["Navigate Errors"
    ("n" "Next error" flyspell-goto-next-error)
    ("p" "Previous error" my/flyspell-goto-previous-error)
    ("b" "Check buffer" flyspell-buffer)]
   
   ["Correct"
    ("c" "Correct word" flyspell-correct-wrapper)
    ("a" "Add to dict" my/spell-add-word-here)
    ("i" "Auto-correct" flyspell-auto-correct-word)]
   
   ["Mode"
    ("m" "Toggle mode" flyspell-mode)
    ("M" "Prog mode" flyspell-prog-mode)]]
  
  [["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]])

;; ============================================================
;; GRAMMAR (LANGUAGETOOL) MENU
;; ============================================================

(transient-define-prefix my/grammar-transient-menu ()
  "LanguageTool grammar checking"
  ["LanguageTool Grammar"
   ["Check"
    ("c" "Check buffer" langtool-check)
    ("d" "Done (clear)" langtool-check-done)
    ("s" "Show error" langtool-show-message-at-point)]
   
   ["Navigate"
    ("n" "Next error" langtool-goto-next-error)
    ("p" "Previous error" langtool-goto-previous-error)]
   
   ["Fix"
    ("f" "Fix buffer" langtool-correct-buffer)
    ("F" "Fix at point" langtool-correct-at-point)]]
  
  [["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]])

;; ============================================================
;; ORG-TRANSCLUSION MENU
;; ============================================================

(transient-define-prefix my/transclusion-transient-menu ()
  "Org-transclusion embedding"
  ["Org-transclusion"
   ["Add/Remove"
    ("a" "Add at point" org-transclusion-add)
    ("A" "Add all" org-transclusion-add-all)
    ("r" "Remove" org-transclusion-remove)
    ("R" "Remove all" org-transclusion-remove-all)]
   
   ["Mode & Edit"
    ("t" "Toggle mode" org-transclusion-mode)
    ("m" "Make from link" org-transclusion-make-from-link)
    ("o" "Open source" org-transclusion-open-source)]
   
   ["Refresh"
    ("g" "Refresh" org-transclusion-refresh)
    ("G" "Live edit" org-transclusion-live-sync-start)]]
  
  [["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]])

;; ============================================================
;; BOOKMARKS MENU
;; ============================================================

(transient-define-prefix my/bookmarks-transient-menu ()
  "Emacs bookmarks management"
  ["Bookmarks"
   ["Create & Jump"
    ("m" "Set bookmark" bookmark-set)
    ("j" "Jump to" bookmark-jump)
    ("J" "Jump other window" bookmark-jump-other-window)]
   
   ["Manage"
    ("l" "List all" bookmark-bmenu-list)
    ("d" "Delete" bookmark-delete)
    ("r" "Rename" bookmark-rename)]
   
   ["Save"
    ("s" "Save bookmarks" bookmark-save)
    ("L" "Load file" bookmark-load)]]
  
  [["Navigation"
    ("q" "Quit" transient-quit-one)
    ("?" "Help" describe-mode)]])

;; ============================================================
;; WINDOW MANAGEMENT MENU
;; ============================================================

(transient-define-prefix my/window-transient-menu ()
  "Advanced window management - navigate, swap, resize, layout."
  :transient-suffix 'transient--do-stay
  :transient-non-suffix 'transient--do-warn
  
  ["Navigate Windows"
   :class transient-row
   ("h" "← Left" windmove-left :transient t)
   ("j" "↓ Down" windmove-down :transient t)
   ("k" "↑ Up" windmove-up :transient t)
   ("l" "→ Right" windmove-right :transient t)]
  
  ["Swap Windows"
   :class transient-row
   ("H" "⇄ Swap left" windmove-swap-states-left :transient t)
   ("J" "⇅ Swap down" windmove-swap-states-down :transient t)
   ("K" "⇅ Swap up" windmove-swap-states-up :transient t)
   ("L" "⇄ Swap right" windmove-swap-states-right :transient t)]
  
  ["Split & Delete"
   ("2" "Split horizontal" split-window-below :transient t)
   ("3" "Split vertical" split-window-right :transient t)
   ("0" "Delete this window" delete-window :transient t)
   ("1" "Delete other windows" delete-other-windows :transient t)]
  
  ["Layout"
   ("u" "Undo layout" winner-undo :transient t)
   ("r" "Redo layout" winner-redo :transient t)
   ("b" "Balance windows" balance-windows :transient t)
   ("=" "Balance windows" balance-windows :transient t)]
  
  ["Resize"
   ("{" "Shrink horizontal" shrink-window-horizontally :transient t)
   ("}" "Enlarge horizontal" enlarge-window-horizontally :transient t)
   ("[" "Shrink vertical" shrink-window :transient t)
   ("]" "Enlarge vertical" enlarge-window :transient t)]
  
  ["Navigation"
   ("q" "Quit" transient-quit-one)
   ("?" "Help" describe-mode)])

(provide '14-transient-menus)
;;; 14-transient-menus.el ends here
