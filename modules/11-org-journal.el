;;; 11-org-journal.el --- Org-journal integration (HYBRID mode) -*- lexical-binding: t; -*-

;;; Commentary:
;; Org-journal with calendar + prev/next navigation
;; Zachowuje 100% Twojego workflow (my/journal)
;; Dodaje: calendar view, prev/next journal, search
;; BONUS: Klik na dzień = search by identifier!

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
  ;; Usuń poprzednie marki (refresh!)
  (calendar-unmark)
  (let ((journal-dates '()))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (when (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)"
                          (file-name-nondirectory file))
        (let ((year (string-to-number (match-string 1 (file-name-nondirectory file))))
              (month (string-to-number (match-string 2 (file-name-nondirectory file))))
              (day (string-to-number (match-string 3 (file-name-nondirectory file)))))
          (push (list month day year) journal-dates))))
    (dolist (date journal-dates)
      (calendar-mark-visible-date date))
    (message "Marked %d journal days! 📅" (length journal-dates))))

;; Wywołaj marking po zmianie miesiąca
(add-hook 'calendar-move-hook 'my/journal-mark-calendar)

;; WAŻNE: Wywołaj marking ZARAZ po otwarciu calendara!
(defun my/open-journal-calendar ()
  "Open calendar and mark journal days (fixed version!)."
  (interactive)
  (calendar)
  ;; Poczekaj na otwarcie, POTEM oznacz!
  (run-at-time "0.1 sec" nil 'my/journal-mark-calendar))


;; ============================================
;; CLICK ON DAY = SEARCH BY IDENTIFIER
;; ============================================

(defun my/journal-search-by-date (date)
  "Search all notes created on DATE (YYYYMMDD identifier format)."
  (interactive)
  (let* ((year (calendar-extract-year date))
         (month (calendar-extract-month date))
         (day (calendar-extract-day date))
         (identifier-pattern (format "%04d%02d%02d" year month day)))
    (consult-ripgrep my-notes-dir (concat ":identifier: " identifier-pattern))))

(defun my/journal-calendar-open-day ()
  "Search notes from selected day in calendar."
  (interactive)
  (let ((date (calendar-cursor-to-date)))
    (my/journal-search-by-date date)))

;; Bind RET w calendar do search
(add-hook 'calendar-mode-hook
          (lambda ()
            (local-set-key (kbd "RET") 'my/journal-calendar-open-day)))

;; ============================================
;; PREV/NEXT JOURNAL NAVIGATION
;; ============================================

(defun my/journal-get-current-date ()
  "Get date from current journal file, or today if not in journal."
  (if (and buffer-file-name
           (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)"
                         (file-name-nondirectory buffer-file-name)))
      (match-string 0 (file-name-nondirectory buffer-file-name))
    (format-time-string "%Y-%m-%d")))

(defun my/journal-get-all-dates ()
  "Get sorted list of all journal dates (YYYY-MM-DD)."
  (let ((dates '()))
    (dolist (file (directory-files my-notes-dir t "-journal\\.org$"))
      (when (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)"
                          (file-name-nondirectory file))
        (push (match-string 1 (file-name-nondirectory file)) dates)))
    (sort dates 'string<)))

(defun my/journal-find-by-direction (direction)
  "Find journal in DIRECTION ('prev or 'next) from current file."
  (let* ((current-date (my/journal-get-current-date))
         (all-dates (my/journal-get-all-dates))
         (target-date nil))
    (cond
     ((eq direction 'prev)
      ;; Znajdź poprzedni
      (dolist (date all-dates)
        (when (string< date current-date)
          (setq target-date date))))
     ((eq direction 'next)
      ;; Znajdź następny
      (setq target-date
            (car (seq-filter (lambda (d) (string> d current-date))
                            all-dates)))))
    ;; Zwróć pełną ścieżkę
    (when target-date
      (car (directory-files my-notes-dir t
                           (concat "-" target-date "-journal\\.org$"))))))

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
;; ENHANCED MY/JOURNAL (navigation links)
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
  "Setup navigation links in journal files."
  (when (and buffer-file-name
             (string-match "-journal\\.org$" buffer-file-name))
    (my/journal-add-navigation-links)))

(add-hook 'org-mode-hook 'my/journal-setup-navigation)

;; ============================================
;; JOURNAL SEARCH
;; ============================================

(defun my/journal-search (query)
  "Search through all journal files for QUERY."
  (interactive "sSearch journals: ")
  (consult-ripgrep my-notes-dir (concat query " *journal*.org")))

;; ============================================
;; BONUS: LICZBA WPISÓW NA DZIEŃ (jak Obsidian!)
;; ============================================

(defun my/journal-count-notes-on-day (date)
  "Count all notes created on DATE (YYYYMMDD)."
  (let* ((year (calendar-extract-year date))
         (month (calendar-extract-month date))
         (day (calendar-extract-day date))
         (identifier-pattern (format "%04d%02d%02d" year month day))
         (count 0))
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (when (string-match identifier-pattern (file-name-nondirectory file))
        (setq count (1+ count))))
    count))

(defun my/journal-show-day-info ()
  "Show number of notes on selected day (Obsidian-style!)."
  (interactive)
  (let* ((date (calendar-cursor-to-date))
         (count (my/journal-count-notes-on-day date))
         (date-str (format "%04d-%02d-%02d"
                          (calendar-extract-year date)
                          (calendar-extract-month date)
                          (calendar-extract-day date))))
    (if (> count 0)
        (message "📝 %s: %d note%s"
                 date-str count (if (= count 1) "" "s"))
      (message "No notes on %s" date-str))))

;; Bind 'i' (info) w calendar
(add-hook 'calendar-mode-hook
          (lambda ()
            (local-set-key (kbd "i") 'my/journal-show-day-info)))

(provide '11-org-journal)
;;; 11-org-journal.el ends here
