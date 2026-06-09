;;; 16-org-export.el --- Org export and PDF settings -*- lexical-binding: t; -*-
;;; Commentary:
;; Global settings for org-mode export, primarily LaTeX/PDF output.

;;; Code:

(with-eval-after-load 'ox-latex
  ;; --- Margins: override geometry package defaults ---
  ;; Default Org LaTeX classes have large margins. We override geometry
  ;; globally so every exported document uses narrower margins.
  (setq org-latex-packages-alist
        '(("margin=2cm" "geometry" t)))

  ;; --- Remove author and date from exported documents ---
  ;; nil = do not include these fields in the LaTeX output at all
  (setq org-export-with-author nil)
  (setq org-export-with-date nil)

  ;; --- Optionally: remove table of contents ---
  ;; (setq org-export-with-toc nil)

  ;; --- Default document class ---
  (setq org-latex-default-class "article")

  ;; --- Compiler: lualatex handles UTF-8 and non-ASCII characters better ---
  (setq org-latex-compiler "lualatex"))

(provide '16-org-export)
;;; 16-org-export.el ends here
