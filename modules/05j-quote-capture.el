;;; Quote capture functionality

(defun my/insert-quote-block ()
  "Insert org-mode quote block with source and optional comment.
If region is active, wraps selected text. Otherwise creates empty block."
  (interactive)
  (let* ((selected-text (when (region-active-p)
                         (buffer-substring-no-properties 
                          (region-beginning) (region-end))))
         (source-title (read-string "Source title (or URL): "))
         (source-url (read-string "URL (optional, press Enter to skip): "))
         (my-thought (read-string "Your thought (optional): ")))
    
    ;; Delete selected text if exists
    (when selected-text
      (delete-region (region-beginning) (region-end)))
    
    ;; Insert quote block
    (insert "#+BEGIN_QUOTE\n")
    (if selected-text
        (insert selected-text "\n")
      (insert "\n"))  ; Empty line for manual paste
    (insert "#+END_QUOTE\n")
    
    ;; Add source
    (insert "— " source-title)
    (when (not (string-empty-p source-url))
      (insert " [[" source-url "][🔗]]"))
    (insert "\n\n")
    
    ;; Add your thought if provided
    (when (not (string-empty-p my-thought))
      (insert "💡 *Moja myśl:* " my-thought "\n\n"))
    
    ;; Position cursor
    (if selected-text
        (forward-line -2)  ; After quote
      (forward-line -4)))) ; Inside quote for pasting

;; Enhanced version with clipboard URL detection
(defun my/smart-quote-from-clipboard ()
  "Smart quote capture - detects URL in clipboard and fetches title.
Works great for web articles!"
  (interactive)
  (let* ((clipboard-text (current-kill 0 t))
         (is-url (string-match-p "^https?://" clipboard-text))
         (source-url (if is-url clipboard-text ""))
         (source-title (if is-url
                          (read-string "Source title: " 
                                      (file-name-base clipboard-text))
                        (read-string "Source title: ")))
         (quote-text (read-string "Quote text (paste here): "))
         (my-thought (read-string "Your thought: ")))
    
    ;; Insert structured quote
    (insert "\n#+BEGIN_QUOTE\n")
    (insert quote-text "\n")
    (insert "#+END_QUOTE\n")
    (insert "— " source-title)
    (when (not (string-empty-p source-url))
      (insert " [[" source-url "][🔗]]"))
    (insert "\n\n")
    
    (when (not (string-empty-p my-thought))
      (insert "💡 *Moja myśl:* " my-thought "\n\n"))))

;; Keybinding
(global-set-key (kbd "C-c q") 'my/insert-quote-block)
(global-set-key (kbd "C-c Q") 'my/smart-quote-from-clipboard)

(provide '05j-quote-capture)
;;; 05j-quote-capture.el ends here
