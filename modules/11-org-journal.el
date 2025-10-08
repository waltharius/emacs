;;; 11-org-journal.el --- Org-journal integration (HYBRID mode) -*- lexical-binding: t; -*-

;;; Commentary:
;; Org-journal with calendar + prev/next navigation
;; Zachowuje 100% Twojego workflow (my/journal)
;; FIXED: Pattern "*-journal__" znajduje WSZYSTKIE journale!

;;; Code:

;; ============================================
;; ORG-JOURNAL PACKAGE
;; ============================================

(use-package org-journal
  :ensure t
  :defer t
  :custom
  (org-journal-dir (expand-file-name "~/notes/"))
  (org-journal-file-type 'daily)
  (org-journal-date-format "%Y-%m-%d %A")
  (org-journal-time-format "%H:%M")
  (org-journal-enable-agenda-integration nil)
  (org-journal-carryover-items nil))

;; ============================================
;; CALENDAR INTEGRATION
;; ============================================

(defun my/journal-mark-calendar ()
  "Mark all journal days in calendar."
  (interactive)
  (calendar-unmark)
  (let ((journal-dates '()))
    ;; FIXED: "*-journal__" pattern!
    (dolist (file (directory-files my-notes-dir nil "*-journal__.*\\.org$"))
      (when (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)" file)
        (let ((year (string-to-number (match-string 1 file)))
              (month (string-to-number (match-string 2 file)))
              (day (string-to-number (match-string 3 file))))
          (push (list month day year) journal-dates))))
    (dolist (date journal-dates)
      (calendar-mark-visible-date date))
    (message "Marked %d journal days! 📅" (length journal-dates))))

(add-hook 'calendar-move-hook 'my/journal-mark-calendar)

(defun my/open-journal-calendar ()
  "Open calendar and mark journal days."
  (interactive)
  (calendar)
  (run-at-time "0.1 sec" nil 'my/journal-mark-calendar))

;; ============================================
;; CLICK ON DAY = OPEN JOURNAL FILE(S)!
;; ============================================

(defun my/journal-files-on-date (date-str)
  "Get all journal files for DATE-STR (YYYY-MM-DD format)."
  (let ((pattern (concat "-" date-str "-journal__"))
        (files '()))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (when (string-match-p pattern (file-name-nondirectory file))
        (push file files)))
    (nreverse files)))

(defun my/journal-search-by-date (date)
  "Open all journal entries for DATE."
  (interactive)
  (let* ((year (calendar-extract-year date))
         (month (calendar-extract-month date))
         (day (calendar-extract-day date))
         (date-str (format "%04d-%02d-%02d" year month day))
         (files (my/journal-files-on-date date-str)))
    (cond
     ((null files)
      (message "No journal entries found for %s" date-str))
     ((= (length files) 1)
      (find-file (car files)))
     (t
      (let ((file (completing-read
                   (format "Open journal for %s: " date-str)
                   (mapcar #'file-name-nondirectory files)
                   nil t)))
        (find-file (expand-file-name file my-notes-dir)))))))

(defun my/journal-calendar-open-day ()
  "Open journal from selected day in calendar."
  (interactive)
  (let ((date (calendar-cursor-to-date)))
    (my/journal-search-by-date date)))

(add-hook 'calendar-mode-hook
          (lambda ()
            (local-set-key (kbd "RET") 'my/journal-calendar-open-day)))

;; ============================================
;; PREV/NEXT JOURNAL NAVIGATION
;; ============================================

(defun my/journal-get-current-date ()
  "Get date from current journal file, or today if not in journal."
  (if (and buffer-file-name
           (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)"
                         (file-name-nondirectory buffer-file-name)))
      (match-string 1 (file-name-nondirectory buffer-file-name))
    (format-time-string "%Y-%m-%d")))

(defun my/journal-get-all-dates ()
  "Get sorted list of all journal dates (YYYY-MM-DD)."
  (let ((dates '()))
    ;; FIXED: "*-journal__" pattern!
    (dolist (file (directory-files my-notes-dir nil "*-journal__.*\\.org$"))
      (when (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" file)
        (push (match-string 1 file) dates)))
    (delete-dups (sort dates 'string<))))

(defun my/journal-find-by-direction (direction)
  "Find journal in DIRECTION ('prev or 'next) from current file."
  (let* ((current-date (my/journal-get-current-date))
         (all-dates (my/journal-get-all-dates))
         (target-date nil))
    (cond
     ((eq direction 'prev)
      (dolist (date all-dates)
        (when (string< date current-date)
          (setq target-date date))))
     ((eq direction 'next)
      (setq target-date
            (car (seq-filter (lambda (d) (string> d current-date))
                            all-dates)))))
    (when target-date
      (car (my/journal-files-on-date target-date)))))

(defun my/journal-prev ()
  "Open previous journal entry."
  (interactive)
  (let ((prev-file (my/journal-find-by-direction 'prev)))
    (if prev-file
        (find-file prev-file)
      (message "No previous journal found. This is the first one! 🎉"))))

(defun my/journal-next ()
  "Open next journal entry."
  (interactive)
  (let ((next-file (my/journal-find-by-direction 'next)))
    (if next-file
        (find-file next-file)
      (message "No next journal found. This is the latest! 🚀"))))

;; ============================================
;; AUTO-INSERT NAVIGATION LINKS!
;; ============================================

(defun my/journal-add-navigation-links ()
  "Add prev/next navigation links at top of journal."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^:END:" nil t)
      (forward-line 1)
      (unless (looking-at "^\\[\\[elisp:")
        (insert "\n[[elisp:(my/journal-prev)][← Poprzedni]] | ")
        (insert "[[elisp:(my/journal-next)][Następny →]]\n")))))

(defun my/journal-setup-navigation ()
  "Setup navigation links in journal files (AUTO!)."
  (when (and buffer-file-name
             (string-match-p "-[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}-journal__.*\\.org$"
                            buffer-file-name))
    (my/journal-add-navigation-links)))

(add-hook 'org-mode-hook 'my/journal-setup-navigation)

;; ============================================
;; JOURNAL SEARCH
;; ============================================

(defun my/journal-search (query)
  "Search through all journal files for QUERY."
  (interactive "sSearch journals: ")
  (let ((files (directory-files my-notes-dir t "*-journal__.*\\.org$")))
    (if files
        (consult-ripgrep my-notes-dir query
                        (cons "--glob"
                              (cons "*-journal__*.org" nil)))
      (message "No journal files found!"))))

;; ============================================
;; BONUS: LICZBA WPISÓW NA DZIEŃ
;; ============================================

(defun my/journal-count-notes-on-day (date)
  "Count all journal entries on DATE."
  (let* ((year (calendar-extract-year date))
         (month (calendar-extract-month date))
         (day (calendar-extract-day date))
         (date-str (format "%04d-%02d-%02d" year month day)))
    (length (my/journal-files-on-date date-str))))

(defun my/journal-show-day-info ()
  "Show number of journal entries on selected day (Obsidian-style!)."
  (interactive)
  (let* ((date (calendar-cursor-to-date))
         (count (my/journal-count-notes-on-day date))
         (date-str (format "%04d-%02d-%02d"
                          (calendar-extract-year date)
                          (calendar-extract-month date)
                          (calendar-extract-day date))))
    (if (> count 0)
        (message "📝 %s: %d journal entr%s" 
                 date-str count (if (= count 1) "y" "ies"))
      (message "No journals on %s" date-str))))

(add-hook 'calendar-mode-hook
          (lambda ()
            (local-set-key (kbd "i") 'my/journal-show-day-info)))

(provide '11-org-journal)
;;; 11-org-journal.el ends here
