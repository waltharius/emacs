;;; 11-org-journal.el --- Org-journal integration (HYBRID mode) -*- lexical-binding: t; -*-

;;; Commentary:
;; Org-journal with calendar + prev/next navigation
;; Zachowuje 100% Twojego workflow (my/journal)
;; Dodaje: calendar view, prev/next journal, search

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
  ;; Format zgodny z Twoim my/journal
  (org-journal-date-format "%Y-%m-%d %A")
  (org-journal-time-format "%H:%M")
  ;; NIE AUTO-CREATE (zachowujemy Twój my/journal!)
  (org-journal-enable-agenda-integration nil)
  (org-journal-carryover-items nil))

;; ============================================
;; CALENDAR INTEGRATION
;; ============================================

(defun my/journal-calendar ()
  "Open calendar and mark journal days."
  (interactive)
  (calendar)
  (my/journal-mark-calendar))

(defun my/journal-mark-calendar ()
  "Mark all journal days in calendar."
  (interactive)
  (let ((journal-dates '()))
    ;; Znajdź wszystkie journale
    (dolist (file (directory-files my-notes-dir t "\\.org$"))
      (when (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)"
                          (file-name-nondirectory file))
        (let ((year (string-to-number (match-string 1 (file-name-nondirectory file))))
              (month (string-to-number (match-string 2 (file-name-nondirectory file))))
              (day (string-to-number (match-string 3 (file-name-nondirectory file)))))
          (push (list month day year) journal-dates))))
    ;; Mark w kalendarzu
    (dolist (date journal-dates)
      (calendar-mark-visible-date date))))

;; Auto-mark gdy otwierasz calendar
(add-hook 'calendar-mode-hook 'my/journal-mark-calendar)

;; ============================================
;; PREV/NEXT JOURNAL NAVIGATION
;; ============================================

(defun my/journal-find-by-offset (days)
  "Find journal file offset by DAYS from today."
  (let* ((current-time (current-time))
         (target-time (time-add current-time (days-to-time days)))
         (target-date (format-time-string "%Y-%m-%d" target-time))
         (pattern (concat "-" target-date "-journal")))
    ;; Szukaj pliku z tą datą
    (car (directory-files my-notes-dir t pattern))))

(defun my/journal-prev ()
  "Open previous journal entry."
  (interactive)
  (let ((prev-file (my/journal-find-by-offset -1)))
    (if prev-file
        (find-file prev-file)
      (message "No previous journal found. Create one with C-c n j!"))))

(defun my/journal-next ()
  "Open next journal entry."
  (interactive)
  (let ((next-file (my/journal-find-by-offset 1)))
    (if next-file
        (find-file next-file)
      (message "No next journal found. Maybe future? 🔮"))))

;; ============================================
;; ENHANCED MY/JOURNAL (dodajemy elisp linki)
;; ============================================

(defun my/journal-add-navigation-links ()
  "Add prev/next navigation links at top of journal."
  (save-excursion
    (goto-char (point-min))
    ;; Znajdź koniec frontmattera
    (when (re-search-forward "^:END:" nil t)
      (forward-line 1)
      (unless (looking-at "^\\[\\[elisp:")
        (insert "\n[[elisp:(my/journal-prev)][← Poprzedni]] | ")
        (insert "[[elisp:(my/journal-next)][Następny →]]\n")))))

;; Dodaj linki przy otwieraniu journala
(defun my/journal-setup-navigation ()
  "Setup navigation links in journal files."
  (when (and buffer-file-name
             (string-match "-journal\\.org$" buffer-file-name))
    (my/journal-add-navigation-links)))

(add-hook 'org-mode-hook 'my/journal-setup-navigation)

;; ============================================
;; KEYBINDINGS (org-mode tylko!)
;; ============================================



;; [ i ] TYLKO w org-mode!
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "[") 'my/journal-prev)
  (define-key org-mode-map (kbd "]") 'my/journal-next))

;; ============================================
;; JOURNAL SEARCH (bonus!)
;; ============================================

(defun my/journal-search (query)
  "Search through all journal files for QUERY."
  (interactive "sSearch journals: ")
  (let ((default-directory my-notes-dir))
    (grep (concat "grep -nH -e \"" query "\" *journal*.org"))))

;; C-c n s - search journals
(global-set-key (kbd "C-c n s") 'my/journal-search)

(provide '11-org-journal)
;;; 11-org-journal.el ends here
