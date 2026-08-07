;;; 05-notes.el --- Essential note creation functions -*- lexical-binding: t; -*-
;;; Commentary:
;; Only the note functions you actually use:
;; - Journal (daily)
;; - Journal (specific date)
;; - Base note (simple)
;; - Essay
;; - Well-being tracking
;;
;; Keywords are read by `my/notes-read-keywords', defined below and
;; also used by 06-capture.el and 24-readwise.el, so that every prompt
;; for tags in this configuration completes against the same
;; vocabulary and behaves the same way.  `my/denote-keywords-edit'
;; applies the same prompt behaviour to Denote's own keyword command,
;; which is what `C-c n d k' runs.
;;
;; NOTE: denote-directory is now ~/notes/ (root) for better search
;;       Journal functions explicitly save to my-notes-journal

;;; Code:

;; ============================================================
;; KEYWORD PROMPT — shared by the note commands in this file
;; ============================================================
;; Tags used to be read here with `read-string' and split on spaces,
;; which offered no completion at all.  With a few dozen keywords that
;; was merely inconvenient; after the Obsidian migration it is a source
;; of near-duplicates -- "filozofia" beside "flozofia", "kant" beside
;; "kanta" -- that no later command can tell apart, because Denote
;; treats each distinct string as its own keyword.
;;
;; `denote-keywords-prompt' is Denote's own prompt.  It completes
;; against the vocabulary Denote infers from existing file names
;; (`denote-infer-keywords' is t, set in 04-denote.el), reads entries
;; separated by `crm-separator' (a comma, set in 01-ui.el), removes
;; duplicates and returns a list.  Calling it rather than writing a
;; private prompt means these commands and `denote-rename-file-keywords'
;; behave identically, and keep behaving identically as Denote changes.
;;
;; Note the change of separator: tags are now typed comma-separated, as
;; everywhere else in Denote, not space-separated.  A keyword may
;; therefore contain a space, which the old prompt could not express.
;;
;; SUBMITTING WHAT WAS TYPED
;;
;; Vertico preselects the first matching candidate, and RET
;; (`vertico-exit') submits the SELECTED CANDIDATE rather than the
;; input.  A keyword that is a prefix of an existing one cannot then be
;; created by typing it: "zuzi" preselects "zuzia" and RET files the
;; note under "zuzia".  Only the element at point is completed, which
;; is why putting the new keyword anywhere but last in the list used to
;; be the way through.
;;
;; Vertico's documented answer is `M-RET' (`vertico-exit-input'), which
;; submits the input as typed.  It works in every prompt and keeps
;; working whatever is configured here.  `my/notes-keyword-preselect'
;; makes it the behaviour of plain RET inside these prompts, by binding
;; `vertico-preselect' around the call.  The binding is dynamic, so it
;; is in force for the recursive minibuffer edit and for nothing else:
;; no hook, no advice, no global state.
;;
;; The cost is one keystroke when reusing an existing keyword: one key
;; steps onto the candidate, another inserts it.  Set
;; `my/notes-keyword-preselect' to `first' to restore Vertico's default
;; and go back to reaching for `M-RET'.
;;
;; KEYS INSIDE THESE PROMPTS
;;
;;   TAB       next candidate (first press leaves the input line)
;;   S-TAB     previous candidate
;;   ,         insert the highlighted candidate and start the next
;;             keyword -- the fast way to pick several from the list
;;   C-TAB     insert the highlighted candidate WITHOUT exiting, when
;;             the separator is not wanted yet
;;   RET       submit: the input when on the input line, the candidate
;;             when one is selected
;;   M-RET     submit the input regardless of selection (Vertico's own)
;;
;; TAB is Vertico's `vertico-insert' by default.  It is moved here
;; because a list appearing under a half-typed word reads as something
;; to step through, and TAB is the key hands reach for to do that.  The
;; rebinding is confined to these prompts: file-name completion
;; elsewhere keeps TAB as insert, where it matters most.
;;
;; Insertion first went to M-TAB, which was the obvious key and does not
;; work: GNOME owns Alt-Tab as the window switcher, so the compositor
;; consumes it and Emacs never sees the event.  The comma is the better
;; key anyway -- in a list of keywords it already means "this one is
;; finished", so completing to the highlighted candidate first is what
;; it was going to be used for regardless.  On the input line, with
;; nothing highlighted, it stays an ordinary comma.
;;
;; It is applied with `minibuffer-with-setup-hook', which is the
;; built-in way to configure one minibuffer session.  The hook exists
;; only for the duration of the call, exactly like the
;; `vertico-preselect' binding -- it is not a hook added to
;; `minibuffer-setup-hook' globally.  `:append' places it after
;; Vertico's own setup so that the local map it installs is the one
;; being extended.

