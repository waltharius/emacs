;;; 05j-fleeting-quote.el --- Fleeting notes for quotes -*- lexical-binding: t; -*-

;;; Commentary:
;; Quick fleeting notes for web quotes with WORKING styling!

;;; Code:

(require 'denote)

;; ============================================================================
;; STYLING - Reapply after theme changes!
;; ============================================================================

(defun my/setup-quote-styling ()
  "Apply styling to quote blocks (theme-aware)."
  (interactive)
  ;; Detect dark vs light
  (let ((is-dark (eq (frame-parameter nil 'background-mode) 'dark)))
    (if is-dark
        ;; Dark theme styling
        (progn
          (set-face-attribute 'org-quote nil
                              :background "#1a2332"
                              :foreground "#d5d8df"
                              :slant 'italic
                              :extend t
                              :inherit 'default)
          (set-face-attribute 'org-block-begin-line nil
                              :foreground "#5a6b8f"
                              :background "#0f1722"
                              :height 0.85
                              :underline t
                              :inherit 'shadow)
          (set-face-attribute 'org-block-end-line nil
                              :foreground "#5a6b8f"
                              :background "#0f1722"
                              :height 0.85
                              :overline t
                              :inherit 'shadow))
      ;; Light theme styling
      (progn
        (set-face-attribute 'org-quote nil
                            :background "#f7f9fb"
                            :foreground "#2a3240"
                            :slant 'italic
                            :extend t
                            :inherit 'default)
        (set-face-attribute 'org-block-begin-line nil
                            :foreground "#8896ab"
                            :background "#e8ecf0"
                            :height 0.85
                            :underline t
                            :inherit 'shadow)
        (set-face-attribute 'org-block-end-line nil
                            :foreground "#8896ab"
                            :background "#e8ecf0"
                            :height 0.85
                            :overline t
                            :inherit 'shadow)))))

;; Apply styling on org-mode load
(add-hook 'org-mode-hook #'my/setup-quote-styling)

;; ⚠️ CRITICAL: Reapply styling after theme changes!
(advice-add 'load-theme :after
            (lambda (&rest _)
              (dolist (buffer (buffer-list))
                (with-current-buffer buffer
                  (when (derived-mode-p 'org-mode)
                    (my/setup-quote-styling))))))

;; Apply to current buffer if already in org-mode
(when (derived-mode-p 'org-mode)
  (my/setup-quote-styling))

;; ============================================================================
;; MAIN FUNCTION - Create fleeting note
;; ============================================================================

(defun my/fleeting-quote ()
  "Create a fleeting note for a quote."
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
;; SMART VERSION
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
         (quote-text (read-string "📖 Quote: "))
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
;; UTILITIES
;; ============================================================================

(defun my/count-fleeting-notes ()
  "Count unprocessed fleeting notes."
  (interactive)
  (let ((count 0))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
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
