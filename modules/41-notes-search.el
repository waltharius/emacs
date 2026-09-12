;;; 41-notes-search.el --- Advanced search across the notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Two commands, both thin layers over machinery that already exists:
;;
;;   `my/notes-grep'          content search, with quoted phrases and a
;;                            date range taken from the Denote identifier
;;   `my/notes-find-by-name'  file-name search, with `title:' and `tag:'
;;                            selectors
;;
;; WHY THE OLD GREP WALKED INTO .snapshots
;; ---------------------------------------
;; `consult-denote-grep' runs whatever `consult-denote-grep-command'
;; names, and that defaults to `consult-grep' -- plain `grep -r'.  The
;; only directories grep skips are the ones consult passes as
;; `--exclude-dir', which come from `grep-find-ignored-directories':
;; .git, CVS, .hg and friends.  `.snapshots' is not on that list, so
;; every btrfs snapshot of the notes tree was searched, and a note that
;; had existed for a year came back once per snapshot.
;;
;; The same mistake as the one recorded for `my/denote-scan-exclude-regexp'
;; in 27-denote-identifiers.el, and it is fixed the same way: by the
;; convention (any dot directory), not by naming the current offenders.
;; Three fixes, in increasing order of scope:
;;
;;   1. `grep-find-ignored-directories' gains the three dot directories
;;      this tree actually contains.  That helps every grep-based
;;      command in Emacs -- `rgrep', `project-find-regexp', the plain
;;      `consult-grep' -- not only the commands in this file.
;;   2. This module's own invocations pass `--exclude-dir=.*' (grep) or
;;      `-g !.*' (ripgrep), which covers dot directories that do not
;;      exist yet.
;;   3. ripgrep is preferred when it is installed.  It skips hidden
;;      directories and honours .gitignore by default, and it is roughly
;;      an order of magnitude faster on a tree this size.
;;
;; Denote's own file listing already skipped dot directories
;; unconditionally (`denote--directory-all-files-recursively'), which is
;; why `denote-open-or-create' was never affected and why
;; `my/notes-find-by-name' below needs no exclusion logic at all.
;;
;; THE QUERY LANGUAGE
;; ------------------
;;   kot pies              both words, anywhere on the same line
;;   "wspólnie z innymi"   that exact sequence, as a literal
;;   date:2014             notes created in 2014
;;   date:2012-01..2015-05 notes created in that closed range
;;   date:<2015            everything before 2015
;;   date:>=2012-03        everything from March 2012 on
;;   from:2012 to:2015     the same as date:2012..2015
;;
;; Anything that is not a date directive is a search term.  Quoted
;; phrases are taken literally (regexp metacharacters are escaped);
;; unquoted words keep their regexp meaning, which is what the previous
;; grep did and what makes `foo.*bar' still work.
;;
;; WHY THE PHRASE IS TRANSLATED RATHER THAN INTERCEPTED
;; ---------------------------------------------------
;; Consult already has the notion of a multi-word pattern that must not
;; be split: a backslash-escaped space (`consult--split-escaped').  So a
;; quoted phrase is not a new feature to build, it is a notation to
;; translate -- `"a b c"' becomes `a\ b\ c' before consult ever sees it.
;;
;; The alternative was to replace `consult--regexp-compiler', which is
;; the hook the consult wiki uses for orderless integration.  It is
;; declared under "Internal variables" in consult.el, and a dynamic
;; binding of it would not survive consult's own input debouncing anyway
;; (the command is rebuilt from a timer, outside the `let').  Translating
;; the query costs one prompt and depends on nothing private.
;;
;; DATES COME FROM THE IDENTIFIER, NOT FROM THE FILE SYSTEM
;; -------------------------------------------------------
;; The range filters on the `YYYYMMDDTHHMMSS' identifier in the file
;; name, so it means "the note is from 2014", not "the file was last
;; written in 2014".  That is the question actually being asked -- a
;; 2014 journal entry edited yesterday is still a 2014 note -- and it is
;; also the cheap one: the filter becomes a file-name glob that grep and
;; ripgrep apply themselves, with no `stat' per file and no file list on
;; the command line.
;;
;; Two consequences worth knowing.  Notes migrated from Obsidian with an
;; unknown creation time carry `T000000', but their date is correct, so
;; they filter correctly.  Files with no identifier at all are excluded
;; whenever a date range is given, because there is nothing to compare.
;;
;; DEPENDENCIES
;; ------------
;;   consult       required by `my/notes-grep'; the command reports and
;;                 stops if it is missing
;;   denote        required by `my/notes-find-by-name'
;;   12-transient  the menu entries, appended through
;;                 `my/transient-append' / `my/transient-replace', both
;;                 of which skip rather than signal
;;
;; Nothing else in the configuration calls into this module.  Deleting
;; the file restores the previous Find menu, because the "g" entry it
;; replaces is put back by 12-transient.el itself on the next start.
;;
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-find

