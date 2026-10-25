;;; init.el --- Clean Emacs configuration (Refactor 2026-01) -*- lexical-binding: t; -*-
;;; Commentary:
;; Minimal configuration - only essential features
;; Built from scratch, tested incrementally

;;; Code:
(setq use-package-compute-statistics t)
;; ============================================================
;; PERFORMANCE: Startup optimization
;; ============================================================

(setq gc-cons-threshold most-positive-fixnum)

;; Steady-state collector threshold, restored once startup is over.
;;
;; NOTE ON THE VALUE: 26-performance.el used to set this to 64 MB on the
;; grounds that inline images raise the allocation rate.  That setting
;; never took effect -- modules load from this file's body, so
;; `after-init-hook' ran afterwards and put the value back to 16 MB.
;; Emacs has therefore been running at 16 MB all along, apparently
;; without trouble.  The value is left where it demonstrably works;
;; raising it is an experiment to run deliberately and measure, not a
;; side effect of moving a setting between files.
(add-hook 'after-init-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024))
            (message "✨ Emacs ready (Main)!")))

;; ============================================================
;; CUSTOM FILE: one per machine, hosts/<host>/custom.el
;; ============================================================
;; Set and loaded at the top of modules/00-core.el, before any option
;; is defined and before any package loads Org (which is what loading
;; it early here was for).  See "Settings of this machine" there.

;; ============================================================
;; WINDOW TITLE: Identify this is window
;; ============================================================

(setq frame-title-format
      '("Emacs [My note system] - "
        (:eval (if (buffer-file-name)
                   (file-name-nondirectory (buffer-file-name))
                 "%b"))))

;; ============================================================
;; LOAD MODULES (in correct order)
;; ============================================================
;; 00-core.el first, by path: it reads this machine's settings and
;; defines the loader.  Every other module is named once below, in load
;; order, and `my/modules-load' (00-core.el) loads it -- or leaves it
;; out when its header says it is optional and this machine has it in
;; `my/modules-off' (C-c n , m), or when a module it needs was not
;; loaded.  An error inside an optional module is reported after
;; start-up instead of stopping it; a core module still stops it.
;; Which modules are optional, and what each needs, is in each file's
;; header (MyPKS-Optional, MyPKS-Requires), not here.

(load (expand-file-name "modules/00-core.el" user-emacs-directory)) ; Package system + variables

(my/modules-load
 '(
   "01-ui"                   ; Sessions, windows, completion, mode line
   "01b-frame-bars"        ; Tool bar and scroll bar off (optional)
   "02-editing"              ; Modern conveniences
   "02b-bold-marker"         ; Obsidian-style bold (word*)
   "03-spelling"             ; Spellcheck (WORKING!)
   "03b-fonts"               ; Fonts (PlaypenSans for journals)
   "04-denote"               ; Denote multi-silo
   "05-notes"                ; Note functions
   ;; Optional: without it there are no metrics commands and no menu
   ;; entries for them, and nothing else changes.
   "05b-journal-metrics"     ; Journal metrics (C-c n c w / W)
   "06-capture"              ; Org-capture (SMART DATE!)
   "07-git"                  ; Git auto-commit
   "08-keybindings"          ; Keybindings
   "09-theme"                ; Theme (light)
   "10-visual-fill"          ; Centered text
   "11-org-appearance"       ; Org visual enhancements
   "12-transient"            ; Transient menu (C-c n)
   "13-centered-writing"     ; Writeroom mode (C-c n W)
   "14-typing-analytics"     ; Typing statistics (keyfreq + keylog)
   "15-workspace"            ; Obsidian-like panels (EXPERIMENTAL)
   "16-org-export"
   "17-bibliography"         ; Citar, CSL, references
   "17b-document-viewers"    ; pdf-tools and nov (optional)
   "17c-zotero"              ; Zotero's attachments folder (off on a new machine)
   "19-philosophy-notes"     ; Philosophy note types (C-c n l)
   "20-transclusion"         ; transclusion for note linking inside other notes
   "21-dashboards"           ; Historical dashboards (C-c n f h)
   "22-zettelkasten"         ; Folgezettel sequences (C-c n z)
   "23-fixed-tabs"           ; Route commands to named tabs
   "24-readwise"             ; Readwise import (C-c r s)
   ;; This block is in dependency order rather than numeric order.
   ;; 27-denote-identifiers.el owns the identifier helpers; 25 loads them
   ;; by path when they are missing, which used to make this file load 27
   ;; a second time, and 26 calls them too.  Loading 27 first makes that
   ;; fallback dormant, which is what it is for.
   "27-denote-identifiers"   ; Identifier integrity after md files moved to org format
   "25-inbox-review"         ; Inbox review for old notes from Obsidian
   "26-maintenance"          ; Integrity checks and repairs (C-c n !)
   ;; Optional: renaming a keyword across the collection, K in the
   ;; repairs column of the Maintenance menu (26-maintenance.el's).
   "26b-maintenance-repairs" ; Keyword repairs (C-c n ! K)
   "28-writing-projects"     ; Writing projects (C-c n p)
   "29-writing-export"       ; ODT/DOCX export via ox-odt + LibreOffice
   "30-link-tooltips"        ; Cheap mouse tooltips over denote: links
   "31-org-images"           ; Image attachments (C-c n i i)
   "32-web-links"            ; insert web link (C-c n i u)
   "33-denote-hubs"          ; Hub notes (C-c n i H)
   ;; Loaded last, and optional.  It appends to the View menu
   ;; from 12-transient.el and defines the faces that 15-workspace.el
   ;; references, both of which degrade rather than fail when absent:
   ;; a missing face renders as `default', and `my/transient-append'
   ;; skips a menu whose anchor it cannot find.
   "34-appearance"           ; Padding, faces, pulse (C-c u)
   ;; Optional: reports days missing from the journal series.
   ;; Degrades on its own if 05b-journal-metrics.el or 21-dashboards.el
   ;; are absent -- see the header of the module.
   "35-journal-gaps"         ; Journal gaps (C-c n f j)
   ;; Optional: summary statistics for the collection.  Reads
   ;; helpers from 26 and 27 and signals a readable error if either is
   ;; missing, rather than measuring nothing and reporting zero.
   "36-notes-stats"          ; Statistics (C-c n f s)
   ;; Optional: task capture, project routing, agenda files.
   ;; Loaded after 28-writing-projects.el on purpose: it takes over
   ;; `org-agenda-files' from that module, and taking over requires
   ;; having the last word.  Without 28 it still works and the agenda
   ;; holds this module's own files only.
   "37-tasks"                ; Tasks & agenda (f8, C-c n A)
   ;; Optional: org-habit setup, fast logging, derived history.
   ;; Loaded after 37-tasks.el because it adds its file to that module's
   ;; `my/tasks-extra-agenda-files' and appends to its menu.  Without 37
   ;; the commands still work; the habit file is simply not in the
   ;; agenda, so no consistency graphs are drawn.
   "38-habits"               ; Habits (f9, C-c n H)
   ;; Optional: remotes and staleness checks for project
   ;; repositories.  Loaded after 28-writing-projects.el, whose creation
   ;; hook it uses; without that module every command reports that there
   ;; are no projects and does nothing.
   "39-project-git"          ; Project git (C-c n p G)
   ;; Optional: markdown-mode set up to match the Org notes,
   ;; and a Markdown note-creation command.  Loaded last because it only
   ;; borrows -- the per-silo typeface from 03b-fonts.el, the docu column
   ;; width from 10-visual-fill.el, two menu entries via 12-transient.el,
   ;; `my/denote-base' from 05-notes.el -- and every borrow is guarded, so
   ;; deleting the file removes Markdown support and nothing else.
   "40-markdown"             ; Markdown notes (C-c n t m)
   ;; Optional: the advanced search commands.  Loaded after
   ;; 12-transient.el because it takes over the "g" entry of the Find
   ;; menu through `my/transient-replace'; without this file that entry
   ;; keeps its original `consult-denote-grep' binding, which is the
   ;; intended degradation.
   "41-notes-search"         ; Search (C-c n f g / n)
   ;; Optional: the front end for tools/obsidian_import.py.
   ;; Loaded after 12-transient.el, whose Tools menu it appends to, and
   ;; after 00-core.el, whose `my-notes-dir' it passes to the script.
   ;; Without this file the import is still available from a shell; only
   ;; the menu entry and the buffer handling around it disappear.
   "42-obsidian-import"      ; Obsidian import (C-c n t o)
   ;; Optional: spaced repetition with org-drill.  Loaded after
   ;; 12-transient.el, whose main menu it appends to, and after
   ;; 04-denote.el, whose file-name keywords identify the card decks.
   ;; Without this file org-drill is simply not installed; nothing else
   ;; refers to it.
   "43-drill"                ; Flashcards (C-c n r)
   ;; Optional: hide or show inline images in the buffer being
   ;; written in.  Loaded after 12-transient.el, whose View menu it
   ;; appends to, and after 40-markdown.el, so that the Markdown half is
   ;; there when the command asks for it.  Without this file images are
   ;; governed by `org-startup-with-inline-images' and Org's own
   ;; C-c C-x C-v alone.
   "44-image-display"        ; Images on/off (C-c u i)
   ;; Optional: standard-page counter beside the word count.
   ;; 01-ui.el asks for it through `fboundp', so without this file the
   ;; mode line shows the word count alone, which is what it showed
   ;; before the module existed.
   "45-standard-pages"       ; Standard pages (M-x report)
   ;; Optional: selected notes published as a Hugo blog.
   ;; Loaded after 12-transient.el, whose Export menu it appends to, and
   ;; after 16-org-export.el, whose denote-link filter it switches off
   ;; for its own exports only.  Without this file nothing is published
   ;; and no other module notices.
   "46-blog"                 ; Blog (C-c n x b)
   ;; Optional: Markdown docs of the NixOS repository as a
   ;; separate Hugo site.  Loaded after 12-transient.el, whose Export
   ;; menu it appends to; depends on no other module.
   "47-repo-docs"            ; Repo docs (C-c n x r)
   ;; Optional: favourite and recently changed settings.
   ;; Loaded after 12-transient.el, whose settings menu it appends to,
   ;; and after 00-core.el, whose settings folder keeps its record.
   ;; Without this file Customize works as before.
   "48-settings-tools"       ; Settings tools (C-c n , * r z)
   ;; Optional: upgrade the installed packages after copying the
   ;; package folder, and go back to such a copy.  Loaded after
   ;; 26-maintenance.el, whose Maintenance menu it adds a column to;
   ;; without that module the commands remain for M-x.
   "49-packages"             ; Package upgrades (C-c n ! U B L)
   ;; Optional: the citation under point shown in the echo area as the
   ;; export will render it.  Needs 17-bibliography.el, whose renderer
   ;; and settings it uses; adds no key and no menu entry.
   "50-cite-preview"         ; Citation preview (echo area)
   ))

(add-hook 'emacs-startup-hook
          (lambda ()
            (message "TOTAL startup: %.3f seconds"
                     (float-time (time-subtract (current-time)
                                                before-init-time)))))

(provide 'init)
;;; init.el ends here
