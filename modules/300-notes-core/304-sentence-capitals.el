;;; 304-sentence-capitals.el --- Capital letter at the start of a sentence, while typing -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; MyPKS-Default: off
;; MyPKS-Switch: my/sentence-capitals-mode
;; MyPKS-Writes: dictionaries/sentence-abbreviations, dictionaries/.gitattributes of the settings folder
;; Docs: ~/.emacs.d/function_helper.org::#sentence-capitals

;;; Commentary:
;; The first word of a sentence gets its capital letter when the word
;; is finished (the space or punctuation typed after it), as a word
;; processor does it: "kot. pies " becomes "kot. Pies ".  Org buffers
;; only, and in them only prose: paragraphs (also in lists and quote
;; blocks) and headline titles.
;;
;; THE PACKAGE
;; -----------
;; captain (GNU ELPA, by Jessica Pavelka) does the typing side: a
;; buffer-local `post-self-insert-hook' that, when a word has just been
;; finished, asks two buffer-local functions whether to act here
;; (`captain-predicate') and where the current sentence starts
;; (`captain-sentence-start-function'), and capitalizes the word when it
;; is the first one.  A word that already holds a capital letter
;; (iPhone, NATO) is left as it is.  This module supplies the two
;; functions for Org; nothing of captain is changed.
;;
;; WHERE A SENTENCE STARTS
;; -----------------------
;; Emacs's own sentence motion (`forward-sentence', with
;; `sentence-end-double-space' nil: one space after a full stop is
;; enough), narrowed to the Org element being written -- a paragraph's
;; text, a headline's title -- so that a sentence never runs on into a
;; list bullet, a keyword line or the previous item.  The first word of
;; a paragraph, of a list item and of a headline title is a sentence
;; start.  `my/sentence-capitals-in-lists' and
;; `my/sentence-capitals-in-headings' take items and titles out.
;;
;; A full stop does not end a sentence after:
;;   - an abbreviation of the list below (np., tzn., m.in., e.g.);
;;   - one letter (J. Kowalski, a. b. c.) and a number of one to three
;;     digits (2. rozdział) or in Roman figures I, V, X (XX. wiek):
;;     ordinals in Polish;
;;   - an ellipsis, "..." or "…": in Polish it ends a sentence or
;;     pauses within one, and which of the two is not something to
;;     guess.
;; In all these cases the next word stays as typed.  The choice is
;; deliberate: a capital that was wanted and not given costs one shift
;; key, a capital given where it was not wanted costs an undo and
;; breaks the sentence being written.
;;
;; THE ABBREVIATIONS
;; -----------------
;; A built-in list, Polish and English (`my/sentence-capitals--default-abbreviations'),
;; and the owner's own in the settings folder, shared by every machine:
;;
;;   <settings folder>/dictionaries/sentence-abbreviations
;;
;; One abbreviation per line, with its full stop; a line "-abbr." takes
;; a built-in one out; lines starting with # are comments.  The file is
;; written by `my/sentence-capitals-add-abbreviation' and
;; `my/sentence-capitals-remove-abbreviation' (C-c n t + and -), and may
;; be edited by hand; it is read again when it changes on disk (a pull
;; of the settings folder).  Lines added on two machines are both kept
;; by git (merge=union, `my/git-merge-by-union').  Matching ignores
;; case: "np." also covers "Np.".  Words that are also ordinary words
;; at the end of a sentence (Polish "im.", English "red.", "art.",
;; "no.") are not in the built-in list.
;;
;; THE SWITCH
;; ----------
;; `my/sentence-capitals-mode' (C-c n , m like every module) turns it
;; on in every Org buffer, open and future; C-c n t c turns it off or on
;; in one buffer only.  C-/ undoes a capital together with the
;; characters typed just before it, as any typing.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'org)
(require 'org-element)

(use-package captain
  :defer t)

;; captain's buffer-local variables, set before captain-mode is turned
;; on in a buffer; captain.el defines them.
(defvar captain-predicate)
(defvar captain-sentence-start-function)
(defvar captain-mode)
(declare-function captain-mode "ext:captain" (&optional arg))

(defgroup my/sentence-capitals nil
  "Capital letter at the start of a sentence, while typing in Org."
  :tag "Capital letters at sentence start"
  :group 'mypks-writing)

(defcustom my/sentence-capitals-in-lists t
  "Non-nil: the first word of a list item gets a capital letter.
Nil leaves it as typed: a Polish list continuing a sentence that ends
with a colon starts its items with a small letter."
  :type 'boolean
  :group 'my/sentence-capitals)

(defcustom my/sentence-capitals-in-headings t
  "Non-nil: the first word of a headline title gets a capital letter."
  :type 'boolean
  :group 'my/sentence-capitals)

(defcustom my/sentence-capitals-abbreviations-file
  (expand-file-name "dictionaries/sentence-abbreviations" my/settings-directory)
  "File with the owner's abbreviations, one per line, with the full stop.
A line \"-abbr.\" takes a built-in abbreviation out; lines starting
with # are comments.  In the settings folder, next to the personal
dictionary, so that every machine shares it."
  :type 'file
  :group 'my/sentence-capitals)

;; ============================================================
;; ABBREVIATIONS
;; ============================================================

(defconst my/sentence-capitals--default-abbreviations
  '(;; Polish: only those written with a full stop.  Abbreviations
    ;; ending in the last letter of the word (dr, mgr, nr, wg, zł,
    ;; mln) take none in Polish and need no entry.
    "np." "tzn." "tj." "tzw." "itd." "itp." "m.in." "ok." "ca." "godz."
    "prof." "doc." "hab." "inż." "ks." "św." "gen." "kpt."
    "ul." "al." "pl." "os." "woj." "pow." "gm." "tel." "wew."
    "str." "cz." "rozdz." "ryc." "rys." "tab." "zob." "por." "tłum."
    "wyd." "oprac." "przyp." "cyt." "poz." "ust." "lit." "jw." "ww."
    "tys." "ds." "dot." "dn." "ur." "zm." "zw." "wsp." "pt."
    "br." "ub." "bm." "n.e." "p.n.e."
    "ang." "łac." "niem." "fr." "ros." "wł."
    ;; English.
    "e.g." "i.e." "etc." "vs." "cf." "approx." "viz." "resp." "incl."
    "esp." "mr." "mrs." "ms." "dr." "st." "jr." "sr." "fig." "figs."
    "eq." "vol." "vols." "ed." "eds." "trans." "pp." "ch." "op.")
  "Abbreviations after which the next word is not a sentence start.
Lower case, with the full stop.  Changed per machine group by
`my/sentence-capitals-abbreviations-file'.")

(defconst my/sentence-capitals--file-header
  "# Abbreviations after which a word gets no capital letter (304-sentence-capitals.el).
# One per line, with its full stop.  A line \"-abbr.\" takes a built-in one out.
# Written by C-c n t + and C-c n t -; may be edited by hand.
"
  "Start of a new abbreviations file.")

(defvar my/sentence-capitals--cache nil
  "(MODIFICATION-TIME . ABBREVIATIONS) of the file when last read.")

(defun my/sentence-capitals--file ()
  "Return the abbreviations file, expanded."
  (expand-file-name my/sentence-capitals-abbreviations-file))

(defun my/sentence-capitals--file-lines ()
  "Return the entries of the abbreviations file, comments and blanks left out."
  (let ((file (my/sentence-capitals--file)))
    (when (file-readable-p file)
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents file))
        (seq-remove (lambda (line) (or (string-empty-p line)
                                       (string-prefix-p "#" line)))
                    (mapcar #'string-trim
                            (split-string (buffer-string) "\n")))))))

(defun my/sentence-capitals--effective (lines)
  "Return the abbreviations in force: the built-in ones changed by LINES.
LINES as the file holds them: \"abbr.\" adds, \"-abbr.\" takes out."
  (let ((list (copy-sequence my/sentence-capitals--default-abbreviations)))
    (dolist (line lines)
      (let ((entry (downcase line)))
        (if (string-prefix-p "-" entry)
            (setq list (delete (substring entry 1) list))
          (unless (member entry list)
            (push entry list)))))
    (sort list #'string<)))

(defun my/sentence-capitals-abbreviations ()
  "Return the abbreviations in force, lower case, sorted.
The file is read again only when its modification time has changed."
  (let ((mtime (file-attribute-modification-time
                (file-attributes (my/sentence-capitals--file)))))
    (if (and my/sentence-capitals--cache
             (equal (car my/sentence-capitals--cache) mtime))
        (cdr my/sentence-capitals--cache)
      (let ((list (my/sentence-capitals--effective
                   (my/sentence-capitals--file-lines))))
        (setq my/sentence-capitals--cache (cons mtime list))
        list))))

(defun my/sentence-capitals--continues-p (token)
  "Non-nil when TOKEN, the text before a sentence end, does not end a sentence.
TOKEN is everything between the previous whitespace and the end of the
punctuation: an abbreviation (np.), one letter or a short number with a
full stop, or a word followed by an ellipsis."
  (let ((case-fold-search nil)
        (word (string-trim token "[[({\"'„“«‹]+" "[])}\"'”’»›]+")))
    (or (string-match-p "\\(?:\\.\\.\\.\\|…\\)\\'" word)
        (and (string-suffix-p "." word)
             (or (string-match-p "\\`[[:alpha:]]\\.\\'" word)
                 (string-match-p "\\`[0-9]\\{1,3\\}\\.\\'" word)
                 (string-match-p "\\`[IVX]+\\.\\'" word)
                 (member (downcase word) (my/sentence-capitals-abbreviations))))
        nil)))

(defun my/sentence-capitals--token-before (pos)
  "Return the run of non-whitespace characters ending before POS's whitespace."
  (save-excursion
    (goto-char pos)
    (skip-chars-backward " \t\n ")
    (let ((end (point)))
      (skip-chars-backward "^ \t\n ")
      (buffer-substring-no-properties (point) end))))

;; ============================================================
;; WHERE CAPTAIN ACTS, AND WHERE A SENTENCE STARTS
;; ============================================================

(defconst my/sentence-capitals--excluded-objects
  '(link code verbatim timestamp latex-fragment citation citation-reference
    inline-src-block inline-babel-call footnote-reference statistics-cookie
    target radio-target macro export-snippet entity table-cell)
  "Org objects inside which nothing is capitalized.")

(defun my/sentence-capitals--text-p ()
  "Non-nil at point in Org prose: `captain-predicate' of this module.
A paragraph or a headline title, outside links, code, verbatim,
timestamps, citations and the like."
  (and (derived-mode-p 'org-mode)
       (memq (org-element-type (org-element-at-point)) '(paragraph headline))
       (not (memq (org-element-type (org-element-context))
                  my/sentence-capitals--excluded-objects))))

(defun my/sentence-capitals--region ()
  "Return (BEG . END) of the text a sentence at point may span, or nil.
A paragraph's contents, which inside a list item start after the
bullet and the check box; a headline's title, without its stars, TODO
keyword, priority and tags."
  (let ((element (org-element-at-point)))
    (pcase (org-element-type element)
      ('paragraph
       (let ((beg (org-element-property :contents-begin element))
             (end (org-element-property :contents-end element)))
         (and beg end (cons beg end))))
      ('headline
       (and my/sentence-capitals-in-headings
            (save-excursion
              (beginning-of-line)
              (let ((case-fold-search nil))
                (and (looking-at org-complex-heading-regexp)
                     (match-beginning 4)
                     (cons (match-beginning 4) (match-end 4))))))))))

(defun my/sentence-capitals--item-start-p (pos)
  "Non-nil when POS is where the text of a list item starts.
Also when called narrowed to that text: the bullet is outside."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char pos)
      (beginning-of-line)
      (and (looking-at org-list-full-item-re)
           (= (match-end 0) pos)))))

(defun my/sentence-capitals--sentence-start ()
  "Return where the sentence at point starts, or nil to leave the word alone.
`captain-sentence-start-function' of this module; captain calls it with
point at the start of the word just finished."
  (when-let* ((region (my/sentence-capitals--region)))
    (save-restriction
      (narrow-to-region (car region) (cdr region))
      (let* ((sentence-end-double-space nil)
             (start (car (bounds-of-thing-at-point 'sentence))))
        (cond
         ((null start) nil)
         ;; The first sentence of the paragraph or title.
         ((= start (point-min))
          (and (or my/sentence-capitals-in-lists
                   (not (my/sentence-capitals--item-start-p start)))
               start))
         ((my/sentence-capitals--continues-p
           (my/sentence-capitals--token-before start))
          nil)
         (t start))))))

;; ============================================================
;; BUFFERS
;; ============================================================

(defvar my/sentence-capitals--warned nil
  "Non-nil once the missing captain package has been reported.")

(defun my/sentence-capitals--buffer (arg)
  "Turn captain on in this buffer with this module's functions (ARG > 0), or off.
Off only where this module turned it on."
  (if (> arg 0)
      (if (not (require 'captain nil t))
          (unless my/sentence-capitals--warned
            (setq my/sentence-capitals--warned t)
            (message "Capitals at sentence start: the captain package is not installed (M-x package-install RET captain)"))
        (setq-local captain-predicate #'my/sentence-capitals--text-p)
        (setq-local captain-sentence-start-function
                    #'my/sentence-capitals--sentence-start)
        (captain-mode 1))
    (when (and (local-variable-p 'captain-predicate)
               (eq captain-predicate #'my/sentence-capitals--text-p))
      (when (bound-and-true-p captain-mode)
        (captain-mode -1))
      (kill-local-variable 'captain-predicate)
      (kill-local-variable 'captain-sentence-start-function))))

(defun my/sentence-capitals--setup ()
  "Turn capitals at sentence start on in a new Org buffer."
  (my/sentence-capitals--buffer 1))

(defun my/sentence-capitals-toggle-buffer ()
  "Turn capitals at sentence start off or on in this buffer only."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Capitals at sentence start work in Org buffers only"))
  (if (bound-and-true-p captain-mode)
      (progn (my/sentence-capitals--buffer -1)
             (message "Capitals at sentence start: off in this buffer"))
    (my/sentence-capitals--buffer 1)
    (when (bound-and-true-p captain-mode)
      (message "Capitals at sentence start: on in this buffer"))))

;; ============================================================
;; COMMANDS: THE OWNER'S ABBREVIATIONS
;; ============================================================

(defun my/sentence-capitals--valid-p (abbreviation)
  "Non-nil when ABBREVIATION is one word with a letter, ending in a full stop."
  (string-match-p "\\`[^ \t\n]*[[:alpha:]][^ \t\n]*\\.\\'" abbreviation))

(defun my/sentence-capitals--write (lines)
  "Write LINES as the abbreviations file, under its comment header."
  (let ((file (my/sentence-capitals--file)))
    (make-directory (file-name-directory file) t)
    (with-temp-buffer
      (insert my/sentence-capitals--file-header)
      (dolist (line lines)
        (insert line "\n"))
      (let ((coding-system-for-write 'utf-8-unix))
        (my/write-region-atomically file)))
    (my/git-merge-by-union file "304-sentence-capitals.el")
    (setq my/sentence-capitals--cache nil)))

(defun my/sentence-capitals--default-before-point ()
  "Return the word before point when it ends in a full stop, else nil."
  (let ((token (string-trim (my/sentence-capitals--token-before (point))
                            "[[({\"'„“«‹]+" "[])}\"'”’»›,;:]+")))
    (and (my/sentence-capitals--valid-p token) (downcase token))))

(defun my/sentence-capitals-add-abbreviation (abbreviation)
  "Add ABBREVIATION: after it, the next word gets no capital letter.
One word ending in a full stop, as np. or m.in.; the word before point
is offered when it is one.  Kept in `my/sentence-capitals-abbreviations-file'."
  (interactive
   (let ((default (my/sentence-capitals--default-before-point)))
     (list (read-string (format-prompt "Abbreviation, with its full stop" default)
                        nil nil default))))
  (let ((abbreviation (downcase (string-trim abbreviation)))
        (lines (my/sentence-capitals--file-lines)))
    (unless (my/sentence-capitals--valid-p abbreviation)
      (user-error "An abbreviation is one word ending in a full stop, as np. or m.in."))
    (cond
     ((member abbreviation (my/sentence-capitals-abbreviations))
      (message "%s is on the list already" abbreviation))
     (t
      ;; A built-in one taken out before comes back by removing that line.
      (my/sentence-capitals--write
       (if (member (concat "-" abbreviation) (mapcar #'downcase lines))
           (seq-remove (lambda (line) (string= (downcase line) (concat "-" abbreviation)))
                       lines)
         (append lines (list abbreviation))))
      (message "Added %s: the word after it keeps the letter it is typed with"
               abbreviation)))))

(defun my/sentence-capitals-remove-abbreviation (abbreviation)
  "Remove ABBREVIATION: a full stop after it ends a sentence again.
Chosen from the abbreviations in force.  One of the owner's is deleted
from `my/sentence-capitals-abbreviations-file'; a built-in one is taken
out there with a line \"-ABBREVIATION\"."
  (interactive
   (let* ((list (my/sentence-capitals-abbreviations))
          (here (my/sentence-capitals--default-before-point))
          (default (and (member here list) here)))
     (list (completing-read (format-prompt "Remove abbreviation" default)
                            list nil t nil nil default))))
  (let* ((abbreviation (downcase (string-trim abbreviation)))
         (lines (seq-remove (lambda (line) (string= (downcase line) abbreviation))
                            (my/sentence-capitals--file-lines))))
    (unless (member abbreviation (my/sentence-capitals-abbreviations))
      (user-error "%s is not on the list" abbreviation))
    (when (member abbreviation my/sentence-capitals--default-abbreviations)
      (setq lines (append lines (list (concat "-" abbreviation)))))
    (my/sentence-capitals--write lines)
    (message "Removed %s: a full stop after it ends a sentence" abbreviation)))

;; ============================================================
;; SWITCH
;; ============================================================

(defconst my/sentence-capitals--menu-entries
  '((insert my/notes-tools-menu (0 0)
            ["Capitals"
             ("c" "In this buffer"     my/sentence-capitals-toggle-buffer)
             ("+" "Add abbreviation"    my/sentence-capitals-add-abbreviation)
             ("-" "Remove abbreviation" my/sentence-capitals-remove-abbreviation)]))
  "Menu entries of this module, for `my/transient-entries'.
A column at the front of the Tools menu (C-c n t).")

(define-minor-mode my/sentence-capitals-mode
  "Capital letter at the start of a sentence, while typing in Org.
On in every Org buffer, open and future; off in all of them.  One
buffer alone: `my/sentence-capitals-toggle-buffer'.  Customize saves
the position in this machine's settings."
  :global t
  :init-value t
  :group 'my/sentence-capitals
  (if my/sentence-capitals-mode
      (add-hook 'org-mode-hook #'my/sentence-capitals--setup)
    (remove-hook 'org-mode-hook #'my/sentence-capitals--setup))
  (setq my/sentence-capitals--cache nil)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (my/sentence-capitals--buffer (if my/sentence-capitals-mode 1 -1)))))
  (with-eval-after-load '212-transient
    (when (fboundp 'my/transient-entries)
      (my/transient-entries my/sentence-capitals-mode
                            my/sentence-capitals--menu-entries))))

;; The switch, applied with the position Customize read from this
;; machine's custom.el.
(my/sentence-capitals-mode (if my/sentence-capitals-mode 1 -1))

(provide '304-sentence-capitals)
;;; 304-sentence-capitals.el ends here
