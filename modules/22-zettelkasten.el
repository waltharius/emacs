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

(defun my/zettel-dired ()
  "Show all sequences in Folgezettel order in a Dired buffer.
With C-u, prompt for a sequence prefix to filter (e.g. only 1a...).
With C-u C-u, also prompt for a depth limit."
  (interactive)
  (my/zettel--in-pks (call-interactively #'denote-sequence-dired)))

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
    ("k" "Previous sibling"           my/zettel-previous-sibling :transient t)
    ("d" "Dired (Folgezettel order)"  my/zettel-dired)]
   ["Organize"
    ("l" "Link to sequence note"      my/zettel-link)
    ("r" "Reparent current"           my/zettel-reparent)
    ("a" "Adopt note into ZK"         my/zettel-adopt)]
   [("q" "Quit" transient-quit-one)]])

;; Append to the main notes menu after "t" (Tools), same pattern as
;; 19-philosophy-notes.el.  Guarded so reloading this file does not
;; add a duplicate entry (transient-get-suffix errors when the key is
;; absent, hence ignore-errors).
(unless (ignore-errors (transient-get-suffix 'my/notes-menu "z"))
  (transient-append-suffix 'my/notes-menu "t"
    '("z" "Zettelkasten →" my/zettelkasten-menu)))

(provide '22-zettelkasten)
;;; 22-zettelkasten.el ends here
