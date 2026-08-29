;;; 36-notes-stats.el --- Summary statistics for the collection -*- lexical-binding: t; -*-
;;; Commentary:
;; One screen answering "how big is this thing, and is it healthy".
;;
;; TWO TIERS, AND WHY THE SPLIT MATTERS
;; ------------------------------------
;; Everything shown when the buffer opens is computed from FILE NAMES
;; and `file-attributes' alone.  Not one note is read.  That is
;; possible because Denote puts the date, the title and the keywords in
;; the name, so counts, sizes, keyword frequencies, growth per month
;; and the whole journal-coverage section are already there for the
;; taking.  It costs one `directory-files-recursively' and returns in
;; well under a second on three thousand notes.
;;
;; The second tier -- word counts, links, orphans -- has to open every
;; file.  It runs only on `c', shows a progress reporter, and caches
;; its result until asked again.  Keeping it off the opening path is
;; what makes the dashboard something to glance at rather than
;; something to wait for.
;;
;; WHAT IS DELEGATED, AND WHAT IS NOT
;; ----------------------------------
;; denote-explore already draws keyword bar charts, a link network and
;; lists of isolated notes, and 26-maintenance.el already finds
;; duplicates, broken links and keyword inventories.  None of that is
;; reimplemented here.  This buffer reports the NUMBER and offers `e',
;; which lists every `denote-explore-' command actually present and
;; runs the chosen one -- built by completion over the obarray rather
;; than from a hardcoded list, so it cannot go stale when the package
;; renames something.
;;
;; The division: a dashboard says how many, a drill-down says which.
;;
;; ON THE NUMBERS THAT ARE MEANT TO LOOK BAD
;; -----------------------------------------
;; Singleton keywords, notes with no keywords, orphans and journal
;; coverage are all reported because they are the ones worth acting on.
;; A statistic nobody would ever change their behaviour over is a
;; statistic not worth computing.
;;
;; DEPENDENCIES
;;   27-denote-identifiers.el  `my/denote--all-files' (hard: without it
;;                             there is no collection to measure)
;;   26-maintenance.el         `my/maintenance--file-keywords' (hard,
;;                             same reason -- the keyword field is
;;                             parsed there and must be parsed once)
;;   34-appearance.el          shared faces (soft: an undefined face
;;                             renders as `default')
;;   35-journal-gaps.el        metrics completeness (soft: that line is
;;                             omitted)
;;   denote-explore            the `e' key (soft)
;;
;; Docs: ~/.emacs.d/function_helper.org::#notes-stats

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'time-date)

(declare-function my/denote--all-files "27-denote-identifiers" ())
(declare-function my/maintenance--file-keywords "26-maintenance" (file))
(declare-function my/fixed-tab-goto "01-ui" (name))
(declare-function my/journal-gaps--required-keys "35-journal-gaps" ())
(declare-function my/journal-gaps--missing-keys "35-journal-gaps" (file required))

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
  "How many recent months the growth chart covers."
  :type 'integer :group 'my-notes-stats)

(defcustom my/notes-stats-bar-width 28
  "Width in characters of the longest bar in the growth chart."
  :type 'integer :group 'my-notes-stats)

;; ============================================================
;; SMALL HELPERS
;; ============================================================

(defun my/notes-stats--require ()
  "Signal unless the modules this one measures with are loaded."
  (unless (fboundp 'my/denote--all-files)
    (user-error "27-denote-identifiers.el is not loaded"))
  (unless (fboundp 'my/maintenance--file-keywords)
    (user-error "26-maintenance.el is not loaded")))

(defun my/notes-stats--size (file)
  "Return FILE's size in bytes, or 0 when it has gone away."
  (or (file-attribute-size (file-attributes file)) 0))

(defun my/notes-stats--identifier-month (file)
  "Return YYYY-MM from FILE's Denote identifier, or nil.
Read from the name: the identifier is the first fifteen characters of
a Denote file name and encodes the creation moment, so a month
histogram needs no file access at all."
  (let ((base (file-name-nondirectory file)))
    (when (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)[0-9]\\{2\\}T" base)
      (concat (match-string 1 base) "-" (match-string 2 base)))))

(defun my/notes-stats--journal-date (file)
  "Return YYYY-MM-DD when FILE is a journal note, else nil."
  (let ((name (file-name-nondirectory file)))
    (when (string-match "--\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)-journal" name)
      (match-string 1 name))))

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

;; ============================================================
;; TIER ONE: NAMES AND ATTRIBUTES ONLY
;; ============================================================

(defun my/notes-stats--sizes (files)
  "Return a hash of FILE -> size in bytes.
Computed once and passed around.  `file-attributes' is a system call,
and the naive spellings of the three things that need a size -- the
total, the largest note, the per-silo breakdown -- would each walk the
list again, with the sort in the middle calling it twice per
comparison.  Three thousand notes turn that into roughly a hundred
thousand stat calls for a number that does not change while the report
is being drawn."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file files table)
      (puthash file (my/notes-stats--size file) table))))