;;; Code:

(require 'seq)
(require 'subr-x)

;; Valueless `defvar', and it is load-bearing rather than tidy.  Under
;; `lexical-binding', `(let ((consult-ripgrep-args ...)) ...)' in a file
;; that has not seen consult.el compiles to a LEXICAL binding: a local
;; variable consult never reads, so the extra arguments would silently
;; have no effect once the configuration is byte-compiled.  Declaring
;; the symbols special here is what makes the bindings dynamic.  Same
;; trap as `denote-use-file-type' in 40-markdown.el.
(defvar consult-ripgrep-args)
(defvar consult-grep-args)

;; ============================================================
;; OPTIONS
;; ============================================================

(defcustom my/notes-search-ignored-directories
  '(".snapshots" ".stversions" ".stfolder")
  "Directory names added to `grep-find-ignored-directories'.

These are the dot directories that actually occur inside the notes
tree: btrfs snapshots and the two Syncthing bookkeeping folders.  The
list exists so that grep-based commands OUTSIDE this module -- `rgrep',
`project-find-regexp', `consult-grep' -- skip them too.

The commands in this module do not depend on it: they exclude every dot
directory by glob, so a new one needs no entry here."
  :type '(repeat string) :group 'my)

(defcustom my/notes-search-earliest-year 1990
  "Year used as the lower bound of an open-ended date range.

`date:<2015' has no start, and a glob list has to start somewhere.  The
value only has to be older than the oldest note; it costs one extra
glob per year, so a wrong guess is slow rather than incorrect."
  :type 'integer :group 'my)

(defcustom my/notes-search-max-globs 200
  "Refuse to build more file-name globs than this for one search.

A range of whole years costs one glob per year, a range with partial
years costs up to twelve more at each end.  Passing several hundred
globs to grep works but is slow enough to look broken, so a range that
wide is almost certainly a typo -- `date:1900..2030' rather than a
deliberate question."
  :type 'integer :group 'my)

(defcustom my/notes-search-prefer-ripgrep t
  "Use ripgrep for content search when the `rg' executable is present.

Set to nil to force plain grep.  Both back ends support everything this
module does; ripgrep is faster and excludes hidden directories on its
own, grep needs to be told."
  :type 'boolean :group 'my)

;; ============================================================
;; EXCLUSIONS FOR EVERY OTHER GREP IN EMACS
;; ============================================================
;; `grep-find-ignored-directories' lives in grep.el, which is not loaded
;; at startup and should not be loaded for this.  The commands below
;; require it when they run; this form covers the case where something
;; else loads grep first.

(with-eval-after-load 'grep
  (dolist (dir my/notes-search-ignored-directories)
    (add-to-list 'grep-find-ignored-directories dir)))

;; The plain `consult-denote-grep' is no longer on the Find menu, but it
;; is still one `M-x' away and is what other Denote integrations call.
;; Pointing it at ripgrep gives it the same exclusions for free.

(with-eval-after-load 'consult-denote
  (when (and my/notes-search-prefer-ripgrep
             (executable-find "rg")
             (boundp 'consult-denote-grep-command))
    (setq consult-denote-grep-command #'consult-ripgrep)))

;; ============================================================
;; TOKENISER
;; ============================================================
;; One pass over the query string.  Double quotes group; everything else
;; is whitespace-separated.  An unterminated quote runs to the end of the
;; string rather than signalling: the user is mid-typing, not wrong.

(defconst my/notes-search--token-regexp
  "\\(?:\"\\([^\"]*\\)\"?\\|\\([^ \t\"]+\\)\\)"
  "Match one token: a double-quoted phrase, or a run of non-blank characters.
Group 1 is the phrase without its quotes, group 2 a bare token.")

(defun my/notes-search--tokenize (query)
  "Split QUERY into a list of (KIND . STRING).
KIND is `phrase' for a double-quoted group and `word' otherwise."
  (let ((start 0) (tokens nil))
    (while (string-match my/notes-search--token-regexp query start)
      (setq start (match-end 0))
      (cond
       ((match-beginning 1)
        (let ((phrase (string-trim (match-string 1 query))))
          (unless (string-empty-p phrase)
            (push (cons 'phrase phrase) tokens))))
       ((match-beginning 2)
        (push (cons 'word (match-string 2 query)) tokens))))
    (nreverse tokens)))

;; ============================================================
;; DATES
;; ============================================================
;; Months are handled as a single integer YYYYMM.  Comparison is then
;; plain `<', and the only arithmetic needed is stepping one month, which
;; is where the year carry lives.

(defun my/notes-search--ym (year month)
  "Return YEAR and MONTH as one YYYYMM integer."
  (+ (* year 100) month))

(defun my/notes-search--ym-year (ym)
  "Return the year part of YM."
  (/ ym 100))

(defun my/notes-search--ym-month (ym)
  "Return the month part of YM."
  (% ym 100))

(defun my/notes-search--ym-next (ym)
  "Return the month after YM."
  (if (= (my/notes-search--ym-month ym) 12)
      (my/notes-search--ym (1+ (my/notes-search--ym-year ym)) 1)
    (1+ ym)))

(defun my/notes-search--ym-previous (ym)
  "Return the month before YM."
  (if (= (my/notes-search--ym-month ym) 1)
      (my/notes-search--ym (1- (my/notes-search--ym-year ym)) 12)
    (1- ym)))

(defun my/notes-search--parse-point (string bound)
  "Parse STRING as a date and return it as a YYYYMM integer.

Accepted forms are YYYY, YYYY-MM and YYYYMM.  BOUND decides what a bare
year means: `start' expands it to January, `end' to December, so that
`2012..2015' covers all of 2015 rather than stopping in January."
  (if (string-match "\\`\\([0-9]\\{4\\}\\)\\(?:[-/]?\\([0-9]\\{2\\}\\)\\)?\\'" string)
      (let* ((year (string-to-number (match-string 1 string)))
             (month-string (match-string 2 string))
             (month (and month-string (string-to-number month-string))))
        (when (and month (not (<= 1 month 12)))
          (user-error "Month `%s' is not between 01 and 12" month-string))
        (my/notes-search--ym year (or month (if (eq bound 'end) 12 1))))
    (user-error "Cannot read `%s' as a date (expected YYYY, YYYY-MM or YYYYMM)"
                string)))

(defun my/notes-search--parse-range (value)
  "Parse VALUE as a date range and return a cons (MIN . MAX).
Either end may be nil, meaning open.  See the header for the accepted
forms."
  (cond
   ;; Both ends are read out of the match data BEFORE either is parsed:
   ;; `my/notes-search--parse-point' runs its own `string-match', which
   ;; replaces the match data this branch is still standing on.
   ((string-match "\\`\\(.+?\\)\\.\\.\\(.+\\)\\'" value)
    (let ((from (match-string 1 value))
          (to (match-string 2 value)))
      (cons (my/notes-search--parse-point from 'start)
            (my/notes-search--parse-point to 'end))))
   ((string-match "\\`<=\\(.+\\)\\'" value)
    (cons nil (my/notes-search--parse-point (match-string 1 value) 'end)))
   ((string-match "\\`<\\(.+\\)\\'" value)
    (cons nil (my/notes-search--ym-previous
               (my/notes-search--parse-point (match-string 1 value) 'start))))
   ((string-match "\\`>=\\(.+\\)\\'" value)
    (cons (my/notes-search--parse-point (match-string 1 value) 'start) nil))
   ((string-match "\\`>\\(.+\\)\\'" value)
    (cons (my/notes-search--ym-next
           (my/notes-search--parse-point (match-string 1 value) 'end))
          nil))
   (t
    (cons (my/notes-search--parse-point value 'start)
          (my/notes-search--parse-point value 'end)))))

(defun my/notes-search--merge-range (range new)
  "Intersect date range RANGE with NEW, either of which may be nil."
  (cond
   ((null range) new)
   ((null new) range)
   (t (cons (if (and (car range) (car new)) (max (car range) (car new))
              (or (car range) (car new)))
            (if (and (cdr range) (cdr new)) (min (cdr range) (cdr new))
              (or (cdr range) (cdr new)))))))

(defun my/notes-search--date-globs (range)
  "Return file-name globs matching Denote identifiers inside RANGE.

RANGE is a cons (MIN . MAX) of YYYYMM integers, either end possibly nil.
A year entirely inside the range costs one glob; a partial year costs
one per month.  Returns nil when RANGE is nil, which means no filter."
  (when range
    (let* ((min (or (car range)
                    (my/notes-search--ym my/notes-search-earliest-year 1)))
           (max (or (cdr range)
                    (my/notes-search--ym
                     (string-to-number (format-time-string "%Y")) 12)))
           (globs nil))
      (when (> min max)
        (user-error "Empty date range: %d is after %d" min max))
      (dolist (year (number-sequence (my/notes-search--ym-year min)
                                     (my/notes-search--ym-year max)))
        (if (and (<= min (my/notes-search--ym year 1))
                 (>= max (my/notes-search--ym year 12)))
            (push (format "%d*" year) globs)
          (dolist (month (number-sequence 1 12))
            (let ((ym (my/notes-search--ym year month)))
              (when (and (<= min ym) (>= max ym))
                (push (format "%d%02d*" year month) globs))))))
      (setq globs (nreverse globs))
      (when (> (length globs) my/notes-search-max-globs)
        (user-error "Date range needs %d globs, over the %d limit -- narrow it"
                    (length globs) my/notes-search-max-globs))
      globs)))

;; ============================================================
;; QUERY -> CONSULT INPUT
;; ============================================================

(defconst my/notes-search--date-directive-regexp
  "\\`\\(date\\|from\\|to\\):\\(.+\\)\\'"
  "Match a date directive token.  Group 1 is the keyword, group 2 its value.")

(defun my/notes-search--literal (string)
  "Return STRING as one consult search term matching it literally.

Two escapes, in this order.  `regexp-quote' first, because consult takes
Emacs regexp syntax at the prompt and converts it to the back end's
dialect itself.  Then every space becomes a backslash-escaped space, so
that consult keeps the phrase as a single pattern instead of splitting
it into independent words."
  (string-replace " " "\\ " (regexp-quote string)))

(defun my/notes-search--protect-dash (term)
  "Return TERM with a leading dash escaped.

Consult reads everything from the first ` -' onwards as command-line
options for the search program, and undoes a `\\-' escape afterwards.
Without this, searching for `-- ' would silently become a flag."
  (if (string-prefix-p "-" term) (concat "\\" term) term))

(defun my/notes-search-parse (query)
  "Parse QUERY into a plist (:pattern STRING :range (MIN . MAX)).

:pattern is ready to be handed to `consult-grep' or `consult-ripgrep' as
initial input, and is nil when the query carries no search terms.
:range is nil when the query carries no date directive."
  (let ((terms nil) (range nil))
    (dolist (token (my/notes-search--tokenize query))
      (pcase token
        (`(phrase . ,text)
         (push (my/notes-search--protect-dash (my/notes-search--literal text)) terms))
        (`(word . ,text)
         (if (string-match my/notes-search--date-directive-regexp text)
             (let* ((keyword (match-string 1 text))
                    (value (match-string 2 text))
                    (new (pcase keyword
                           ("from" (my/notes-search--parse-range (concat ">=" value)))
                           ("to" (my/notes-search--parse-range (concat "<=" value)))
                           (_ (my/notes-search--parse-range value)))))
               (setq range (my/notes-search--merge-range range new)))
           (push (my/notes-search--protect-dash text) terms)))))
    (list :pattern (when terms (string-join (nreverse terms) " "))
          :range range)))

;; ============================================================
;; BACK END ARGUMENTS
;; ============================================================

(defun my/notes-search--use-ripgrep-p ()
  "Return non-nil when content search should go through ripgrep."
  (and my/notes-search-prefer-ripgrep
       (executable-find "rg")
       (fboundp 'consult-ripgrep)))

(defun my/notes-search--file-args (globs ripgrep)
  "Return extra command-line arguments restricting the files searched.

GLOBS is a list of file-name globs, or nil for no date filter.  RIPGREP
selects the flag spelling.  The dot-directory exclusion is appended
last, because in both programs a later pattern wins over an earlier one
and the date globs are a whitelist."
  (append
   (mapcan (lambda (glob)
             (if ripgrep (list "-g" glob) (list (concat "--include=" glob))))
           globs)
   (if ripgrep (list "-g" "!.*") (list "--exclude-dir=.*"))))

;; ============================================================
;; COMMAND: content search
;; ============================================================

(defvar my/notes-search-query-history nil
  "Minibuffer history for `my/notes-grep'.")

(defun my/notes-search--query-prompt ()
  "Read a content-search query in the minibuffer."
  (read-string
   "Search notes (\"phrase\" words date:2012-01..2015-05): "
   nil 'my/notes-search-query-history))

;;;###autoload
(defun my/notes-grep (query)
  "Search the text of the notes for QUERY.

QUERY is read with the small language described in the header of this
module: quoted phrases are literal, unquoted words are regexps that must
all appear on the same line, and `date:', `from:' and `to:' restrict the
search to notes whose Denote identifier falls in a range.

The translated query is handed to consult as initial input, so the
search stays live from there: editing the pattern re-runs it, and text
typed after a second `#' filters the results without re-running
anything.

Docs: ~/.emacs.d/function_helper.org::#fn-notes-grep"
  (interactive (list (my/notes-search--query-prompt)))
  (unless (fboundp 'consult-grep)
    (user-error "Consult is not available; content search needs it"))
  (require 'grep nil t)
  (let* ((parsed (my/notes-search-parse query))
         (pattern (plist-get parsed :pattern))
         (globs (my/notes-search--date-globs (plist-get parsed :range)))
         (ripgrep (my/notes-search--use-ripgrep-p))
         (extra (my/notes-search--file-args globs ripgrep))
         ;; `consult-ripgrep-args' and `consult-grep-args' are read once,
         ;; when consult builds the command line, and that happens inside
         ;; the call below -- so a dynamic binding around it is enough,
         ;; and is what consult-denote does for the same purpose.  Both
         ;; options accept a list whose elements are strings or
         ;; expressions, so appending keeps whatever the user has set,
         ;; including the exclusion expression in the grep default.
         (rg-args (append (ensure-list consult-ripgrep-args) extra))
         (grep-args (append (ensure-list consult-grep-args) extra)))
    (if ripgrep
        (let ((consult-ripgrep-args rg-args))
          (consult-ripgrep my-notes-dir pattern))
      (let ((consult-grep-args grep-args))
        (consult-grep my-notes-dir pattern)))))

;; ============================================================
;; COMMAND: file-name search
;; ============================================================
;; Denote file names are `IDENTIFIER==SIGNATURE--TITLE__KEYWORDS.ext',
;; so a selector is just a regexp anchored on the separator that starts
;; the component:
;;
;;   title:  after `--', stopping before the keywords (`_' never occurs
;;           inside a sluggified title)
;;   tag:    a whole keyword between `_' and the next `_' or the dot of
;;           the extension -- an exact keyword rather than a prefix,
;;           because the prompt completes over the real vocabulary and a
;;           prefix match would make `tag:praca' also mean `pracownia'
;;
;; Several selectors are ANDed, which is why this filters a file list in
;; Lisp instead of handing one regexp to `denote-directory-files'.

(defvar my/notes-search-name-history nil
  "Minibuffer history for `my/notes-find-by-name'.")

(defun my/notes-search--slug (string)
  "Return STRING as it would appear inside a Denote file name."
  (cond
   ((fboundp 'denote-sluggify-title) (denote-sluggify-title string))
   (t (downcase (string-replace " " "-" string)))))

(defun my/notes-search--name-candidates ()
  "Return completion candidates for the file-name prompt.
The two selectors, plus every keyword already in use, so that the
vocabulary can be picked from a list instead of recalled."
  (append '("title:" "tag:")
          (when (fboundp 'denote-keywords)
            (mapcar (lambda (keyword) (concat "tag:" keyword))
                    (denote-keywords)))))

(defun my/notes-search--name-prompt ()
  "Read a file-name query in the minibuffer."
  (completing-read
   "Find note (title:word tag:keyword, or plain text): "
   (my/notes-search--name-candidates)
   nil nil nil 'my/notes-search-name-history))

(defun my/notes-search--name-regexps (query)
  "Return the list of regexps QUERY imposes on a Denote file name."
  (let ((regexps nil))
    (dolist (token (my/notes-search--tokenize query))
      (let ((text (cdr token)))
        ;; As in `my/notes-search--parse-range': the value is taken out
        ;; of the match data before the slugifier gets a chance to run a
        ;; regexp of its own and replace it.
        (cond
         ((string-match "\\`title:\\(.+\\)\\'" text)
          (let ((value (match-string 1 text)))
            (push (concat "--[^_/]*" (regexp-quote (my/notes-search--slug value)))
                  regexps)))
         ((string-match "\\`tag:\\(.+\\)\\'" text)
          (let ((value (match-string 1 text)))
            (push (concat "_" (regexp-quote (my/notes-search--slug value)) "[_.]")
                  regexps)))
         ((string-empty-p text) nil)
         (t (push (regexp-quote (my/notes-search--slug text)) regexps)))))
    (nreverse regexps)))

(defun my/notes-search--matching-files (query)
  "Return the notes whose file name satisfies every selector in QUERY.
Newest first, by identifier."
  (let ((regexps (my/notes-search--name-regexps query))
        (files (denote-directory-files)))
    (when regexps
      (setq files
            (seq-filter
             (lambda (file)
               (let ((name (file-name-nondirectory file))
                     (case-fold-search t))
                 (seq-every-p (lambda (re) (string-match-p re name)) regexps)))
             files)))
    (sort files (lambda (a b)
                  (string> (file-name-nondirectory a)
                           (file-name-nondirectory b))))))

;;;###autoload
(defun my/notes-find-by-name (query &optional list-them)
  "Open a note whose file name matches QUERY.

QUERY is a sequence of selectors: `title:word' matches inside the title,
`tag:keyword' matches one whole keyword, and anything else matches
anywhere in the file name.  Several selectors all have to match.  The
prompt completes over the keywords already in use, so `tag:' can be
picked from a list rather than remembered.

With a prefix argument, or when LIST-THEM is non-nil, show every match
in a Dired buffer instead of asking which one to open.

Docs: ~/.emacs.d/function_helper.org::#fn-notes-find-by-name"
  (interactive (list (my/notes-search--name-prompt) current-prefix-arg))
  (unless (fboundp 'denote-directory-files)
    (user-error "Denote is not available; file-name search needs it"))
  (let ((files (my/notes-search--matching-files query)))
    (cond
     ((null files)
      (message "No note matches `%s'" query))
     (list-them
      (let ((buffer (dired (cons my-notes-dir files))))
        (with-current-buffer buffer
          (rename-buffer (format "*notes: %s*" query) :unique))))
     (t
      (let* ((relative (mapcar (lambda (file)
                                 (cons (file-relative-name file my-notes-dir) file))
                               files))
             (choice (completing-read
                      (format "Open note (%d matching): " (length files))
                      relative nil t)))
        (find-file (alist-get choice relative nil nil #'equal)))))))

;; ============================================================
;; MENU
;; ============================================================
;; "g" is taken over rather than added next to: the new command with an
;; empty date range and no quotes does exactly what the old one did, so
;; two entries would differ only in which one is remembered.  The
;; takeover goes through `my/transient-replace', which skips when the
;; menu or the key is absent, and 12-transient.el keeps declaring the
;; plain `consult-denote-grep' on that key -- so deleting this file
;; restores the previous behaviour on the next start instead of leaving
;; a void command behind.

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-replace)
    (my/transient-replace 'my/notes-find-menu "g"
                          '("g" "Grep notes" my/notes-grep)))
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-find-menu "g"
                         '("n" "Find by title/tag" my/notes-find-by-name))))

(provide '41-notes-search)
;;; 41-notes-search.el ends here
