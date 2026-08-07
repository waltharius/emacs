;;; 06-capture.el --- Org-capture for ideas -*- lexical-binding: t; -*-
;;; Commentary:
;; Quick capture system for ideas and fleeting thoughts.
;;
;; C-c n c    — Ideas capture (opens to the RIGHT of the current window)
;; C-c c      — Standard org-capture menu
;;
;; Confirming a capture with C-c C-c asks one question with three
;; answers: TAB onto an existing capture heading files the text under it,
;; typed text names the capture's own heading, and an empty answer leaves
;; it untitled exactly as before.  Filing under an existing heading
;; appends the text with a source line instead of a property drawer, so a
;; continuing thread stays one heading rather than becoming two nearly
;; identical ones.
;;
;; Processing captures:
;; C-c n c m  — Promote heading to Denote note (create or append)
;; C-c C-w    — Refile heading to existing note (standard org-refile)
;;
;; A capture heading gathered this way holds material from several
;; origins.  C-c n c m carries each across in capture order with its own
;; source line, emitting one only when the origin changes.
;;
;; Keywords for a promoted note are read by `my/notes-read-keywords'
;; from 05-notes.el, which init.el loads first, so that every tag
;; prompt in this configuration completes against the same vocabulary.
;;
;; HOW THE RIGHT-SIDE WINDOW WORKS
;; --------------------------------
;; org-capture-mode-hook fires after the capture buffer is created
;; and displayed. At that point we:
;;   1. Remember which window was selected when capture was invoked
;;      (stored in my/capture--origin-window before org-capture runs).
;;   2. In the hook, delete all windows except the origin, then split
;;      right, and display the capture buffer in the new right window.
;; This bypasses display-buffer-alist entirely, which org-capture
;; ignores for its own buffer management.

;;; Code:

(require 'org)
(require 'org-capture)
(require 'org-element)
(require 'subr-x)
(require 'seq)
;; This module calls `denote', `denote-retrieve-filename-identifier'
;; and reads `denote-last-path', so declare the dependency explicitly
;; instead of relying on load order of other modules.
(require 'denote)

;; ============================================================
;; CAPTURE WINDOW: track origin window before capture fires
;; ============================================================

(defvar my/capture--origin-window nil
  "Window that was selected when `my/capture-idea' was invoked.
