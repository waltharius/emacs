;;; 22-zettelkasten.el --- Folgezettel sequences with denote-sequence -*- lexical-binding: t; -*-
;;; Commentary:
;; Luhmann-style Zettelkasten layer on top of Denote, using the
;; official `denote-sequence' package (GNU ELPA, by Protesilaos).
;;
;; Design decisions for THIS config:
;;
;; - Sequences live in the ~/notes/pks/ silo only.  Journal and docu
;;   notes are excluded on purpose: a journal is time-structured and a
;;   Zettelkasten is idea-structured (Christian Tietze deliberately
;;   keeps them separate too).  All sequence-creating commands here
;;   bind `denote-directory' to the pks silo, mirroring the pattern
;;   used by my/denote-base in 05-notes.el.
;;
;; - Scheme is `alphanumeric' (1, 1a, 1a1, ...) because signatures
;;   land in file names and the compact form keeps them readable in
;;   dired and completion.  If sequences ever get so deep that "1zzzv2"
;;   stops being readable, `denote-sequence-convert' switches the whole
;;   collection to another scheme in one command.
;;
;; - Not every note needs a sequence.  Plain Denote notes and sequence
;;   notes coexist; a signature is added only when a thought explicitly
;;   continues or branches from another.  This follows the manual:
;;   "The denote-sequence.el optional extension is not necessary for
;;   such a workflow."
;;
;; Menu: C-c n z (appended to my/notes-menu, same pattern as
;; 19-philosophy-notes.el uses for C-c n l).
;;
;; Docs: ~/.emacs.d/function_helper.org::#menu-zettelkasten

;;; Code:

(require 'transient)

;; ============================================================
;; DENOTE-SEQUENCE: official Folgezettel extension
;; ============================================================

(use-package denote-sequence
  :ensure t
  :after denote
  :config
  ;; Compact Luhmann-style signatures: 1, 1a, 1a1, 1b, 2, ...
  ;; The default is 'numeric (1, 1=1, 1=1=2).  All schemes are
  ;; mutually convertible later with denote-sequence-convert.
  (setq denote-sequence-scheme 'alphanumeric))

;; ============================================================
;; SILO-AWARE WRAPPERS
;; ============================================================
;; denote-sequence commands use `denote-directory' both to FIND
;; existing sequences and to CREATE new files.  Binding it to the pks
;; silo keeps the Zettelkasten in one place and stops journal/docu
;; file names from ever getting signatures.

(defmacro my/zettel--in-pks (&rest body)
  "Run BODY with `denote-directory' bound to the pks silo."
  `(let ((denote-directory my-notes-pks))
     ,@body))

(defun my/zettel-new-parent ()
  "Start a new top-level thought thread (new parent sequence) in pks."
  (interactive)
  (my/zettel--in-pks (call-interactively #'denote-sequence-new-parent)))

(defun my/zettel-new-child ()
  "Branch off: create a child of a sequence chosen via completion."
  (interactive)
  (my/zettel--in-pks (call-interactively #'denote-sequence-new-child)))

(defun my/zettel-new-child-of-current ()
  "Branch off from the note in the current buffer (child of current)."
  (interactive)
  (my/zettel--in-pks
   (call-interactively #'denote-sequence-new-child-of-current)))

(defun my/zettel-new-sibling-of-current ()
  "Continue the train of thought: sibling of the current note."
  (interactive)
  (my/zettel--in-pks
   (call-interactively #'denote-sequence-new-sibling-of-current)))

(defun my/zettel-find ()
  "Visit a parent/sibling/child of the current note's sequence."
  (interactive)
  (my/zettel--in-pks (call-interactively #'denote-sequence-find)))

(defun my/zettel-next-sibling ()
  "Jump to the next sibling in the current sequence."
  (interactive)
  (my/zettel--in-pks
   (call-interactively #'denote-sequence-find-next-sibling)))

(defun my/zettel-previous-sibling ()
  "Jump to the previous sibling in the current sequence."
  (interactive)
  (my/zettel--in-pks
   (call-interactively #'denote-sequence-find-previous-sibling)))

(defconst my/zettel--dired-buffer-regexp "prefix .*; depth "
  "Match buffer names produced by `denote-sequence-dired'.
That command names its buffer after the prefix and depth it was built
with.  The quoting around those two values follows `text-quoting-style'
(curly by default), so this regexp matches only the literal words
around them and stays agnostic about the quote characters.")

(defun my/zettel--kill-stale-dired-buffers ()
  "Kill Dired buffers left over from earlier `denote-sequence-dired' runs.

Works around a staleness problem: invoking the command a second time
with a different prefix displays the *previous* invocation's file list.
The buffer name updates to the new filter while the contents do not,
so the listing is consistently one step behind, and the correct list
only appears after asking for the same prefix twice.

The cause is upstream, in how the package reuses an existing Dired
buffer.  `denote-sequence-dired' ends in

    (denote-sort-dired--prepare-buffer directory files-fn dired-name buffer-name)

where DIRECTORY is the same for every invocation in one silo, and
FILES-FN is a lambda that computes the listing.  When a Dired buffer
for that directory already exists it gets reused and renamed rather
than rebuilt from FILES-FN.  Killing the old buffers first leaves
nothing to reuse, so every invocation builds its list from scratch.

Note that this kills the current buffer when it is itself such a
listing, which is the normal case when narrowing a view down step by
step.  That is harmless here: a new Dired buffer is created and
displayed immediately afterwards."
  (dolist (buffer (buffer-list))
    (when (and (buffer-live-p buffer)
               (string-match-p my/zettel--dired-buffer-regexp
                               (buffer-name buffer))
               (with-current-buffer buffer (derived-mode-p 'dired-mode)))
      (kill-buffer buffer))))

(defun my/zettel-dired (&optional arg)
  "Show sequences in a Dired buffer, ordered by Folgezettel.
ARG is handed to `denote-sequence-dired' as its prefix argument: nil
lists everything, `(4)' prompts for a sequence prefix to filter by,
`(16)' prompts for a prefix and a depth limit.

Called from a transient menu, ARG is always nil no matter what the
user typed: a transient prefix consumes the universal argument for
its own purposes, so a C-u pressed before C-c n z never reaches the
suffix command.  That is why the menu binds `my/zettel-dired-prefix'
and `my/zettel-dired-prefix-depth' as separate entries instead of
relying on C-u.

Previous listings are killed first, see
`my/zettel--kill-stale-dired-buffers' for why."
  (interactive "P")
  (my/zettel--kill-stale-dired-buffers)
  (my/zettel--in-pks
   (let ((current-prefix-arg arg))
     (call-interactively #'denote-sequence-dired))))

(defun my/zettel-hierarchy (&optional arg)
  "Show the sequence tree, indented, with titles read from front matter.
ARG is handed to `denote-sequence-view-hierarchy\=' as its prefix
argument: nil shows everything, `(4)\=' prompts for a sequence prefix,
`(16)\=' prompts for a prefix and a depth limit.  As with
`my/zettel-dired\=', a transient prefix consumes the universal argument
before the suffix sees it, which is why the menu binds the prompting
variants as separate entries.

This is the view where a long descriptive title pays for itself.  Dired
and the completion prompts show FILE NAMES, so they show the shortened
slug; `denote-sequence--hierarchy-insert\=' calls
`denote-retrieve-title-or-filename\=', which reads `#+title:\=' from the
front matter and only falls back to the file name.  The full sentence
appears here whatever the file is called.

No stale-buffer workaround is needed, unlike `my/zettel-dired\=': the
hierarchy command derives its buffer name from the prefix and depth and
calls `erase-buffer\=' before rebuilding, so each invocation produces its
own buffer with its own contents.

In the resulting buffer: RET visits, TAB folds, S-TAB folds everything,
n/p move between visible entries, f/b move between siblings, g reverts,
q quits."
  (interactive "P")
  (my/zettel--in-pks
   (let ((current-prefix-arg arg))
     (call-interactively #'denote-sequence-view-hierarchy))))

(defun my/zettel-hierarchy-prefix ()
  "Like `my/zettel-hierarchy\=', but always prompt for a sequence prefix.
An empty prefix at the prompt means no filtering."
  (interactive)
  (my/zettel-hierarchy '(4)))

(defun my/zettel-dired-prefix ()
  "Like `my/zettel-dired', but always prompt for a sequence prefix.
An empty prefix at the prompt means no filtering."
  (interactive)
  (my/zettel-dired '(4)))

(defun my/zettel-dired-prefix-depth ()
  "Like `my/zettel-dired', but prompt for a sequence prefix and a depth.
Depth counts levels, so a depth of 2 under prefix 1 shows 1, 1a and
1b but not 1a1."
  (interactive)
  (my/zettel-dired '(16)))

(defun my/zettel-link ()
  "Insert a link, completing only among sequence notes."
  (interactive)
  (my/zettel--in-pks (call-interactively #'denote-sequence-link)))

(defun my/zettel-reparent ()
  "Move the current note (or file at point in Dired) under another sequence."
  (interactive)
  (my/zettel--in-pks (call-interactively #'denote-sequence-reparent)))

(defun my/zettel-adopt ()
  "Give the current non-sequence note a sequence (make it a new parent).
Use this to promote an ordinary pks note into the Zettelkasten;
follow with my/zettel-reparent to place it under an existing thread."
  (interactive)
  (my/zettel--in-pks
   (call-interactively #'denote-sequence-rename-as-parent)))

;; ============================================================
;; TRANSIENT SUB-MENU  (C-c n z)
;; ============================================================

(transient-define-prefix my/zettelkasten-menu ()
  "Folgezettel sequence operations (pks silo)."
  [["New in sequence"
    ("n" "New thread (parent)"        my/zettel-new-parent)
    ("c" "Child of current"           my/zettel-new-child-of-current)
    ("C" "Child of chosen..."         my/zettel-new-child)
    ("s" "Sibling of current"         my/zettel-new-sibling-of-current)]
   ["Navigate"
    ("f" "Find relative..."           my/zettel-find)
    ("j" "Next sibling"               my/zettel-next-sibling :transient t)
    ("k" "Previous sibling"           my/zettel-previous-sibling :transient t)]
   ["Tree"
    ("h" "Hierarchy (titles)"         my/zettel-hierarchy)
    ("H" "Hierarchy from prefix..."   my/zettel-hierarchy-prefix)
    ("d" "Dired (file names)"         my/zettel-dired)
    ("p" "Dired by prefix..."         my/zettel-dired-prefix)
    ("P" "Dired prefix + depth..."    my/zettel-dired-prefix-depth)]
   ["Organize"
    ("l" "Link to sequence note"      my/zettel-link)
    ("r" "Reparent current"           my/zettel-reparent)
    ("a" "Adopt note into ZK"         my/zettel-adopt)]
   [("q" "Quit" transient-quit-one)]])

;; Append to the main notes menu after "t" (Tools), same pattern as
;; 19-philosophy-notes.el.  `my/transient-append' itself degrades when
;; the prefix or anchor is missing, but calling it unguarded needs
;; 12-transient.el to have been loaded first -- removing that module
;; would abort init here with a void-function error naming this file
;; rather than the missing one.
(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-menu "t"
                         '("z" "Zettelkasten →" my/zettelkasten-menu))))

(provide '22-zettelkasten)
;;; 22-zettelkasten.el ends here
