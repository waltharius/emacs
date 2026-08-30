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
;; CUSTOM FILE: Load early so face definitions are set before
;; any package loads org (prevents nil :foreground warnings)
;; ============================================================

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

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

(let ((modules-dir (expand-file-name "modules/" user-emacs-directory)))
  (load (concat modules-dir "00-core.el"))          ; Package system + variables
  (load (concat modules-dir "01-ui.el"))            ; Interface + sessions
  (load (concat modules-dir "02-editing.el"))       ; Modern conveniences
  (load (concat modules-dir "02b-bold-marker.el"))  ; Obsidian-style bold (word*)
  (load (concat modules-dir "03-spelling.el"))      ; Spellcheck (WORKING!)
  (load (concat modules-dir "03b-fonts.el"))        ; Fonts (PlaypenSans for journals)
  (load (concat modules-dir "04-denote.el"))        ; Denote multi-silo
  (load (concat modules-dir "05-notes.el"))         ; Note functions
  ;; Optional module: the second argument to `load' is NOERROR, so
  ;; deleting this file degrades to "no metrics commands, no menu
  ;; entries" instead of aborting init.el partway through.
  (load (concat modules-dir "05b-journal-metrics.el") t) ; Journal metrics (C-c n c w / W)
  (load (concat modules-dir "06-capture.el"))       ; Org-capture (SMART DATE!)
  (load (concat modules-dir "07-git.el"))           ; Git auto-commit
  (load (concat modules-dir "08-keybindings.el"))   ; Keybindings
  (load (concat modules-dir "09-theme.el"))         ; Theme (light)
  (load (concat modules-dir "10-visual-fill.el"))   ; Centered text
  (load (concat modules-dir "11-org-appearance.el")) ; Org visual enhancements
  (load (concat modules-dir "12-transient.el"))     ; Transient menu (C-c n)
  (load (concat modules-dir "13-centered-writing.el")) ; Writeroom mode (C-c n W)
  (load (concat modules-dir "14-typing-analytics.el")) ; Typing statistics (keyfreq + keylog)
  (load (concat modules-dir "15-workspace.el"))     ; Obsidian-like panels (EXPERIMENTAL)
  (load (concat modules-dir "16-org-export.el"))
  (load (concat modules-dir "17-bibliography.el"))  ; Citar + org-noter + pdf-tools
  (load (concat modules-dir "18-zotero-transient.el")) ; Zotero transient menu
  (load (concat modules-dir "19-philosophy-notes.el")) ; Philosophy note types (C-c n l)
  (load (concat modules-dir "20-transclusion.el")) ;; transclusion for note linking inside other notes
  (load (concat modules-dir "21-dashboards.el"))   ; Historical dashboards (C-c n f h)
  (load (concat modules-dir "22-zettelkasten.el")) ; Folgezettel sequences (C-c n z)
  (load (concat modules-dir "23-fixed-tabs.el"))   ; Route commands to named tabs
  (load (concat modules-dir "24-readwise.el"))     ; Readwise import (C-c r s)
  ;; This block is in dependency order rather than numeric order.
  ;; 27-denote-identifiers.el owns the identifier helpers; 25 loads them
  ;; by path when they are missing, which used to make this file load 27
  ;; a second time, and 26 calls them too.  Loading 27 first makes that
  ;; fallback dormant, which is what it is for.
  (load (concat modules-dir "27-denote-identifiers.el")) ; Identifier integrity after md files moved to org format
  (load (concat modules-dir "25-inbox-review.el")) ; Inbox review for old notes from Obsidian
  (load (concat modules-dir "26-maintenance.el")) ; Integrity checks and repairs (C-c n !)
  (load (concat modules-dir "28-writing-projects.el")) ; Writing projects (C-c n p)
  (load (concat modules-dir "29-writing-export.el")) ; ODT/DOCX export via ox-odt + LibreOffice
  (load (concat modules-dir "30-link-tooltips.el")) ; Cheap mouse tooltips over denote: links
  (load (concat modules-dir "31-org-images.el")) ; Image attachments (C-c n i i)
  (load (concat modules-dir "32-web-links.el")) ; insert web link (C-c n i u)
  (load (concat modules-dir "33-denote-hubs.el")) ; Hub notes (C-c n i H)
  ;; Loaded last, and optional (NOERROR).  It appends to the View menu
  ;; from 12-transient.el and defines the faces that 15-workspace.el
  ;; references, both of which degrade rather than fail when absent:
  ;; a missing face renders as `default', and `my/transient-append'
  ;; skips a menu whose anchor it cannot find.
  (load (concat modules-dir "34-appearance.el") t) ; Padding, faces, pulse (C-c u)
  ;; Optional (NOERROR): reports days missing from the journal series.
  ;; Degrades on its own if 05b-journal-metrics.el or 21-dashboards.el
  ;; are absent -- see the header of the module.
  (load (concat modules-dir "35-journal-gaps.el") t) ; Journal gaps (C-c n f j)
  ;; Optional (NOERROR): summary statistics for the collection.  Reads
  ;; helpers from 26 and 27 and signals a readable error if either is
  ;; missing, rather than measuring nothing and reporting zero.
  (load (concat modules-dir "36-notes-stats.el") t) ; Statistics (C-c n f s)
  ;; Optional (NOERROR): task capture, project routing, agenda files.
  ;; Loaded after 28-writing-projects.el on purpose: it takes over
  ;; `org-agenda-files' from that module, and taking over requires
  ;; having the last word.  Without 28 it still works and the agenda
  ;; holds this module's own files only.
  (load (concat modules-dir "37-tasks.el") t) ; Tasks & agenda (f8, C-c n A)
  )

(add-hook 'emacs-startup-hook
          (lambda ()
            (message "TOTAL startup: %.3f seconds"
                     (float-time (time-subtract (current-time)
                                                before-init-time)))))

(provide 'init)
;;; init.el ends here
