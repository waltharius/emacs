;;; 36-notes-stats.el --- Summary statistics for the collection -*- lexical-binding: t; -*-
;;; Commentary:
;; One screen answering "how big is this thing, and is it healthy",
;; with the interesting numbers clickable and the whole thing
;; exportable to Org.
;;
;; TWO TIERS
;; ---------
;; Everything on the opening screen except the two extreme-note titles
;; is computed from FILE NAMES and `file-attributes' alone.  Denote
;; puts the date, the signature, the title and the keywords in the
;; name, so counts, sizes, keyword frequencies, growth per month and
;; per year, the zettelkasten breakdown and the whole journal-coverage
;; section are already there for the taking.
;;
;; The second tier -- words, links, orphans -- opens every file.  It
;; runs only on `c', with a progress reporter, and caches until asked
;; again.  Keeping it off the opening path is what makes this something
;; to glance at rather than something to wait for.
;;
;; TWO VIEWS OF SIZE, DISAGREEING ON PURPOSE
;; -----------------------------------------
;; "Notes by directory" counts .org files, grouped by the top-level
;; directory they sit in -- so `inbox' appears next to the three silos
;; instead of being swallowed by an "other" row that says nothing about
;; what is in it.
;;
;; "On disk" counts FILES, every extension, same grouping.  The two
;; differ by more than an order of magnitude: `attachments/' is around
;; two hundred megabytes against twelve for the entire journal.  A
;; report on "how big is this" counting only notes is off by a factor
;; of twenty; one counting only bytes says the collection is mostly
;; photographs.  Both are true and neither alone is useful.
;;
;; DOT DIRECTORIES
;; ---------------
;; Excluded from both.  `.snapshots/' holds complete btrfs copies of
;; the tree; counting it reported 728,000 notes across 2.7 GB and
;; turned the growth chart into a chart of snapshot activity.  See the
;; doc string of `my/denote-scan-exclude-regexp' in
;; 27-denote-identifiers.el, which is where that was fixed.
;;
;; CLICKABLE, AND WHY IN BOTH RENDERINGS
;; -------------------------------------
;; A statistic worth reporting is one somebody might act on, and acting
;; on it means opening the notes behind it.  Titles, the first journal
;; entry, the singleton-keyword count and the no-keyword count are all
;; buttons: in the buffer they open a note in a window on the right, and
;; in the exported Org file they are real `denote:' links.
;;
;; The Org export is therefore genuine Org -- headings, tables and
;; links -- not the buffer text wrapped in an `example' block.  An
;; example block would have preserved the bars and lost every link,
;; which is the wrong trade for a file whose point is to be clicked
;; through.  The bars are dropped from the export instead: the number
;; is on the same line, and U+2588 is not a glyph the PDF font can be
;; relied on to have.
;;
;; WHAT IS DELEGATED
;; -----------------
;; denote-explore draws the charts and the link network;
;; 26-maintenance.el finds duplicates, broken links, keyword
;; inventories, and renames or merges a keyword across the collection.
;; None of it is reimplemented.  A dashboard says how many; a
;; drill-down says which; a maintenance command changes it.
;;
;; DEPENDENCIES
;;   27-denote-identifiers.el  `my/denote--all-files' (hard)
;;   26-maintenance.el         `my/maintenance--file-keywords' (hard),
;;                             `my/maintenance-rename-keyword' (soft)
;;   34-appearance.el          shared faces (soft)
;;   35-journal-gaps.el        metrics completeness (soft)
;;   denote-explore            the `e' key (soft)
;;
;; Docs: ~/.emacs.d/function_helper.org::#notes-stats

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'time-date)
(require 'button)

(declare-function my/denote--all-files "27-denote-identifiers" ())
(declare-function my/maintenance--file-keywords "26-maintenance" (file))
(declare-function my/maintenance-rename-keyword "26-maintenance" (&optional k r))
(declare-function my/fixed-tab-goto "01-ui" (name))
(declare-function my/journal-gaps--required-keys "35-journal-gaps" ())
(declare-function my/journal-gaps--missing-keys "35-journal-gaps" (file required))
(declare-function my/org-export-to-pdf "16-org-export" ())

(defgroup my-notes-stats nil
  "Summary statistics for the note collection."
  :group 'convenience)

(defcustom my/notes-stats-buffer-name "*Notes Stats*"
  "Name of the statistics buffer."
  :type 'string :group 'my-notes-stats)

(defcustom my/notes-stats-top-keywords 12
  "How many of the most-used keywords to list."
  :type 'integer :group 'my-notes-stats)

(defcustom my/notes-stats-growth-months 12
  "How many recent months the monthly chart covers."
  :type 'integer :group 'my-notes-stats)

(defcustom my/notes-stats-keyword-exclude-dirs '("inbox")
  "Top-level directories left out of the KEYWORD statistics.

Counts and sizes still include these directories; only the keyword
figures and the two drill-down lists skip them.  The split is
deliberate: size answers \"how much is there\", and a note in the inbox
is there, while the keyword figures answer \"how well is the collection
organised\", and a note in the inbox has not been organised yet.

WHY THE INBOX IN PARTICULAR
---------------------------
A staged note is not part of the system.  Its keywords, title and
identifier are all provisional -- filing it through
25-inbox-review.el may change any of them -- so a keyword that appears
once, in the inbox, is not a keyword used once.  It is a keyword that
has not been decided on.

It is also not reachable.  Denote's own listing excludes the inbox,
so a `denote:' link to a staged note does not resolve, which makes
every entry in the singleton list a dead end.  A list nobody can click
through is worse than no list: it looks like work to be done.

DIFFERENT FROM 26-maintenance.el ON PURPOSE
-------------------------------------------
That module includes the inbox, and its header says why: a keyword
renamed everywhere except there comes back one note at a time as notes
are filed.  For a WRITING command that is right.  For a REPORT it is
the opposite, because the report is a list of things to act on and
those notes cannot be acted on yet."
  :type '(repeat string) :group 'my-notes-stats)

(defcustom my/notes-stats-bar-width 28
  "Width in characters of the longest bar."
  :type 'integer :group 'my-notes-stats)

;; ============================================================
;; FILE-NAME READING
;; ============================================================

(defun my/notes-stats--size (file)
  "Return FILE's size in bytes, or 0 when it has gone away."
  (or (file-attribute-size (file-attributes file)) 0))

(defun my/notes-stats--identifier (file)
  "Return FILE's Denote identifier, or nil."
  (let ((base (file-name-nondirectory file)))
    (when (string-match "\\`\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)" base)
      (match-string 1 base))))

