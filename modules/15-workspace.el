;;; 15-workspace.el --- Notes dashboard and workspace tools -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Custom notes dashboard and workspace features for Denote.
;; Replaces dired-sidebar (which conflicted with transient menus).
;;
;; FEATURES:
;;   1. Custom notes dashboard  - Clickable titles grouped into sections,
;;                                sections arranged into side-by-side
;;                                columns, in its own named tab.
;;   2. Denote-explore          - Tag stats and network (on demand)
;;
;; SECTIONS AND COLUMNS:
;;   Sections are data: `my/dashboard-sections' maps a symbol to the
;;   function that renders it, and `my/dashboard-columns' says which
;;   sections go in which column.  Adding a section or moving one is an
;;   edit to a list, not to the renderer.
;;
;;   Each column is a separate window in the dashboard tab, so the
;;   columns scroll independently.  Two columns rather than three is a
;;   width decision: a column narrower than about sixty characters
;;   truncates ordinary note titles, and three columns on a 130-column
;;   frame leave twenty-three characters for a title.
;;
;; SORTING STRATEGY:
;;   - Recently Modified section : by mtime (what you edited last)
;;   - Journal section           : by creation date from identifier
;;   - PKS / Docu sections       : by mtime (what you edited last)
;;   - Hub / Zettel sections     : by mtime (what you edited last)
;;   - Tag popup                 : by creation date from identifier, newest first
;;                                 Files without identifier (captures.org) sort last.
;;
;; KEYBINDINGS:
;;   C-c w d  - Open/refresh notes dashboard (also C-c n f d in transient)
;;   C-c w x  - Show tag statistics (also C-c n f t)
;;   C-c w r  - Jump to random note (also C-c n f r)
;;   g        - Refresh dashboard (inside dashboard buffer)
;;   q        - Close the columns and bury the dashboard
;;
;; RELATED MODULE:
;;   33-denote-hubs.el owns what counts as a hub note.  The Hub section
;;   calls `my/denote-hub-files' when that module is loaded and falls
;;   back to its own file-name scan when it is not, so neither module
;;   requires the other.
;;
;; HOW TO REVERT:
;;   Remove (load ... "15-workspace.el") from init.el.  Nothing else
;;   changes -- which is now true rather than aspirational: spell
;;   checking, session restore and the backlinks window no longer pass
;;   through this file.

;;; Code:

;; ============================================================
;; HELPERS: Read org frontmatter from Denote files
;; ============================================================

;; Front matter regexps, shared by every reader below so they cannot
;; drift apart.
;;
;; The horizontal-whitespace class [ \t] is deliberate and load-bearing:
;; `\s-' is the *syntax* class for whitespace, and in a temp buffer
;; (fundamental mode, standard syntax table) a newline has whitespace
;; syntax.  So "^#\\+filetags:\\s-*\\(.+\\)$" against an empty
;;
;;     #+filetags:
;;     #+identifier: 20260726T150901
;;
;; consumes the newline as part of `\s-*' and captures the *next* line,
;; reporting the identifier line as the file's tags.  Matching only
;; spaces and tabs keeps the search on its own line.
;;
;; The capture group is `.*' rather than `.+' for the same reason: an
;; empty value must produce an empty match on this line instead of
;; failing and letting a later line satisfy the search.

(defconst my/denote-title-regexp "^#\\+title:[ \t]*\\(.*\\)$"
  "Match the `#+title:' front matter line, capturing its value.")

(defconst my/denote-filetags-regexp "^#\\+filetags:[ \t]*\\(.*\\)$"
  "Match the `#+filetags:' front matter line, capturing its value.")

(defun my/denote--parse-title (file)
  "Return the trimmed `#+title:' value in the current buffer.
Falls back to the base name of FILE when absent or empty."
  (goto-char (point-min))
  (let ((value (when (re-search-forward my/denote-title-regexp nil t)
                 (string-trim (match-string 1)))))
    (if (or (null value) (string-empty-p value))
        (file-name-base file)
      value)))

(defun my/denote--parse-tags ()
  "Return the `#+filetags:' value in the current buffer as a list.
An absent or empty line yields nil."
  (goto-char (point-min))
  (when (re-search-forward my/denote-filetags-regexp nil t)
    (split-string (match-string 1) ":" t "[ \t]+")))

