;;; 19-philosophy-notes.el --- Philosophy note types (Denote) -*- lexical-binding: t; -*-
;;; Commentary:
;; Adds a dedicated submenu for creating philosophy notes, following the
;; note taxonomy from the study plan (Zettelkasten adapted to philosophy).
;;
;; Five note types, each identified by a Denote *type* keyword:
;;   literatura  - one note per source text (scaffolding: what it says, links)
;;   pojecie     - one atomic concept per note (definition, tensions, links)
;;   mysliciel   - one philosopher per note (central project, interlocutors)
;;   problem     - one problem per note (genesis, solutions, criticism)
;;   mapa        - one map-of-content per phase (index linking period notes)
;;
;; Each note additionally gets an *epoch/tradition* keyword (starozytnosc,
;; nowozytnosc, ...) prompted with completion, matching the plan's
;; "double keyword" scheme: type + epoch.
;;
;; Every note is created in the pks silo (`my-notes-pks').
;;
;; Access: C-c n  ->  l  (Philosophy submenu)  ->  l/p/m/b/i
;;
;; LOADING: this file must be loaded AFTER 12-transient.el (it appends an
;; entry to `my/notes-menu'). Add to init.el:
;;   (load (concat modules-dir "19-philosophy-notes.el"))
;;
;; Keyword strings are given in ASCII (pojecie, mysliciel) on purpose:
;; Denote sluggifies keywords to ASCII anyway, so passing them pre-sluggified
;; keeps the filename and #+filetags deterministic.

;;; Code:

(require 'transient)
(require 'denote)

;; ============================================================
;; KEYWORDS: type + epoch/tradition
;; ============================================================

(defvar my/philosophy-type-keywords
  '("literatura" "pojęcie" "myęliciel" "problem" "mapa")
  "Denote *type* keywords for the five philosophy note types.
One of these is added automatically by each creation command.")

(defvar my/philosophy-epoch-keywords
  '("starozytność" "średniowiecze" "nowożytnosc" "współczesność"
    "analityczna" "kontynentalna")
  "Denote *epoch/tradition* keywords offered as completion for the
second keyword of a philosophy note.  Edit this list freely; it is only
a completion source, not a fixed set (new keywords are accepted).")

;; Register the type and epoch keywords with Denote so they show up in
;; completion (e.g. `denote-rename-file-keywords') even before any note
;; that uses them exists.  `denote-infer-keywords' handles the rest later.
(dolist (kw (append my/philosophy-type-keywords my/philosophy-epoch-keywords))
  (add-to-list 'denote-known-keywords kw))

;; ============================================================
;; CORE: create one philosophy note in the pks silo
;; ============================================================

(defun my/philosophy--create-note (type-keyword body)
  "Create a philosophy note tagged TYPE-KEYWORD in the pks silo.

Prompts for a title and for one or more epoch/tradition keywords
(completion against `my/philosophy-epoch-keywords', comma-separated,
optional).  TYPE-KEYWORD is always prepended, so the note carries at
least the type keyword.  BODY, when non-nil, is inserted at the end of
the new note as a minimal Org scaffold."
  (let* ((title (read-string "Title: "))
         ;; Only epoch/tradition (and any extra) keywords are asked for
         ;; here; the type keyword is added automatically below.
         (extra (seq-remove
                 #'string-empty-p
                 (completing-read-multiple
                  "Epoch/tradition keywords (comma-separated, optional): "
                  my/philosophy-epoch-keywords nil nil)))
         (keywords (cons type-keyword extra))
         ;; Bind denote-directory so the note lands in the pks silo,
         ;; regardless of the global (root) denote-directory.
         (denote-directory my-notes-pks))
    (if (string-empty-p title)
        (denote nil keywords)
      (denote title keywords))
    (when body
      (save-excursion
        (goto-char (point-max))
        (insert body)
        (save-buffer)))))

;; ============================================================
;; TYPE COMMANDS (minimal 1-2 heading scaffolds, content in Polish)
;; ============================================================

(defun my/philosophy-note-literatura ()
  "Create a literature note (keyword: literatura) in the pks silo."
  (interactive)
  (my/philosophy--create-note
   "literatura"
   "\n* Streszczenie (moimi słowami)\n\n* Linki\n"))

(defun my/philosophy-note-pojecie ()
  "Create a concept note (keyword: pojecie) in the pks silo."
  (interactive)
  (my/philosophy--create-note
   "pojecie"
   "\n* Definicja (moimi słowami)\n\n* Napięcia i krytyka\n"))

(defun my/philosophy-note-mysliciel ()
  "Create a thinker note (keyword: mysliciel) in the pks silo."
  (interactive)
  (my/philosophy--create-note
   "mysliciel"
   "\n* Centralny projekt\n\n* Komu odpowiada / kto odpowiada jemu\n"))

(defun my/philosophy-note-problem ()
  "Create a problem note (keyword: problem) in the pks silo."
  (interactive)
  (my/philosophy--create-note
   "problem"
   "\n* Geneza\n\n* Rozwiązania i krytyka\n"))

(defun my/philosophy-note-mapa ()
  "Create a map-of-content note (keyword: mapa) in the pks silo."
  (interactive)
  (my/philosophy--create-note
   "mapa"
   "\n* Notatki z okresu\n"))

;; ============================================================
;; SUBMENU (C-c n l)
;; ============================================================

(transient-define-prefix my/philosophy-notes-menu ()
  "Create philosophy notes — every note is saved in the pks silo."
  ["Philosophy Notes — pks silo"
   ["Create"
    ("l" "Literature (literatura)" my/philosophy-note-literatura)
    ("p" "Concept (pojęcie)"       my/philosophy-note-pojecie)
    ("m" "Thinker (myśliciel)"     my/philosophy-note-mysliciel)
    ("b" "Problem (problem)"       my/philosophy-note-problem)
    ("i" "Map / MOC (mapa)"        my/philosophy-note-mapa)]
   ["Navigation"
    ("q" "Quit" transient-quit-one)]])

;; ============================================================
;; HOOK INTO THE MAIN NOTES MENU (C-c n)
;; ============================================================
;; Insert the philosophy submenu under "l", right after the "e" (Essay)
;; entry in the Create column of `my/notes-menu' (defined in 12-transient).

(with-eval-after-load '12-transient
  ;; Idempotent: drop any previous "l" entry before re-adding it, so that
  ;; re-evaluating this file does not create duplicate menu items.
  (ignore-errors (transient-remove-suffix 'my/notes-menu "l"))
  (transient-append-suffix 'my/notes-menu "e"
    '("l" "Philosophy →" my/philosophy-notes-menu)))

(provide '19-philosophy-notes)
;;; 19-philosophy-notes.el ends here