(defun my/notes-stats--year-month (file)
  "Return (YEAR . MONTH) as strings from FILE's identifier, or nil."
  (let ((base (file-name-nondirectory file)))
    (when (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)[0-9]\\{2\\}T" base)
      (cons (match-string 1 base) (match-string 2 base)))))

(defun my/notes-stats--signature (file)
  "Return FILE's Denote signature, or nil.

A signature is what makes a note part of a Folgezettel sequence: the
`==SIGNATURE' field that `denote-sequence' writes between the
identifier and the title.  Its presence is the test for a zettelkasten
note, because that is exactly what 22-zettelkasten.el adds when a
thought is placed in a sequence, and nothing else in the collection
carries one."
  (let ((base (file-name-nondirectory file)))
    (when (string-match "==\\([^-]+\\)--" base)
      (match-string 1 base))))

(defun my/notes-stats--signature-depth (signature)
  "Return the depth of SIGNATURE in the alphanumeric scheme.
`1' is 1, `1a' is 2, `1a1' is 3: each alternation between digits and
letters is one step further from the trunk."
  (let ((depth 0) (index 0))
    (while (string-match "[0-9]+\\|[a-zA-Z]+" signature index)
      (setq depth (1+ depth))
      (setq index (match-end 0)))
    depth))

(defun my/notes-stats--journal-date (file)
  "Return YYYY-MM-DD when FILE is a journal note, else nil."
  (let ((name (file-name-nondirectory file)))
    (when (string-match "--\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)-journal" name)
      (match-string 1 name))))

(defun my/notes-stats--top-directory (file)
  "Return the top-level directory of FILE relative to `my-notes-dir'.
Files sitting directly in the notes root are grouped as \"(root)\"."
  (let* ((root (file-name-as-directory (expand-file-name my-notes-dir)))
         (relative (file-relative-name (expand-file-name file) root))
         (slash (string-search "/" relative)))
    (if slash (substring relative 0 slash) "(root)")))

(defun my/notes-stats--title (file)
  "Return FILE's `#+title:', or its base name.
The only place on the opening screen where a file is read, and it is
read twice: once for the largest note and once for the smallest.  A
file name slug is not a title -- it is lowercased, stripped of
punctuation and truncated -- and the two extremes are the entries most
likely to be opened."
  (with-temp-buffer
    (insert-file-contents file nil 0 500)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+title:[ \t]+\\(.+\\)$" nil t)
        (string-trim (match-string 1))
      (file-name-base file))))

;; ============================================================
;; SMALL FORMATTING HELPERS
;; ============================================================

(defun my/notes-stats--day-number (date)
  "Return DATE (YYYY-MM-DD) as an absolute day number."
  (time-to-days
   (encode-time (list 0 0 12
                      (string-to-number (substring date 8 10))
                      (string-to-number (substring date 5 7))
                      (string-to-number (substring date 0 4))
                      nil -1 nil))))

(defun my/notes-stats--percent (part whole)
  "Return PART of WHOLE as a percentage string, or a dash when WHOLE is 0."
  (if (zerop whole) "-" (format "%.1f%%" (/ (* 100.0 part) whole))))

(defun my/notes-stats--bar (value maximum)
  "Return a bar of block characters for VALUE scaled against MAXIMUM."
  (if (or (zerop maximum) (zerop value))
      ""
    (make-string (max 1 (round (* my/notes-stats-bar-width
                                 (/ (float value) maximum))))
                 ?\u2588)))

(defun my/notes-stats--face (name fallback)
  "Return face NAME when it is defined, else FALLBACK."
  (if (facep name) name fallback))

;; ============================================================
;; COLLECTING
;; ============================================================
;; One pass, one plist.  Both renderers read this and neither computes
;; anything of its own, so the buffer and the exported file cannot
;; disagree about a number -- which is the failure that makes an
;; exported report worse than no report.