(defun my/denote-file-title (file)
  "Return #+title from FILE (first 800 bytes only, for speed)."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file nil 0 800)
        (my/denote--parse-title file))
    (error (file-name-base file))))

(defun my/denote-file-tags (file)
  "Return list of tags from #+filetags in FILE."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file nil 0 800)
        (my/denote--parse-tags))
    (error nil)))

(defun my/denote-file-signature (file)
  "Return the Denote SIGNATURE of FILE, or nil when it has none.
The signature is the file name component between == and the -- that
begins the title.  Files created without a signature simply have no
== segment."
  (let ((name (file-name-nondirectory file)))
    (when (string-match "==\\([^=]+?\\)\\(?:--\\|__\\|\\.\\)" name)
      (match-string 1 name))))

(defun my/denote-file-metadata (file)
  "Return a cons of (TITLE . TAGS) for FILE, reading it only once.

`my/denote-file-title' and `my/denote-file-tags' each open the file
separately, which is fine when only one of them is needed.  The
dashboard needs both for every line, so this reads the front matter in
a single pass instead of hitting each file twice.

TITLE falls back to the file base name, TAGS to nil, on any error."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file nil 0 800)
        (cons (my/denote--parse-title file)
              (my/denote--parse-tags)))
    (error (cons (file-name-base file) nil))))

(defun my/denote-file-identifier (file)
  "Return the Denote identifier string from FILE basename, or nil."
  (let ((base (file-name-base file)))
    (when (string-match "^\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)" base)
      (match-string 1 base))))

(defun my/denote-identifier< (file-a file-b)
  "Return t if FILE-A was created before FILE-B by Denote identifier."
  (let ((id-a (my/denote-file-identifier file-a))
        (id-b (my/denote-file-identifier file-b)))
    (cond
     ((and id-a id-b) (string< id-a id-b))
     (id-a            t)
     (t               nil))))

(defun my/denote-org-files-in (directory)
  "Return .org files in DIRECTORY sorted newest-modified first."
  (when (file-directory-p directory)
    (sort (directory-files directory t "\\.org$" t)
          (lambda (a b)
            (time-less-p (nth 5 (file-attributes b))
                         (nth 5 (file-attributes a)))))))

