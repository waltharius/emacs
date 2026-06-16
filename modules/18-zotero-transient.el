;;; 18-zotero-transient.el --- Transient menu for bibliography/Zotero -*- lexical-binding: t; -*-
;;; Commentary:
;; Minimal transient menu for bibliographic note workflow.
;;
;; Keybindings:
;;   n — create new note from a Zotero reference (PDF opens on the right automatically)
;;   o — open an existing bibliographic note
;;   f — reopen PDF on the right for the note you are currently editing
;;   e — open the BibTeX entry in refs.bib
;;   u — open URL or DOI in browser
;;   i — insert an in-text citation [cite:@key]
;;   R — insert full bibliography at point
;;   S — insert short reference (Author, Title, Year) at point

;;; Code:

(require 'transient)

(transient-define-prefix my/zotero-menu ()
  "Bibliography & reading (C-c x)"

  ["Notes"
   [("n" "New note from reference"        citar-create-note)
    ("o" "Open existing bib note"         citar-denote-open-note)]]

  ["Open"
   [("f" "Open PDF for this note"         my/open-bib-pdf-right)
    ("e" "Open BibTeX entry"              citar-open-entry)
    ("u" "Open URL / DOI"                 citar-open-links)
    ("i" "Insert citation [cite:@key]"    citar-insert-citation)]]

  ["Insert reference at point"
   [("R" "Full bibliography"              my/insert-full-reference)
    ("S" "Short: Author, Title (Year)"    my/insert-short-reference)]]

  [("q" "Quit" transient-quit-one)])

(global-set-key (kbd "C-c x") 'my/zotero-menu)

(provide '18-zotero-transient)
;;; 18-zotero-transient.el ends here
