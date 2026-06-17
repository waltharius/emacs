;;; 05-notes.el --- Essential note creation functions -*- lexical-binding: t; -*-
;;; Commentary:
;; Only the note functions you actually use:
;; - Journal (daily)
;; - Journal (specific date)
;; - Base note (simple)
;; - Essay
;; - Well-being tracking
;;
;; NOTE: denote-directory is now ~/notes/ (root) for better search
;;       Journal functions explicitly save to my-notes-journal

;;; Code:

;; ============================================================
;; JOURNAL: Daily note
;; ============================================================

(defun my/denote-journal ()
  "Create or open today's journal note.
  If journal exists, add new timestamped entry.
  Journal files go to ~/notes/journal/"
  (interactive)
  (let* ((today (format-time-string "%Y-%m-%d"))
         (time-now (format-time-string "%H:%M"))
         (journal-pattern (concat "--" today "-journal"))
         (existing-journal nil))
    
    ;; Search for existing journal in journal silo
    (dolist (file (directory-files my-notes-journal t "\\.org$"))
      (when (string-match-p journal-pattern (file-name-nondirectory file))
        (setq existing-journal file)))
    
    (if existing-journal
        ;; Journal exists - add new entry
        (progn
          (find-file existing-journal)
          (goto-char (point-max))
          
          ;; Smart spacing: always one blank line
          (save-excursion
            (goto-char (point-max))
            (skip-chars-backward " \t\n")
            (delete-region (point) (point-max)))
          
          (goto-char (point-max))
          (insert "\n\n")
          (insert (format "* %s\n" time-now))
          (message "Added entry to journal"))
      
      ;; Create new journal
      (let* ((id (format-time-string "%Y%m%dT%H%M%S"))
             (slug (format "%s-journal" today))
             (filename (format "%s--%s__journal.org" id slug))
             (filepath (expand-file-name filename my-notes-journal)))
        
        (find-file filepath)
        
        ;; Front matter
        (insert (format "#+title:      %s Journal\n" today))
        (insert (format "#+date:       [%s]\n" (format-time-string "%Y-%m-%d %a %H:%M")))
        (insert "#+filetags:   :journal:\n")
        (insert (format "#+identifier: %s\n" id))
        
        ;; Well-being property
        (insert ":PROPERTIES:\n")
        (insert ":well-being:  \n")
        (insert ":END:\n\n")
        
        ;; First entry
        (insert (format "* %s\n" time-now))
        
        (save-buffer)
        (message "Created new journal")))))

;; ============================================================
;; JOURNAL: Specific date (for migration/backdating)
;; ============================================================