(defun my/denote-org-files-in-by-id (directory)
  "Return .org files in DIRECTORY sorted newest-created first (by identifier)."
  (when (file-directory-p directory)
    (let* ((all     (directory-files directory t "\\.org$" t))
           (dated   (seq-filter  #'my/denote-file-identifier all))
           (undated (seq-remove  #'my/denote-file-identifier all)))
      (append
       (sort dated (lambda (a b) (my/denote-identifier< b a)))
       undated))))

(defun my/denote--all-silo-files ()
  "Return every .org file in the silos listed in `my-tasks-agenda-dirs'.

Uses that list from 00-core.el so a silo added there is picked up by
every section built on this helper.  Entries of the list that are files
rather than directories (captures.org) are skipped, which is what each
collector here did separately before."
  (let (result)
    (dolist (dir my-tasks-agenda-dirs result)
      (when (file-directory-p dir)
        (setq result (nconc result (directory-files dir t "\\.org\\'" t)))))))

(defun my/denote--sort-by-mtime (files)
  "Return FILES sorted newest-modified first.
FILES is copied first: `sort' is destructive and the caller's list may
be one of the shared collectors' return values."
  (sort (copy-sequence files)
        (lambda (a b)
          (time-less-p (nth 5 (file-attributes b))
                       (nth 5 (file-attributes a))))))

(defun my/denote-recently-modified (days)
  "Return .org files across all silos modified within DAYS, newest first."
  (let ((cutoff (time-subtract (current-time) (days-to-time days))))
    (my/denote--sort-by-mtime
     (seq-filter (lambda (f)
                   (time-less-p cutoff (nth 5 (file-attributes f))))
                 (my/denote--all-silo-files)))))

;; ============================================================
;; COLLECTORS: hub notes and Folgezettel notes
;; ============================================================

(defun my/denote--filename-keywords (file)
  "Return the Denote keywords in FILE's name as a list of strings.
Parsed from the `__keyword_keyword' component with a plain regexp, so
the collectors below do not depend on which helper names a given Denote
version exposes."
  (let ((base (file-name-base file)))
    (when (string-match "__\\(.*\\)\\'" base)
      (split-string (match-string 1 base) "_" t))))

(defun my/denote-hub-notes ()
  "Return hub notes across every silo, newest-modified first.

What counts as a hub is owned by 33-denote-hubs.el, so
`my/denote-hub-files' is used when that module is loaded.  The fallback
scans file names for the same keyword, which keeps this section working
without it.  Resolution happens at call time, so the load order of the
two modules does not matter."
  (my/denote--sort-by-mtime
   (if (fboundp 'my/denote-hub-files)
       (my/denote-hub-files)
     (let ((keyword (if (boundp 'my/denote-hub-keyword)
                        my/denote-hub-keyword
                      "hub")))
       (seq-filter (lambda (f)
                     (member keyword (my/denote--filename-keywords f)))
                   (my/denote--all-silo-files))))))

(defun my/denote-signature-notes ()
  "Return notes carrying a Denote signature, newest-modified first.

The filter is a regexp over file names, so only the notes that survive
it are ever asked for their modification time -- which is what keeps
this section cheap across a collection of several thousand files."
  (my/denote--sort-by-mtime
   (seq-filter #'my/denote-file-signature (my/denote--all-silo-files))))


(defun my/denote-all-tags ()
  "Return alist of (tag . files) sorted by usage count descending.

The one collector here that opens every file rather than reading names
only, because a tag lives in the front matter.  It is what makes a
dashboard refresh cost seconds on a large collection; the hub and
signature sections added beside it are name-only scans and cost
nothing by comparison."
  (let ((tag-map (make-hash-table :test 'equal)))
    (dolist (f (my/denote--all-silo-files))
      (dolist (tag (my/denote-file-tags f))
        (puthash tag (cons f (gethash tag tag-map '())) tag-map)))
    (let ((pairs '()))
      (maphash (lambda (tag files) (push (cons tag files) pairs)) tag-map)
      (sort pairs (lambda (a b) (> (length (cdr a)) (length (cdr b))))))))

;; ============================================================
;; DASHBOARD: Rendering helpers
;; ============================================================

(defconst my/dashboard-buffer-name "*Notes Dashboard*")

(defconst my/dashboard-tab-name "Dashboard"
  "Name of the tab-bar tab the dashboard lives in.
Passed to `my/fixed-tab-goto' (01-ui.el), which switches to that tab
and creates it when it is missing.")

(defun my/dashboard-open-in-new-tab (file)
  "Open FILE in a new named tab."
  (tab-bar-new-tab)
  (find-file file)
  (tab-bar-rename-tab (my/denote-file-title file)))

(defun my/dashboard-insert-section-header (title)
  "Insert a styled section TITLE line."
  (insert "\n")
  (insert (propertize (concat "  " title "\n")
                      'face 'my/dashboard-section))
  (insert "\n"))

(defvar my/dashboard-signature-width 5
  "Column width reserved for the Denote signature in dashboard lines.
Notes without a signature get blank padding, so titles stay aligned
whether or not a section mixes sequence notes with plain ones.
Signatures longer than this keep a single separating space and push
their own line right rather than widening every line; 5 covers
everything up to `1zzzv' comfortably.")

(defvar my/dashboard-show-tags t
  "Whether dashboard lines end with the note's tags.")

(defvar my/dashboard-tag-column 92
  "Column at which the dashboard tag list starts.
A fixed column rather than a window-relative one, because the buffer
is rendered before it is displayed, so window width is not reliably
known at render time.  Lines whose title runs past this column get two
spaces before their tags instead, which is the honest degradation:
the tags stay readable, they just stop lining up.")

(defvar my/dashboard-hidden-tags '("journal" "docu")
  "Tags never shown in dashboard lines.
The Journal and Documentation sections are already labelled as such,
so repeating the silo tag on every line of them is noise that only
pushes the informative tags further right.")

;; ============================================================
;; SECTION SIZE LIMITS
;; ============================================================

(defgroup my/dashboard nil
  "The Notes Dashboard: sections, limits and column layout."
  :group 'convenience)

(defcustom my/dashboard-recent-days 10
  "Age in days of the oldest file the Recently Modified section shows."
  :type 'integer
  :group 'my/dashboard)

(defcustom my/dashboard-recent-limit 20
  "Maximum number of lines in the Recently Modified section, or nil for all.

The section answers \"what have I been working on\", and modification
time stops witnessing that after a bulk operation: rewriting front
matter across the collection stamps every file with the same afternoon
and buries the answer under thousands of lines.

A cap is the honest fix rather than a workaround, because there is no
cheap substitute for the signal.  The date of the last commit touching
a file would be the real answer, but that is one git subprocess per
file and this collection has thousands of them, on every refresh.  When
the cap hides entries, the section says how many."
  :type '(choice integer (const :tag "No limit" nil))
  :group 'my/dashboard)

(defcustom my/dashboard-journal-limit 10
  "Maximum number of lines in the Journal section."
  :type 'integer
  :group 'my/dashboard)

(defcustom my/dashboard-silo-limit 20
  "Maximum number of lines in the PKS, Documentation, Hub and Zettel sections.
One value for the four because they are the same kind of list -- the
most recently touched notes of a set -- and four separate options would
be four things to keep in step for no gain."
  :type 'integer
  :group 'my/dashboard)

(defcustom my/dashboard-tag-limit 30
  "Maximum number of tags listed in the Tags section."
  :type 'integer
  :group 'my/dashboard)

(defun my/dashboard-insert-file-link (file &optional date-source)
  "Insert a clickable line for FILE: date, signature, title, tags.

DATE-SOURCE controls which date is shown:
  \='mtime (default) — file modification time; used for Recently Modified,
                       PKS, and Docu sections where \"what changed last\"
                       is the relevant signal.
  \='id             — creation date parsed from the Denote identifier
                       (YYYYMMDDTHHMMSS prefix); used for Journal and tag
                       popups where chronological creation order matters.
                       Falls back to mtime when the file has no identifier
                       (e.g. captures.org).

The clickable region covers date, signature and title.  Tags are
appended outside it as plain dimmed text, so they can keep their own
face instead of inheriting the button's."
  (let* ((meta    (my/denote-file-metadata file))
         (title   (car meta))
         (tags    (seq-remove (lambda (tag) (member tag my/dashboard-hidden-tags))
                              (cdr meta)))
         ;; Pad by hand: Emacs `format' has no dynamic field width, so
         ;; "%-*s" is not valid (that is C printf syntax).  At least one
         ;; space is always kept, so an over-long signature pushes its
         ;; own line right instead of running into the title.
         (sig     (let ((s (or (my/denote-file-signature file) "")))
                    (concat s (make-string
                               (max 1 (- my/dashboard-signature-width
                                         (length s)))
                               ?\s))))
         (date    (pcase date-source
                    ('id
                     (let ((id (my/denote-file-identifier file)))
                       (if id
                           (concat (substring id 0 4) "-"
                                   (substring id 4 6) "-"
                                   (substring id 6 8))
                         (format-time-string "%Y-%m-%d"
                                             (nth 5 (file-attributes file))))))
                    (_
                     (format-time-string "%Y-%m-%d"
                                         (nth 5 (file-attributes file))))))
         (display (format "  %s  %s%s" date sig title))
         (start   (point)))
    (insert display)
    (make-text-button start (point)
                      'action (let ((f file))
                                (lambda (_b) (my/dashboard-open-in-new-tab f)))
                      'follow-link t
                      'help-echo file
                      'mouse-face 'highlight
                      'face 'my/dashboard-note)
    (when (and my/dashboard-show-tags tags)
      (let ((pad (max 2 (- my/dashboard-tag-column (current-column)))))
        (insert (propertize (concat (make-string pad ?\s)
                                    ":" (string-join tags ":") ":")
                            'face 'my/dashboard-tags))))
    (insert "\n")))

(defun my/dashboard-insert-tag-line (tag files)
  "Insert a clickable TAG line showing note count."
  (let* ((display (format "  %-24s  %d notes" tag (length files)))
         (start   (point)))
    (insert display)
    (make-text-button start (point)
                      'action (let ((tg tag) (fl files))
                                (lambda (_b)
                                  (my/dashboard-show-tag-notes tg fl)))
                      'follow-link t
                      'help-echo (format "Show notes tagged :%s:" tag)
                      'mouse-face 'highlight
                      'face 'my/dashboard-tag-button)
    (insert "\n")))

(defun my/dashboard-show-tag-notes (tag files)
  "Pop up a clickable list of FILES tagged TAG, sorted by creation date.

The popup buffer uses `special-mode' as its base, which provides
read-only protection and the standard \='q\=' (quit-window) keybinding
without any manual setup."
  (let* ((dated   (seq-filter #'my/denote-file-identifier files))
         (undated (seq-remove #'my/denote-file-identifier files))
         (sorted  (append
                   (sort dated (lambda (a b) (my/denote-identifier< b a)))
                   undated))
         (buf (get-buffer-create (format "*Tag: %s*" tag))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert (propertize
                 (format "Notes tagged :%s: (%d)  --  sorted by creation date\n\n"
                         tag (length files))
                 'face 'my/dashboard-section))
        (dolist (f sorted)
          (my/dashboard-insert-file-link f 'id))
        (insert "\n")
        (insert (propertize "  q = close" 'face 'my/dashboard-hint))))
    (display-buffer buf '(display-buffer-below-selected (window-height . 0.4)))))

;; ============================================================
;; DASHBOARD: Sections
;; ============================================================
;; Each section is a function that inserts its own header and body into
;; the current buffer.  They are registered as data in
;; `my/dashboard-sections' and arranged by `my/dashboard-columns', so
;; adding a section or moving one between columns is an edit to a list,
;; not to the renderer.

(defun my/dashboard--insert-capped (files limit &optional date-source)
  "Insert clickable lines for the first LIMIT of FILES.
LIMIT nil means all of them.  When entries are left out, a dimmed line
says how many, because a list silently truncated to a round number is
indistinguishable from a list that happens to be that long.
DATE-SOURCE is passed through to `my/dashboard-insert-file-link'."
  (let* ((total (length files))
         (shown (if limit (seq-take files limit) files)))
    (dolist (f shown)
      (my/dashboard-insert-file-link f date-source))
    (when (> total (length shown))
      (insert (propertize (format "  ... and %d more\n"
                                  (- total (length shown)))
                          'face 'my/dashboard-hint)))))

(defun my/dashboard--section-recent ()
  "Insert the Recently Modified section."
  (my/dashboard-insert-section-header
   (format "Recently Modified  (last %d days)" my/dashboard-recent-days))
  (let ((recent (my/denote-recently-modified my/dashboard-recent-days)))
    (if recent
        (my/dashboard--insert-capped recent my/dashboard-recent-limit)
      (insert (format "  (no files modified in the last %d days)\n"
                      my/dashboard-recent-days)))))

(defun my/dashboard--section-journal ()
  "Insert the Journal section, newest created first."
  (my/dashboard-insert-section-header
   (format "Journal  [%s]" (abbreviate-file-name my-notes-journal)))
  (my/dashboard--insert-capped
   (my/denote-org-files-in-by-id my-notes-journal)
   my/dashboard-journal-limit 'id))

(defun my/dashboard--section-pks ()
  "Insert the PKS section, newest modified first."
  (my/dashboard-insert-section-header
   (format "PKS -- Personal Knowledge  [%s]" (abbreviate-file-name my-notes-pks)))
  (my/dashboard--insert-capped
   (my/denote-org-files-in my-notes-pks) my/dashboard-silo-limit))

(defun my/dashboard--section-docu ()
  "Insert the Documentation section, newest modified first."
  (my/dashboard-insert-section-header
   (format "Documentation  [%s]" (abbreviate-file-name my-notes-docu)))
  (my/dashboard--insert-capped
   (my/denote-org-files-in my-notes-docu) my/dashboard-silo-limit))

(defun my/dashboard--section-hub ()
  "Insert the Hub section: notes carrying the hub keyword, any silo."
  (my/dashboard-insert-section-header "HUB  (notes tagged :hub:)")
  (let ((hubs (my/denote-hub-notes)))
    (if hubs
        (my/dashboard--insert-capped hubs my/dashboard-silo-limit)
      (insert "  (no hub notes yet)\n"))))

(defun my/dashboard--section-zettel ()
  "Insert the Zettelkasten section: notes carrying a Denote signature."
  (my/dashboard-insert-section-header "Zettelkasten  (notes with a signature)")
  (let ((zettel (my/denote-signature-notes)))
    (if zettel
        (my/dashboard--insert-capped zettel my/dashboard-silo-limit)
      (insert "  (no notes with a signature yet)\n"))))

(defun my/dashboard--section-tags ()
  "Insert the Tags section: most used tags, clickable."
  (my/dashboard-insert-section-header "Tags  (click to list notes)")
  (dolist (pair (seq-take (my/denote-all-tags) my/dashboard-tag-limit))
    (my/dashboard-insert-tag-line (car pair) (cdr pair))))

(defvar my/dashboard-sections
  '((recent  . my/dashboard--section-recent)
    (journal . my/dashboard--section-journal)
    (pks     . my/dashboard--section-pks)
    (docu    . my/dashboard--section-docu)
    (hub     . my/dashboard--section-hub)
    (zettel  . my/dashboard--section-zettel)
    (tags    . my/dashboard--section-tags))
  "Alist of (SYMBOL . FUNCTION) for every available dashboard section.
FUNCTION takes no arguments and inserts the whole section, header
included, into the current buffer.  A symbol named in
`my/dashboard-columns' but missing here renders as a visible complaint
rather than an error, so a typo costs one line and not the dashboard.")

(defcustom my/dashboard-columns
  '((recent journal docu)
    (pks hub zettel tags))
  "Dashboard sections, grouped into side-by-side columns.

One list per column, left to right; each holds symbols from
`my/dashboard-sections'.  The columns are separate windows in the
dashboard tab, so they scroll independently and an unbalanced split
costs nothing but empty space.

Two columns rather than three is a width decision, not a preference.
The line format is two spaces, a ten-character date, a five-character
signature field and the title, so a column narrower than about sixty
characters truncates ordinary titles.  On a 130-column frame two
columns leave roughly sixty-six characters each; three leave
twenty-three, which is not enough for a title like \"Chrześcijaństwo -
religia niewolników\".

Tags are dropped from note lines whenever there is more than one
column: they start at `my/dashboard-tag-column' and no split column is
that wide.  They stay reachable through the Tags section.

A single column, `((recent journal pks docu tags))', restores the
pre-2026-08 layout including per-line tags."
  :type '(repeat (repeat symbol))
  :group 'my/dashboard)

;; ============================================================
;; DASHBOARD: Major mode
;; ============================================================

(defvar my/dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'my/open-notes-dashboard)
    (define-key map (kbd "q") #'my/dashboard-quit)
    map)
  "Keymap for `my/dashboard-mode'.")

(define-derived-mode my/dashboard-mode special-mode "Notes Dashboard"
  "Major mode for the Notes Dashboard columns.

Derived from `special-mode', which supplies the read-only buffer that
was previously arranged by hand with `read-only-mode' and
`local-set-key'.  One mode for every column is what keeps the two
buffers behaving identically.

Lines are truncated rather than wrapped: a title too long for a narrow
column is cut at the window edge instead of folding onto a second line
and breaking the alignment of everything below it.

\\{my/dashboard-mode-map}"
  (setq truncate-lines t))

(defun my/dashboard-quit ()
  "Leave the dashboard: one window again, dashboard buffer buried.
`bury-buffer' on its own would dismiss only the column point happens to
be in and leave the others on screen."
  (interactive)
  (delete-other-windows)
  (bury-buffer))

;; ============================================================
;; DASHBOARD: Main render function
;; ============================================================

(defun my/dashboard--column-buffer-name (index)
  "Return the buffer name of dashboard column INDEX, counting from 1.
Column 1 keeps the historical `my/dashboard-buffer-name', so anything
that refers to the dashboard by name still finds it."
  (if (= index 1)
      my/dashboard-buffer-name
    (format "*Notes Dashboard %d*" index)))

(defun my/dashboard--kill-stale-column-buffers (columns)
  "Kill column buffers left over from a layout wider than COLUMNS.
Narrowing `my/dashboard-columns' would otherwise leave the discarded
columns in the buffer list, still showing whatever they last held."
  (dolist (buf (buffer-list))
    (let ((name (buffer-name buf)))
      (when (and name
                 (string-match "\\`\\*Notes Dashboard \\([0-9]+\\)\\*\\'" name)
                 (> (string-to-number (match-string 1 name)) columns))
        (kill-buffer buf)))))

(defun my/dashboard--render-column (sections index total)
  "Render SECTIONS into the buffer for column INDEX of TOTAL, and return it."
  (let ((buf (get-buffer-create (my/dashboard--column-buffer-name index))))
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            ;; Per-line tags need `my/dashboard-tag-column' and no split
            ;; column is that wide, so they are shown only when the
            ;; dashboard is a single column.
            (my/dashboard-show-tags (and my/dashboard-show-tags (= total 1))))
        (my/dashboard-mode)
        (erase-buffer)
        (when (= index 1)
          (insert "\n")
          (insert (propertize "  Notes Dashboard\n"
                              'face 'my/dashboard-title))
          (insert (propertize
                   (format "  %s\n"
                           (format-time-string "Refreshed: %Y-%m-%d %H:%M"))
                   'face 'my/dashboard-hint)))
        (dolist (section sections)
          (let ((fn (alist-get section my/dashboard-sections)))
            (if (functionp fn)
                (funcall fn)
              (my/dashboard-insert-section-header
               (format "Unknown section: %s" section)))))
        (insert "\n")
        (when (= index total)
          (insert (propertize
                   "  g = refresh  |  q = close  |  C-c w r = random note\n"
                   'face 'my/dashboard-hint)))
        (goto-char (point-min))))
    buf))

(defun my/render-notes-dashboard ()
  "Render every column of `my/dashboard-columns' and return their buffers.
The buffers are returned left to right; arranging them into windows is
`my/open-notes-dashboard''s job."
  (let* ((columns (or my/dashboard-columns '((recent journal pks docu tags))))
         (total (length columns))
         (index 0))
    (prog1 (mapcar (lambda (sections)
                     (setq index (1+ index))
                     (my/dashboard--render-column sections index total))
                   columns)
      (my/dashboard--kill-stale-column-buffers total))))

;; ============================================================
;; DASHBOARD: Open in named tab
;; ============================================================

(defun my/open-notes-dashboard ()
  "Open or refresh the Notes Dashboard in its own named tab.

The tab is reset to a single window before the columns are split off,
so the layout is the same whatever the tab held before -- the same
reasoning as `my/dashboards--show-navigation' in 21-dashboards.el.
Point ends up in the leftmost column."
  (interactive)
  (my/fixed-tab-goto my/dashboard-tab-name)
  (let ((buffers (my/render-notes-dashboard)))
    (switch-to-buffer (car buffers))
    (delete-other-windows)
    ;; Each split is taken from the window just created, so the columns
    ;; end up in the order of `my/dashboard-columns' rather than
    ;; reversed, which is what repeatedly splitting the first window
    ;; would give.
    (let ((window (selected-window)))
      (dolist (buf (cdr buffers))
        (setq window (split-window window nil 'right))
        (set-window-buffer window buf)))
    (balance-windows)
    (car buffers)))

;; ============================================================
;; STARTUP: Open Dashboard once the session is ready
;; ============================================================
;; This module used to work out for itself when startup had finished:
;; one hook for the case where a desktop was restored, another for the
;; case where there was none, two timers, and a "does the Dashboard tab
;; exist already?" test to keep both paths from firing.  It also
;; unblocked Hunspell along the way -- which has nothing to do with a
;; dashboard, and meant that dropping this module silently disabled
;; spell checking for the whole session.
;;
;; `my/desktop-after-startup-hook' (01-ui.el) answers the question once,
;; for everyone: it fires after startup whether or not a session was
;; restored, and it fires exactly once.  The duplicate paths and the
;; tab-existence test went with it.  This module now states what it
;; wants, not when it may have it, and 03-spelling.el states its own.

(if (boundp 'my/desktop-after-startup-hook)
    (add-hook 'my/desktop-after-startup-hook #'my/open-notes-dashboard)
  ;; Without 01-ui.el there is no session to wait for, so open directly.
  (add-hook 'emacs-startup-hook #'my/open-notes-dashboard 95))

;; ============================================================
;; DENOTE-EXPLORE: Tag stats (lazy loaded)
;; ============================================================

(use-package denote-explore
  :ensure t
  :after (denote org)
  :commands (denote-explore-count-notes
             denote-explore-count-keywords
             denote-explore-identify-duplicate-notes
             denote-explore-random-note
             denote-explore-network)
  :custom
  (denote-explore-network-directory (expand-file-name my-notes-dir))
  (denote-explore-network-filename "denote-network.json"))

(defun my/notes-explore ()
  "Show tag and note statistics."
  (interactive)
  (require 'denote-explore)
  (denote-explore-count-notes))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c w d") #'my/open-notes-dashboard)
(global-set-key (kbd "C-c w x") #'my/notes-explore)
(global-set-key (kbd "C-c w r") #'denote-explore-random-note)

(provide '15-workspace)
;;; 15-workspace.el ends here
