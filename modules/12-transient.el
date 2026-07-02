;;; 12-transient.el --- Transient menu for notes (hierarchical) -*- lexical-binding: t; -*-
;;; Commentary:
;; Unified transient menu for all note-related operations.
;; Accessed with C-c n — hierarchical structure with sub-menus:
;;
;;   C-c n c  — Create / Capture
;;   C-c n f  — Find (search & navigation)
;;   C-c n i  — Insert (links, time, date, well-being)
;;   C-c n d  — Document / File management
;;   C-c n x  — eXport
;;   C-c n v  — View
;;   C-c n t  — Tools (Zotero/Bib, spelling, future integrations)
;;   C-c n l  — Philosophy (appended dynamically by 19-philosophy-notes.el)
;;   C-c n h  — Function Help (opens function_helper.org)
;;
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-main

;;; Code:

(require 'transient)

;; ============================================================
;; SUB-MENU: Create / Capture  (C-c n c)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-create
;; ============================================================

(transient-define-prefix my/notes-create-menu ()
  "Create notes and run captures."
  [["Create"
    ("n" "New note"       my/denote-base)
    ("j" "Journal today"  my/denote-journal)
    ("J" "Journal date"   my/denote-journal-date)
    ("e" "Essay"          my/denote-essay)
    ("L" "Linked note"    my/denote-linked-note)]
   ["Capture"
    ("i" "Ideas capture"   my/capture-idea)
    ("c" "Capture menu"    org-capture)
    ("m" "Promote to note" my/capture-promote-to-note)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Find / Search  (C-c n f)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-find
;; ============================================================

(transient-define-prefix my/notes-find-menu ()
  "Search and navigate notes."
  [["Find"
    ("f" "Find file"    denote-open-or-create)
    ("g" "Grep notes"   consult-denote-grep)
    ("b" "Backlinks"    denote-backlinks)]
   ["Overview"
    ("d" "Dashboard"    my/open-notes-dashboard)
    ("t" "Tag stats"    my/notes-explore)
    ("r" "Random note"  denote-explore-random-note)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Insert  (C-c n i)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-insert
;; ============================================================

(transient-define-prefix my/notes-insert-menu ()
  "Insert links, dates, and content."
  [["Link"
    ("l" "Insert link"  denote-link)
    ("L" "Linked note"  my/denote-linked-note)]
   ["Date & Time"
    ("h" "Time (HH:MM)"      insert-current-time)
    ("d" "Date (YYYY-MM-DD)" insert-current-date)]
   ["Other"
    ("w" "Well-being"  my/denote-set-wellbeing)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Document / File management  (C-c n d)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-doc
;; ============================================================

(transient-define-prefix my/notes-doc-menu ()
  "File and document management."
  [["File"
    ("r" "Rename file"    denote-rename-file)
    ("k" "Add keywords"   denote-rename-file-keywords)
    ("d" "Delete note"    my/denote-delete-note)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Export  (C-c n x)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-export
;; ============================================================

(transient-define-prefix my/notes-export-menu ()
  "Export notes to PDF."
  [["Export"
    ("p" "Export to PDF"           my/org-export-to-pdf)
    ("P" "Batch PDF — ANY keyword" my/org-export-pdf-by-keyword)
    ("Q" "Batch PDF — ALL keywords" my/org-export-pdf-by-all-keywords)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: View toggles  (C-c n v)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-view
;; ============================================================

(transient-define-prefix my/notes-view-menu ()
  "Toggle visual appearance settings."
  [["Toggle"
    ("c" "Center text"      my/toggle-visual-fill-column-center)
    ("w" "Writing mode"     my/toggle-writeroom)
    ("i" "Indent headings"  my/toggle-org-indent)
    ("e" "Emphasis markers" my/toggle-emphasis-markers)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Tools  (C-c n t)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-tools
;; ============================================================

(transient-define-prefix my/notes-tools-menu ()
  "External tools and integrations."
  [["Bibliography"
    ("z" "Zotero / Bib →" my/zotero-menu)]
   ["Spelling"
    ("s" "Correct previous"  my/spell-correct-previous  :transient t)
    ("a" "Add to dict"       my/spell-add-previous-to-dict :transient t)
    ("S" "Check visible"     my/spell-check-visible)
    ("b" "Check full buffer" my/spell-check-buffer-full)
    ("T" "Toggle spellcheck" my/toggle-flyspell)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; HELPER: Open function_helper.org in new tab
;; Docs: ~/.emacs.d/function_helper.org::#fn-open-function-helper
;; ============================================================

(defun my/open-function-helper ()
  "Open ~/.emacs.d/function_helper.org in a new tab."
  (interactive)
  (tab-bar-new-tab)
  (find-file (expand-file-name "function_helper.org" user-emacs-directory))
  (when (fboundp 'org-overview)
    (org-overview)))

;; ============================================================
;; MAIN NOTES MENU  (C-c n)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-main
;; ============================================================

(transient-define-prefix my/notes-menu ()
  "Unified menu for all note operations."
  [["Notes"
    ("c" "Create → new/journal/essay/capture"       my/notes-create-menu)
    ("f" "Find → file/grep/backlinks/random"         my/notes-find-menu)
    ("i" "Insert → transclusion/link/time/date"       my/notes-insert-menu)
    ("d" "Document → rename/keywords/delete"     my/notes-doc-menu)
    ("x" "Export → pdf/batch-any/batch-all"       my/notes-export-menu)]
   ["Settings & Tools"
    ("v" "View → center/writing/indent/emphasis"         my/notes-view-menu)
    ("t" "Tools → zotero/spelling"        my/notes-tools-menu)
    ;; "l" is reserved: 19-philosophy-notes.el appends it dynamically
    ;; Quick correct access as this is most used functions for me
    ("s" "Correct previous"  my/spell-correct-previous  :transient t)
    ("a" "Add to dict"       my/spell-add-previous-to-dict :transient t)
    ]
   [("h" "Function Help"  my/open-function-helper)
    ("q" "Quit"            transient-quit-one)]])

;; ============================================================
;; KEYBINDING
;; ============================================================

(global-set-key (kbd "C-c n") 'my/notes-menu)

(provide '12-transient)
;;; 12-transient.el ends here