(defun my/notes-stats--total-size (files sizes)
  "Return the total size of FILES, using the SIZES table.
A `dolist' accumulator rather than `(apply #\='+ ...)': `apply' with a
list of three thousand arguments is close enough to the limit on
argument count to be worth not finding out."
  (let ((sum 0))
    (dolist (file files sum)
      (setq sum (+ sum (gethash file sizes 0))))))

(defun my/notes-stats--silo-rows (files sizes)
  "Return (NAME DIR COUNT BYTES) per silo, plus a row for anything outside them."
  (let ((rows (mapcar (lambda (dir)
                        (list (file-name-nondirectory
                               (directory-file-name dir))
                              dir 0 0))
                      (if (boundp 'my/denote-silo-directories)
                          my/denote-silo-directories
                        (list my-notes-journal my-notes-pks my-notes-docu))))
        (other (list "other" nil 0 0)))
    (dolist (file files)
      (let ((row (seq-find (lambda (r)
                             (and (nth 1 r)
                                  (string-prefix-p (expand-file-name (nth 1 r))
                                                   (expand-file-name file))))
                           rows)))
        (setq row (or row other))
        (setf (nth 2 row) (1+ (nth 2 row)))
        (setf (nth 3 row) (+ (nth 3 row) (gethash file sizes 0)))))
    (append rows (when (> (nth 2 other) 0) (list other)))))

(defun my/notes-stats--keyword-counts (files)
  "Return a hash of keyword -> number of notes carrying it."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file files table)
      (dolist (keyword (my/maintenance--file-keywords file))
        (puthash keyword (1+ (gethash keyword table 0)) table)))))

(defun my/notes-stats--journal-map (files)
  "Return a hash of YYYY-MM-DD -> journal file.
Built once.  Looking a day up by scanning the whole file list is fine
for one day and quadratic for a year of them -- the metrics line below
would otherwise run a regexp over three thousand names three hundred
and sixty-five times."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file files table)
      (when-let* ((date (my/notes-stats--journal-date file)))
        (unless (gethash date table)
          (puthash date file table))))))

