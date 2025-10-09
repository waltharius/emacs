;;; 05d-denote-wellbeing.el --- Simple well-being tracking (1-10 scale) -*- lexical-binding: t; -*-
;;
;; Description: Fast daily mood tracking with optional keywords
;;
;; USAGE:
;;   M-x my/denote-wellbeing-entry  → Add score (1-10) to today's journal
;;   M-x my/denote-wellbeing-stats  → Show averages (7/30 days)
;;
;; STORED AS:
;;   :PROPERTIES:
;;   :well-being: 6
;;   :END:
;;
;; OPTIONAL KEYWORDS (if provided):
;;   #śpiący #zła-pogoda #ból-głowy #radość #sukcesy
;;
;; TODO - Future enhancements (OPTIONAL!):
;; - [ ] Line graph visualization (7/30 days trend)
;; - [ ] Calendar heatmap (emoji-based: 🟢🟡🔴)
;; - [ ] Correlation with sleep/exercise (from journal context)
;; - [ ] Weekly/monthly averages comparison
;; - [ ] Export to CSV for external analysis
;; - [ ] Import from Obsidian (bulk import with keywords)
;;
;;; Code:

;; ============================================================
;; ENTRY - Add well-being score to today's journal
;; ============================================================

(defun my/denote-wellbeing-entry ()
  "Add well-being score (1-10) to today's journal.
Optionally add keywords (e.g. 'śpiący zła-pogoda ból-głowy')."
  (interactive)
  (let* ((score (read-number "Well-being (1-10): "))
         (keywords (read-string "Keywords (optional, space-separated): " nil nil "")))
    
    ;; Validate score
    (unless (and (>= score 1) (<= score 10))
      (user-error "Score must be between 1-10!"))
    
    ;; Find or create today's journal
    (let* ((today (format-time-string "%Y-%m-%d"))
           (journal-pattern (concat "--" today ".*journal"))
           (existing-journal nil))
      
      ;; Search for existing journal
      (dolist (file (directory-files my-notes-dir t "\\.org$"))
        (when (string-match-p journal-pattern (file-name-nondirectory file))
          (setq existing-journal file)))
      
      (if existing-journal
          ;; Journal exists - update well-being property
          (progn
            (find-file existing-journal)
            (goto-char (point-min))
            
            ;; Find or create PROPERTIES drawer
            (if (re-search-forward "^:PROPERTIES:" nil t)
                ;; Properties exist - update or add well-being
                (progn
                  (let ((props-end (save-excursion
                                     (re-search-forward "^:END:" nil t)
                                     (point))))
                    (goto-char (match-beginning 0))
                    (forward-line 1)
                    (if (re-search-forward "^:well-being:" props-end t)
                        ;; Update existing value
                        (progn
                          (beginning-of-line)
                          (kill-line)
                          (insert (format ":well-being: %d" score)))
                      ;; Add new well-being property
                      (goto-char (- props-end 6))  ; Before :END:
                      (insert (format ":well-being: %d\n" score)))))
              ;; No properties - create drawer
              (goto-char (point-min))
              (re-search-forward "^#\\+identifier:" nil t)
              (forward-line 1)
              (insert ":PROPERTIES:\n")
              (insert (format ":well-being: %d\n" score))
              (insert ":END:\n"))
            
            ;; Add keywords if provided
            (when (and keywords (not (string-empty-p keywords)))
              (goto-char (point-max))
              (unless (bolp) (insert "\n"))
              (insert "\n** Well-being context\n")
              (dolist (kw (split-string keywords))
                (insert (format "#%s " kw)))
              (insert "\n"))
            
            (save-buffer)
            (message "✓ Well-being: %d %s" score
                     (if (string-empty-p keywords) "" 
                       (concat "| Keywords: " keywords))))
        
        ;; No journal today - create one with well-being
        (user-error "No journal for today! Create journal first with M-x my/denote-journal")))))

;; ============================================================
;; STATISTICS - Show averages
;; ============================================================

(defun my/denote-wellbeing-stats ()
  "Show well-being statistics (7/30 days average)."
  (interactive)
  (let ((all-scores '())
        (last-7-scores '())
        (last-30-scores '())
        (today (float-time))
        (7-days-ago (- (float-time) (* 7 86400)))
        (30-days-ago (- (float-time) (* 30 86400))))
    
    ;; Collect all well-being scores from journals
    (dolist (file (directory-files my-notes-dir t "journal.*\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward "^:well-being: \\([0-9]+\\)" nil t)
          (let* ((score (string-to-number (match-string 1)))
                 (file-time (float-time (nth 5 (file-attributes file)))))
            (push score all-scores)
            (when (>= file-time 7-days-ago)
              (push score last-7-scores))
            (when (>= file-time 30-days-ago)
              (push score last-30-scores))))))
    
    ;; Calculate averages
    (let ((avg-all (if all-scores (/ (apply #'+ all-scores) (float (length all-scores))) 0))
          (avg-7 (if last-7-scores (/ (apply #'+ last-7-scores) (float (length last-7-scores))) 0))
          (avg-30 (if last-30-scores (/ (apply #'+ last-30-scores) (float (length last-30-scores))) 0)))
      
      ;; Display in minibuffer
      (message "Well-being | Last 7 days: %.1f (%d entries) | Last 30 days: %.1f (%d entries) | All time: %.1f (%d entries)"
               avg-7 (length last-7-scores)
               avg-30 (length last-30-scores)
               avg-all (length all-scores)))))

;; ============================================================
;; JOURNAL - Filter by well-being score
;; ============================================================

(defun my/denote-wellbeing-journal ()
  "Show all journals filtered by well-being score range."
  (interactive)
  (let* ((min-score (read-number "Minimum score (1-10): " 1))
         (max-score (read-number "Maximum score (1-10): " 10))
         (matching-files '()))
    
    ;; Find all journals within score range
    (dolist (file (directory-files my-notes-dir t "journal.*\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward "^:well-being: \\([0-9]+\\)" nil t)
          (let ((score (string-to-number (match-string 1))))
            (when (and (>= score min-score) (<= score max-score))
              (push (cons file score) matching-files))))))
    
    ;; Display results
    (if matching-files
        (let ((buffer-name "*Well-being Journal*"))
          (with-current-buffer (get-buffer-create buffer-name)
            (read-only-mode -1)
            (erase-buffer)
            (insert (format "** Journals with well-being %d-%d\n\n" min-score max-score))
            (dolist (entry (sort matching-files (lambda (a b) (> (cdr a) (cdr b)))))
              (insert (format "- [%d] %s\n" (cdr entry) 
                              (file-name-nondirectory (car entry)))))
            (insert "\n[q] Close\n")
            (goto-char (point-min))
            (org-mode)
            (read-only-mode 1)
            (local-set-key (kbd "q") 'quit-window)
            (switch-to-buffer buffer-name)))
      (message "No journals found with well-being %d-%d" min-score max-score))))

(provide '05d-denote-wellbeing)
;;; 05d-denote-wellbeing.el ends here