Used by `my/capture--show-right' to place the capture buffer
to the right of the originating note window.")

(defun my/capture--show-right ()
  "Place the just-created capture buffer to the right of the origin window.
Called from `org-capture-mode-hook'.
Only acts when `my/capture--origin-window' is set (i.e. capture was
started via `my/capture-idea', not the generic org-capture menu)."
  (when (and my/capture--origin-window
             (window-live-p my/capture--origin-window))
    (let ((cap-buf (current-buffer)))
      (delete-other-windows my/capture--origin-window)
      (let ((right-win (split-window my/capture--origin-window nil 'right)))
        (set-window-buffer right-win cap-buf)
        (select-window right-win))
      (setq my/capture--origin-window nil))))

(add-hook 'org-capture-mode-hook #'my/capture--show-right)

;; ============================================================
;; HELPER: Get #+title: from ORIGINAL buffer
;; ============================================================

(defun my/get-capture-origin-title ()
  "Get #+title: from the buffer where capture was initiated."
  (let ((orig-buf (org-capture-get :original-buffer)))
    (if orig-buf
        (with-current-buffer orig-buf
          (condition-case nil
              (or (when (eq major-mode 'org-mode)
                    (cadar (org-collect-keywords '("title"))))
                  (when (buffer-file-name)
                    (file-name-base (buffer-file-name)))
                  (buffer-name)
                  "Untitled")
            (error "Untitled")))
      "Untitled")))

;; ============================================================
;; HELPER: Get denote: link from ORIGINAL buffer
;; ============================================================

(defun my/get-capture-origin-id ()
  "Get denote: link from the buffer where capture was initiated."
  (let ((orig-buf (org-capture-get :original-buffer)))
    (if orig-buf
        (with-current-buffer orig-buf
          (condition-case nil
              (let ((file-path (buffer-file-name)))
                (if file-path
                    (let ((id (denote-retrieve-filename-identifier file-path)))
                      (if id
                          (format "denote:%s" id)
                        (format "file:%s" file-path)))
                  "Untitled"))
            (error "Untitled")))
      "Untitled")))

;; ============================================================
;; ORG-CAPTURE: Templates
;; ============================================================

(use-package org-capture
  :ensure nil
  :config

  (unless (file-exists-p my-journal-captures)
    (with-temp-file my-journal-captures
      (insert "#+title: Ideas\n")
      (insert "#+filetags: :captures:\n\n")
      (insert "* Ideas\n\n")))

  (setq org-capture-templates
        '(("j" "Ideas capture" entry
           (file+headline my-journal-captures "Ideas")
           "* \n:PROPERTIES:\n:SOURCE: [[%(my/get-capture-origin-id)][%(my/get-capture-origin-title)]]\n:CAPTURED: %U\n:END:\n\n%?"
           :empty-lines 1
           :prepend nil))))

;; ============================================================
;; DIRECT CAPTURE: C-c n c fires template "j" without menu
;; ============================================================


;; ============================================================
;; SOURCE LINES: one format, used in both files
;; ============================================================
;; A capture carries where it came from and when.  Under its own heading
;; that is a property drawer, which Org only recognises directly beneath
;; a heading.  A fragment appended into an existing heading has no
;; heading of its own, so the same information has to be body text, and
;; body text is also what a promoted note receives.  One format serves
;; both:
;;
;;   Source: [[denote:20260715T101500][Przewodnik po bibliografii]] — [2026-08-02 nie 18:10]
;;
;; Both sides of this file read and write it through the three functions
;; below, so the capture side and the promotion side cannot drift apart.
;;
;; CAVEAT worth knowing: a line of ordinary prose that begins with
;; "Source:" will be read as metadata.  Indent it or rephrase it.

(defconst my/capture-source-line-regexp "\\`Source:[ \t]*\\(.+\\)\\'"
  "Match a source line, capturing everything after the label.")

(defun my/capture--source-value (source captured)
  "Combine SOURCE and CAPTURED into the value of a source line.
Either may be nil.  Returns nil when SOURCE is missing, since a
timestamp without an origin says nothing useful."
  (when (and source (not (string-empty-p (string-trim source))))
    (if (and captured (not (string-empty-p (string-trim captured))))
        (format "%s — %s" (string-trim source) (string-trim captured))
      (string-trim source))))

(defun my/capture--source-key (value)
  "Return the identity of source line VALUE for duplicate suppression.

The bracket link when there is one, so that the same origin captured
at two different times counts as one source; otherwise the whole
value.  Returns nil for nil."
  (when value
    (if (string-match "\\[\\[.*?\\]\\]" value)
        (match-string 0 value)
      (string-trim value))))

;; ============================================================
;; FILING A CAPTURE UNDER AN EXISTING HEADING
;; ============================================================
;; A capture often continues a thread that already has a heading in
;; captures.org.  Retyping that heading is how near-duplicates are born:
;; "Do poprawy w moim systemie notowania Emacs" against the same words
;; with one letter different is two headings to Org, and two notes once
;; each is promoted.
;;
;; So the choice is offered at the moment of confirming, when what was
;; written is on screen and it is clear which thread it belongs to.
;; Choosing an existing heading appends the text under it with a source
;; line instead of a drawer -- no second heading, nothing to retype, and
;; nothing for `my/capture-promote-to-note' to mistake for a separate
;; subject.
;;
;; The same prompt names a capture that is starting a new thread, because
;; that is the same decision seen from the other side, and because the
;; template leaves the headline empty: without somewhere to type a title,
;; every new capture arrives unnamed and promotion has no default.
;;
;; HOW IT WORKS, AND WHERE IT IS FRAGILE
;;
;; org-capture decides where an entry goes before the buffer is opened,
;; and nothing in its API changes that decision at the end.  The entry is
;; therefore allowed to file normally and moved afterwards:
;;
;;   `org-capture-prepare-finalize-hook'  ask, while the buffer is still
;;                                        on screen; record the answer
;;   `org-capture-after-finalize-hook'    move the stored entry
;;
;; Two things make that safe rather than clever.  The hook asks nothing
;; when `org-note-abort' is set, so `C-c C-k' stays silent.  And the
;; entry to move is identified twice over: it is the last level-2
;; heading under `Ideas', and its CAPTURED property must equal the one
;; read from the capture buffer a moment earlier.  If those disagree --
;; because the entry was refiled with `C-c C-w', or a template changed,
;; or Org filed it somewhere unexpected -- nothing is moved and the
;; capture is left exactly where Org put it, with a message saying so.
;; Failing visibly and changing nothing is the whole point of the second
;; check.

(defconst my/capture-ideas-heading "Ideas"
  "Top-level heading in `my-journal-captures' that captures are filed under.
Must match the headline named in `org-capture-templates'.")

(defvar my/capture--attach-target nil
  "Heading chosen at finalize time, or nil to leave the capture alone.")

(defvar my/capture--attach-stamp nil
  "CAPTURED value of the entry being finalised, used to identify it.")

(defun my/capture--captures-buffer ()
  "Return a buffer visiting `my-journal-captures', or nil."
  (when (and (boundp 'my-journal-captures)
             (file-exists-p my-journal-captures))
    (find-file-noselect my-journal-captures)))

(defun my/capture--ideas-bounds ()
  "Return (BEG . END) of the `Ideas' subtree in the current buffer, or nil."
  (when-let* ((beg (org-find-exact-headline-in-buffer
                    my/capture-ideas-heading (current-buffer) t)))
    (save-excursion
      (goto-char beg)
      (cons beg (save-excursion (org-end-of-subtree t t) (point))))))

(defun my/capture--existing-headings ()
  "Return the non-empty capture headings currently under `Ideas'.

Level-2 headings only: a capture is a direct child of `Ideas', and
anything deeper belongs to a capture rather than being one.  Headings
with no text are skipped -- the template leaves the headline empty, so
an unnamed capture is one that was never given a subject and cannot
serve as a destination for another."
  (let (headings)
    (when-let* ((buffer (my/capture--captures-buffer)))
      (with-current-buffer buffer
        (org-with-wide-buffer
         (when-let* ((bounds (my/capture--ideas-bounds)))
           (goto-char (car bounds))
           (while (re-search-forward "^\\*\\* \\(.*\\)$" (cdr bounds) t)
             (let ((title (string-trim (match-string-no-properties 1))))
               (unless (string-empty-p title)
                 (push title headings))))))))
    (nreverse headings)))

(defun my/capture--last-entry-position (bounds)
  "Return the position of the last level-2 heading within BOUNDS, or nil."
  (save-excursion
    (goto-char (car bounds))
    (let (last)
      (while (re-search-forward "^\\*\\* " (cdr bounds) t)
        (setq last (match-beginning 0)))
      last)))

(defvar vertico-preselect)

(defun my/capture--read-destination (headings)
  "Read where the capture being finalised should go.

Returns one of HEADINGS to file it there, a new title to name the
capture with, or an empty string to leave it untitled where org-capture
put it.

The prompt behaves like the keyword prompts in 05-notes.el, and for the
same reason: with Vertico's own settings, RET submits the highlighted
candidate rather than what was typed, so a new heading whose name begins
like an existing one could not be entered at all.  Binding
`my/notes-keyword-preselect' here makes RET literal and TAB the way to
step onto an existing heading, which is the behaviour already learnt
from tagging.  The variable is named for keywords because that is where
it was first needed; it governs one behaviour and is deliberately not
duplicated under a second name.

Unlike a keyword prompt this one reads a single value, so no separator
key is installed: a heading may contain a comma."
  (let ((vertico-preselect (if (boundp 'my/notes-keyword-preselect)
                               my/notes-keyword-preselect
                             'prompt)))
    (string-trim
     (minibuffer-with-setup-hook
         (:append (lambda ()
                    (when (fboundp 'my/notes--completion-keys)
                      ;; No separator argument: a heading is a single
                      ;; value and may legitimately contain a comma.
                      (my/notes--completion-keys))))
       (completing-read
        "File under (TAB for existing, text for a new heading, empty for none): "
        headings nil nil)))))

(defun my/capture--buffer-captured ()
  "Return the CAPTURED property of the capture entry in this buffer."
  (save-excursion
    (goto-char (point-min))
    (org-entry-get (point) "CAPTURED")))

(defun my/capture--set-heading (title)
  "Give the capture entry in this buffer the headline TITLE."
  (save-excursion
    (goto-char (point-min))
    (when (org-at-heading-p)
      (org-edit-headline title))))

(defun my/capture--ask-target ()
  "Ask where the capture being finalised should go.
Runs from `org-capture-prepare-finalize-hook'.

Three outcomes from one prompt:

  an existing heading  the text is filed under it, with a source line
                       and no second heading
  anything else typed  the capture keeps its own heading, named with
                       what was typed
  nothing typed        the capture keeps its own heading, untitled,
                       exactly as before

Naming happens here, by editing the capture buffer while it is still
open, rather than after filing: the headline is right there, and Org
writes it out for us.

Stays silent in three cases: an abort, a template other than the Ideas
one, and a refile.  `C-c C-w' already chooses a destination and moves
the entry itself; asking as well would have two mechanisms moving one
entry."
  (setq my/capture--attach-target nil
        my/capture--attach-stamp nil)
  (when (and (not (bound-and-true-p org-note-abort))
             (not (bound-and-true-p org-capture-is-refiling))
             (equal (org-capture-get :key) "j"))
    (let* ((headings (my/capture--existing-headings))
           (answer   (my/capture--read-destination headings)))
      (cond
       ((member answer headings)
        (setq my/capture--attach-target answer
              my/capture--attach-stamp  (my/capture--buffer-captured)))
       ((not (string-empty-p answer))
        (my/capture--set-heading answer))))))

(defun my/capture--fragment-from-entry ()
  "Return the capture entry at point as a body fragment, or nil if empty.

Point must be on the capture heading.  Produces a source line followed
by the body, and keeps any heading text the entry was given as its own
paragraph -- discarding text that was typed is not something a filing
decision should do quietly."
  (let* ((heading  (string-trim (or (org-get-heading t t t t) "")))
         (source   (my/capture--source-value
                    (org-entry-get (point) "SOURCE")
                    (org-entry-get (point) "CAPTURED")))
         (element  (org-element-at-point))
         (beg      (org-element-property :contents-begin element))
         (end      (org-element-property :contents-end element))
         (body     (if (and beg end)
                       (my/--strip-properties-drawer
                        (buffer-substring-no-properties beg end))
                     ""))
         (blocks   (delq nil
                         (list (unless (string-empty-p heading) heading)
                               (unless (string-empty-p (string-trim body))
                                 (string-trim body))))))
    ;; A source line on its own says where nothing came from.
    (when blocks
      (string-join (delq nil (cons (when source (format "Source: %s" source))
                                   blocks))
                   "\n\n"))))

(defun my/capture--attach-last-entry ()
  "Move the entry just filed by org-capture under `my/capture--attach-target'.
Runs from `org-capture-after-finalize-hook'.

Nothing is deleted until the destination has been located and the
replacement text built, so every way this can fail leaves the capture
where org-capture put it."
  (let ((target my/capture--attach-target)
        (stamp  my/capture--attach-stamp)
        (buffer (my/capture--captures-buffer)))
    (setq my/capture--attach-target nil
          my/capture--attach-stamp nil)
    (when (and target buffer)
      (with-current-buffer buffer
        (org-with-wide-buffer
         (let* ((bounds (my/capture--ideas-bounds))
                (entry  (and bounds (my/capture--last-entry-position bounds))))
           (cond
            ((null entry)
             (message "Capture left in place: no entry found under `%s'"
                      my/capture-ideas-heading))
            (t
             (goto-char entry)
             (cond
              ((not (equal (org-entry-get (point) "CAPTURED") stamp))
               (message "Capture left in place: the last entry is not the one just written"))
              (t
               (let ((fragment  (my/capture--fragment-from-entry))
                     (entry-end (save-excursion (org-end-of-subtree t t) (point)))
                     (destination (org-find-exact-headline-in-buffer
                                   target (current-buffer))))
                 (cond
                  ((null fragment)
                   (delete-region entry entry-end)
                   (save-buffer)
                   (message "Empty capture discarded"))
                  ((null destination)
                   (message "Capture left in place: heading \"%s\" disappeared" target))
                  (t
                   ;; DESTINATION is a marker, so it stays valid across
                   ;; the deletion below however the two regions are
                   ;; ordered in the file.
                   (delete-region entry entry-end)
                   (goto-char destination)
                   (goto-char (save-excursion (org-end-of-subtree t t) (point)))
                   (skip-chars-backward " \t\n")
                   (unless (bolp) (insert "\n"))
                   (insert "\n" fragment "\n")
                   (save-buffer)
                   (set-marker destination nil)
                   (message "✓ Filed under \"%s\"" target))))))))))))))

(add-hook 'org-capture-prepare-finalize-hook #'my/capture--ask-target)
(add-hook 'org-capture-after-finalize-hook #'my/capture--attach-last-entry)

(defun my/capture-idea ()
  "Directly invoke Ideas capture (template j) — no menu shown.
Opens capture buffer to the RIGHT of the current window.
Records SOURCE link to the originating note automatically."
  (interactive)
  (setq my/capture--origin-window (selected-window))
  (org-capture nil "j"))

;; ============================================================
;; HELPERS: Note lookup across silos
;; ============================================================

(defun my/--note-get-title (file)
  "Return #+title from FILE, or nil."
  (with-temp-buffer
    (insert-file-contents file nil 0 4096)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title:[ \t]+\\(.+\\)$" nil t)
      (string-trim (match-string 1)))))

(defun my/--all-note-silos ()
  "Return list of note silo directories to search."
  (delq nil
        (mapcar (lambda (dir)
                  (when (and (boundp dir)
                             (symbol-value dir)
                             (file-directory-p (symbol-value dir)))
                    (expand-file-name (symbol-value dir))))
                '(my-notes-journal my-notes-pks my-notes-docu))))

(defun my/--find-notes-by-title-global (title)
  "Return a list of .org files whose #+title matches TITLE across all silos.
Comparison is case-insensitive and ignores surrounding whitespace."
  (let ((wanted (downcase (string-trim title)))
        matches)
    (dolist (dir (my/--all-note-silos))
      (dolist (file (directory-files-recursively dir "\\.org\\'"))
        (let ((file-title (my/--note-get-title file)))
          (when (and file-title
                     (string= (downcase (string-trim file-title)) wanted))
            (push file matches)))))
    (nreverse matches)))

(defun my/--note-last-source (file)
  "Return the last source line value found in FILE, or nil."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (last-source)
      (while (re-search-forward "^Source:[ \t]+\\(.+\\)$" nil t)
        (setq last-source (string-trim (match-string 1))))
      last-source)))

;; ============================================================
;; HELPERS: Building and inserting the promoted fragment
;; ============================================================

(defun my/--note-fragment (segments &optional last-source)
  "Return the text to insert into a note for SEGMENTS.

SEGMENTS is an ordered list of (SOURCE-VALUE . TEXT) as produced by
`my/capture--split-into-segments'.  A source line is emitted before a
segment only when its origin differs from the one emitted before it,
so a run of material from the same place is labelled once.  LAST-SOURCE
is the value of the last source line already present in the target
note, and takes part in that comparison, which stops a note from
repeating a label it already ends with.

Order is the capture order; nothing is reordered or merged."
  (let ((blocks nil)
        (previous (my/capture--source-key last-source)))
    (dolist (segment segments)
      (let* ((source (car segment))
             (text   (string-trim-right (or (cdr segment) "")))
             (key    (my/capture--source-key source)))
        (unless (string-empty-p (string-trim text))
          (when (and key (not (equal key previous)))
            (push (format "Source: %s" source) blocks)
            (setq previous key))
          (push text blocks))))
    (if blocks
        (concat (string-join (nreverse blocks) "\n\n") "\n")
      "")))

(defun my/--append-to-note (file segments)
  "Append SEGMENTS to FILE, suppressing a source label the note already ends with."
  (let ((fragment (my/--note-fragment segments (my/--note-last-source file))))
    (unless (string-empty-p fragment)
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (unless (bolp)
          (insert "\n"))
        (unless (looking-back "\n\n" nil)
          (insert "\n"))
        (insert fragment)
        (save-buffer)))))

(defun my/--move-note-to-silo (file target-dir)
  "Move FILE to TARGET-DIR and return the new absolute path.
If FILE is visited by a buffer, update that buffer too."
  (let* ((target-dir (file-name-as-directory (expand-file-name target-dir)))
         (old-path   (expand-file-name file))
         (new-path   (expand-file-name (file-name-nondirectory old-path) target-dir))
         (buf        (find-buffer-visiting old-path)))
    (unless (file-equal-p (file-name-directory old-path) target-dir)
      (rename-file old-path new-path 1)
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (set-visited-file-name new-path t t))))
    new-path))

(defun my/--insert-note-body-at-top (segments)
  "Insert SEGMENTS into the current Denote note, after the front matter.
Leaves exactly one blank line between the front matter and the
inserted fragment."
  (save-excursion
    (goto-char (point-min))
    ;; Skip optional blank lines at the very top.
    ;; NOTE: every whitespace-skipping loop below MUST be guarded with
    ;; (not (eobp)).  At end of buffer `looking-at-p' still matches
    ;; \"^[[:space:]]*$\" (an empty line) while `forward-line' can no
    ;; longer move point, so an unguarded loop spins forever.  A fresh
    ;; Denote note contains nothing after the front matter, which is
    ;; exactly the case that used to freeze note creation.
    (while (and (not (eobp)) (looking-at-p "^[[:space:]]*$"))
      (forward-line 1))
    ;; Move across every consecutive front matter line: #+title:,
    ;; #+date:, #+filetags:, #+identifier:, etc.
    (while (and (not (eobp)) (looking-at-p "^#\\+[[:alnum:]_-]+:"))
      (forward-line 1))
    ;; Normalise: delete all blank lines directly after the front
    ;; matter, then insert exactly one separator line ourselves.
    (let ((blank-beg (point)))
      (while (and (not (eobp)) (looking-at-p "^[[:space:]]*$"))
        (forward-line 1))
      (delete-region blank-beg (point)))
    (insert "\n")
    (insert (my/--note-fragment segments))))

;; ============================================================
;; HELPERS: Reading the capture heading
;; ============================================================

(defun my/--strip-properties-drawer (text)
  "Return TEXT with a leading :PROPERTIES: drawer removed and trimmed."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (when (looking-at-p ":PROPERTIES:")
      (let ((drawer-beg (point)))
        (when (re-search-forward "^:END:[ \t]*\n?" nil t)
          (delete-region drawer-beg (point)))))
    (string-trim (buffer-string))))

