;;; 45-standard-pages.el --- Standard pages of prose -*- lexical-binding: t; -*-
;;; Commentary:
;; How much text a note will amount to, measured in STANDARD PAGES.
;;
;; WHAT A STANDARD PAGE IS
;; -----------------------
;; The Polish publishing and translation convention: 1800 characters
;; INCLUDING SPACES is one page (`strona znormalizowana', 1800 znakow ze
;; spacjami).  It is the unit commissions, translation rates and
;; university requirements are written in, which is why it is worth
;; having on screen while writing rather than worked out afterwards.
;; 1600 is used in some literary contexts; `my/standard-page-characters'
;; holds the number, so either convention is one setting away.
;;
;; WHAT COUNTS AS PROSE
;; --------------------
;; Only what will end up in the exported document.  Skipped:
;;
;;   #+keyword: lines, which includes #+begin_ and #+end_ directives
;;   property and LOGBOOK drawers, from the opener to :END:
;;   Org comment lines (#)
;;   Markdown code fences and YAML front matter
;;
;; Kept: ordinary paragraphs, headline text without its stars, table
;; rows, and the BODY of a quote or source block.  A block's contents
;; are exported and read as text; only the two directives around them
;; are machinery.
;;
;; APPROXIMATION WORTH KNOWING
;; ---------------------------
;; Each counted line contributes its trimmed length plus one character
;; for the break that follows it, which is what a space between two
;; words would have been had the paragraph been one long line.  A note
;; written with hard line breaks therefore counts a fraction of a
;; percent differently from the same text soft-wrapped.  Publishers
;; count the exported file, and no counter that reads Org source can
;; match that exactly; this one is meant to answer "roughly how long is
;; this" while typing, and it does.
;;
;; WHERE IT SHOWS
;; --------------
;; In the mode line, beside the word count, which 01-ui.el owns and
;; which calls into this module when it is loaded.  With a region
;; active, both numbers describe the region and are shown in brackets.
;; `M-x my/standard-pages-report' gives the exact figures.
;;
;; Docs: ~/.emacs.d/function_helper.org::#standard-pages

;;; Code:

(require 'subr-x)

(defgroup my-standard-pages nil
  "Counting prose in standard pages.
Named without the slash, matching `my-journal-gaps' in
35-journal-gaps.el: a group sharing a symbol with a command makes both
harder to find, and the pre-commit duplicate scan cannot tell the two
apart."
  :group 'convenience)

(defcustom my/standard-page-characters 1800
  "Characters, spaces included, in one standard page.
1800 is the usual Polish convention; 1600 appears in some literary
contracts."
  :type 'integer :group 'my-standard-pages)

(defcustom my/standard-pages-modes '(org-mode markdown-mode text-mode)
  "Modes the counter is computed in.
Derived modes count, so `denote' notes and Markdown notes are both
covered by the entries above."
  :type '(repeat symbol) :group 'my-standard-pages)

;; ============================================================
;; COUNTING
;; ============================================================

(defconst my/standard-pages--drawer-open
  "\\`[ \t]*:[A-Za-z][A-Za-z0-9_@#%-]*:[ \t]*\\'"
  "A line opening a drawer, property or otherwise.")

(defconst my/standard-pages--drawer-close "\\`[ \t]*:END:[ \t]*\\'"
  "The line closing any drawer.")

(defun my/standard-pages--line-prose (line state)
  "Return the prose of LINE, or nil, given and updating parser STATE.

STATE is a cons of (IN-DRAWER . IN-FRONT-MATTER), destructively
updated, because the classification of a line depends on the ones
before it and a line-at-a-time scan is what keeps this cheap enough to
run from the mode line."
  (cond
   ;; Inside a drawer: nothing until :END:, which is itself skipped.
   ((car state)
    (when (string-match-p my/standard-pages--drawer-close line)
      (setcar state nil))
    nil)
   ;; Inside Markdown YAML front matter: nothing until the closing ---.
   ((cdr state)
    (when (string-match-p "\\`---[ \t]*\\'" line)
      (setcdr state nil))
    nil)
   ((string-match-p my/standard-pages--drawer-open line)
    (setcar state t)
    nil)
   ;; #+keyword:, #+begin_src, #+end_quote -- machinery, not prose.
   ((string-match-p "\\`[ \t]*#\\+" line) nil)
   ;; Org comment.
   ((string-match-p "\\`[ \t]*#\\([ \t]\\|\\'\\)" line) nil)
   ;; Markdown code fence.
   ((string-match-p "\\`[ \t]*\\(```\\|~~~\\)" line) nil)
   ;; Headline: the stars are markup, the text is prose.
   ((string-match "\\`\\*+[ \t]+\\(.*\\)\\'" line) (match-string 1 line))
   (t line)))

(defun my/standard-pages-characters (beg end)
  "Return the number of prose characters between BEG and END.
See the header of 45-standard-pages.el for what counts as prose and for
the one-character-per-line-break approximation."
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      ;; The front-matter flag starts true only when the region opens on
      ;; the `---' of a Markdown file; anywhere else a `---' line is a
      ;; horizontal rule and must not swallow the rest of the note.
      (let* ((state (cons nil (and (derived-mode-p 'markdown-mode)
                                   (= (point-min) (point))
                                   (looking-at-p "---[ \t]*$"))))
             (count 0))
        (when (cdr state) (forward-line 1))
        (while (not (eobp))
          (let* ((line (buffer-substring-no-properties
                        (line-beginning-position) (line-end-position)))
                 (prose (my/standard-pages--line-prose line state)))
            (when prose
              (let ((trimmed (string-trim prose)))
                (unless (string-empty-p trimmed)
                  ;; +1 stands for the break after the line, which is a
                  ;; space once the paragraph is exported.
                  (setq count (+ count (length trimmed) 1))))))
          (forward-line 1))
        ;; The last line has no break after it.
        (max 0 (1- count))))))

;; ============================================================
;; CACHE
;; ============================================================
;; The mode line is redrawn after every keystroke, and scanning a long
;; note line by line that often is not free.  `buffer-chars-modified-tick'
;; changes exactly when the text does, so a count taken at one tick is
;; still correct at the same tick; the bounds are part of the key so
;; that a region and the whole buffer do not overwrite each other.

(defvar-local my/standard-pages--cache nil
  "Last result, as (TICK BEG END CHARACTERS).")

(defun my/standard-pages-cached (beg end)
  "Return the prose characters between BEG and END, from cache when valid."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (equal (list tick beg end) (butlast my/standard-pages--cache))
      (setq my/standard-pages--cache
            (list tick beg end (my/standard-pages-characters beg end))))
    (car (last my/standard-pages--cache))))

(defun my/standard-pages (beg end)
  "Return the number of standard pages between BEG and END, as a float."
  (/ (float (my/standard-pages-cached beg end))
     (max 1 my/standard-page-characters)))

;; ============================================================
;; MODE LINE
;; ============================================================

(defun my/standard-pages-active-p ()
  "Return non-nil when the counter applies to this buffer."
  (apply #'derived-mode-p my/standard-pages-modes))

(defun my/standard-pages-string (beg end)
  "Return the mode-line text for the pages between BEG and END, or nil."
  (when (my/standard-pages-active-p)
    (format " %.1fp" (my/standard-pages beg end))))

;; ============================================================
;; REPORT
;; ============================================================

;;;###autoload
(defun my/standard-pages-report ()
  "Report prose characters, words and standard pages for this buffer.
Describes the region when one is active, the whole buffer otherwise."
  (interactive)
  (let* ((region (use-region-p))
         (beg (if region (region-beginning) (point-min)))
         (end (if region (region-end) (point-max)))
         (characters (my/standard-pages-characters beg end)))
    (message "%s: %d prose characters, %d words, %.2f standard pages (%d each)"
             (if region "Region" "Buffer")
             characters (count-words beg end)
             (/ (float characters) (max 1 my/standard-page-characters))
             my/standard-page-characters)))

(provide '45-standard-pages)
;;; 45-standard-pages.el ends here
