;;; 17-bibliography.el --- Zotero/Citar bibliography integration -*- lexical-binding: t; -*-
;;; Commentary:
;; Citation and bibliography management via Citar + Zotero Better BibTeX.
;;
;; Prerequisites (already satisfied in packages.nix):
;;   - ~/notes/refs.bib   — auto-exported by Better BibTeX in Zotero
;;   - poppler, poppler_utils, pkg-config, libpng in home.packages (for pdf-tools)
;;
;; Phase 1: citar + citar-denote — search and insert citations
;; Phase 2: org-cite export via biblatex
;; Phase 3: pdf-tools + org-noter — side-by-side reading and highlight extraction

;;; Code:

;; ============================================================
;; PHASE 1: CITAR — citation search and insertion
;; ============================================================

(use-package citar
  :ensure t
  :custom
  ;; Path to Better BibTeX auto-exported bibliography
  (citar-bibliography '("~/notes/refs.bib"))
  ;; Where to look for PDF/ePub attachments (Zotero storage)
  (citar-library-paths '("~/syncthing/Zotero/storage/"))
  ;; Notes live in pks/ silo
  (citar-notes-paths (list (expand-file-name "pks/" my-notes-dir)))
  :config
  ;; Tell org-cite to use citar for completion and insertion
  (setq org-cite-global-bibliography '("~/notes/refs.bib"))
  (setq org-cite-insert-processor 'citar)
  (setq org-cite-follow-processor 'citar)
  (setq org-cite-activate-processor 'citar))

;; ============================================================
;; PHASE 1: CITAR-DENOTE — bridge citar into Denote
;; ============================================================

(use-package citar-denote
  :ensure t
  :after (citar denote)
  :custom
  ;; New bibliographic notes go into pks/ silo
  (citar-denote-subdir "pks/")
  ;; Keyword automatically added to all bibliographic notes
  ;; (citar-denote-keyword "zotero")
  ;; Use org-cite [cite:@key] format (not @key alone)
  (citar-denote-use-bib-keywords t)
  ;; Better title for new notes from refs
  (citar-denote-title-format "author-year-title")
  (citar-denote-title-format-authors 1)
  :config
  (citar-denote-mode 1))

;; ============================================================
;; PHASE 3: PDF-TOOLS — native PDF viewer (replaces doc-view)
;; ============================================================
;; Requires: poppler, poppler_utils, pkg-config, libpng in NixOS packages.nix
;; First-time setup: M-x pdf-tools-install (compiles epdfinfo binary)
;; Verify prerequisites BEFORE running pdf-tools-install:
;;   $ pkg-config --exists poppler-glib && echo OK

(use-package pdf-tools
  :ensure t
  :magic ("%PDF" . pdf-view-mode)
  :config
  ;; Install silently on first load if epdfinfo is not yet compiled
  (pdf-tools-install :no-query)
  (add-hook 'pdf-view-mode-hook
          (lambda () (display-line-numbers-mode -1))))
;; ============================================================
;; PHASE 3: ORG-NOTER — side-by-side reading + annotation
;; ============================================================

(use-package org-noter
  :ensure t
  :after (org pdf-tools)
  :custom
  ;; Search for notes in the pks/ silo
  (org-noter-notes-search-path
   (list (expand-file-name "pks/" my-notes-dir)))
  ;; Do not create a single monolithic notes file — use citar-denote notes
  (org-noter-default-notes-file-names nil)
  ;; Always split window vertically (PDF left, notes right)
  (org-noter-notes-window-location 'vertical-split)
  ;; Insert precise location on every note
  (org-noter-always-create-frame nil)
  (org-noter-insert-note-no-questions t))

;; ============================================================
;; PHASE 3: ORG-PDFTOOLS — richer annotation + highlight extraction
;; ============================================================

(use-package org-pdftools
  :ensure t
  :after (pdf-tools org-noter)
  :hook (org-mode . org-pdftools-setup-link))

(use-package org-noter-pdftools
  :ensure t
  :after (org-noter org-pdftools))

;; ============================================================
;; PHASE 3: NOV — ePub reader (for ePub annotations via org-noter)
;; ============================================================

(use-package nov
  :ensure t
  :mode ("\\.epub\\'" . nov-mode))

(provide '17-bibliography)
;;; 17-bibliography.el ends here
