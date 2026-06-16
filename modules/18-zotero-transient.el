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
   [("n" "Open/create note for ref"     citar-denote-dwim)
    ("N" "Open note for ref"            citar-denote-open-note)
    ("R" "Refs not in any note"         citar-denote-nocite)
    ("b" "Keys cited here, not in bib"  citar-denote-nobib)
    ("r" "Find note by reference"       citar-denote-find-reference)]]

  ["PDF Reading — org-noter"
   [("p" "Start org-noter session"      org-noter)
    ("I" "Insert precise note (in noter)" org-noter-insert-precise-note :transient t)
    ("s" "Sync scroll position"         org-noter-sync-current-note :transient t)]]

  ["Bibliography File"
   [("e" "Open refs.bib directly"
     (lambda () (interactive)
       (find-file "~/notes/refs.bib")))
    ("R" "Refresh citar cache"          citar-refresh)]]

  [("q" "Quit"  transient-quit-one)])

;; ============================================================
;; KEYBINDINGS
;; ============================================================

;; Standalone: C-c x
(global-set-key (kbd "C-c x") 'my/zotero-menu)

(provide '18-zotero-transient)
;;; 18-zotero-transient.el ends here
