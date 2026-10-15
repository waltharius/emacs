;;; 18-zotero-transient.el --- Transient menu for bibliography/Zotero -*- lexical-binding: t; -*-

;; MyPKS-Requires: 17-bibliography
;; MyPKS-Optional: yes
;; Docs: ~/.emacs.d/function_helper.org::#menu-zotero-detail

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
;;   c — check notes for citation keys missing from the bibliography
;;   C — rename a citation key across the notes
;;   ? — report whether CSL export is configured correctly
;;   , — settings: the .bib file, Zotero's folder, CSL styles
;;
;; This module is the menu for 17-bibliography.el and depends on it:
;; every command below comes from there or from citar, which that file
;; configures.  The dependency runs one way only -- 17 knows nothing
;; about this file -- so the functionality works without the menu, but
;; not the other way round.

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

  ["Maintenance"
   [("c" "Check keys in notes"            my/cite-check-keys)
    ("C" "Rename a citation key"          my/cite-rename-key)
    ("?" "Check CSL export setup"         my/csl-check-setup)
    ("," "Settings: .bib file, Zotero, CSL" my/bibliography-settings)]]

  [("q" "Quit" transient-quit-one)])

(global-set-key (kbd "C-c x") 'my/zotero-menu)

;; Inserted into the Integrations column of the Tools menu (C-c n t z)
;; rather than declared in 12-transient.el, so that turning this module
;; off takes the entry with it and leaves the menu whole.
(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-insert)
    (my/transient-insert 'my/notes-tools-menu "q"
                         '("z" "Zotero / Bib →" my/zotero-menu))))

(provide '18-zotero-transient)
;;; 18-zotero-transient.el ends here
