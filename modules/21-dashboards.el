;;; 21-dashboards.el --- Historical note dashboards -*- lexical-binding: t; -*-
;;; Commentary:
;; Adds "This Day in History" and "This Day, Every Month" dashboards.
;; These views scan Denote identifiers (date-based file names) and
;; find notes matching today's day-of-month across previous years,
;; or across every month where a note happens to exist on that day.
;;
;; Journal notes are distinguished by the `journal' Denote keyword in
;; the file name, with a content fallback for notes whose name has lost
;; its keywords.  Until 2026-08 this test looked for a :well-being:
;; property instead; that property is being retired by
;; 05b-journal-metrics.el, and a note migrated to the metrics drawer no
;; longer carries it, so the old test silently stopped recognising
;; migrated and newly created journals.
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
  "Return non-nil when FILE is a journal note.

Primary test: the `journal\=' Denote keyword in the file name.  Every
journal file created by `my/denote-journal\=' or
`my/denote-journal-date\=' carries it, and reading it costs no file
access at all.  The keyword segment is parsed here with a plain regexp
rather than through a Denote helper, so this predicate does not depend
on which helper names a given Denote version exposes.

Fallback, for a note whose name lost its keywords in some earlier
migration: any of the three metrics formats -- the #+wellbeing: keyword
(schema 2), the metrics headline (schema 1) or the legacy :well-being:
drawer (schema 0)."
  (let* ((base (file-name-base file))
         (keywords (when (string-match "__\\(.*\\)\\\'" base)
                     (split-string (match-string 1 base) "_" t))))
    (or (and keywords (member "journal" keywords) t)
        (with-temp-buffer
          (insert-file-contents file nil 0 1200)
          (let ((case-fold-search t))
            (goto-char (point-min))
            (or (re-search-forward "^#\\+wellbeing:" nil t)
                (re-search-forward "^[ \t]*:well-being:" nil t)
                (re-search-forward
                 (format "^\\* %s[ \t]*$"
                         (regexp-quote my-journal-metrics-heading))
                 nil t)))))))

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

;; ============================================================
;; FILTERS
;; ============================================================

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

(defun my/dashboards--collect-same-day-every-month (&optional journals-only)
  "Return notes whose day-of-month matches today, across every month
and year, excluding today's own date. When JOURNALS-ONLY is non-nil,
keep only journal notes. Sorted newest year first, then newest
month first."
  (let* ((today (decode-time (current-time)))
         (target-day (nth 3 today))
         (current-month (nth 4 today))
         (current-year (nth 5 today))
         (entries (delq nil (mapcar #'my/dashboards--entry
                                     (my/dashboards--all-note-files)))))
    (sort
     (seq-filter
      (lambda (e)
        (and (= (plist-get e :day) target-day)
             (not (and (= (plist-get e :month) current-month)
                       (= (plist-get e :year) current-year)))
             (or (not journals-only) (plist-get e :journal))))
      entries)
     (lambda (a b)
       (or (> (plist-get a :year) (plist-get b :year))
           (and (= (plist-get a :year) (plist-get b :year))
                (> (plist-get a :month) (plist-get b :month))))))))

;; ============================================================
;; NAVIGATION BUFFER
;; ============================================================