(defun my/notes-stats--journal-days (journal-map)
  "Return the sorted list of days present in JOURNAL-MAP."
  (sort (hash-table-keys journal-map) #'string<))

(defun my/notes-stats--streaks (days)
  "Return (LONGEST . CURRENT) for the sorted date list DAYS.
CURRENT counts back from today, and tolerates today itself being
absent: a streak that is intact up to yesterday is still a streak at
nine in the morning."
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
;; TIER TWO: READS EVERY FILE
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
      (when-let* ((id (and (string-match "\\`\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)"
                                         (file-name-nondirectory file))
                           (match-string 1 (file-name-nondirectory file)))))
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
    ;; links to nothing, which is the `no-links' count above: a
    ;; reference note may legitimately have no outgoing links, while a
    ;; note nothing points at is one nothing will ever lead you back to.
    (let ((orphans 0))
      (maphash (lambda (id _file)
                 (unless (gethash id targets) (setq orphans (1+ orphans))))
               identifiers)
      (list :words words :links links :no-links no-links :orphans orphans))))

;; ============================================================
;; RENDERING
;; ============================================================

(defun my/notes-stats--face (name fallback)
  "Return face NAME when it is defined, else FALLBACK."
  (if (facep name) name fallback))

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

(defun my/notes-stats--render ()
  "Draw the whole report into the current buffer."
  (my/notes-stats--require)
  (let* ((inhibit-read-only t)
         (files (my/denote--all-files))
         (total (length files))
         (sizes (my/notes-stats--sizes files))
         (bytes (my/notes-stats--total-size files sizes))
         (keywords (my/notes-stats--keyword-counts files))
         (journal-map (my/notes-stats--journal-map files))
         (journal-days (my/notes-stats--journal-days journal-map)))
    (erase-buffer)
    (insert (propertize "  Notes Statistics\n"
                        'face (my/notes-stats--face 'my/dashboard-title 'bold)))
    (insert (propertize (format "  %s\n" (format-time-string "%Y-%m-%d %H:%M"))
                        'face (my/notes-stats--face 'my/dashboard-hint 'shadow)))

    ;; -- Collection --------------------------------------------
    (my/notes-stats--heading "Collection")
    (my/notes-stats--line "Notes" (number-to-string total))
    (my/notes-stats--line "Total size" (file-size-human-readable bytes))
    (my/notes-stats--line "Average note"
                          (if (zerop total) "-"
                            (file-size-human-readable (/ bytes total))))
    (when files
      (let ((largest (car files)))
        (dolist (file (cdr files))
          (when (> (gethash file sizes 0) (gethash largest sizes 0))
            (setq largest file)))
        (my/notes-stats--line "Largest note"
                              (file-size-human-readable (gethash largest sizes 0))
                              (file-name-base largest))))

    ;; -- Silos -------------------------------------------------
    (my/notes-stats--heading "Silos")
    (dolist (row (my/notes-stats--silo-rows files sizes))
      (pcase-let ((`(,name ,_dir ,count ,size) row))
        (my/notes-stats--line
         name
         (format "%5d notes   %9s" count (file-size-human-readable size))
         (format "%s of notes, %s of size"
                 (my/notes-stats--percent count total)
                 (my/notes-stats--percent size bytes)))))

    ;; -- Journal -----------------------------------------------
    (my/notes-stats--heading "Journal")
    (if (null journal-days)
        (my/notes-stats--line "Entries" "none found")
      (let* ((first (car journal-days))
             (elapsed (1+ (- (time-to-days (current-time))
                             (my/notes-stats--day-number first))))
             (covered (length journal-days))
             (streaks (my/notes-stats--streaks journal-days)))
        (my/notes-stats--line "First entry" first)
        (my/notes-stats--line "Days since" (number-to-string elapsed))
        (my/notes-stats--line "Days with an entry"
                              (number-to-string covered)
                              (format "coverage %s"
                                      (my/notes-stats--percent covered elapsed)))
        (my/notes-stats--line "Days without one"
                              (number-to-string (- elapsed covered)))
        (my/notes-stats--line "Longest streak"
                              (format "%d days" (car streaks)))
        (my/notes-stats--line "Current streak"
                              (format "%d days" (cdr streaks)))
        ;; Metrics completeness, only when 35-journal-gaps.el is here.
        ;; The last 365 days rather than everything: the whole series
        ;; would mean opening every journal note, which belongs in the
        ;; second tier, and a year is the horizon anyone acts on.
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
                (when-let* ((file (gethash day journal-map)))
                  (when (my/journal-gaps--missing-keys file required)
                    (setq incomplete (1+ incomplete)))))
              (my/notes-stats--line
               "Missing metrics"
               (format "%d of %d" incomplete (length recent))
               "last 365 days -- C-c n f j to fix"))))))

    ;; -- Keywords ----------------------------------------------
    (my/notes-stats--heading "Keywords")
    (let* ((distinct (hash-table-count keywords))
           (assignments (let ((sum 0))
                          (maphash (lambda (_k v) (setq sum (+ sum v))) keywords)
                          sum))
           (singletons (let ((n 0))
                         (maphash (lambda (_k v) (when (= v 1) (setq n (1+ n))))
                                  keywords)
                         n))
           (bare (seq-count (lambda (f) (null (my/maintenance--file-keywords f)))
                            files))
           (pairs (let (acc)
                    (maphash (lambda (k v) (push (cons k v) acc)) keywords)
                    (sort acc (lambda (a b) (> (cdr a) (cdr b)))))))
      (my/notes-stats--line "Distinct keywords" (number-to-string distinct))
      (my/notes-stats--line "Assignments" (number-to-string assignments)
                            (format "%.2f per note"
                                    (if (zerop total) 0.0
                                      (/ (float assignments) total))))
      (my/notes-stats--line "Used once only" (number-to-string singletons)
                            "candidates for merging or removal")
      (my/notes-stats--line "Notes with no keywords" (number-to-string bare))
      (insert "\n")
      (let ((maximum (cdar pairs)))
        (dolist (pair (seq-take pairs my/notes-stats-top-keywords))
          (insert (format "  %-22s %5d  %s\n" (car pair) (cdr pair)
                          (my/notes-stats--bar (cdr pair) maximum))))))

    ;; -- Growth ------------------------------------------------
    (my/notes-stats--heading
     (format "Notes created, last %d months" my/notes-stats-growth-months))
    (let ((months (make-hash-table :test #'equal)))
      (dolist (file files)
        (when-let* ((month (my/notes-stats--identifier-month file)))
          (puthash month (1+ (gethash month months 0)) months)))
      (let* ((keys (sort (hash-table-keys months) #'string<))
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
                                  (format "%s (%d)" busiest (gethash busiest months)))))))

    ;; -- Deep tier ---------------------------------------------
    (my/notes-stats--heading "Content")
    (if (null my/notes-stats--deep)
        (my/notes-stats--line "Not computed" "press c"
                              "reads every note; a few seconds")
      (let ((deep my/notes-stats--deep))
        (my/notes-stats--line "Words" (number-to-string (plist-get deep :words))
                              (format "%d per note"
                                      (if (zerop total) 0
                                        (/ (plist-get deep :words) total))))
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

    (insert "\n"
            (propertize
             "  g refresh   c compute content   e denote-explore   q quit\n"
             'face (my/notes-stats--face 'my/dashboard-hint 'shadow)))
    (goto-char (point-min))))

;; ============================================================
;; COMMANDS
;; ============================================================

(defun my/notes-stats-refresh ()
  "Rebuild the fast statistics, keeping any computed content figures."
  (interactive)
  (my/notes-stats--render))

(defun my/notes-stats-compute-deep ()
  "Read every note and add word, link and orphan counts to the report."
  (interactive)
  (my/notes-stats--require)
  (setq my/notes-stats--deep (my/notes-stats--deep-scan (my/denote--all-files)))
  (my/notes-stats--render))

(defun my/notes-stats-explore ()
  "Run one of the `denote-explore-' commands, chosen by completion.
Built from the obarray rather than a hardcoded list, so a command
renamed or added upstream appears here without this file changing, and
one that is removed simply stops being offered."
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

(defvar my/notes-stats-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'my/notes-stats-refresh)
    (define-key map (kbd "c") #'my/notes-stats-compute-deep)
    (define-key map (kbd "e") #'my/notes-stats-explore)
    map)
  "Keymap for `my/notes-stats-mode'.")

(define-derived-mode my/notes-stats-mode special-mode "Notes Stats"
  "Major mode for the note statistics report.
\\{my/notes-stats-mode-map}"
  (setq-local truncate-lines t)
  ;; The report is a single column of its own; a centred text column
  ;; would push the bars off the right edge.
  (when (bound-and-true-p visual-fill-column-mode)
    (visual-fill-column-mode -1)))

;;;###autoload
(defun my/notes-stats ()
  "Show summary statistics for the note collection.

Everything on the opening screen comes from file names and file
attributes -- no note is read.  Press `c' for word, link and orphan
counts, which do read every file.  Press `e' for denote-explore's
charts, network view and drill-down lists."
  (interactive)
  (my/notes-stats--require)
  (let ((buffer (get-buffer-create my/notes-stats-buffer-name)))
    (with-current-buffer buffer
      (my/notes-stats-mode)
      (my/notes-stats--render))
    (when (and (fboundp 'my/fixed-tab-goto)
               (boundp 'my/dashboards-tab-name))
      (my/fixed-tab-goto my/dashboards-tab-name))
    (switch-to-buffer buffer)))

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
