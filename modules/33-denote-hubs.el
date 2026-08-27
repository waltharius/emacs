;;; 33-denote-hubs.el --- Collect notes under Denote hub notes -*- lexical-binding: t; -*-
;;; Commentary:
;; A HUB is an ordinary Denote note carrying the `hub' keyword in the
;; `__keyword' component of its file name.  Its body is a plain Org list
;; of links to the notes that belong to it, each with a one-line
;; description:
;;
;;   - [[denote:20260828T101500][Title of the note]] — why it is here
;;
;; One command, `my/denote-add-to-hub', appends the note in the current
;; buffer to a hub of one's choosing, creating the hub first when asked.
;;
;; Hubs are found by KEYWORD, never by file content: the scan combines
;; `denote-directory-files' with `denote-extract-keywords-from-path',
;; both of which read file names only, so no note is opened to answer
;; the question "is this a hub".
;;
;; DEPENDENCIES
;; - denote 4.1 or later.  Every helper used here is public API of that
;;   release: `denote-directory-files',
;;   `denote-extract-keywords-from-path',
;;   `denote-retrieve-filename-identifier',
;;   `denote-retrieve-front-matter-title-value',
;;   `denote-filetype-heuristics' and `denote' itself, which returns the
;;   path of the note it created.
;; - 00-core.el for `my-notes-pks', the default location of new hubs.
;; - 12-transient.el is OPTIONAL: the menu entry is added through
;;   `my/transient-append', which reports and skips instead of
;;   signalling, so removing the menu module leaves this one working
;;   under M-x.
;;
;; NOT RELATED to the project hubs of 28-writing-projects.el.  Those are
;; scaffolding files under ~/projects/ and are not Denote notes at all.
;; The two namespaces are kept apart on purpose -- `my/writing--hub-*'
;; there, `my/denote-hub--*' here -- because a shared prefix is how two
;; modules end up redefining each other's helpers.
;;
;; Docs: ~/.emacs.d/function_helper.org::#fn-my-denote-add-to-hub

;;; Code:

(require 'denote)
(require 'seq)
(require 'subr-x)

(defgroup my-denote-hubs nil
  "Hub notes gathering links to other Denote notes."
  :group 'convenience)

(defcustom my/denote-hub-keyword "hub"
  "Denote keyword that marks a note as a hub.
Matched against the `__keyword' component of the file name."
  :type 'string
  :group 'my-denote-hubs)

(defcustom my/denote-hub-directory my-notes-pks
  "Silo in which `my/denote-add-to-hub' creates a new hub note.
Assumption: a new hub goes to the pks silo without asking, because the
only prompt specified for hub creation is the title."
  :type 'directory
  :group 'my-denote-hubs)

(defconst my/denote-hub-new-label "[Nowy HUB]"
  "Completion candidate standing for \"create a new hub instead\".")

;; Register the keyword so it completes in `denote-rename-file-keywords'
;; and friends before the first hub exists, the same way
;; 19-philosophy-notes.el registers its own vocabulary.
(with-eval-after-load 'denote
  (add-to-list 'denote-known-keywords my/denote-hub-keyword))

;; ============================================================
;; FINDING HUBS
;; ============================================================

(defun my/denote-hub--hub-p (file)
  "Return non-nil when FILE's name carries `my/denote-hub-keyword'."
  (and (member my/denote-hub-keyword
               (denote-extract-keywords-from-path file))
       t))

(defun my/denote-hub-files ()
  "Return every Denote note whose file name carries the hub keyword.
Text files only: an attachment can hold a keyword but cannot hold a
list of links."
  (seq-filter #'my/denote-hub--hub-p
              (denote-directory-files nil nil :text-only)))

(defun my/denote-hub--title (file)
  "Return the `#+title:' value of FILE, or its file name if it has none.
Denote reads a live buffer visiting FILE in preference to the copy on
disk, so an unsaved title change is picked up."
  (or (denote-retrieve-front-matter-title-value
       file (denote-filetype-heuristics file))
      (file-name-base file)))

(defun my/denote-hub--candidates ()
  "Return an alist of (LABEL . FILE) for every hub note.
LABEL is \"TITLE (IDENTIFIER)\"; the identifier is what tells apart two
hubs that happen to share a title."
  (mapcar (lambda (file)
            (cons (format "%s (%s)"
                          (my/denote-hub--title file)
                          (or (denote-retrieve-filename-identifier file) "?"))
                  file))
          (my/denote-hub-files)))

(defun my/denote-hub--completion-table (candidates)
  "Return a completion table over CANDIDATES that preserves their order.
Completion frontends sort candidates by their own criteria, which would
move `my/denote-hub-new-label' out of the last position it is meant to
occupy.  Declaring `identity' as the sort function is the documented way
to keep the given order."
  (lambda (string predicate action)
    (if (eq action 'metadata)
        '(metadata (display-sort-function . identity)
                   (cycle-sort-function . identity))
      (complete-with-action action candidates string predicate))))

;; ============================================================
;; WRITING INTO A HUB
;; ============================================================

(defun my/denote-hub--entry (identifier title description)
  "Return the hub list item linking to IDENTIFIER and shown as TITLE.
DESCRIPTION follows an em dash.  Assumption: an empty description
produces the link alone rather than a trailing dash."
  (if (string-empty-p description)
      (format "- [[denote:%s][%s]]" identifier title)
    (format "- [[denote:%s][%s]] — %s" identifier title description)))

(defun my/denote-hub--append (file text)
  "Append TEXT at the end of FILE, one blank line below its content.

A buffer already visiting FILE is reused and left open; a buffer opened
here is saved and killed again, so the command does not accumulate
buffers for hubs that were not being edited."
  (let* ((existing (find-buffer-visiting file))
         (buffer (or existing (find-file-noselect file))))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-max))
        ;; Trailing whitespace is removed first so the separator is
        ;; exactly one blank line, whatever the file happened to end
        ;; with.
        (skip-chars-backward " \t\n")
        (delete-region (point) (point-max))
        (insert "\n\n" text "\n"))
      (save-buffer))
    (unless existing
      (kill-buffer buffer))))

