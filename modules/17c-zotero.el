;;; 17c-zotero.el --- Zotero's attachments folder for citar -*- lexical-binding: t; -*-

;; MyPKS-Requires: 17-bibliography
;; MyPKS-Optional: yes
;; MyPKS-Default: off
;; Docs: ~/.emacs.d/function_helper.org::#zotero-attachments

;;; Commentary:

;; What only Zotero gives the bibliography: the folder where it stores
;; the PDFs and other files of its items.  citar looks there for the
;; file of a reference (C-c x f), beside the file field of the .bib
;; entry, which Better BibTeX can export too.  Everything else of
;; citing works with a .bib from any program and is 17-bibliography.el
;; (split on 2026-10-25zg, as decided on the module map).
;;
;; Off on a new machine, as the modules that need another program are
;; (00-core.el, MODULES A NEW MACHINE STARTS WITHOUT); C-c n , m turns
;; it on.  The option keeps its name, `my/zotero-storage-directory', so
;; a folder saved before the split is still read.

;;; Code:

(defvar citar-library-paths)

(defun my/zotero-apply ()
  "Point citar at Zotero's attachments folder, once citar is loaded."
  (with-eval-after-load 'citar
    (setq citar-library-paths
          (and my/zotero-storage-directory
               (list (expand-file-name my/zotero-storage-directory))))))

(defcustom my/zotero-storage-directory "~/Zotero/storage/"
  "Folder holding the PDFs and other attachments Zotero stores.
The default is where Zotero keeps them unless told otherwise.  Where
citar looks for the file of a reference (`C-c x f'), beside the file
field of its .bib entry.  Nil for none.  Takes effect at once."
  :type '(choice (directory :tag "Folder") (const :tag "None" nil))
  :tag "Zotero attachments folder (PDFs)"
  :set (my/settings-apply-on-set #'my/zotero-apply)
  :group 'my/bibliography)

(my/zotero-apply)

(provide '17c-zotero)
;;; 17c-zotero.el ends here