(defun my/--capture-promote-target-point ()
  "Return buffer position of heading that should be promoted.
If point is on a subheading, ask whether to use current heading or parent.
Top-level capture headings are used directly."
  (save-excursion
    (org-back-to-heading t)
    (let ((current-point (point))
          (current-level (org-outline-level)))
      (if (<= current-level 2)
          current-point
        (let ((choice
               (completing-read
                "Promote: "
                '("current heading" "parent heading")
                nil t nil nil "parent heading")))
          (cond
           ((string= choice "current heading")
            current-point)
           ((save-excursion
              (org-up-heading-safe)
              (point)))
           (t current-point)))))))

(defun my/capture--split-into-segments (body heading-source heading-captured)
  "Split BODY into an ordered list of (SOURCE-VALUE . TEXT).

A capture heading can hold material from several origins: the entry it
was created with, plus every fragment later filed under it, each
introduced by its own source line.  This turns that back into ordered
pairs.

The heading's own SOURCE and CAPTURED properties describe the text
before the first source line in BODY, which is what an entry captured
the old way consists of entirely.  Nothing therefore needs migrating:
an entry with no source lines in its body comes back as one segment."
  (let ((segments nil)
        (current (my/capture--source-value heading-source heading-captured))
        (chunk nil))
    (dolist (line (split-string (or body "") "\n"))
      (if (string-match my/capture-source-line-regexp line)
          (progn
            (push (cons current (string-join (nreverse chunk) "\n")) segments)
            (setq chunk nil
                  current (string-trim (match-string 1 line))))
        (push line chunk)))
    (push (cons current (string-join (nreverse chunk) "\n")) segments)
    (seq-remove (lambda (segment)
                  (string-empty-p (string-trim (or (cdr segment) ""))))
                (nreverse segments))))

