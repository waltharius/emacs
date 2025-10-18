;;; 05j-fleeting-quote.el --- Fleeting notes for quotes -*- lexical-binding: t; -*-
;;; Commentary:
;; Quick fleeting notes for web quotes with WORKING styling!

;;; Code:

;; ============================================================================
;; STYLING - Beautiful quote blocks (ACTUALLY WORKS!)
;; ============================================================================

;; Method 1: Custom faces with defface (proper way!)
(defface my-org-quote-face
  '((((background dark))
     (:background "#2a2a3a"
      :foreground "#d0d0d0"
      :slant italic
      :extend t))
    (((background light))
     (:background "#f0f4f8"
      :foreground "#2d3748"
      :slant italic
      :extend t)))
  "Face for 'org-mode' quote blocks."
  :group 'org-faces)

(defface my-org-quote-border-face
  '((((background dark))
     (:background "#2a2a3a"
      :box (:line-width (5 . 0) :color "#5f87af" :style nil)))
    (((background light))
     (:background "#f0f4f8"
      :box (:line-width (5 . 0) :color "#4299e1" :style nil))))
  "Face for quote block border."
  :group 'org-faces)

;; Apply custom faces to org-quote
(defun my/setup-quote-styling ()
  "Apply custom styling to org quote blocks."
  (face-remap-add-relative 'org-quote 'my-org-quote-face)
  (face-remap-add-relative 'org-quote 'my-org-quote-border-face)
  ;; Style BEGIN/END lines
  (face-remap-add-relative 'org-block-begin-line
                          '(:foreground "#718096" :height 0.9 :underline t))
  (face-remap-add-relative 'org-block-end-line
                          '(:foreground "#718096" :height 0.9 :overline t)))

;; Hook to all org-mode buffers
(add-hook 'org-mode-hook #'my/setup-quote-styling)

;; Apply to existing buffers
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'org-mode)
      (my/setup-quote-styling))))

;; ============================================================================
;; MAIN FUNCTION - Create fleeting note
;; ============================================================================

(defun my/fleeting-quote ()
  "Create a fleeting note for a quote.
Properly tags with 'fleeting' and stores metadata in PROPERTIES drawer."
  (interactive)
  (let* ((title (read-string "📝 Note title: "))
         (source-url (read-string "🔗 Source URL: "))
         (source-title (read-string "📚 Source title: "))
         (quote-text (read-string "📖 Quote text: "))
         (reflection (read-string "💭 Your reflection: "))
         (tags '("fleeting")))
    
    (when (string-empty-p title)
      (user-error "Title cannot be empty!"))
    (when (string-empty-p quote-text)
      (user-error "Quote text cannot be empty!"))
    
    ;; Create Denote note
    (denote title tags)
    
    ;; Add PROPERTIES drawer (org-mode standard!)
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^#\\+identifier:" nil t)
        (forward-line 1)
        (insert "\n:PROPERTIES:\n")
        (unless (string-empty-p source-url)
          (insert (format ":SOURCE_URL: %s\n" source-url)))
        (unless (string-empty-p source-title)
          (insert (format ":SOURCE_TITLE: %s\n" source-title)))
        (insert (format ":CAPTURED: %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]")))
        (insert ":FLEETING: unprocessed\n")  ;; For counting!
        (insert ":END:\n\n")))
    
    ;; Add content
    (goto-char (point-max))
    (insert "\n* Quote\n\n")
    (insert "#+BEGIN_QUOTE\n")
    (insert quote-text "\n")
    (insert "#+END_QUOTE\n\n")
    (insert "📚 *Source:* " source-title)
    (unless (string-empty-p source-url)
      (insert (format " – [[%s][🔗 Link]]" source-url)))
    (insert "\n\n")
    
    (when (not (string-empty-p reflection))
      (insert "* Reflection\n\n")
      (insert "💭 " reflection "\n\n"))
    
    (insert "* Process into permanent note\n\n")
    (insert "- [ ] Expand reflection\n")
    (insert "- [ ] Link to related notes\n")
    (insert "- [ ] Create permanent note if valuable\n")
    
    ;; Apply styling and save
    (my/setup-quote-styling)
    (save-buffer)
    
    ;; Position cursor
    (goto-char (point-min))
    (when (search-forward "* Reflection" nil t)
      (forward-line 2))
    
    (message "✅ Fleeting note created: %s" title)))

