;;; 05j-fleeting-quote.el --- Fleeting notes for quotes -*- lexical-binding: t; -*-

;; Description: Quick fleeting notes for capturing quotes from web articles

;;; Commentary:
;; Creates Denote-compatible fleeting notes for web quotes
;; Automatically adds 'fleeting' tag, stores URL and source in metadata
;; Beautiful styling for both dark (modus-vivendi) and light (modus-operandi) themes

;;; Code:

;; ============================================================================
;; STYLING - Beautiful quote blocks (theme-aware!)
;; ============================================================================

(defun my/quote-faces-for-theme ()
  "Set quote faces based on current theme."
  (let ((is-dark (eq (frame-parameter nil 'background-mode) 'dark)))
    (if is-dark
        ;; Dark theme (modus-vivendi, wombat, gruvbox-dark)
        (custom-set-faces
         '(org-quote ((t (:background "#2a2a3a"
                          :foreground "#d0d0d0"
                          :slant italic
                          :extend t
                          :box (:line-width 5 :color "#5f87af" :style nil)))))
         '(org-block-begin-line ((t (:foreground "#718096"
                                     :background "#1a202c"
                                     :underline t
                                     :height 0.8))))
         '(org-block-end-line ((t (:foreground "#718096"
                                   :background "#1a202c"
                                   :overline t
                                   :height 0.8)))))
      ;; Light theme (modus-operandi, leuven)
      (custom-set-faces
       '(org-quote ((t (:background "#f0f4f8"
                        :foreground "#2d3748"
                        :slant italic
                        :extend t
                        :box (:line-width 5 :color "#4299e1" :style nil)))))
       '(org-block-begin-line ((t (:foreground "#a0aec0"
                                   :background "#e2e8f0"
                                   :underline t
                                   :height 0.8))))
       '(org-block-end-line ((t (:foreground "#a0aec0"
                                 :background "#e2e8f0"
                                 :overline t
                                 :height 0.8))))))))

;; Apply styling on load and theme change
(my/quote-faces-for-theme)
(add-hook 'after-load-theme-hook #'my/quote-faces-for-theme)

;; ============================================================================
;; MAIN FUNCTION - Create fleeting note with quote
;; ============================================================================