(defun my/notes-stats--require ()
  "Signal unless the modules this one measures with are loaded."
  (unless (fboundp 'my/denote--all-files)
    (user-error "27-denote-identifiers.el is not loaded"))
  (unless (fboundp 'my/maintenance--file-keywords)
    (user-error "26-maintenance.el is not loaded")))

(defun my/notes-stats--disk-rows ()
  "Return (NAME COUNT BYTES) for each top-level entry under `my-notes-dir'.
Every file, whatever its extension.  Dot directories skipped."
  (let ((root (expand-file-name my-notes-dir))
        rows)
    (dolist (entry (directory-files root t) (nreverse rows))
      (let ((name (file-name-nondirectory entry)))
        (unless (string-prefix-p "." name)
          (if (file-directory-p entry)
              (let ((count 0) (bytes 0))
                (dolist (file (directory-files-recursively
                               entry ".*" nil
                               (lambda (dir)
                                 (not (string-prefix-p
                                       "." (file-name-nondirectory
                                            (directory-file-name dir)))))))
                  (setq count (1+ count))
                  (setq bytes (+ bytes (my/notes-stats--size file))))
                (push (list name count bytes) rows))
            (push (list name 1 (my/notes-stats--size entry)) rows)))))))

(defun my/notes-stats--collect ()
  "Gather every figure the report shows.  Returns a plist."
  (my/notes-stats--require)
  (let* ((files (my/denote--all-files))
         (total (length files))
         (sizes (make-hash-table :test #'equal))
         (dirs (make-hash-table :test #'equal))
         (keywords (make-hash-table :test #'equal))
         (keyword-files (make-hash-table :test #'equal))
         (months (make-hash-table :test #'equal))
         (years (make-hash-table :test #'equal))
         (journal (make-hash-table :test #'equal))
         (bytes 0) (largest nil) (smallest nil) (keyword-total 0)
         (bare nil) (zettel nil))
    (dolist (file files)
      (let ((size (my/notes-stats--size file)))
        (puthash file size sizes)
        (setq bytes (+ bytes size))
        (when (or (null largest) (> size (gethash largest sizes 0)))
          (setq largest file))
        (when (or (null smallest) (< size (gethash smallest sizes 0)))
          (setq smallest file)))
      ;; Directory grouping.  Named rows rather than one "other": a row
      ;; called `inbox' with 443 notes says something; a row called
      ;; `other' with 443 notes says only that the code did not look.
      (let* ((dir (my/notes-stats--top-directory file))
             (row (or (gethash dir dirs) (puthash dir (list 0 0) dirs))))
        (setf (nth 0 row) (1+ (nth 0 row)))
        (setf (nth 1 row) (+ (nth 1 row) (gethash file sizes 0))))
      ;; Keyword statistics skip the excluded directories; every other
      ;; figure in this loop counts the file.  See
      ;; `my/notes-stats-keyword-exclude-dirs'.
      (unless (member (my/notes-stats--top-directory file)
                      my/notes-stats-keyword-exclude-dirs)
        (setq keyword-total (1+ keyword-total))
        (let ((keys (my/maintenance--file-keywords file)))
          (if (null keys)
              (push file bare)
            (dolist (key keys)
              (puthash key (1+ (gethash key keywords 0)) keywords)
              (push file (gethash key keyword-files nil))))))
      (when-let* ((ym (my/notes-stats--year-month file)))
        (puthash (concat (car ym) "-" (cdr ym))
                 (1+ (gethash (concat (car ym) "-" (cdr ym)) months 0)) months)
        (puthash (car ym) (1+ (gethash (car ym) years 0)) years))
      (when-let* ((date (my/notes-stats--journal-date file)))
        (unless (gethash date journal) (puthash date file journal)))
      (when-let* ((signature (my/notes-stats--signature file)))
        (push (cons file signature) zettel)))
    (list :files files :total total :sizes sizes :bytes bytes
          :dirs dirs :keywords keywords :keyword-files keyword-files
          :keyword-total keyword-total
          :months months :years years :journal journal
          :largest largest :smallest smallest
          :bare (nreverse bare) :zettel (nreverse zettel))))

(defun my/notes-stats--singletons (data)
  "Return an alist of (KEYWORD . FILE) for keywords used by exactly one note."
  (let ((keywords (plist-get data :keywords))
        (keyword-files (plist-get data :keyword-files))
        acc)
    (maphash (lambda (key count)
               (when (= count 1)
                 (push (cons key (car (gethash key keyword-files))) acc)))
             keywords)
    (sort acc (lambda (a b) (string< (car a) (car b))))))

(defun my/notes-stats--streaks (days)
  "Return (LONGEST . CURRENT) for the sorted date list DAYS.
CURRENT tolerates today itself being absent: a streak intact up to
yesterday is still a streak at nine in the morning."
  (if (null days)
      (cons 0 0)
    (let* ((numbers (mapcar #'my/notes-stats--day-number days))
           (today (time-to-days (current-time)))
           (longest 1) (run 1) (previous (car numbers)))
      (dolist (n (cdr numbers))
        (setq run (if (= n (1+ previous)) (1+ run) 1))
        (setq longest (max longest run))
        (setq previous n))
      (let ((current 0) (expected (if (memq today numbers) today (1- today))))
        (while (memq expected numbers)
          (setq current (1+ current))
          (setq expected (1- expected)))
        (cons longest current)))))

;; ============================================================
;; TIER TWO
;; ============================================================

(defvar-local my/notes-stats--deep nil
  "Cached plist from `my/notes-stats-compute-deep', or nil.")

(defun my/notes-stats--deep-scan (files)
  "Read every file in FILES and return a plist of content statistics."
  (let ((words 0) (links 0) (no-links 0)
        (targets (make-hash-table :test #'equal))
        (identifiers (make-hash-table :test #'equal))
        (reporter (make-progress-reporter "Reading notes... " 0 (length files)))
        (index 0))
    (dolist (file files)
      (progress-reporter-update reporter (setq index (1+ index)))
      (when-let* ((id (my/notes-stats--identifier file)))
        (puthash id file identifiers))
      (with-temp-buffer
        (insert-file-contents file)
        (setq words (+ words (count-words (point-min) (point-max))))
        (goto-char (point-min))
        (let ((here 0))
          (while (re-search-forward "denote:\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)" nil t)
            (setq here (1+ here))
            (puthash (match-string 1) t targets))
          (setq links (+ links here))
          (when (zerop here) (setq no-links (1+ no-links))))))
    (progress-reporter-done reporter)
    ;; An orphan is a note nothing links TO.  Distinct from a note that
    ;; links to nothing: a reference note may legitimately have no
    ;; outgoing links, while a note nothing points at is one nothing
    ;; will ever lead you back to.
    (let ((orphans 0))
      (maphash (lambda (id _file)
                 (unless (gethash id targets) (setq orphans (1+ orphans))))
               identifiers)
      (list :words words :links links :no-links no-links :orphans orphans))))

;; ============================================================
;; OPENING NOTES FROM THE REPORT
;; ============================================================

(defvar-local my/notes-stats--preview-window nil
  "Window this report reuses for the notes opened from it.")

(defun my/notes-stats--visit (file)
  "Show FILE in the window to the right of the report.
The window is created on the first visit and reused afterwards, so
clicking through twenty singleton keywords does not leave twenty
windows.  Point stays in the report: the report is the thing being
worked through, and the note is what is being looked at."
  (let ((buffer (find-file-noselect file))
        (origin (selected-window)))
    (unless (window-live-p my/notes-stats--preview-window)
      (setq my/notes-stats--preview-window
            (split-window origin nil 'right)))
    (set-window-buffer my/notes-stats--preview-window buffer)
    (select-window origin)))

(defun my/notes-stats--note-button (file label)
  "Insert LABEL as a button visiting FILE."
  (insert-text-button
   label
   'face (my/notes-stats--face 'my/dashboard-note 'link)
   'help-echo (abbreviate-file-name file)
   'follow-link t
   'action (let ((target file)
                 (report (current-buffer)))
             (lambda (_button)
               (with-current-buffer report
                 (my/notes-stats--visit target))))))

(defun my/notes-stats--list-button (label opener)
  "Insert LABEL as a button running OPENER, a function of no arguments."
  (insert-text-button
   label
   'face (my/notes-stats--face 'my/dashboard-tag-button 'link)
   'follow-link t
   'action (lambda (_button) (funcall opener))))

;; ============================================================
;; DRILL-DOWN BUFFERS
;; ============================================================

(defun my/notes-stats-rename-keyword ()
  "Run `my/maintenance-rename-keyword', for merging a singleton away."
  (interactive)
  (if (fboundp 'my/maintenance-rename-keyword)
      (call-interactively #'my/maintenance-rename-keyword)
    (user-error "26-maintenance.el is not loaded")))

;; ============================================================
;; BUFFER RENDERING
;; ============================================================


(defvar my/notes-stats-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "r") #'my/notes-stats-rename-keyword)
    (define-key map (kbd "n") #'forward-button)
    (define-key map (kbd "p") #'backward-button)
    map)
  "Keymap for `my/notes-stats-list-mode'.")

(define-derived-mode my/notes-stats-list-mode special-mode "Stats List"
  "Major mode for the drill-down lists opened from the statistics report.
\\{my/notes-stats-list-mode-map}"
  (setq-local truncate-lines t)
  (when (bound-and-true-p visual-fill-column-mode)
    (visual-fill-column-mode -1)))

(defun my/notes-stats--show-list (name intro entries)
  "Display ENTRIES in a buffer called NAME under the heading INTRO.
ENTRIES is a list of (HEADING . FILE); HEADING is shown as text and
FILE, when non-nil, as a button beneath it."
  (let ((report (current-buffer))
        (buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/notes-stats-list-mode)
        (setq my/notes-stats--preview-window
              (buffer-local-value 'my/notes-stats--preview-window report))
        (insert (propertize (concat "  " intro "\n\n")
                            'face (my/notes-stats--face 'my/dashboard-title 'bold)))
        (dolist (entry entries)
          (insert "  " (propertize (car entry) 'face
                                   (my/notes-stats--face 'my/dashboard-section 'bold))
                  "\n")
          (when (cdr entry)
            (insert "      ")
            (my/notes-stats--note-button (cdr entry)
                                         (my/notes-stats--title (cdr entry)))
            (insert "\n")))
        (goto-char (point-min))))
    (switch-to-buffer buffer)))

(defun my/notes-stats-show-singletons ()
  "List keywords used by exactly one note, each with a link to it.

A singleton is usually a near-duplicate of a keyword that is in real
use -- `filozofia' beside `filozofie' -- or a one-off that was never
going to become a category.  Either way the fix is
`my/maintenance-rename-keyword' (26-maintenance.el), which merges one
keyword into another or removes it across the collection; `r' here
calls it."
  (interactive)
  (let ((singletons (my/notes-stats--singletons (my/notes-stats--collect))))
    (my/notes-stats--show-list
     "*Singleton Keywords*"
     (format "%d keywords used by exactly one note%s   --   r to merge or remove one"
             (length singletons)
             (if my/notes-stats-keyword-exclude-dirs
                 (format " (%s excluded)"
                         (string-join my/notes-stats-keyword-exclude-dirs ", "))
               ""))
     (mapcar (lambda (pair) (cons (concat ":" (car pair) ":") (cdr pair)))
             singletons))))

(defun my/notes-stats-show-bare ()
  "List notes carrying no keywords at all."
  (interactive)
  (let ((bare (plist-get (my/notes-stats--collect) :bare)))
    (my/notes-stats--show-list
     "*Notes Without Keywords*"
     (format "%d notes with no keywords%s" (length bare)
             (if my/notes-stats-keyword-exclude-dirs
                 (format " (%s excluded)"
                         (string-join my/notes-stats-keyword-exclude-dirs ", "))
               ""))
     (mapcar (lambda (file) (cons (my/notes-stats--top-directory file) file))
             bare))))

(defun my/notes-stats--heading (text)
  "Insert TEXT as a section heading."
  (insert "\n" (propertize text 'face
                           (my/notes-stats--face 'my/dashboard-section 'bold))
          "\n\n"))

(defun my/notes-stats--line (label value &optional note)
  "Insert LABEL, VALUE and an optional dim NOTE."
  (insert (format "  %-28s %s" label value))
  (when note
    (insert "  " (propertize note 'face
                             (my/notes-stats--face 'my/dashboard-hint 'shadow))))
  (insert "\n"))

(defun my/notes-stats--dim (text)
  "Return TEXT in the hint face."
  (propertize text 'face (my/notes-stats--face 'my/dashboard-hint 'shadow)))

(defun my/notes-stats--render (data)
  "Draw the report for DATA into the current buffer."
  (let* ((inhibit-read-only t)
         (total (plist-get data :total))
         (bytes (plist-get data :bytes))
         (sizes (plist-get data :sizes))
         (keywords (plist-get data :keywords))
         (journal (plist-get data :journal))
         (journal-days (sort (hash-table-keys journal) #'string<)))
    (erase-buffer)
    (insert (propertize "  Notes Statistics\n"
                        'face (my/notes-stats--face 'my/dashboard-title 'bold)))
    (insert (my/notes-stats--dim (format "  %s\n" (format-time-string "%Y-%m-%d %H:%M"))))

    ;; -- Collection --------------------------------------------
    (my/notes-stats--heading "Collection")
    (my/notes-stats--line "Notes" (number-to-string total))
    (my/notes-stats--line "Total size" (file-size-human-readable bytes))
    (my/notes-stats--line "Average note"
                          (if (zerop total) "-"
                            (file-size-human-readable (/ bytes total))))
    (dolist (pair (list (cons "Largest note" (plist-get data :largest))
                        (cons "Smallest note" (plist-get data :smallest))))
      (when (cdr pair)
        (insert (format "  %-28s %s  " (car pair)
                        (file-size-human-readable (gethash (cdr pair) sizes 0))))
        (my/notes-stats--note-button (cdr pair) (my/notes-stats--title (cdr pair)))
        (insert "\n")))

    ;; -- Notes by directory ------------------------------------
    (my/notes-stats--heading "Notes by directory")
    (let ((rows (let (acc)
                  (maphash (lambda (dir row) (push (cons dir row) acc))
                           (plist-get data :dirs))
                  (sort acc (lambda (a b) (> (nth 0 (cdr a)) (nth 0 (cdr b))))))))
      (dolist (row rows)
        (my/notes-stats--line
         (car row)
         (format "%5d notes   %9s" (nth 0 (cdr row))
                 (file-size-human-readable (nth 1 (cdr row))))
         (format "%s of notes, %s of size"
                 (my/notes-stats--percent (nth 0 (cdr row)) total)
                 (my/notes-stats--percent (nth 1 (cdr row)) bytes)))))

    ;; -- On disk -----------------------------------------------
    (my/notes-stats--heading "On disk (all file types)")
    (let* ((rows (my/notes-stats--disk-rows))
           (disk (let ((sum 0)) (dolist (r rows sum) (setq sum (+ sum (nth 2 r)))))))
      (dolist (row rows)
        (my/notes-stats--line
         (nth 0 row)
         (format "%6d files   %9s" (nth 1 row)
                 (file-size-human-readable (nth 2 row)))
         (my/notes-stats--percent (nth 2 row) disk)))
      (my/notes-stats--line "TOTAL ON DISK" (file-size-human-readable disk)
                            "dot directories excluded"))

    ;; -- Zettelkasten ------------------------------------------
    (my/notes-stats--heading "Zettelkasten")
    (let ((zettel (plist-get data :zettel)))
      (if (null zettel)
          (my/notes-stats--line "Sequenced notes" "none"
                                "a signature is added only when a thought joins a sequence")
        (let* ((depths (mapcar (lambda (z) (my/notes-stats--signature-depth (cdr z)))
                               zettel))
               (trunks (seq-uniq
                        (mapcar (lambda (z)
                                  (if (string-match "\\`[0-9]+" (cdr z))
                                      (match-string 0 (cdr z))
                                    (cdr z)))
                                zettel))))
          (my/notes-stats--line "Sequenced notes" (number-to-string (length zettel))
                                (format "%s of all notes"
                                        (my/notes-stats--percent (length zettel) total)))
          (my/notes-stats--line "Top-level sequences" (number-to-string (length trunks)))
          (my/notes-stats--line "Deepest signature"
                                (format "%d levels" (apply #'max depths)))
          (my/notes-stats--line "Average depth"
                                (format "%.2f" (/ (float (apply #'+ 0 depths))
                                                  (length depths)))))))

    ;; -- Journal -----------------------------------------------
    (my/notes-stats--heading "Journal")
    (if (null journal-days)
        (my/notes-stats--line "Entries" "none found")
      (let* ((first-day (car journal-days))
             (elapsed (1+ (- (time-to-days (current-time))
                             (my/notes-stats--day-number first-day))))
             (covered (length journal-days))
             (streaks (my/notes-stats--streaks journal-days)))
        (insert (format "  %-28s %s  " "First entry" first-day))
        (my/notes-stats--note-button (gethash first-day journal)
                                     (my/notes-stats--title (gethash first-day journal)))
        (insert "\n")
        (my/notes-stats--line "Days since" (number-to-string elapsed))
        (my/notes-stats--line "Days with an entry" (number-to-string covered)
                              (format "coverage %s"
                                      (my/notes-stats--percent covered elapsed)))
        (my/notes-stats--line "Days without one"
                              (number-to-string (- elapsed covered)))
        (my/notes-stats--line "Longest streak" (format "%d days" (car streaks)))
        (my/notes-stats--line "Current streak" (format "%d days" (cdr streaks)))
        (when (and (fboundp 'my/journal-gaps--required-keys)
                   (fboundp 'my/journal-gaps--missing-keys))
          (let* ((required (my/journal-gaps--required-keys))
                 (cutoff (- (time-to-days (current-time)) 365))
                 (recent (seq-filter
                          (lambda (d) (> (my/notes-stats--day-number d) cutoff))
                          journal-days))
                 (incomplete 0))
            (when required
              (dolist (day recent)
                (when (my/journal-gaps--missing-keys (gethash day journal) required)
                  (setq incomplete (1+ incomplete))))
              (my/notes-stats--line "Missing metrics"
                                    (format "%d of %d" incomplete (length recent))
                                    "last 365 days -- C-c n f j to fix"))))))

    ;; -- Keywords ----------------------------------------------
    (my/notes-stats--heading
     (if my/notes-stats-keyword-exclude-dirs
         (format "Keywords (%s excluded)"
                 (string-join my/notes-stats-keyword-exclude-dirs ", "))
       "Keywords"))
    (let* ((distinct (hash-table-count keywords))
           (counted (plist-get data :keyword-total))
           (assignments (let ((sum 0))
                          (maphash (lambda (_k v) (setq sum (+ sum v))) keywords)
                          sum))
           (singletons (length (my/notes-stats--singletons data)))
           (bare (length (plist-get data :bare)))
           (pairs (let (acc)
                    (maphash (lambda (k v) (push (cons k v) acc)) keywords)
                    (sort acc (lambda (a b) (> (cdr a) (cdr b)))))))
      (my/notes-stats--line "Notes counted" (number-to-string counted)
                            (format "of %d; %d staged and not yet organised"
                                    total (- total counted)))
      (my/notes-stats--line "Distinct keywords" (number-to-string distinct))
      (my/notes-stats--line "Assignments" (number-to-string assignments)
                            (format "%.2f per note"
                                    (if (zerop counted) 0.0
                                      (/ (float assignments) counted))))
      (insert (format "  %-28s " "Used once only"))
      (my/notes-stats--list-button (number-to-string singletons)
                                   #'my/notes-stats-show-singletons)
      (insert "  " (my/notes-stats--dim "click to list and merge") "\n")
      (insert (format "  %-28s " "Notes with no keywords"))
      (my/notes-stats--list-button (number-to-string bare)
                                   #'my/notes-stats-show-bare)
      (insert "  " (my/notes-stats--dim "click to list") "\n\n")
      (let ((maximum (cdar pairs)))
        (dolist (pair (seq-take pairs my/notes-stats-top-keywords))
          (insert (format "  %-22s %5d  %s\n" (car pair) (cdr pair)
                          (my/notes-stats--bar (cdr pair) maximum))))))

    ;; -- Growth ------------------------------------------------
    (my/notes-stats--heading
     (format "Notes created, last %d months" my/notes-stats-growth-months))
    (let* ((months (plist-get data :months))
           (keys (sort (hash-table-keys months) #'string<))
           (recent (last keys my/notes-stats-growth-months))
           (maximum (apply #'max 1 (mapcar (lambda (m) (gethash m months)) recent))))
      (dolist (month recent)
        (insert (format "  %-10s %5d  %s\n" month (gethash month months)
                        (my/notes-stats--bar (gethash month months) maximum))))
      (when keys
        (let ((busiest (car (sort (copy-sequence keys)
                                  (lambda (a b) (> (gethash a months)
                                                   (gethash b months)))))))
          (insert "\n")
          (my/notes-stats--line "Busiest month ever"
                                (format "%s (%d)" busiest (gethash busiest months))))))

    ;; -- Per year ----------------------------------------------
    (my/notes-stats--heading "Notes created, per year")
    (let* ((years (plist-get data :years))
           (keys (sort (hash-table-keys years) #'string<))
           (maximum (apply #'max 1 (mapcar (lambda (y) (gethash y years)) keys))))
      (dolist (year keys)
        (insert (format "  %-10s %5d  %s\n" year (gethash year years)
                        (my/notes-stats--bar (gethash year years) maximum)))))

    ;; -- Content -----------------------------------------------
    (my/notes-stats--heading "Content")
    (if (null my/notes-stats--deep)
        (my/notes-stats--line "Not computed" "press c"
                              "reads every note; a few seconds")
      (let ((deep my/notes-stats--deep))
        (my/notes-stats--line "Words" (number-to-string (plist-get deep :words))
                              (format "%d per note"
                                      (if (zerop total) 0 (/ (plist-get deep :words) total))))
        (my/notes-stats--line "Denote links" (number-to-string (plist-get deep :links))
                              (format "%.2f per note"
                                      (if (zerop total) 0.0
                                        (/ (float (plist-get deep :links)) total))))
        (my/notes-stats--line "Link to nothing"
                              (number-to-string (plist-get deep :no-links))
                              "no outgoing denote: link")
        (my/notes-stats--line "Nothing links to"
                              (number-to-string (plist-get deep :orphans))
                              "unreachable by following links")))

    (insert "\n" (my/notes-stats--dim
                  "  g refresh   c content   e denote-explore   x export   q quit\n"))
    (goto-char (point-min))))

;; ============================================================
;; ORG RENDERING
;; ============================================================

(defun my/notes-stats--org-link (file)
  "Return FILE as a `denote:' link with its title, or a plain title."
  (let ((title (my/notes-stats--title file))
        (id (my/notes-stats--identifier file)))
    (if id (format "[[denote:%s][%s]]" id title) title)))

(defun my/notes-stats--render-org (data)
  "Insert DATA as Org markup into the current buffer.

Real Org -- headings, tables and `denote:' links -- rather than the
report buffer wrapped in an `example' block.  The block would have
preserved the bars and lost every link, which is the wrong trade for a
file whose point is to be clicked through.  The bars are dropped
instead: the number is on the same line, and U+2588 is not a glyph the
PDF font can be relied on to have."
  (let* ((total (plist-get data :total))
         (bytes (plist-get data :bytes))
         (sizes (plist-get data :sizes))
         (keywords (plist-get data :keywords))
         (journal (plist-get data :journal))
         (journal-days (sort (hash-table-keys journal) #'string<)))
    (insert "#+title:      Notes statistics " (format-time-string "%Y-%m-%d") "\n"
            "#+date:       " (format-time-string "[%Y-%m-%d %a %H:%M]") "\n"
            "#+filetags:   :docu:stats:\n"
            "#+language:   en\n"
            "#+options:    toc:t num:nil\n\n")

    (insert "* Collection\n\n")
    (insert "| Measure | Value |\n|---|---|\n")
    (insert (format "| Notes | %d |\n" total))
    (insert (format "| Total size | %s |\n" (file-size-human-readable bytes)))
    (insert (format "| Average note | %s |\n"
                    (if (zerop total) "-" (file-size-human-readable (/ bytes total)))))
    (dolist (pair (list (cons "Largest" (plist-get data :largest))
                        (cons "Smallest" (plist-get data :smallest))))
      (when (cdr pair)
        (insert (format "| %s note | %s -- %s |\n" (car pair)
                        (file-size-human-readable (gethash (cdr pair) sizes 0))
                        (my/notes-stats--org-link (cdr pair))))))

    (insert "\n* Notes by directory\n\n| Directory | Notes | Size | Share |\n|---|---|---|---|\n")
    (let ((rows (let (acc)
                  (maphash (lambda (dir row) (push (cons dir row) acc))
                           (plist-get data :dirs))
                  (sort acc (lambda (a b) (> (nth 0 (cdr a)) (nth 0 (cdr b))))))))
      (dolist (row rows)
        (insert (format "| %s | %d | %s | %s |\n" (car row) (nth 0 (cdr row))
                        (file-size-human-readable (nth 1 (cdr row)))
                        (my/notes-stats--percent (nth 0 (cdr row)) total)))))

    (insert "\n* On disk\n\n| Entry | Files | Size |\n|---|---|---|\n")
    (dolist (row (my/notes-stats--disk-rows))
      (insert (format "| %s | %d | %s |\n" (nth 0 row) (nth 1 row)
                      (file-size-human-readable (nth 2 row)))))

    (let ((zettel (plist-get data :zettel)))
      (insert "\n* Zettelkasten\n\n")
      (if (null zettel)
          (insert "No sequenced notes.\n")
        (let ((depths (mapcar (lambda (z) (my/notes-stats--signature-depth (cdr z)))
                              zettel)))
          (insert "| Measure | Value |\n|---|---|\n")
          (insert (format "| Sequenced notes | %d (%s of all) |\n"
                          (length zettel)
                          (my/notes-stats--percent (length zettel) total)))
          (insert (format "| Deepest signature | %d levels |\n" (apply #'max depths)))
          (insert (format "| Average depth | %.2f |\n"
                          (/ (float (apply #'+ 0 depths)) (length depths)))))))

    (insert "\n* Journal\n\n")
    (if (null journal-days)
        (insert "No journal notes found.\n")
      (let* ((first-day (car journal-days))
             (elapsed (1+ (- (time-to-days (current-time))
                             (my/notes-stats--day-number first-day))))
             (covered (length journal-days))
             (streaks (my/notes-stats--streaks journal-days)))
        (insert "| Measure | Value |\n|---|---|\n")
        (insert (format "| First entry | %s -- %s |\n" first-day
                        (my/notes-stats--org-link (gethash first-day journal))))
        (insert (format "| Days since | %d |\n" elapsed))
        (insert (format "| Days with an entry | %d (%s) |\n" covered
                        (my/notes-stats--percent covered elapsed)))
        (insert (format "| Days without one | %d |\n" (- elapsed covered)))
        (insert (format "| Longest streak | %d days |\n" (car streaks)))
        (insert (format "| Current streak | %d days |\n" (cdr streaks)))))

    (insert "\n* Keywords\n\n")
    (when my/notes-stats-keyword-exclude-dirs
      (insert (format "Notes in %s are excluded: a staged note is not part of the\ncollection yet, its keywords are provisional, and a =denote:= link to\nit does not resolve.\n\n"
                      (string-join my/notes-stats-keyword-exclude-dirs ", "))))
    (let* ((counted (plist-get data :keyword-total))
           (assignments (let ((sum 0))
                          (maphash (lambda (_k v) (setq sum (+ sum v))) keywords)
                          sum))
           (singletons (my/notes-stats--singletons data))
           (bare (plist-get data :bare))
           (pairs (let (acc)
                    (maphash (lambda (k v) (push (cons k v) acc)) keywords)
                    (sort acc (lambda (a b) (> (cdr a) (cdr b)))))))
      (insert "| Measure | Value |\n|---|---|\n")
      (insert (format "| Notes counted | %d of %d |\n" counted total))
      (insert (format "| Distinct keywords | %d |\n" (hash-table-count keywords)))
      (insert (format "| Assignments | %d |\n" assignments))
      (insert (format "| Used once only | %d |\n" (length singletons)))
      (insert (format "| Notes with no keywords | %d |\n" (length bare)))
      (insert "\n** Most used\n\n| Keyword | Notes |\n|---|---|\n")
      (dolist (pair (seq-take pairs my/notes-stats-top-keywords))
        (insert (format "| %s | %d |\n" (car pair) (cdr pair))))
      (insert "\n** Used once only\n\n")
      (if (null singletons)
          (insert "None.\n")
        (dolist (pair singletons)
          (insert (format "- =%s= -- %s\n" (car pair)
                          (my/notes-stats--org-link (cdr pair))))))
      (insert "\n** Notes with no keywords\n\n")
      (if (null bare)
          (insert "None.\n")
        (dolist (file bare)
          (insert (format "- %s\n" (my/notes-stats--org-link file))))))

    (insert "\n* Notes created\n\n** Per year\n\n| Year | Notes |\n|---|---|\n")
    (let* ((years (plist-get data :years))
           (keys (sort (hash-table-keys years) #'string<)))
      (dolist (year keys)
        (insert (format "| %s | %d |\n" year (gethash year years)))))
    (insert "\n** Per month, last "
            (number-to-string my/notes-stats-growth-months)
            "\n\n| Month | Notes |\n|---|---|\n")
    (let* ((months (plist-get data :months))
           (keys (sort (hash-table-keys months) #'string<)))
      (dolist (month (last keys my/notes-stats-growth-months))
        (insert (format "| %s | %d |\n" month (gethash month months)))))

    (when my/notes-stats--deep
      (let ((deep my/notes-stats--deep))
        (insert "\n* Content\n\n| Measure | Value |\n|---|---|\n")
        (insert (format "| Words | %d |\n" (plist-get deep :words)))
        (insert (format "| Denote links | %d |\n" (plist-get deep :links)))
        (insert (format "| Link to nothing | %d |\n" (plist-get deep :no-links)))
        (insert (format "| Nothing links to | %d |\n" (plist-get deep :orphans)))))))

;; ============================================================
;; COMMANDS
;; ============================================================

(defun my/notes-stats-refresh ()
  "Rebuild the report, keeping any computed content figures."
  (interactive)
  (my/notes-stats--render (my/notes-stats--collect)))

(defun my/notes-stats-compute-deep ()
  "Read every note and add word, link and orphan counts to the report."
  (interactive)
  (my/notes-stats--require)
  (setq my/notes-stats--deep (my/notes-stats--deep-scan (my/denote--all-files)))
  (my/notes-stats-refresh))

(defun my/notes-stats-explore ()
  "Run one of the `denote-explore-' commands, chosen by completion.
Built from the obarray rather than a hardcoded list, so a command
renamed or added upstream appears without this file changing."
  (interactive)
  (unless (require 'denote-explore nil t)
    (user-error "denote-explore is not available"))
  (let ((commands (let (acc)
                    (mapatoms (lambda (symbol)
                                (when (and (commandp symbol)
                                           (string-prefix-p "denote-explore-"
                                                            (symbol-name symbol)))
                                  (push (symbol-name symbol) acc))))
                    (sort acc #'string<))))
    (call-interactively (intern (completing-read "denote-explore: " commands nil t)))))

(defun my/notes-stats-export ()
  "Write the report to an Org file with working links, and open it.
From the opened file, `C-c p' (`my/org-export-to-pdf') produces the
PDF.  The two steps stay separate because that command has its own
rules about where a PDF goes and which font it uses, and duplicating
them here would be a second place to keep them right."
  (interactive)
  (let* ((deep my/notes-stats--deep)
         (default (expand-file-name
                   (format "notes-stats-%s.org" (format-time-string "%Y-%m-%d"))
                   (if (boundp 'my-notes-docu) my-notes-docu "~/")))
         (target (read-file-name "Write report to: " nil default nil
                                 (file-name-nondirectory default)))
         (data (my/notes-stats--collect)))
    (with-temp-file target
      ;; The renderer reads `my/notes-stats--deep', which is buffer-local
      ;; to the report; carry it into the temp buffer or the Content
      ;; section silently disappears from an export made right after
      ;; pressing `c'.
      (setq-local my/notes-stats--deep deep)
      (my/notes-stats--render-org data))
    (find-file target)
    (message "Written.  C-c p exports it to PDF")))

(defvar my/notes-stats-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'my/notes-stats-refresh)
    (define-key map (kbd "c") #'my/notes-stats-compute-deep)
    (define-key map (kbd "e") #'my/notes-stats-explore)
    (define-key map (kbd "x") #'my/notes-stats-export)
    (define-key map (kbd "n") #'forward-button)
    (define-key map (kbd "p") #'backward-button)
    map)
  "Keymap for `my/notes-stats-mode'.")

(define-derived-mode my/notes-stats-mode special-mode "Notes Stats"
  "Major mode for the note statistics report.
\\{my/notes-stats-mode-map}"
  (setq-local truncate-lines t)
  ;; A centred text column would push the bars off the right edge.
  (when (bound-and-true-p visual-fill-column-mode)
    (visual-fill-column-mode -1)))

;;;###autoload
(defun my/notes-stats ()
  "Show summary statistics for the note collection.

Titles, the first journal entry and the two keyword counts are
buttons: clicking opens the note, or the list, in a window on the
right.  `c' adds word, link and orphan counts.  `e' runs a
denote-explore command.  `x' writes the whole thing to an Org file
with working `denote:' links."
  (interactive)
  (my/notes-stats--require)
  (let ((buffer (get-buffer-create my/notes-stats-buffer-name)))
    (with-current-buffer buffer
      (my/notes-stats-mode)
      (my/notes-stats--render (my/notes-stats--collect)))
    (when (and (fboundp 'my/fixed-tab-goto)
               (boundp 'my/dashboards-tab-name))
      (my/fixed-tab-goto my/dashboards-tab-name))
    (switch-to-buffer buffer)
    (delete-other-windows)))

;; ============================================================
;; MENU
;; ============================================================

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-find-menu "t"
                         '("s" "Statistics" my/notes-stats))))

(global-set-key (kbd "C-c w s") #'my/notes-stats)

(provide '36-notes-stats)
;;; 36-notes-stats.el ends here