(defun my/denote-journal-date ()
  "Create or open journal for a specific date (for migrating old entries).

  Behaviour:
  - If a journal for the chosen date already exists: open it, append
    a heading '* Uzupełnienie' with ADDED_AT and EVENT_DATE properties
    at the bottom and place the cursor there - ready to write.
  - If no journal exists for that date: create a new file.
    The denote identifier uses T000000 (zeroed time) to signal that
    the file was created retroactively. The first heading is also
    '* Uzupełnienie' with properties."
  (interactive)
  (let* ((date-input    (org-read-date nil nil nil "Date: "))
         (parsed-time   (org-parse-time-string date-input))
         (encoded-time  (apply 'encode-time parsed-time))
         (date-formatted (format-time-string "%Y-%m-%d" encoded-time))
         (added-at-stamp (format-time-string "%Y-%m-%d %a %H:%M"))
         (journal-pattern (concat "--" date-formatted "-journal"))
         (existing-journal nil))

    ;; Search for existing journal for the chosen date
    (dolist (file (directory-files my-notes-journal t "\\.org$"))
      (when (string-match-p journal-pattern (file-name-nondirectory file))
        (setq existing-journal file)))

    (if existing-journal
        ;; --------------------------------------------------------
        ;; Journal for that date exists - append supplement heading
        ;; --------------------------------------------------------
        (progn
          (find-file existing-journal)

          ;; Clean trailing whitespace/newlines
          (save-excursion
            (goto-char (point-max))
            (skip-chars-backward " \t\n")
            (delete-region (point) (point-max)))

          (goto-char (point-max))
          (insert "\n\n* Uzupełnienie\n")
          (insert ":PROPERTIES:\n")
          (insert (format ":ADDED_AT:   [%s]\n" added-at-stamp))
          (insert (format ":EVENT_DATE: [%s]\n" date-formatted))
          (insert ":END:\n\n")
          (message "Opened existing journal for %s - cursor below '* Uzupełnienie'"
                   date-formatted))

      ;; --------------------------------------------------------
      ;; No journal for that date - create a fresh backdated file
      ;; ID uses T000000 to mark it as retroactively created.
      ;; --------------------------------------------------------
      (let* ((id       (format-time-string "%Y%m%dT000000" encoded-time))
             (slug     (format "%s-journal" date-formatted))
             (filename (format "%s--%s__journal.org" id slug))
             (filepath (expand-file-name filename my-notes-journal)))

        (find-file filepath)
        (insert (format "#+title:      %s Journal\n" date-formatted))
        (insert (format "#+date:       %s\n"
                        (format-time-string "[%Y-%m-%d %a]" encoded-time)))
        (insert "#+filetags:   :journal:\n")
        (insert (format "#+identifier: %s\n" id))
        (insert ":PROPERTIES:\n")
        (insert ":well-being:  \n")
        (insert ":END:\n\n")
        ;; First heading carries the real creation timestamp in properties
        (insert "* Uzupełnienie\n")
        (insert ":PROPERTIES:\n")
        (insert (format ":ADDED_AT:   [%s]\n" added-at-stamp))
        (insert (format ":EVENT_DATE: [%s]\n" date-formatted))
        (insert ":END:\n")
        (save-buffer)
        (message "Created backdated journal for %s (written %s)"
                 date-formatted added-at-stamp)))))

;; ============================================================
;; BASE NOTE: Simple note with title and tags
;; ============================================================

(defun my/denote-base ()
  "Create a simple note with title and tags.
  You'll be asked which silo (journal/pks/docu) to save in."
  (interactive)
  (let* ((title (read-string "Title: "))
         (keywords-string (read-string "Tags (space-separated): "))
         (keywords (if (string-empty-p keywords-string)
                       nil
                     (split-string keywords-string " " t)))
         (silo (completing-read "Save in: " 
                               '("pks" "docu" "journal") 
                               nil t "pks"))
         (target-dir (cond
                      ((string= silo "journal") my-notes-journal)
                      ((string= silo "docu") my-notes-docu)
                      (t my-notes-pks))))
    
    ;; Temporarily set denote-directory to target silo
    (let ((denote-directory target-dir))
      (if (string-empty-p title)
          (denote nil keywords)
        (denote title keywords)))))

;; ============================================================
;; ESSAY: Writing project
;; ============================================================

(defun my/denote-essay ()
  "Create essay template (writing project).
  Essays go to ~/notes/pks/ by default."
  (interactive)
  (let* ((essay-title (read-string "Essay title: "))
         (title (format "ESEJ: %s" essay-title))
         (project-tag (read-string "Project tag: "))
         (tags (list "esej" "project" project-tag))
         (denote-directory my-notes-pks))  ; Essays in pks silo
    
    (denote title tags)
    
    ;; Add essay template
    (save-excursion
      (goto-char (point-max))
      (insert "\n* Metadata\n")
      (insert "- Subject: \n")
      (insert "- Deadline: \n")
      (insert "- Length: \n")
      (insert "- Status: Planning\n\n")
      (insert "* Essay Plan\n")
      (insert "** Introduction\n\n")
      (insert "** Main Part\n\n")
      (insert "** Conclusion\n\n")
      (insert "* Bibliography\n\n")
      (insert "* Working Notes\n\n")
      (save-buffer))
    
    ;; Position cursor at Subject field
    (goto-char (point-min))
    (re-search-forward "^- Subject: " nil t)))

;; ============================================================
;; WELL-BEING: Set well-being score for journal
;; ============================================================

(defun my/denote-set-wellbeing ()
  "Set well-being score (1-10) for current journal note."
  (interactive)
  (if (not (string-match-p "journal" (or (buffer-file-name) "")))
      (message "This is not a journal note!")
    (let ((score (read-number "Well-being score (1-10): " 5)))
      (when (and (>= score 1) (<= score 10))
        (save-excursion
          (goto-char (point-min))
          (if (re-search-forward ":well-being: *\\([0-9]*\\)" nil t)
              (replace-match (number-to-string score) nil nil nil 1)
            (message "Could not find well-being property"))
          (save-buffer)
          (message "Well-being set to %d" score))))))

;; ============================================================
;; HELPER: Insert current time (HH:MM)
;; ============================================================

(defun insert-current-time ()
  "Insert current time in HH:MM format."
  (interactive)
  (insert (format-time-string "%H:%M")))

;; ============================================================
;; HELPER: Insert current date (YYYY-MM-DD)
;; ============================================================

(defun insert-current-date ()
  "Insert current date in YYYY-MM-DD format."
  (interactive)
  (insert (format-time-string "%Y-%m-%d")))

;; ============================================================
;; HELPER: Delete current note (Git-aware)
;; ============================================================

(defun my/denote-delete-note ()
  "Delete current note file and buffer.
  Uses 'git rm' if file is tracked, otherwise regular delete."
  (interactive)
  (let* ((file (buffer-file-name))
         (name (file-name-nondirectory file)))
    (if (not file)
        (message "This is not a file!")
      (when (yes-or-no-p (format "Delete note: %s? " name))
        ;; Check if in Git repo
        (if (and (executable-find "git")
                 (= 0 (call-process "git" nil nil nil
                                   "ls-files" "--error-unmatch" file)))
            (progn
              (shell-command (format "git rm -f '%s'" file))
              (message "Deleted from Git: %s" name))
          (progn
            (delete-file file)
            (message "Deleted: %s" name)))
        (kill-buffer (current-buffer))))))

(with-eval-after-load 'org
  (setq org-agenda-files
        (list my-notes-journal
              my-notes-pks
              my-notes-docu
              my-fleeting-file
              my-journal-captures)))

(provide '05-notes)
;;; 05-notes.el ends here