;; ============================================================================
;; SMART VERSION with clipboard detection
;; ============================================================================

(defun my/fleeting-quote-smart ()
  "Smart fleeting note - auto-detects URL from clipboard."
  (interactive)
  (let* ((clipboard-text (condition-case nil
                            (current-kill 0 t)
                          (error "")))
         (is-url (string-match-p "^https?://" clipboard-text))
         (source-url (if is-url
                        (read-string "🔗 Source URL: " clipboard-text)
                      (read-string "🔗 Source URL: ")))
         (source-title (read-string "📚 Source title: "))
         (title (read-string "📝 Note title: "
                           (if (and source-title (not (string-empty-p source-title)))
                               (substring source-title 0 (min 50 (length source-title)))
                             "")))
         (quote-text (read-string "📖 Quote (paste here): "))
         (reflection (read-string "💭 Reflection: "))
         (tags '("fleeting")))
    
    (denote title tags)
    
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^#\\+identifier:" nil t)
        (forward-line 1)
        (insert "\n:PROPERTIES:\n")
        (unless (string-empty-p source-url)
          (insert (format ":SOURCE_URL: %s\n" source-url)))
        (unless (string-empty-p source-title)
          (insert (format ":SOURCE_TITLE: %s\n" source-title)))
        (insert (format ":CAPTURED: %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]")))
        (insert ":FLEETING: unprocessed\n")
        (insert ":END:\n\n")))
    
    (goto-char (point-max))
    (insert "\n* Quote\n\n")
    (insert "#+BEGIN_QUOTE\n")
    (insert quote-text "\n")
    (insert "#+END_QUOTE\n\n")
    (insert "📚 *Source:* " source-title)
    (unless (string-empty-p source-url)
      (insert (format " – [[%s][🔗 Link]]" source-url)))
    (insert "\n\n")
    
    (when (not (string-empty-p reflection))
      (insert "* Reflection\n\n")
      (insert "💭 " reflection "\n\n"))
    
    (insert "* Process into permanent note\n\n")
    (insert "- [ ] Expand reflection\n")
    (insert "- [ ] Link to related notes\n")
    (insert "- [ ] Create permanent note if valuable\n")
    
    (my/setup-quote-styling)
    (save-buffer)
    
    (goto-char (point-min))
    (when (search-forward "* Reflection" nil t)
      (forward-line 2))
    
    (message "✅ Fleeting note created: %s" title)))

;; ============================================================================
;; UTILITIES - FIXED counting!
;; ============================================================================

(defun my/count-fleeting-notes ()
  "Count unprocessed fleeting notes (check FLEETING property!)."
  (interactive)
  (let ((count 0))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        ;; Check for :FLEETING: unprocessed in PROPERTIES drawer
        (when (and (re-search-forward "^#\\+filetags:.*:fleeting:" nil t)
                   (progn
                     (goto-char (point-min))
                     (re-search-forward ":FLEETING:[ \t]+unprocessed" nil t)))
          (setq count (1+ count)))))
    (message "📊 Unprocessed fleeting notes: %d" count)
    count))

(defun my/list-fleeting-notes ()
  "List all fleeting notes for review."
  (interactive)
  (let ((fleeting-files (seq-filter
                         (lambda (file)
                           (with-temp-buffer
                             (insert-file-contents file nil 0 500)
                             (goto-char (point-min))
                             (re-search-forward "^#\\+filetags:.*:fleeting:" nil t)))
                         (directory-files my-notes-dir t "\\.org$"))))
    (if fleeting-files
        (let ((choice (completing-read "Fleeting notes: "
                                      (mapcar #'file-name-nondirectory fleeting-files))))
          (find-file (expand-file-name choice my-notes-dir)))
      (message "No fleeting notes found!"))))

(defun my/mark-fleeting-processed ()
  "Mark current fleeting note as processed."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward ":FLEETING:[ \t]+unprocessed" nil t)
        (progn
          (replace-match ":FLEETING: processed")
          (save-buffer)
          (message "✅ Marked as processed!"))
      (message "Not a fleeting note or already processed!"))))

;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

(global-set-key (kbd "C-c q") 'my/fleeting-quote)
(global-set-key (kbd "C-c Q") 'my/fleeting-quote-smart)

(provide '05j-fleeting-quote)
;;; 05j-fleeting-quote.el ends here