(defcustom my/dashboards-tab-name "History"
  "Name of the tab-bar tab holding the note history navigation buffer."
  :type 'string
  :group 'my-dashboards)

(defcustom my/dashboards-nav-width 52
  "Width in columns of the navigation window when the tab is split.
This is the width given to the LEFT window; the note fills the rest."
  :type 'integer
  :group 'my-dashboards)

(defvar-local my/dashboards--preview-window nil
  "Window in which notes picked from the navigation buffer are shown.
Buffer-local to the navigation buffer, since that is where the button
actions run.  Nil means no preview window exists yet, in which case the
next visit splits one off.  Always validated with `window-live-p'
before use: the window may have been closed by `delete-other-windows'
or by switching tabs, and a stale window object must not be reused.")

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
     'help-echo file
     ;; Stored on the button so keyboard navigation can find the file
     ;; without re-parsing the line.
     'my-file file
     'action (lambda (button)
               (my/dashboards--visit (button-get button 'my-file))))
    (insert "\n")))

(defun my/dashboards--visit (file)
  "Show FILE in the navigation buffer's preview window.

Reuses the same window for every visit, so clicking through the list
replaces the note on the right rather than piling up windows.  Point
stays in the navigation buffer.

`switch-to-buffer' inside `with-selected-window' is used rather than
the shorter `set-window-buffer' because only the former records the
outgoing buffer in that window's history, which is what makes
\\[previous-buffer] and \\[next-buffer] step back through previously
previewed notes."
  (let ((window (if (window-live-p my/dashboards--preview-window)
                    my/dashboards--preview-window
                  (setq my/dashboards--preview-window
                        (split-window-right my/dashboards-nav-width)))))
    (with-selected-window window
      (switch-to-buffer (find-file-noselect file)))))

(defun my/dashboards--file-at-point ()
  "Return the note file of the button on the current line, or nil."
  (let ((button (or (button-at (point))
                    (save-excursion
                      (forward-line 0)
                      (button-at (point))))))
    (when button (button-get button 'my-file))))

(defun my/dashboards-visit-at-point ()
  "Preview the note on the current line."
  (interactive)
  (if-let* ((file (my/dashboards--file-at-point)))
      (my/dashboards--visit file)
    (message "No note on this line")))

(defun my/dashboards-next-and-visit ()
  "Move to the next entry and preview it."
  (interactive)
  (forward-line 1)
  (my/dashboards-visit-at-point))

(defun my/dashboards-previous-and-visit ()
  "Move to the previous entry and preview it."
  (interactive)
  (forward-line -1)
  (my/dashboards-visit-at-point))

(defvar my/dashboards-nav-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n")   #'my/dashboards-next-and-visit)
    (define-key map (kbd "p")   #'my/dashboards-previous-and-visit)
    (define-key map (kbd "o")   #'my/dashboards-visit-at-point)
    (define-key map (kbd "RET") #'my/dashboards-visit-at-point)
    map)
  "Keymap for `my/dashboards-nav-mode'.")

(define-derived-mode my/dashboards-nav-mode special-mode "Note History"
  "Major mode for the note history navigation buffer.
\\{my/dashboards-nav-mode-map}"
  (hl-line-mode 1))

(defun my/dashboards--goto-tab ()
  "Switch to the history tab, creating it beside the current one if absent."
  (my/fixed-tab-goto my/dashboards-tab-name))

(defun my/dashboards--show-navigation (entries title)
  "Display ENTRIES as clickable lines in the history tab, titled TITLE."
  (let ((buffer (get-buffer-create my/dashboards-nav-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/dashboards-nav-mode)
        ;; A window recorded by an earlier invocation is meaningless
        ;; now: the layout is about to be reset below.
        (setq my/dashboards--preview-window nil)
        (insert title "\n\n")
        (if entries
            (dolist (entry entries) (my/dashboards--insert-button-line entry))
          (insert "No matching notes.\n"))
        (goto-char (point-min))
        (forward-line 2)))
    (my/dashboards--goto-tab)
    (switch-to-buffer buffer)
    ;; Start from a single window so the first visit produces exactly
    ;; the intended two-pane layout regardless of what the tab held.
    (delete-other-windows)
    buffer))

(defun my/dashboards--open-first-and-show-nav (entries title)
  "List ENTRIES under TITLE in the history tab and preview the newest."
  (if (null entries)
      (message "No matching notes for: %s" title)
    (my/dashboards--show-navigation entries title)
    (my/dashboards-visit-at-point)))

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

(defun my/dashboards-open-same-day-every-month ()
  "Open the most recent note whose day-of-month matches today,
across every month and year."
  (interactive)
  (my/dashboards--open-first-and-show-nav
   (my/dashboards--collect-same-day-every-month nil)
   "This Day, Every Month — all notes"))

(defun my/dashboards-open-same-day-every-month-journals ()
  "Open the most recent journal note whose day-of-month matches
today, across every month and year."
  (interactive)
  (my/dashboards--open-first-and-show-nav
   (my/dashboards--collect-same-day-every-month t)
   "This Day, Every Month — journals"))

;; ============================================================
;; SUB-MENU: History  (C-c n f h)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-history
;; ============================================================

(transient-define-prefix my/dashboards-history-menu ()
  "Historical dashboards: same day across years or across months."
  [["This Day in History (years)"
    ("t" "All silos"       my/dashboards-open-this-day-history)
    ("j" "Journals only"   my/dashboards-open-this-day-history-journals)]
   ["This Day, Every Month"
    ("m" "All silos"       my/dashboards-open-same-day-every-month)
    ("M" "Journals only"   my/dashboards-open-same-day-every-month-journals)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; DYNAMIC MENU INTEGRATION
;; Appends "History →" to the existing "Overview" group inside
;; my/notes-find-menu, right after the existing "r" (Random note)
;; entry, following the same pattern as 19-philosophy-notes.el.
;; ============================================================

(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-find-menu "r"
                       '("h" "History →" my/dashboards-history-menu)))

(provide '21-dashboards)
;;; 21-dashboards.el ends here
