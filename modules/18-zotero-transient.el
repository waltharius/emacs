;;; 18-zotero-transient.el --- Transient menu for bibliography/Zotero -*- lexical-binding: t; -*-
;;; Code:

(require 'transient)

(transient-define-prefix my/zotero-menu ()
  "Bibliography, citations, and reading."

  ["Notes"
   [("n" "New note from reference"      citar-create-note)
    ("o" "Open existing bib note"       citar-denote-open-note)
    ("a" "Add reference to note"        citar-denote-add-reference)]]

  ["Open"
   [("f" "Open PDF for this note"       citar-open-files)
    ("e" "Open BibTeX entry"            citar-open-entry)
    ("u" "Open URL / DOI"               citar-open-links)
    ("i" "Insert citation [cite:@key]"  citar-insert-citation)]]

  ["Reading (org-noter)"
   [("r" "Start reading session"        org-noter)
    ("I" "Insert note at position"      org-noter-insert-precise-note :transient t)
    ("s" "Sync scroll"                  org-noter-sync-current-note   :transient t)]]

  [("q" "Quit" transient-quit-one)])

(global-set-key (kbd "C-c x") 'my/zotero-menu)

(provide '18-zotero-transient)
;;; 18-zotero-transient.el ends here
