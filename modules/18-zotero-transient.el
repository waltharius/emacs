;;; 18-zotero-transient.el --- Transient menu for bibliography/Zotero -*- lexical-binding: t; -*-
;;; Commentary:
;; Standalone transient menu for all citation and bibliography operations.
;; Available as:
;;   C-c x         — direct access
;;   C-c n u       — from main notes menu (same menu object, different entry point)

;;; Code:

(require 'transient)

;; ============================================================
;; ZOTERO / BIBLIOGRAPHY TRANSIENT MENU
;; ============================================================

(transient-define-prefix my/zotero-menu ()
  "Bibliography, citations, and Zotero integration."

  ["Citations — Insert & Open"
   [("i" "Insert citation [cite:@key]"  citar-insert-citation)
    ("o" "Open entry in .bib"           citar-open-entry)
    ("f" "Open PDF/ePub attachment"     citar-open)
    ("u" "Open URL or DOI"              citar-open-links)]]

  ["Denote Notes — Bibliographic"
   [("n" "Master book create note"    citar-create-note)
    ("N" "Open/create note (dwim)"    citar-denote-dwim)
    ("R" "Open note for ref"          citar-denote-open-note)
    ("A" "Add reference to note"      citar-denote-add-reference)
    ("D" "Remove reference from note" citar-denote-remove-reference)
    ("c" "Find citation in notes"     citar-denote-find-citation)
    ("F" "Find notes citing this ref" citar-denote-find-reference)
    ("u" "Uncited entries"            citar-denote-nocite)
    ("b" "Dead citekeys check"        citar-denote-nobib)]]

  ["Citar"
   [("o" "Open ref (files/notes/links)" citar-open)
    ("e" "Open BibTeX entry"            citar-open-entry)
    ("p" "Open PDF/file"                citar-open-files)
    ("l" "Open DOI/URL"                 citar-open-links)
    ("r" "Copy reference"               citar-copy-reference)]]
  
  ["PDF Reading — org-noter"
   [("p" "Start org-noter session"      org-noter)
    ("I" "Insert precise note (in noter)" org-noter-insert-precise-note :transient t)
    ("s" "Sync scroll position"         org-noter-sync-current-note :transient t)]]

  [("q" "Quit"  transient-quit-one)])

;; ============================================================
;; KEYBINDINGS
;; ============================================================

;; Standalone: C-c x
(global-set-key (kbd "C-c x") 'my/zotero-menu)

(provide '18-zotero-transient)
;;; 18-zotero-transient.el ends here
