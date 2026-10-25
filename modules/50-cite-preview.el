;;; 50-cite-preview.el --- The citation under point shown as it will export -*- lexical-binding: t; -*-

;; MyPKS-Requires: 17-bibliography
;; MyPKS-Optional: yes
;; MyPKS-Switch: my/cite-preview-mode
;; Docs: ~/.emacs.d/function_helper.org::#cite-preview

;;; Commentary:
;; With point on a citation, [cite:@key 45], the echo area shows what
;; the export will make of it: the footnote of a note style, the
;; parenthesis of an author-date one, page and prefix included.  As an
;; office suite shows a footnote as it will print, within what a text
;; editor can know: the number of the footnote and the shortened form of
;; a repeated citation depend on the whole document and appear only in
;; the export, so the preview is always the first, full citation.
;;
;; WHY ELDOC, NOT THE CITATION REPLACED IN THE TEXT
;;
;; org-cite-csl-activate (by the author of citeproc-el) displays the
;; rendered citation in place of its text.  Its README calls it
;; experimental: deleting after a citation is confusing, filling counts
;; the hidden text, and note styles -- the default style here is one --
;; render badly.  It would also replace citar as the activation
;; processor.  ElDoc, Emacs's own channel for "what is under point",
;; leaves the text and citar alone.
;;
;; HOW
;;
;; The keys and their locators are parsed by Org's own CSL export
;; (`org-cite-csl--parse-reference', `org-cite-csl--create-structure-
;; params'), internal functions used without the export state; where
;; they are missing or fail, the keys alone are rendered.  Not
;; `org-cite-csl--create-structure': for a note style it wraps the
;; citation in a footnote, changing the parsed document.  The rendering
;; is 17-bibliography's (`my/reference-render-citation'): the style of
;; the document's #+cite_export: line or `my/csl-default-style', the
;; language of #+language:, the entries read from the bibliography
;; files once and again after a change.

;;; Code:

(require 'cl-lib)

(declare-function org-element-context "org-element")
(declare-function org-element-type "org-element")
(declare-function org-element-property "org-element")
(declare-function org-element-interpret-data "org-element")
(declare-function org-collect-keywords "org")
(declare-function org-cite-get-references "oc")
(declare-function org-cite-citation-style "oc")
(declare-function org-cite-csl--parse-reference "oc-csl")
(declare-function org-cite-csl--create-structure-params "oc-csl")
(declare-function citeproc-citation-create "ext:citeproc-cite")
(declare-function my/reference-missing "17-bibliography")
(declare-function my/reference-render-citation "17-bibliography")
(defvar my/csl-default-style)

(defgroup my/cite-preview nil
  "The citation under point shown as it will export (50-cite-preview.el)."
  :tag "Citation preview"
  :group 'mypks-writing)

(defun my/cite-preview--citation-at-point ()
  "Return the Org citation object at point, or nil."
  (let ((context (org-element-context)))
    (pcase (org-element-type context)
      ('citation context)
      ('citation-reference (org-element-property :parent context)))))

(defun my/cite-preview--style-name ()
  "Return the CSL style the export of this buffer uses.
The style of a \"#+cite_export: csl STYLE\" line, else
`my/csl-default-style' -- also when the line names another processor."
  (let* ((spec (cadar (org-collect-keywords '("CITE_EXPORT"))))
         (parts (and spec (split-string spec "[ \t]+" t))))
    (if (and (equal (car parts) "csl") (cadr parts))
        (cadr parts)
      my/csl-default-style)))

(defun my/cite-preview--keys (citation)
  "Return the keys of CITATION."
  (mapcar (lambda (reference) (org-element-property :key reference))
          (org-cite-get-references citation)))

(defun my/cite-preview--global-affixes (citation cites)
  "Return CITES with the global prefix and suffix of CITATION added.
As `org-cite-csl--create-structure' does: the prefix before the first
reference's, the suffix after the last one's, joined by a space."
  (let ((prefix (org-element-property :prefix citation))
        (suffix (org-element-property :suffix citation)))
    (when (and prefix cites)
      (let ((item (assq 'prefix (car cites))))
        (setcdr item (string-trim (concat (org-element-interpret-data prefix)
                                          " " (cdr item))))))
    (when (and suffix cites)
      (let ((item (assq 'suffix (car (last cites)))))
        (setcdr item (string-trim (concat (cdr item) " "
                                          (org-element-interpret-data suffix))))))
    cites))

(defun my/cite-preview--structure (citation)
  "Return a citeproc structure for CITATION, parsed as the export does.
Locators, prefixes, suffixes and the style variant (noauthor and the
others) by Org's CSL export; the keys alone when its internal functions
are missing or fail."
  (or (and (require 'oc-csl nil t)
           (fboundp 'org-cite-csl--parse-reference)
           (fboundp 'org-cite-csl--create-structure-params)
           (ignore-errors
             (apply #'citeproc-citation-create
                    :cites (my/cite-preview--global-affixes
                            citation
                            (mapcar (lambda (reference)
                                      (org-cite-csl--parse-reference reference nil))
                                    (org-cite-get-references citation)))
                    (org-cite-csl--create-structure-params citation nil))))
      (citeproc-citation-create
       :cites (mapcar (lambda (key) (list (cons 'id key)))
                      (my/cite-preview--keys citation)))))

(defun my/cite-preview-at-point ()
  "Return the citation at point as the export will render it, or nil.
A string naming the keys the bibliography lacks, or what went wrong,
instead of an error: it is shown while moving through the text."
  (when-let* ((citation (and (require 'oc nil t)
                             (my/cite-preview--citation-at-point))))
    (unless (member (car (org-cite-citation-style citation nil)) '("nocite" "n"))
      (condition-case err
          (let ((missing (my/reference-missing (my/cite-preview--keys citation))))
            (if missing
                (format "Not in the bibliography: %s" (string-join missing ", "))
              ;; Without the text properties the parsed locators carry
              ;; (Org's objects, with their parents).
              (substring-no-properties
               (my/reference-render-citation (my/cite-preview--structure citation)
                                             (my/cite-preview--style-name)))))
        (error (format "Citation preview: %s" (error-message-string err)))))))

(defun my/cite-preview--eldoc (&rest _)
  "ElDoc function: the citation at point as it will export."
  (my/cite-preview-at-point))

(defvar-local my/cite-preview--eldoc-ours nil
  "Non-nil when this module turned `eldoc-mode' on in this buffer.")

(defun my/cite-preview--setup ()
  "Show citations in this Org buffer's echo area through ElDoc."
  (add-hook 'eldoc-documentation-functions #'my/cite-preview--eldoc nil t)
  (unless (bound-and-true-p eldoc-mode)
    (eldoc-mode 1)
    (setq my/cite-preview--eldoc-ours t)))

(defun my/cite-preview--teardown ()
  "Undo `my/cite-preview--setup' in this buffer."
  (remove-hook 'eldoc-documentation-functions #'my/cite-preview--eldoc t)
  (when my/cite-preview--eldoc-ours
    (eldoc-mode -1)
    (setq my/cite-preview--eldoc-ours nil)))

;; ============================================================
;; ON AND OFF
;; ============================================================
;; `my/cite-preview-mode' is this module's switch (module contract,
;; rule 12): on, every Org buffer, open or opened later, shows the
;; citation under point; off, none does.  Customize saves the position
;; in this machine's settings (M-x customize-option RET
;; my/cite-preview-mode).

(define-minor-mode my/cite-preview-mode
  "Citations shown in the echo area as they will export.
On: with point on [cite:...] in an Org buffer, the echo area shows the
citation rendered in the document's CSL style.  Off: nothing is shown,
and `my/cite-preview-at-point' remains for Lisp.  Customize saves the
position in this machine's settings."
  :global t
  :init-value t
  :group 'my/cite-preview
  (if my/cite-preview-mode
      (add-hook 'org-mode-hook #'my/cite-preview--setup)
    (remove-hook 'org-mode-hook #'my/cite-preview--setup))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (if my/cite-preview-mode
            (my/cite-preview--setup)
          (my/cite-preview--teardown))))))

(my/cite-preview-mode (if my/cite-preview-mode 1 -1))

(provide '50-cite-preview)
;;; 50-cite-preview.el ends here
