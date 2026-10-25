;;; 117b-document-viewers.el --- PDF and EPUB viewers: pdf-tools and nov -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; Docs: ~/.emacs.d/function_helper.org::#document-viewers

;;; Commentary:

;; Viewers for documents Emacs itself reads poorly: PDF through
;; pdf-tools, EPUB through nov.  Part of how Emacs works, whatever the
;; notes (group 100 of MODULES.org); split from 417-bibliography.el on
;; 2026-10-25zd, where they had been because the PDFs of the
;; bibliography are the ones most often opened.
;;
;; Nothing else needs this module.  Without it a PDF opens in Emacs's
;; own DocView (pages as images, through Ghostscript) and an EPUB as an
;; archive; citar still inserts keys, makes notes and opens the
;; attachment of a reference, in whatever mode Emacs has for it.
;;
;; Prerequisites for pdf-tools (already satisfied in packages.nix):
;; poppler, poppler_utils, pkg-config, libpng -- its server, epdfinfo,
;; is built from source the first time a PDF is opened, after a
;; question.

;;; Code:

(require 'cl-lib)

;; ============================================================
;; PDF-TOOLS -- native PDF viewer
;; ============================================================

;; `pdf-loader-install', pdf-tools' own on-demand setup, not
;; `pdf-tools-install' in :config: that ran whenever pdf-tools was
;; loaded -- also by the byte compilation of its own files during the
;; first install -- and built the epdfinfo server then, unasked (the
;; build may ask for the sudo password to install libraries).  Now
;; the first PDF opened loads pdf-tools, which asks before building.

(defun my/document-viewers--pdf-on-demand ()
  "Set PDF Tools up to load, and build its server, with the first PDF.
`pdf-loader-install' sets pdf-tools up at once when pdf-tools is loaded
already -- as it is in the session that installed it, by the byte
compilation of its own files -- and so asks about building the server
in the middle of the first start (and fails in batch, where nobody can
answer).  Told that pdf-tools is not loaded, it waits for a PDF, as in
every later session."
  ;; Loaded first, outside the binding below: a `provide' inside it
  ;; would be undone when the binding ends.
  (when (require 'pdf-loader nil t)
    ;; `cl-progv' binds `features' dynamically.  It has no `defvar' in
    ;; Lisp, so a plain `let' in this lexically bound file would bind a
    ;; local name `featurep' never reads; `dlet' would, but makes the
    ;; compiler ask for a prefix on a name that is Emacs's own.
    (cl-progv '(features) (list (remq 'pdf-tools features))
      (pdf-loader-install))))

(use-package pdf-tools
  :ensure t
  :defer t
  :init
  (my/document-viewers--pdf-on-demand)
  :config
  (add-hook 'pdf-view-mode-hook
            (lambda () (display-line-numbers-mode -1))))

;; ============================================================
;; NOV -- EPUB reader
;; ============================================================

(use-package nov
  :ensure t
  :mode ("\\.epub\\'" . nov-mode))

(provide '117b-document-viewers)
;;; 117b-document-viewers.el ends here