;; ============================================================
;; COMMAND
;; ============================================================

(defun my/denote-add-to-hub ()
  "Add a link to the current note to a hub note.

Prompts for one of the existing hubs -- notes carrying
`my/denote-hub-keyword' in their file name -- or for
`my/denote-hub-new-label', which creates one.  Then prompts for a
one-line description and appends

  - [[denote:IDENTIFIER][TITLE]] — DESCRIPTION

at the end of the hub.  IDENTIFIER and TITLE belong to the current
note, and TITLE is its `#+title:' value verbatim: a note whose title
already contains its signature contributes it, and no signature is
added to a note that has none.

Choosing `my/denote-hub-new-label' creates a note in
`my/denote-hub-directory' with the hub keyword and the title given at
the prompt.  Its own one-line description becomes the first line of the
body, and the link entry goes one blank line below it."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "This buffer is not visiting a file"))
    (let ((identifier (denote-retrieve-filename-identifier file))
          (title (my/denote-hub--title file)))
      (unless identifier
        (user-error "Not a Denote note (no identifier in the file name)"))
      (let* ((candidates (my/denote-hub--candidates))
             (choice (completing-read
                      "HUB: "
                      (my/denote-hub--completion-table
                       (append (mapcar #'car candidates)
                               (list my/denote-hub-new-label)))
                      nil t))
             (hub (cdr (assoc choice candidates))))
        (if hub
            (let ((entry (my/denote-hub--entry
                          identifier title
                          (read-string "Entry description: "))))
              (my/denote-hub--append hub entry)
              (message "Added to hub: %s" (my/denote-hub--title hub)))
          ;; New hub.  Every prompt is answered before anything is
          ;; created, so C-g leaves no half-built note behind.
          (let ((hub-title (string-trim (read-string "New HUB title: "))))
            (when (string-empty-p hub-title)
              (user-error "A hub needs a title"))
            (let* ((hub-description (read-string "HUB description: "))
                   (entry (my/denote-hub--entry
                           identifier title
                           (read-string "Entry description: ")))
                   ;; `denote' returns the path of the note it created
                   ;; and visits it.  Assumption: the new hub is left
                   ;; open, which is Denote's own behaviour and the
                   ;; simplest outcome.
                   (new-hub (let ((denote-directory my/denote-hub-directory))
                              (denote hub-title
                                      (list my/denote-hub-keyword)))))
              (my/denote-hub--append
               new-hub (concat hub-description "\n\n" entry))
              (message "Created hub: %s" hub-title))))))))

;; ============================================================
;; MENU INTEGRATION  (C-c n i H)
;; ============================================================
;; Anchored on "L" (Linked note), which 12-transient.el defines itself.
;; Anchoring on a key contributed by another optional module is how the
;; Insert menu lost four entries at once in August 2026.

(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-insert-menu "L"
                       '("H" "Add to HUB" my/denote-add-to-hub)))

(provide '33-denote-hubs)
;;; 33-denote-hubs.el ends here
