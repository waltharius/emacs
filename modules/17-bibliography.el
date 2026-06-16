;;; 17-bibliography.el --- Zotero/Citar bibliography integration -*- lexical-binding: t; -*-
;;; Commentary:
;; Citation and bibliography management via Citar + Zotero Better BibTeX.
;;
;; Prerequisites (already satisfied in packages.nix):
;;   - ~/notes/refs.bib   — auto-exported by Better BibTeX in Zotero
;;   - poppler, poppler_utils, pkg-config, libpng in home.packages (for pdf-tools)
;;
;; Workflow:
;;   1. M-x my/zotero-menu (C-c x) → n  — create note from Zotero ref, PDF opens on the right
;;   2. M-x my/zotero-menu (C-c x) → f  — reopen PDF on the right for the current note

;;; Code:

;; ============================================================
;; CITAR — citation search and insertion
;; ============================================================

(use-package citar
  :ensure t
  :custom
  (citar-bibliography '("~/notes/refs.bib"))
  (citar-library-paths '("~/syncthing/Zotero/storage/"))
  (citar-notes-paths (list (expand-file-name "pks/" my-notes-dir)))
  :config
  (setq org-cite-global-bibliography '("~/notes/refs.bib"))
  (setq org-cite-insert-processor 'citar)
  (setq org-cite-follow-processor 'citar)
  (setq org-cite-activate-processor 'citar))

;; ============================================================
;; DENOTE TEMPLATE: Bibliographic note front matter
;; ============================================================
;; Note: #+reference is added automatically by citar-denote — do not duplicate it here.
;; Fields that do not expand (origdate, pagetotal) are omitted — add manually if needed.

(with-eval-after-load 'denote
  (add-to-list 'denote-templates
               '(biblio . "#+entry-type:  %^{=type=}
#+authors:     %^{author}
#+translator:  %^{translator}
#+publisher:   %^{publisher}
#+year:        %^{year}
#+language:    %^{langid}

")))

;; ============================================================
;; CITAR-DENOTE — bridge citar into Denote
;; ============================================================

(use-package citar-denote
  :ensure t
  :after (citar denote)
  :custom
  (citar-denote-subdir "pks/")
  (citar-denote-use-bib-keywords t)
  (citar-denote-title-format "author-year-title")
  (citar-denote-title-format-authors 1)
  (citar-denote-template 'biblio)
  :config
  (citar-denote-mode 1))

;; ============================================================
;; HELPER: Reopen PDF for current bibliographic note on the right
;; ============================================================
;; Use this when you return to a note whose PDF is closed.
;; Splits the window vertically and opens the PDF on the right,
;; mimicking the behaviour of citar-create-note on first creation.

(defun my/open-bib-pdf-right ()
  "Open PDF for the current bibliographic note in a right window split."
  (interactive)
  (if-let* ((file (buffer-file-name))
             (keys (citar-denote--retrieve-references file))
             (key (car keys)))
      (progn
        (when (one-window-p) (split-window-right))
        (other-window 1)
        (citar-open-files key))
    (message "No #+reference found in this note")))

;; ============================================================
;; PDF-TOOLS — native PDF viewer
;; ============================================================

(use-package pdf-tools
  :ensure t
  :magic ("%PDF" . pdf-view-mode)
  :config
  (pdf-tools-install :no-query)
  (add-hook 'pdf-view-mode-hook
            (lambda () (display-line-numbers-mode -1))))

;; ============================================================
;; NOV — ePub reader
;; ============================================================

(use-package nov
  :ensure t
  :mode ("\\.epub\\'" . nov-mode))

(provide '17-bibliography)
;;; 17-bibliography.el ends here
