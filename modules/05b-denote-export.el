;;; 05b-denote-export.el --- Denote export functions -*- lexical-binding: t; -*-
;;; Commentary:
;; Description: HTML/PDF export with auto-cleanup and dedicated folders
;;
;;; Code:

;; ============================================================
;; HTML EXPORT - Dedicated folder & auto-cleanup
;; ============================================================

;; Create html/ folder if not exists
(let ((html-dir (expand-file-name "html/" my-notes-dir)))
  (unless (file-directory-p html-dir)
    (make-directory html-dir t)
    (message "✓ Created html/ folder in %s" my-notes-dir)))

(defun my/org-export-cleanup (backend)
  "Clean up LaTeX artifacts and move HTML to dedicated folder after export."
  (when (eq backend 'html)
    (let ((base-name (file-name-sans-extension buffer-file-name))
          (html-file (concat base-name ".html"))
          (html-dir (expand-file-name "html/" my-notes-dir)))
      
      ;; 1. Delete LaTeX artifacts
      (dolist (ext '("aux" "log" "tex" "fdb_latexmk" "fls" "out" "toc" "nav" "snm"))
        (let ((artifact (concat base-name "." ext)))
          (when (file-exists-p artifact)
            (delete-file artifact)
            (message "✓ Deleted %s" (file-name-nondirectory artifact)))))
      
      ;; 2. Move HTML to dedicated folder
      (when (file-exists-p html-file)
        (let ((target-html (expand-file-name (file-name-nondirectory html-file) html-dir)))
          (rename-file html-file target-html t)
          (message "✓ HTML exported to: %s" target-html))))))

;; Hook: Run cleanup AFTER export finishes
(add-hook 'org-export-finished-hook 'my/org-export-cleanup)

;; ============================================================
;; TAGS EXPORT
;; ============================================================

(defun my/denote-export-all-tags ()
  "Export all tags from Denote notes to tags-list.org with statistics."
  (interactive)
  (let* ((all-files (denote-directory-files))
         (all-tags (delete-dups
                    (sort (flatten-list
                           (mapcar (lambda (file)
                                     (denote-extract-keywords-from-path file))
                                   all-files))
                          'string<)))
         (tag-counts (mapcar (lambda (tag)
                               (cons tag
                                     (length (seq-filter (lambda (file)
                                                           (member tag (denote-extract-keywords-from-path file)))
                                                         all-files))))
                             all-tags))
         (output-file (expand-file-name "tags-list.org" denote-directory)))
    
    ;; Write to file
    (with-temp-file output-file
      (insert "#+TITLE: Lista Wszystkich Tagów\n")
      (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d %H:%M")))
      (insert (format "Łącznie tagów: %d\n" (length all-tags)))
      (insert (format "Łącznie notatek: %d\n\n" (length all-files)))
      
      ;; Table with counts
      (insert "** Wszystkie tagi z liczbą notatek\n")
      (insert "| Tag | Liczba notatek |\n")
      (insert "|---------------------|\n")
      (dolist (tag-count tag-counts)
        (insert (format "| %s | %d |\n" (car tag-count) (cdr tag-count))))
      
      (insert "\n** Lista alfabetyczna (tylko nazwy)\n")
      (dolist (tag all-tags)
        (insert (format "- %s\n" tag))))
    
    ;; Open file
    (find-file output-file)
    (message "✓ Tagi wyeksportowane do %s" output-file)))

(provide '05b-denote-export)
;;; 05b-denote-export.el ends here
