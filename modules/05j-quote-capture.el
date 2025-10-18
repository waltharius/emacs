;;; 05j-quote-capture.el --- Quote capture functionality  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

;; STYLING - piękne cytaty w Emacsie
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

;; FUNCTION - wstawianie cytatów z emoji
(defun my/insert-quote-block ()
  "Insert beautiful quote block with emojis and source."
  (interactive)
  (let* ((selected-text (when (region-active-p)
                         (buffer-substring-no-properties
                          (region-beginning) (region-end))))
         (source-title (read-string "📖 Source title: "))
         (source-url (read-string "🔗 URL (optional): "))
         (page-number (read-string "📄 Page/section (optional): "))
         (my-thought (read-string "💭 Your reflection (optional): ")))
    
    (when selected-text
      (delete-region (region-beginning) (region-end)))
    
    ;; Insert structured quote
    (insert "\n#+BEGIN_QUOTE\n")
    (if selected-text
        (insert selected-text "\n")
      (insert "\n"))  ; Placeholder for manual paste
    (insert "#+END_QUOTE\n\n")
    
    ;; Source info with emojis
    (insert "📚 *Source:* " source-title)
    (when (not (string-empty-p source-url))
      (insert " – [[" source-url "][🔗 Link]]"))
    (when (not (string-empty-p page-number))
      (insert " (p. " page-number ")"))
    (insert "\n\n")
    
    ;; My reflection
    (when (not (string-empty-p my-thought))
      (insert "💭 *Reflection:* /" my-thought "/\n\n"))
    
    ;; Position cursor
    (if selected-text
        (forward-line -4)  ; After quote
      (forward-line -6)))) ; Inside quote for pasting

;; KEYBINDING
(global-set-key (kbd "C-c q") 'my/insert-quote-block)

;; Opcjonalnie: ukryj markery #+BEGIN/END gdy nie edytujesz
(setq org-hide-emphasis-markers t)  ; Już masz w 10-org-formatting.el

(provide '05j-quote-capture)
;;; 05j-quote-capture.el ends here
