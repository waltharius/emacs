;;; 21-dashboards.el --- Historical note dashboards -*- lexical-binding: t; -*-
;;; Commentary:
;; Adds "This Day in History" and "Same Day Last Month" dashboards.
;; These views scan Denote identifiers (date-based file names) and
;; find notes matching today's month/day across previous years, or
;; the same day one month ago.
;;
;; Journal notes are distinguished by the :well-being: property in
;; the file's property drawer (this is the only marker that differs
;; between journal notes and all other notes in this system).
;;
;; This menu is appended dynamically to the existing "Overview"
;; section of my/notes-find-menu (C-c n f), the same way
;; 19-philosophy-notes.el appends "Philosophy" to my/notes-menu.
;; If this file is removed from init.el, the menu entry disappears
;; automatically, without editing 12-transient.el.
;;
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-history

;;; Code:

(require 'org)
(require 'button)
(require 'calendar)
(require 'transient)

(defgroup my-dashboards nil
  "Historical dashboards for Denote notes."
  :group 'convenience)

(defcustom my/dashboards-nav-buffer-name "*Note History*"
  "Name of the navigation buffer used by historical dashboards."
  :type 'string)

;; ============================================================
;; DATA COLLECTION
;; ============================================================

(defun my/dashboards--all-note-files ()
  "Return all Denote note files across every silo."
  (if (fboundp 'denote-directory-files)
      (denote-directory-files)
    (user-error "Denote is not available; load 04-denote.el first")))

(defun my/dashboards--read-front-matter-field (file field)
  "Return FIELD value from FILE front matter, or nil if absent."
  (with-temp-buffer
    (insert-file-contents file nil 0 800)
    (goto-char (point-min))
    (when (re-search-forward
           (format "^#\\+%s:[ \t]+\\(.+\\)$" (regexp-quote field))
           nil t)
      (string-trim (match-string 1)))))

(defun my/dashboards--identifier (file)
  "Return the Denote identifier from FILE front matter."
  (my/dashboards--read-front-matter-field file "identifier"))

(defun my/dashboards--title (file)
  "Return the title from FILE front matter, or fall back to file name."
  (or (my/dashboards--read-front-matter-field file "title")
      (file-name-base file)))

(defun my/dashboards--journal-p (file)
  "Return non-nil when FILE contains the :well-being: property.
This is the only marker distinguishing journal notes from the rest."
  (with-temp-buffer
    (insert-file-contents file nil 0 1200)
    (let ((case-fold-search t))
      (goto-char (point-min))
      (re-search-forward "^[ \t]*:well-being:" nil t))))

(defun my/dashboards--identifier-date (identifier)
  "Parse IDENTIFIER (YYYYMMDDTHHMMSS) into a plist :year :month :day."
  (when (and identifier
             (string-match
              "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T[0-9]\\{6\\}\\'"
              identifier))
    (list :year  (string-to-number (match-string 1 identifier))
          :month (string-to-number (match-string 2 identifier))
          :day   (string-to-number (match-string 3 identifier)))))

(defun my/dashboards--entry (file)
  "Return a normalized metadata plist for FILE, or nil if no valid date."
  (let* ((identifier (my/dashboards--identifier file))
         (date-parts (my/dashboards--identifier-date identifier)))
    (when date-parts
      (list :file file
            :title (my/dashboards--title file)
            :identifier identifier
            :year (plist-get date-parts :year)
            :month (plist-get date-parts :month)
            :day (plist-get date-parts :day)
            :journal (my/dashboards--journal-p file)))))

(defun my/dashboards--today-month-day ()
  "Return (MONTH DAY) for today."
  (let ((now (decode-time (current-time))))
    (list (nth 4 now) (nth 3 now))))

(defun my/dashboards--previous-month-same-day ()
  "Return (YEAR MONTH DAY) for the same day one month ago.
Return nil when that day does not exist in the previous month
\(e.g. running this on March 31st, since February has no 31st\)."
  (let* ((now (decode-time (current-time)))
         (day (nth 3 now))
         (month (nth 4 now))
         (year (nth 5 now))
         (target-month (if (= month 1) 12 (1- month)))
         (target-year (if (= month 1) (1- year) year))
         (last-day (calendar-last-day-of-month target-month target-year)))
    (when (<= day last-day)
      (list target-year target-month day))))

(defun my/dashboards--collect-this-day-history (&optional journals-only)
  "Return notes from today's month/day in previous years, newest first.
When JOURNALS-ONLY is non-nil, keep only journal notes."
  (pcase-let* ((`(,month ,day) (my/dashboards--today-month-day))
               (current-year (nth 5 (decode-time (current-time))))
               (entries (delq nil (mapcar #'my/dashboards--entry
                                           (my/dashboards--all-note-files)))))
    (sort
     (seq-filter
      (lambda (e)
        (and (= (plist-get e :month) month)
             (= (plist-get e :day) day)
             (< (plist-get e :year) current-year)
             (or (not journals-only) (plist-get e :journal))))
      entries)
     (lambda (a b) (> (plist-get a :year) (plist-get b :year))))))

(defun my/dashboards--collect-one-month-ago (&optional journals-only)
  "Return notes created exactly one month ago on the same day.
When JOURNALS-ONLY is non-nil, keep only journal notes.
Signals a user-error when the previous month has no matching day."
  (let ((target (my/dashboards--previous-month-same-day)))
    (unless target
      (user-error "This day of the month did not exist last month"))
    (pcase-let* ((`(,year ,month ,day) target)
                 (entries (delq nil (mapcar #'my/dashboards--entry
                                             (my/dashboards--all-note-files)))))
      (seq-filter
       (lambda (e)
         (and (= (plist-get e :year) year)
              (= (plist-get e :month) month)
              (= (plist-get e :day) day)
              (or (not journals-only) (plist-get e :journal))))
       entries))))

;; ============================================================
;; NAVIGATION BUFFER
;; ============================================================

(defun my/dashboards--insert-button-line (entry)
  "Insert a clickable line for ENTRY into the current buffer."
  (let* ((file (plist-get entry :file))
         (label (format "%04d-%02d-%02d  %s"
                        (plist-get entry :year)
                        (plist-get entry :month)
                        (plist-get entry :day)
                        (plist-get entry :title))))
    (insert-text-button
     label
     'follow-link t
     'action (lambda (_button) (find-file file)))
    (insert "\n")))

(defun my/dashboards--show-navigation (entries title)
  "Display ENTRIES as clickable lines in a dedicated buffer titled TITLE."
  (let ((buffer (get-buffer-create my/dashboards-nav-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert title "\n\n")
        (if entries
            (dolist (entry entries) (my/dashboards--insert-button-line entry))
          (insert "No matching notes.\n"))))
    (display-buffer buffer)))

(defun my/dashboards--open-first-and-show-nav (entries title)
  "Open the newest file from ENTRIES and list all matches under TITLE."
  (if (null entries)
      (message "No matching notes for: %s" title)
    (find-file (plist-get (car entries) :file))
    (my/dashboards--show-navigation entries title)))

;; ============================================================
;; INTERACTIVE COMMANDS
;; ============================================================

(defun my/dashboards-open-this-day-history ()
  "Open the newest note from today's month/day in previous years."
  (interactive)
  (my/dashboards--open-first-and-show-nav
   (my/dashboards--collect-this-day-history nil)
   "This Day in History — all notes"))

(defun my/dashboards-open-this-day-history-journals ()
  "Open the newest journal note from today's month/day in previous years."
  (interactive)
  (my/dashboards--open-first-and-show-nav
   (my/dashboards--collect-this-day-history t)
   "This Day in History — journals"))

(defun my/dashboards-open-one-month-ago ()
  "Open notes created exactly one month ago on the same day."
  (interactive)
  (my/dashboards--open-first-and-show-nav
   (my/dashboards--collect-one-month-ago nil)
   "Same Day Last Month — all notes"))

(defun my/dashboards-open-one-month-ago-journals ()
  "Open journal notes created exactly one month ago on the same day."
  (interactive)
  (my/dashboards--open-first-and-show-nav
   (my/dashboards--collect-one-month-ago t)
   "Same Day Last Month — journals"))

;; ============================================================
;; SUB-MENU: History  (C-c n f h)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-history
;; ============================================================

(transient-define-prefix my/dashboards-history-menu ()
  "Historical dashboards: same day, previous years or previous month."
  [["This Day in History"
    ("t" "All silos"       my/dashboards-open-this-day-history)
    ("j" "Journals only"   my/dashboards-open-this-day-history-journals)]
   ["Same Day Last Month"
    ("m" "All silos"       my/dashboards-open-one-month-ago)
    ("M" "Journals only"   my/dashboards-open-one-month-ago-journals)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; DYNAMIC MENU INTEGRATION
;; Appends "History →" to the existing "Overview" group inside
;; my/notes-find-menu, right after the existing "r" (Random note)
;; entry, following the same pattern as 19-philosophy-notes.el.
;; ============================================================

(with-eval-after-load '12-transient
  (ignore-errors
    (transient-remove-suffix 'my/notes-find-menu "h"))
  (transient-append-suffix
   'my/notes-find-menu "r"
   '("h" "History →" my/dashboards-history-menu)))

(provide '21-dashboards)
;;; 21-dashboards.el ends here