(defgroup my/notes nil
  "Note creation commands."
  :group 'convenience)

(defcustom my/notes-keyword-preselect 'prompt
  "Value bound to `vertico-preselect' during keyword prompts.

`prompt' selects the input line, so RET submits what was typed and
an existing keyword is taken with <down> RET, or with TAB to insert
it without leaving the prompt.

`first' restores Vertico's own behaviour, where RET submits the
first matching candidate and `M-RET' is needed to submit the input
as typed.

Any other value `vertico-preselect' accepts is passed through
unchanged.  Has no effect without Vertico."
  :type '(choice (const :tag "Input line (RET is literal)" prompt)
                 (const :tag "First candidate (Vertico default)" first)
                 (const :tag "Only when nothing matches" no-match)
                 (symbol :tag "Other `vertico-preselect' value"))
  :group 'my/notes)

(defcustom my/notes-keyword-tab-navigates t
  "Non-nil means TAB steps down the candidate list in keyword prompts.

TAB is then `vertico-next', S-TAB is `vertico-previous', and
`vertico-insert' -- insert the selected candidate without exiting --
moves to M-TAB.  Only keyword prompts are affected; every other
minibuffer keeps Vertico's defaults.

Set to nil to leave these prompts with Vertico's own bindings, where
TAB inserts and the arrow keys navigate."
  :type 'boolean
  :group 'my/notes)

;; Declared, not defined: `vertico-preselect' belongs to Vertico.  The
;; declaration marks the symbol special for this file, so that the
;; `let' below is a dynamic binding rather than a lexical one even when
;; Vertico has not been loaded -- in which case the binding exists and
;; nothing reads it.
(defvar vertico-preselect)
(defvar vertico-map)

(defvar my/notes--completion-separator nil
  "Separator character bound by `my/notes--completion-keys', or nil.")

(defun my/notes-completion-separate ()
  "Insert the highlighted candidate, then start the next entry.

On the input line, with nothing highlighted, this is an ordinary
separator character -- which is what typing a new keyword by hand
needs.  With a candidate highlighted it completes to that candidate
first, so choosing several existing keywords is: filter, TAB, comma,
repeat.

`vertico--index' is Vertico's own variable and no part of a public
API.  When it is absent or negative this degrades to inserting the
character, which is what the key does anyway, so a future Vertico that
renames it costs a keystroke rather than breaking the prompt."
  (interactive)
  (when (and (fboundp 'vertico-insert)
             (integerp (bound-and-true-p vertico--index))
             (>= vertico--index 0))
    (vertico-insert))
  (insert (or (bound-and-true-p my/notes--completion-separator) ",")))

(defun my/notes--completion-keys (&optional separator)
  "Install candidate-stepping keys in the current minibuffer.

Called from `minibuffer-with-setup-hook' at each prompt that wants
them, never from `minibuffer-setup-hook' itself, so no other prompt can
reach it.  Builds a child of whatever local map is in place -- which is
Vertico's, since `:append' orders this after Vertico's setup -- and
leaves everything it does not name alone.

  TAB      next candidate
  S-TAB    previous candidate
  C-TAB    insert the highlighted candidate WITHOUT exiting

SEPARATOR, when given, is a string bound to
`my/notes-completion-separate', which does the same insertion and then
starts the next entry.  Only prompts that read a separated list pass
one; a prompt reading a single value must not, since the character has
no special meaning there and may legitimately occur in the answer.

NOT M-TAB.  That was the obvious key and it does not work: GNOME owns
Alt-Tab as the window switcher, so the compositor consumes it and Emacs
never sees the event."
  (when (and my/notes-keyword-tab-navigates
             (fboundp 'vertico-next))
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map (current-local-map))
      ;; Both spellings of each key: a graphical frame sends the
      ;; function-key form, a terminal the control-character form.
      (define-key map (kbd "TAB")       #'vertico-next)
      (define-key map (kbd "<tab>")     #'vertico-next)
      (define-key map (kbd "S-TAB")     #'vertico-previous)
      (define-key map (kbd "<backtab>") #'vertico-previous)
      (define-key map (kbd "C-TAB")     #'vertico-insert)
      (define-key map (kbd "<C-tab>")   #'vertico-insert)
      (when separator
        (setq-local my/notes--completion-separator separator)
        (define-key map (kbd separator) #'my/notes-completion-separate))
      (use-local-map map))))

(defun my/notes-read-keywords (&optional prompt initial)
  "Read keywords, completing against the keywords already in use.

PROMPT replaces the default prompt text, INITIAL is inserted as
initial minibuffer content.  Returns a list of strings, or nil when
nothing was entered.

Falls back to a plain space-separated string prompt if Denote is
not available, so that note creation still works rather than
failing on a missing function."
  (if (fboundp 'denote-keywords-prompt)
      (let* ((vertico-preselect my/notes-keyword-preselect)
             (keywords (minibuffer-with-setup-hook
                           (:append (lambda () (my/notes--completion-keys ",")))
                         (denote-keywords-prompt prompt initial))))
        ;; Older Denote sorts inside the prompt, newer exposes it
        ;; separately; call it when present and take the result as-is
        ;; otherwise.
        (if (fboundp 'denote-keywords-sort)
            (denote-keywords-sort keywords)
          keywords))
    (let ((input (read-string (format "%s (space-separated): "
                                      (or prompt "Tags")))))
      (unless (string-empty-p input)
        (split-string input " " t)))))

(defun my/denote-keywords-edit ()
  "Add or change the keywords of a Denote file.

`denote-rename-file-keywords' with `my/notes-keyword-preselect' in
force, so that the keyword prompt behaves the same way here as in
the note creation commands above.  Everything else -- which file is
acted on, how front matter is rewritten, what is confirmed -- is
Denote's and is deliberately not reimplemented.

Both bindings cover every minibuffer entered by that command, which
in practice is only the keyword prompt: `denote-rename-file-keywords'
takes its file from the current buffer or from the Dired marks
without asking."
  (interactive)
  (unless (fboundp 'denote-rename-file-keywords)
    (user-error "Denote is not available"))
  (let ((vertico-preselect my/notes-keyword-preselect))
    (minibuffer-with-setup-hook
        (:append (lambda () (my/notes--completion-keys ",")))
      (call-interactively #'denote-rename-file-keywords))))


;; ============================================================
;; JOURNAL: Daily note
;; ============================================================

(defun my/denote-journal ()
  "Create or open today's journal note.
  If journal exists, add new timestamped entry.
  Journal files go to ~/notes/journal/"
  (interactive)
  (let* ((today (format-time-string "%Y-%m-%d"))
         (time-now (format-time-string "%H:%M"))
         (journal-pattern (concat "--" today "-journal"))
         (existing-journal nil))

    ;; Search for existing journal in journal silo
    (dolist (file (directory-files my-notes-journal t "\\.org$"))
      (when (string-match-p journal-pattern (file-name-nondirectory file))
        (setq existing-journal file)))

    (if existing-journal
        ;; Journal exists - add new entry
        (progn
          (find-file existing-journal)
          (goto-char (point-max))

          ;; Smart spacing: always one blank line
          (save-excursion
            (goto-char (point-max))
            (skip-chars-backward " \t\n")
            (delete-region (point) (point-max)))

          (goto-char (point-max))
          (insert "\n\n")
          (insert (format "* %s\n" time-now))
          (message "Added entry to journal"))

      ;; Create new journal
      (let* ((id (format-time-string "%Y%m%dT%H%M%S"))
             (slug (format "%s-journal" today))
             (filename (format "%s--%s__journal.org" id slug))
             (filepath (expand-file-name filename my-notes-journal)))

        (find-file filepath)

        ;; Front matter
        (insert (format "#+title:      %s Journal\n" today))
        (insert (format "#+date:       [%s]\n" (format-time-string "%Y-%m-%d %a %H:%M")))
        (insert "#+filetags:   :journal:\n")
        (insert (format "#+identifier: %s\n" id))

        ;; Well-being property
        (insert ":PROPERTIES:\n")
        (insert ":well-being:  \n")
        (insert ":END:\n\n")

        ;; First entry
        (insert (format "* %s\n" time-now))

        (save-buffer)
        (message "Created new journal")))))

;; ============================================================
;; JOURNAL: Specific date (for migration/backdating)
;; ============================================================

(defun my/denote-journal-date ()
  "Create or open journal for a specific date (for migrating old entries).

  Behaviour:
  - If a journal for the chosen date already exists: open it, append
    a heading '* Uzupełnienie' with ADDED_AT and EVENT_DATE properties
    at the bottom and place the cursor there - ready to write.
  - If no journal exists for that date: create a new file.
    The denote identifier uses T000000 (zeroed time) to signal that
    the file was created retroactively. The first heading is also
    '* Uzupełnienie' with properties."
  (interactive)
  (let* ((date-input    (org-read-date nil nil nil "Date: "))
         (parsed-time   (org-parse-time-string date-input))
         (encoded-time  (apply 'encode-time parsed-time))
         (date-formatted (format-time-string "%Y-%m-%d" encoded-time))
         (added-at-stamp (format-time-string "%Y-%m-%d %a %H:%M"))
         (journal-pattern (concat "--" date-formatted "-journal"))
         (existing-journal nil))

    ;; Search for existing journal for the chosen date
    (dolist (file (directory-files my-notes-journal t "\\.org$"))
      (when (string-match-p journal-pattern (file-name-nondirectory file))
        (setq existing-journal file)))

    (if existing-journal
        ;; --------------------------------------------------------
        ;; Journal for that date exists - append supplement heading
        ;; --------------------------------------------------------
        (progn
          (find-file existing-journal)

          ;; Clean trailing whitespace/newlines
          (save-excursion
            (goto-char (point-max))
            (skip-chars-backward " \t\n")
            (delete-region (point) (point-max)))

          (goto-char (point-max))
          (insert "\n\n* Uzupełnienie\n")
          (insert ":PROPERTIES:\n")
          (insert (format ":ADDED_AT:   [%s]\n" added-at-stamp))
          (insert (format ":EVENT_DATE: [%s]\n" date-formatted))
          (insert ":END:\n\n")
          (message "Opened existing journal for %s - cursor below '* Uzupełnienie'"
                   date-formatted))

      ;; --------------------------------------------------------
      ;; No journal for that date - create a fresh backdated file
      ;; ID uses T000000 to mark it as retroactively created.
      ;; --------------------------------------------------------
      (let* ((id       (format-time-string "%Y%m%dT000000" encoded-time))
             (slug     (format "%s-journal" date-formatted))
             (filename (format "%s--%s__journal.org" id slug))
             (filepath (expand-file-name filename my-notes-journal)))

        (find-file filepath)
        (insert (format "#+title:      %s Journal\n" date-formatted))
        (insert (format "#+date:       %s\n"
                        (format-time-string "[%Y-%m-%d %a]" encoded-time)))
        (insert "#+filetags:   :journal:\n")
        (insert (format "#+identifier: %s\n" id))
        (insert ":PROPERTIES:\n")
        (insert ":well-being:  \n")
        (insert ":END:\n\n")
        ;; First heading carries the real creation timestamp in properties
        (insert "* Uzupełnienie\n")
        (insert ":PROPERTIES:\n")
        (insert (format ":ADDED_AT:   [%s]\n" added-at-stamp))
        (insert (format ":EVENT_DATE: [%s]\n" date-formatted))
        (insert ":END:\n")
        (save-buffer)
        (message "Created backdated journal for %s (written %s)"
                 date-formatted added-at-stamp)))))

;; ============================================================
;; BASE NOTE: Simple note with title and tags
;; ============================================================

(defun my/denote-base ()
  "Create a simple note with title and tags.
  You'll be asked which silo (journal/pks/docu) to save in."
  (interactive)
  (let* ((title (read-string "Title: "))
         (keywords (my/notes-read-keywords))
         (silo (completing-read "Save in: "
                               '("pks" "docu" "journal")
                               nil t "pks"))
         (target-dir (cond
                      ((string= silo "journal") my-notes-journal)
                      ((string= silo "docu") my-notes-docu)
                      (t my-notes-pks))))

    ;; Temporarily set denote-directory to target silo
    (let ((denote-directory target-dir))
      (if (string-empty-p title)
          (denote nil keywords)
        (denote title keywords)))))

;; ============================================================
;; ESSAY: Writing project
;; ============================================================

(defun my/denote-essay ()
  "Create essay template (writing project).
  Essays go to ~/notes/pks/ by default."
  (interactive)
  (let* ((essay-title (read-string "Essay title: "))
         (title (format "ESEJ: %s" essay-title))
         ;; Completed like any other keyword: the project tag is the
         ;; one that must match an existing note's tag exactly, since
         ;; it is what later gathers the essay's material.
         (project-tags (my/notes-read-keywords "Project KEYWORDS"))
         (tags (append '("esej" "project") project-tags))
         (denote-directory my-notes-pks))  ; Essays in pks silo

    (denote title tags)

    ;; Add essay template
    (save-excursion
      (goto-char (point-max))
      (insert "\n* Metadata\n")
      (insert "- Subject: \n")
      (insert "- Deadline: \n")
      (insert "- Length: \n")
      (insert "- Status: Planning\n\n")
      (insert "* Essay Plan\n")
      (insert "** Introduction\n\n")
      (insert "** Main Part\n\n")
      (insert "** Conclusion\n\n")
      (insert "* Bibliography\n\n")
      (insert "* Working Notes\n\n")
      (save-buffer))

    ;; Position cursor at Subject field
    (goto-char (point-min))
    (re-search-forward "^- Subject: " nil t)))

;; ============================================================
;; WELL-BEING: Set well-being score for journal
;; ============================================================

(defun my/denote-set-wellbeing ()
  "Set well-being score (1-10) for current journal note."
  (interactive)
  (if (not (string-match-p "journal" (or (buffer-file-name) "")))
      (message "This is not a journal note!")
    (let ((score (read-number "Well-being score (1-10): " 5)))
      (when (and (>= score 1) (<= score 10))
        (save-excursion
          (goto-char (point-min))
          (if (re-search-forward ":well-being: *\\([0-9]*\\)" nil t)
              (replace-match (number-to-string score) nil nil nil 1)
            (message "Could not find well-being property"))
          (save-buffer)
          (message "Well-being set to %d" score))))))

;; ============================================================
;; HELPER: Insert current time (HH:MM)
;; ============================================================

(defun insert-current-time ()
  "Insert current time in HH:MM format."
  (interactive)
  (insert (format-time-string "%H:%M")))

;; ============================================================
;; HELPER: Insert current date (YYYY-MM-DD)
;; ============================================================

(defun insert-current-date ()
  "Insert current date in YYYY-MM-DD format."
  (interactive)
  (insert (format-time-string "%Y-%m-%d")))

;; ============================================================
;; HELPER: Delete current note (Git-aware)
;; ============================================================

(defun my/denote-delete-note ()
  "Delete current note file and buffer.
  Uses 'git rm' if file is tracked, otherwise regular delete."
  (interactive)
  (let* ((file (buffer-file-name))
         (name (file-name-nondirectory file)))
    (if (not file)
        (message "This is not a file!")
      (when (yes-or-no-p (format "Delete note: %s? " name))
        ;; Check if in Git repo — call-process is safe against filenames
        ;; with apostrophes or other special characters (no shell involved).
        (if (and (executable-find "git")
                 (= 0 (call-process "git" nil nil nil
                                   "ls-files" "--error-unmatch" file)))
            (progn
              (call-process "git" nil nil nil "rm" "-f" file)
              (message "Deleted from Git: %s" name))
          (progn
            (delete-file file)
            (message "Deleted: %s" name)))
        (kill-buffer (current-buffer))))))

;; ============================================================
;; MOVE NOTE BETWEEN SILOS
;; ============================================================
;; Reads identifiers with `my/denote--file-identifier', which belongs to
;; 27-denote-identifiers.el -- the module that owns identifier integrity
;; and is also where 25-inbox-review.el gets it from.  A copy used to
;; live here as well.  Two copies of a four-line function is not a
;; maintenance cost worth mentioning, but two definitions of one symbol
;; is: the later-loading module wins, silently, and the earlier one gets
;; whatever behaviour that other module happened to give it.
;;
;; Resolution is at call time, so the load order does not matter; the
;; guard in `my/denote-move-to-silo' turns a missing module into a
;; sentence rather than a void-function backtrace.

(defvar my/denote-silo-alist
  `(("journal" . ,my-notes-journal)
    ("pks"     . ,my-notes-pks)
    ("docu"    . ,my-notes-docu))
  "Alist of (NAME . DIRECTORY) for every Denote silo.
Used by `my/denote-move-to-silo' to build its completion list.
Add an entry here when a new silo is added to 00-core.el.")

(defun my/denote--file-title (file)
  "Return the `#+title:' value of FILE, or nil if absent.
Reads only the beginning of FILE: Denote front matter is always at
the top, so there is no reason to load a whole note from disk."
  (with-temp-buffer
    (ignore-errors
      (insert-file-contents file nil 0 4000))
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title:[ \t]+\\(.*?\\)[ \t]*$" nil t)
      (match-string-no-properties 1))))

(defun my/denote--silo-note-files (dir)
  "Return the Denote files directly inside DIR.
Non-recursive on purpose: the silos in this configuration are flat.

Named for what it returns rather than generically: 27-denote-identifiers.el
has its own scan with a different shape and a different job, and the two
carried the same name until one of them started being called with the
wrong number of arguments."
  (when (file-directory-p dir)
    (directory-files dir t "\\`[0-9]\\{8\\}T[0-9]\\{6\\}")))

(defun my/denote--current-silo (file)
  "Return the silo name FILE currently lives in, or nil if none matches."
  (car (seq-find (lambda (cell)
                   (file-in-directory-p file (cdr cell)))
                 my/denote-silo-alist)))

(defun my/denote--titles-equal-p (a b)
  "Compare titles A and B, ignoring case and surrounding whitespace.
Uses `downcase' rather than `string-equal-ignore-case', which only
exists from Emacs 29 onwards while Denote itself supports 28.1."
  (and a b (string= (downcase (string-trim a))
                    (downcase (string-trim b)))))

(defun my/denote--relocate (source target)
  "Move SOURCE to TARGET, using \"git mv\" when SOURCE is tracked.
Mirrors the git handling of `my/denote-delete-note' so that history
is preserved instead of showing an unrelated delete plus add."
  (let ((default-directory (file-name-directory source)))
    (if (and (executable-find "git")
             (= 0 (call-process "git" nil nil nil
                                "ls-files" "--error-unmatch" source)))
        (unless (= 0 (call-process "git" nil nil nil "mv" source target))
          ;; git mv can refuse (e.g. target outside the repo); fall back.
          (rename-file source target t))
      (rename-file source target t))))

(defun my/denote--remove (file)
  "Delete FILE, using \"git rm\" when it is tracked."
  (let ((default-directory (file-name-directory file)))
    (if (and (executable-find "git")
             (= 0 (call-process "git" nil nil nil
                                "ls-files" "--error-unmatch" file)))
        (call-process "git" nil nil nil "rm" "-f" file)
      (delete-file file))))

(defun my/denote-move-to-silo ()
  "Move the current Denote note to another silo.

Prompts for the destination silo, then checks the destination for
conflicts before moving anything:

- No note with the same `#+title:' there: move straight away.
- A note with the same title exists: ask whether to overwrite it or
  to keep both.  Two notes may share a title as long as their
  identifiers differ, which is the normal Denote situation.
- Keeping both is impossible when the identifiers are also equal,
  because the resulting file names would be identical.  In that case
  ask for a new title (applied via `denote-rename-file-using-front-matter')
  or cancel.

Note that a new title does NOT resolve the underlying identifier
clash: two notes sharing an identifier make `denote:' links to that
identifier ambiguous.  The retitling path exists to unblock the move;
the duplicate identifier still needs sorting out afterwards."
  (interactive)
  (unless (fboundp 'my/denote--file-identifier)
    (user-error "27-denote-identifiers.el is not loaded"))
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "This buffer is not visiting a file"))
    (unless (my/denote--file-identifier file)
      (user-error "Not a Denote file (no identifier in the file name)"))
    (when (buffer-modified-p)
      (if (y-or-n-p "Buffer has unsaved changes.  Save before moving? ")
          (save-buffer)
        (user-error "Aborted: save the buffer first")))

    (let* ((current-silo (my/denote--current-silo file))
           (candidates (seq-remove (lambda (cell)
                                     (equal (car cell) current-silo))
                                   my/denote-silo-alist))
           (choice (completing-read
                    (format "Move to silo (currently: %s): "
                            (or current-silo "outside any silo"))
                    (mapcar #'car candidates) nil t))
           (target-dir (cdr (assoc choice my/denote-silo-alist)))
           (title (my/denote--file-title file))
           (identifier (my/denote--file-identifier file)))

      (unless (file-directory-p target-dir)
        (user-error "Target silo does not exist: %s" target-dir))

      (let* ((target-files (my/denote--silo-note-files target-dir))
             (title-matches
              (seq-filter (lambda (f)
                            (my/denote--titles-equal-p title
                                                       (my/denote--file-title f)))
                          target-files))
             (proceed t))

        (when title-matches
          (pcase (completing-read
                  (format "%d note(s) titled \"%s\" already in %s.  Action: "
                          (length title-matches) (or title "?") choice)
                  '("keep both" "overwrite" "cancel") nil t "keep both")
            ("cancel"
             (setq proceed nil))

            ("overwrite"
             (let ((victim (if (= (length title-matches) 1)
                               (car title-matches)
                             (completing-read "Overwrite which note? "
                                              title-matches nil t))))
               (if (yes-or-no-p (format "Permanently delete %s? "
                                        (file-name-nondirectory victim)))
                   (my/denote--remove victim)
                 (setq proceed nil))))

            ("keep both"
             ;; Two notes can share a title only if their identifiers
             ;; differ; otherwise both file names would be identical.
             (when (seq-find (lambda (f)
                               (equal identifier (my/denote--file-identifier f)))
                             title-matches)
               (let ((new-title
                      (read-string
                       "Same title AND identifier there.  New title (empty = cancel): ")))
                 (if (string-empty-p (string-trim new-title))
                     (setq proceed nil)
                   ;; Update front matter, then let Denote derive the new
                   ;; file name from it.  Doing it this way avoids calling
                   ;; Denote's sluggify internals directly.
                   (save-excursion
                     (goto-char (point-min))
                     (if (re-search-forward "^#\\+title:[ \t]+.*$" nil t)
                         (replace-match (concat "#+title:      " new-title) t t)
                       (setq proceed nil)))
                   (when proceed
                     (save-buffer)
                     (call-interactively #'denote-rename-file-using-front-matter)
                     (setq file (buffer-file-name)))))))))

        (when proceed
          (let ((target (expand-file-name (file-name-nondirectory file)
                                          target-dir)))
            (if (file-exists-p target)
                (user-error "Target file already exists: %s" target)
              (my/denote--relocate file target)
              (set-visited-file-name target nil t)
              (set-buffer-modified-p nil)
              (message "Moved to %s: %s"
                       choice (file-name-nondirectory target)))))))))


;; ============================================================
;; LINKED NOTE: Create new note with backlink to source
;; ============================================================

(defun my/denote-linked-note ()
  "Create a new note linked to the current .org buffer.

  From source note:
  - Inserts a forward link [[denote:ID][Title]] at point.

  In new note:
  - Adds :BACKLINK: property pointing back to the source.
  - Opens in a window to the right, cursor moves there.

  Only works when called from a Denote .org file with #+identifier."
  (interactive)

  ;; --- Guard: must be called from an .org file ---
  (unless (and (buffer-file-name)
               (string-suffix-p ".org" (buffer-file-name)))
    (user-error "Not an .org file — aborting"))

  ;; --- Collect source note data ---
  (let* ((source-buffer (current-buffer))
         (source-file   (buffer-file-name))

         (source-id
          (save-excursion
            (goto-char (point-min))
            (if (re-search-forward "^#\\+identifier:[ \t]+\\([0-9A-Za-z]+\\)" nil t)
                (match-string-no-properties 1)
              nil)))

         (source-title
          (save-excursion
            (goto-char (point-min))
            (if (re-search-forward "^#\\+title:[ \t]+\\(.+\\)" nil t)
                (string-trim (match-string-no-properties 1))
              (file-name-nondirectory source-file)))))

    (unless source-id
      (user-error "Source file has no #+identifier — not a Denote note?"))

    ;; --- Ask for parameters BEFORE touching windows ---
    (let* ((new-title       (read-string "New note title: "))
           (keywords        (my/notes-read-keywords))
           (silo            (completing-read "Save in: "
                                            '("pks" "docu" "journal")
                                            nil t "pks"))
           (target-dir      (cond
                             ((string= silo "journal") my-notes-journal)
                             ((string= silo "docu")   my-notes-docu)
                             (t                        my-notes-pks)))

           ;; --- Create note inside save-window-excursion so Denote
           ;;     cannot change the window layout ---
           (new-file
            (save-window-excursion
              (let ((denote-directory target-dir))
                (denote new-title keywords))
              (buffer-file-name)))

           (new-id
            (if (string-match "\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)" new-file)
                (match-string 1 new-file)
              nil)))

      (unless new-id
        (user-error "Could not extract ID from new note filename: %s" new-file))

      ;; --- Backlink in new note ---
      (with-current-buffer (find-file-noselect new-file)
        (save-excursion
          (goto-char (point-min))
          (if (re-search-forward "^:PROPERTIES:" nil t)
              (progn
                (re-search-forward "^:END:" nil t)
                (beginning-of-line)
                (insert (format ":BACKLINK:   [[denote:%s][%s]]\n"
                                source-id source-title)))
            (goto-char (point-min))
            (while (looking-at "^#\\+")
              (forward-line 1))
            (insert (format ":PROPERTIES:\n:BACKLINK:   [[denote:%s][%s]]\n:END:\n\n"
                            source-id source-title))))
        (save-buffer))

      ;; --- Forward link in source note ---
      (with-current-buffer source-buffer
        (insert (format "[[denote:%s][%s]]" new-id new-title))
        (save-buffer))

      ;; --- Layout: source on left, new note on right ---
      ;; At this point current-buffer is source-buffer (save-window-excursion
      ;; restored the window layout), so split-window-right splits it correctly.
      (let ((new-window (split-window-right)))
        (select-window new-window)
        (find-file new-file)
        (goto-char (point-max)))

      (message "Linked note created: %s ← → %s" source-title new-title))))

(provide '05-notes)
;;; 05-notes.el ends here