(defun my/fleeting-quote ()
  "Create a fleeting note for a quote with beautiful formatting.
Asks for: title, source URL, quote text, and your reflection.
Automatically tags with 'fleeting' and stores metadata."
  (interactive)
  (let* ((title (read-string "📝 Note title (short): "))
         (source-url (read-string "🔗 Source URL: "))
         (source-title (read-string "📚 Source title: "))
         (quote-text (read-string "📖 Quote text: "))
         (reflection (read-string "💭 Your reflection: "))
         (tags '("fleeting")))  ; Auto-add fleeting tag
    
    ;; Validate inputs
    (when (string-empty-p title)
      (user-error "Title cannot be empty!"))
    (when (string-empty-p quote-text)
      (user-error "Quote text cannot be empty!"))
    
    ;; Create Denote note with fleeting tag
    (denote title tags)
    
    ;; Add custom metadata properties (after Denote frontmatter)
    (save-excursion
      (goto-char (point-min))
      ;; Find end of Denote frontmatter (after #+identifier:)
      (when (re-search-forward "^#\\+identifier:" nil t)
        (forward-line 1)
        ;; Insert custom properties
        (insert "\n")
        (insert "#+BEGIN_PROPERTIES\n")
        (unless (string-empty-p source-url)
          (insert (format ":SOURCE_URL: %s\n" source-url)))
        (unless (string-empty-p source-title)
          (insert (format ":SOURCE_TITLE: %s\n" source-title)))
        (insert (format ":CAPTURED: %s\n" (format-time-string "%Y-%m-%d %a %H:%M")))
        (insert "#+END_PROPERTIES\n")
        (insert "\n")))
    
    ;; Add quote and reflection
    (goto-char (point-max))
    (insert "\n* Quote\n\n")
    (insert "#+BEGIN_QUOTE\n")
    (insert quote-text "\n")
    (insert "#+END_QUOTE\n\n")
    
    ;; Source with link
    (insert "📚 *Source:* " source-title)
    (unless (string-empty-p source-url)
      (insert (format " – [[%s][🔗 Link]]" source-url)))
    (insert "\n\n")
    
    ;; Reflection
    (when (not (string-empty-p reflection))
      (insert "* Reflection\n\n")
      (insert "💭 " reflection "\n\n"))
    
    ;; Add section for processing
    (insert "* Process into permanent note\n\n")
    (insert "- [ ] Expand reflection\n")
    (insert "- [ ] Link to related notes\n")
    (insert "- [ ] Create permanent note if valuable\n")
    
    ;; Save and position cursor
    (save-buffer)
    (goto-char (point-min))
    (when (search-forward "* Reflection" nil t)
      (forward-line 2))
    
    (message "✅ Fleeting note created: %s" title)))

;; ============================================================================
;; SMART VERSION - Auto-detect URL from clipboard
;; ============================================================================

(defun my/fleeting-quote-smart ()
  "Smart fleeting note - auto-detects URL from clipboard.
If clipboard contains URL, pre-fills source URL field."
  (interactive)
  (let* ((clipboard-text (condition-case nil
                            (current-kill 0 t)
                          (error "")))
         (is-url (string-match-p "^https?://" clipboard-text))
         (source-url (if is-url
                        (read-string "🔗 Source URL: " clipboard-text)
                      (read-string "🔗 Source URL: ")))
         (source-title (read-string "📚 Source title: "))
         (title (read-string "📝 Note title (short): "
                           (if (and source-title (not (string-empty-p source-title)))
                               (substring source-title 0 (min 50 (length source-title)))
                             "")))
         (quote-text (read-string "📖 Quote text (paste here): "))
         (reflection (read-string "💭 Your reflection: "))
         (tags '("fleeting")))
    
    ;; Same as above - create note
    (denote title tags)
    
    ;; Add metadata
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^#\\+identifier:" nil t)
        (forward-line 1)
        (insert "\n#+BEGIN_PROPERTIES\n")
        (unless (string-empty-p source-url)
          (insert (format ":SOURCE_URL: %s\n" source-url)))
        (unless (string-empty-p source-title)
          (insert (format ":SOURCE_TITLE: %s\n" source-title)))
        (insert (format ":CAPTURED: %s\n" (format-time-string "%Y-%m-%d %a %H:%M")))
        (insert "#+END_PROPERTIES\n\n")))
    
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
    
    (save-buffer)
    (goto-char (point-min))
    (when (search-forward "* Reflection" nil t)
      (forward-line 2))
    
    (message "✅ Fleeting note created: %s" title)))

;; ============================================================================
;; UTILITIES - Find and manage fleeting notes
;; ============================================================================

(defun my/list-fleeting-notes ()
  "List all fleeting notes for review."
  (interactive)
  (let ((fleeting-files (seq-filter
                         (lambda (file)
                           (with-temp-buffer
                             (insert-file-contents file nil 0 500)
                             (goto-char (point-min))
                             (re-search-forward "^#\\+filetags:.*fleeting" nil t)))
                         (directory-files my-notes-dir t "\\.org$"))))
    (if fleeting-files
        (let ((choice (completing-read "Fleeting notes: "
                                      (mapcar #'file-name-nondirectory fleeting-files))))
          (find-file (expand-file-name choice my-notes-dir)))
      (message "No fleeting notes found!"))))

(defun my/count-fleeting-notes ()
  "Count unprocessed fleeting notes."
  (interactive)
  (let ((count 0))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file nil 0 1000)
        (when (and (re-search-forward "^#\\+filetags:.*fleeting" nil t)
                   (re-search-forward "- \\[ \\] Create permanent note" nil t))
          (setq count (1+ count)))))
    (message "📊 Unprocessed fleeting notes: %d" count)
    count))

;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

(global-set-key (kbd "C-c q") 'my/fleeting-quote)
(global-set-key (kbd "C-c Q") 'my/fleeting-quote-smart)

(provide '05j-fleeting-quote)
;;; 05j-fleeting-quote.el ends here