(defun my/--capture-heading-data-at (pos)
  "Return plist with heading data for subtree at POS.
Result contains :title :segments :beg :end.
:segments is the ordered (SOURCE-VALUE . TEXT) list described in
`my/capture--split-into-segments'.
:beg and :end are markers so later buffer edits cannot invalidate them."
  (save-excursion
    (goto-char pos)
    (org-back-to-heading t)
    (let* ((title (org-get-heading t t t t))
           (source (org-entry-get (point) "SOURCE"))
           (captured (org-entry-get (point) "CAPTURED"))
           (beg (copy-marker (point)))
           (end (copy-marker
                 (save-excursion
                   (org-end-of-subtree t)
                   (forward-line 1)
                   (point))))
           (element (org-element-at-point))
           (contents-begin (org-element-property :contents-begin element))
           (contents-end   (org-element-property :contents-end element))
           (body
            (if (and contents-begin contents-end)
                (my/--strip-properties-drawer
                 (buffer-substring-no-properties contents-begin contents-end))
              "")))
      (list :title title
            :segments (my/capture--split-into-segments body source captured)
            :beg beg
            :end end))))

;; ============================================================
;; PROMOTE CAPTURE HEADING TO DENOTE NOTE (create or append)
;; ============================================================

(defun my/--capture-remove-heading (buffer beg end)
  "Delete region BEG..END (markers) in BUFFER and save it."
  (with-current-buffer buffer
    (delete-region beg end)
    (save-buffer))
  ;; Detach markers so they no longer slow down buffer editing.
  (set-marker beg nil)
  (set-marker end nil))

(defun my/capture-promote-to-note ()
  "Promote capture heading to a Denote note.

Behavior:
- Ask for title, tags, and preferred silo.
- Search all silos for an existing note with the same #+title.
- If none exists, create a new note in the chosen silo.
- If exactly one exists in the same silo, append to it.
- If exactly one exists in another silo, ask whether to move it to the
  chosen silo before appending.
- If multiple notes with the same title exist, abort with a warning.

Only the capture body is copied; the PROPERTIES drawer is stripped.

A capture heading may hold material from several origins, gathered
there by `C-c C-c' over successive captures.  Each is carried across
with its own source line, in capture order, and a source line is
emitted only when the origin changes -- including against the line the
target note already ends with, so a note is never given a label it just
had."
  (interactive)
  (unless (eq major-mode 'org-mode)
    (user-error "Not in org-mode"))
  (save-excursion
    (condition-case nil
        (org-back-to-heading t)
      (error (user-error "Not inside an org heading"))))
  (let* ((target-pos    (my/--capture-promote-target-point))
         (target-data   (my/--capture-heading-data-at target-pos))
         (heading-title (plist-get target-data :title))
         (title         (read-string "Note title: " heading-title))
         (keywords      (my/notes-read-keywords))
         (silo-key      (read-char-choice
                         "Save in: [j]ournal [p]ks [d]ocu: "
                         '(?j ?p ?d)))
         (silo          (pcase silo-key
                          (?j "journal")
                          (?d "docu")
                          (_  "pks")))
         (target-dir    (pcase silo
                          ("journal" my-notes-journal)
                          ("docu"    my-notes-docu)
                          (_         my-notes-pks)))
         (segments      (plist-get target-data :segments))
         (captures-buf  (current-buffer))
         (heading-beg   (plist-get target-data :beg))
         (heading-end   (plist-get target-data :end))
         (matches       (my/--find-notes-by-title-global title)))
    (cond
     ((> (length matches) 1)
      (user-error
       "Found %d notes with title \"%s\". Resolve duplicates first."
       (length matches) title))

     ((= (length matches) 1)
      (let* ((existing-file (car matches))
             (existing-dir  (file-name-directory existing-file))
             (same-silo
              (file-equal-p
               (file-name-as-directory (expand-file-name existing-dir))
               (file-name-as-directory (expand-file-name target-dir))))
             (final-file
              (if same-silo
                  existing-file
                (if (y-or-n-p
                     (format
                      "Note exists in %s, not %s. Move it to %s and append? "
                      (abbreviate-file-name existing-dir)
                      silo
                      silo))
                    (my/--move-note-to-silo existing-file target-dir)
                  existing-file))))
        (my/--append-to-note final-file segments)
        (my/--capture-remove-heading captures-buf heading-beg heading-end)
        (message "✓ Appended to existing note: \"%s\"" title)))

     (t
      ;; `denote-directory' is a defcustom (special variable), so a
      ;; dynamic let-binding redirects note creation into the silo.
      (let ((denote-directory target-dir))
        (denote title keywords))
      ;; `denote' leaves the new note buffer current, but do not rely on
      ;; that implicitly: operate on the file it records in
      ;; `denote-last-path'.
      (with-current-buffer (or (and denote-last-path
                                    (find-buffer-visiting denote-last-path))
                               (current-buffer))
        (my/--insert-note-body-at-top segments)
        (save-buffer))
      (my/--capture-remove-heading captures-buf heading-beg heading-end)
      (message "✓ Note created: \"%s\" → %s/" title silo)))))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c c") 'org-capture)

(provide '06-capture)
;;; 06-capture.el ends here
