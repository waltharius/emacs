;;; 12-transient.el --- Transient menu for notes (hierarchical) -*- lexical-binding: t; -*-

;; MyPKS-Requires: 05-notes
;; MyPKS-Optional: no

;;; Commentary:
;; Unified transient menu for all note-related operations.
;; Accessed with C-c n — hierarchical structure with sub-menus:
;;
;;   C-c n c  — Create / Capture
;;   C-c n f  — Find (search & navigation)
;;   C-c n i  — Insert (links, time, date)
;;   C-c n d  — Document / File management
;;   C-c n x  — eXport
;;   C-c n v  — View
;;   C-c n t  — Tools (Zotero/Bib, spelling, future integrations)
;;   C-c n l  — Philosophy (appended dynamically by 19-philosophy-notes.el)
;;   C-c n z  — Zettelkasten (appended dynamically by 22-zettelkasten.el)
;;   C-c n !  — Maintenance (appended dynamically by 26-maintenance.el)
;;   C-c n h  — Function Help (opens function_helper.org)
;;
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-main

;;; Code:

(require 'transient)
(require 'seq)

;; ============================================================
;; SUB-MENU: Create / Capture  (C-c n c)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-create
;; ============================================================

(transient-define-prefix my/notes-create-menu ()
  "Create notes and run captures."
  ;; "w" and "W" are reserved: 05b-journal-metrics.el appends the two
  ;; metrics commands after "J" dynamically, so that deleting that module
  ;; leaves this menu valid instead of binding void commands.
  ;;
  ;; The Capture column (i c m) is inserted by 06-capture.el before the
  ;; Quit column, coordinate (0 1), so that without that module the menu
  ;; simply has no Capture column.
  [["Create"
    ("n" "New note"       my/denote-base)
    ("j" "Journal today"  my/denote-journal)
    ("J" "Journal date"   my/denote-journal-date)
    ("e" "Essay"          my/denote-essay)
    ("L" "Linked note"    my/denote-linked-note)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Find / Search  (C-c n f)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-find
;; ============================================================

(transient-define-prefix my/notes-find-menu ()
  "Search and navigate notes."
  ;; The Overview column is filled by the modules, each inserting before
  ;; "q": 15-workspace.el (d t r), 21-dashboards.el (h),
  ;; 35-journal-gaps.el (j), 36-notes-stats.el (s), in load order.
  [["Find"
    ("f" "Find file"    denote-open-or-create)
    ("g" "Grep notes"   consult-denote-grep)
    ("b" "Backlinks"    denote-backlinks)]
   ["Overview"
    ("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Insert  (C-c n i)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-insert
;; ============================================================

(transient-define-prefix my/notes-insert-menu ()
  "Insert links, dates, and content."
  ;; The old ("w" "Well-being") entry is gone.  It edited the :well-being:
  ;; line in a drawer that Org never parsed as properties, and that drawer
  ;; is being retired.  Its replacement lives in the Create menu and is
  ;; appended there by 05b-journal-metrics.el, so that removing the metrics
  ;; module removes the menu entry with it.
  [["Link"
    ("l" "Insert link"  denote-link)
    ("L" "Linked note"  my/denote-linked-note)]
   ["Date & Time"
    ("h" "Time (HH:MM)"      insert-current-time)
    ("d" "Date (YYYY-MM-DD)" insert-current-date)
    ;; Declared here rather than appended by the owning module, the way
    ;; the Create menu declares the other 05-notes.el commands:
    ;; 05-notes.el is loaded without NOERROR, so it is always present
    ;; and there is nothing to degrade around.
    ("w" "Week's days"       my/journal-insert-week-links)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Document / File management  (C-c n d)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-doc
;; ============================================================

(transient-define-prefix my/notes-doc-menu ()
  "File and document management."
  [["File"
    ("r" "Rename file"    denote-rename-file)
    ("k" "Add keywords"   my/denote-keywords-edit)
    ("c" "Change silo"    my/denote-move-to-silo)
    ("d" "Delete note"    my/denote-delete-note)
    ("!" "Deletion questions on/off (this session)" my/confirm-deletion-toggle-session)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Export  (C-c n x)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-export
;; ============================================================

(transient-define-prefix my/notes-export-menu ()
  "Export notes: PDF, office documents, sites."
  ;; Filled by the modules, each inserting before "q", in load order:
  ;; 16-org-export.el (p P Q), 29-writing-export.el (O W ?),
  ;; 46-blog.el (b), 47-repo-docs.el (r).
  [["Export"
    ("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: View toggles  (C-c n v)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-view
;; ============================================================

;; The Toggle column is filled by the modules, each inserting its
;; entries before "q" with `my/transient-insert': 10-visual-fill.el (c),
;; 11-org-appearance.el (i e), 13-centered-writing.el (w),
;; 30-link-tooltips.el (T), 34-appearance.el (t y p W S),
;; 44-image-display.el (m).  The column "Detach to own frame" (f F) is
;; appended after it by 23-fixed-tabs.el.
(transient-define-prefix my/notes-view-menu ()
  "Toggle visual appearance settings."
  [["Toggle"
    ("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SUB-MENU: Tools  (C-c n t)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-tools
;; ============================================================

;; The Integrations column is filled by the modules themselves, each
;; inserting its entry before "q" with `my/transient-insert':
;; 18-zotero-transient.el (z), 24-readwise.el (r), 25-inbox-review.el
;; (i), 40-markdown.el (m), 42-obsidian-import.el (o).  Quit is the
;; anchor because it is the one entry no module owns.  The Spelling
;; column is inserted before it, as a group, by 03-spelling.el.
(transient-define-prefix my/notes-tools-menu ()
  "External tools and integrations."
  [["Integrations"
    ("q" "Quit" transient-quit-one)]])

;; ============================================================
;; HELPER: Open function_helper.org in new tab
;; Docs: ~/.emacs.d/function_helper.org::#fn-open-function-helper
;; ============================================================

(defun my/open-function-helper ()
  "Open ~/.emacs.d/function_helper.org in a new tab."
  (interactive)
  (tab-bar-new-tab)
  (find-file (expand-file-name "function_helper.org" user-emacs-directory))
  (when (fboundp 'org-overview)
    (org-overview)))

;; ============================================================
;; MAIN NOTES MENU  (C-c n)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-main
;; ============================================================

;; ============================================================
;; SAFE MENU EXTENSION
;; ============================================================
;; Feature modules add their own entries to these menus with
;; `transient-append-suffix', which needs an anchor: an existing key to
;; append after.  Anchoring on a key contributed by ANOTHER feature
;; module couples the two, and `transient-append-suffix' signals when
;; the anchor is absent -- during module loading, which aborts init.el
;; partway and leaves the rest of the configuration unloaded.
;;
;; That turns "I removed a module I do not use" into a broken Emacs,
;; and the error names the appending module rather than the missing
;; one, so the cause is not obvious.
;;
;; This wrapper degrades instead: a missing prefix or anchor leaves the
;; entry out and says so, which is the correct outcome -- an entry
;; whose neighbour does not exist has nowhere meaningful to go.
;;
;; SKIPPED ENTRIES ARE RECORDED, AND A TAKEN KEY IS SHOWN.  "Says so"
;; used to mean one line in *Messages*, which nobody reads at start-up.
;; The dangerous case is a key two modules both want: the module loaded
;; first keeps it, the other's entry is missing, and nothing looks
;; wrong.  Every skipped entry now goes to `my/transient-skipped', and
;; after start-up one warning lists the ones that point at a mistake:
;;
;;   taken       the key already runs another command        warned
;;   no-anchor   the neighbour to add next to is missing     warned
;;   no-prefix   the whole menu is missing (its module off)  listed only
;;
;; `my/transient-skipped-report' lists all three.  The same command on
;; the same key is not recorded: that is a module re-adding its own
;; entry (re-evaluating a file during development).  The pre-commit
;; check `menukeys' (hooks/lint.py) finds taken keys before Emacs runs.

(defvar my/transient-skipped nil
  "Menu entries left out while modules added them, oldest first.
Each is a plist: :menu, :key, :command, :reason (`taken', `no-anchor',
`no-prefix' or `error'), :module (the file defining the command), and
for `taken' :holder (the command already on the key), for `no-anchor'
:anchor.  Shown by `my/transient-skipped-report'.")

(defun my/transient--command-of (suffix)
  "Return the command of SUFFIX, or of the first entry when it is a group.
SUFFIX is a specification as passed to `my/transient-append':
\='(\"k\" \"Label\" command ...) or a group vector."
  (let ((entry (if (vectorp suffix) (seq-find #'consp (append suffix nil)) suffix)))
    (seq-find (lambda (x) (and (symbolp x) (not (keywordp x)))) (cddr entry))))

(defun my/transient--layout-command (layout-entry)
  "Return the command of LAYOUT-ENTRY, as `transient-get-suffix' gives it.
Transient has changed the shape between versions: (LEVEL CLASS PLIST)
in the one built into Emacs 29, (CLASS . PLIST) in transient 0.13 (which
comes with Magit), vectors in others.  The value after the first
:command, wherever it is; nil when there is none.

Until 2026-10-22 only the first shape was read.  With transient 0.13
this returned nil, so a module switched off kept its menu entries
\(`my/transient-remove' saw another command on the key) -- found by the
weekly switch test (tests/weekly/)."
  (let ((todo (list layout-entry)) (found nil))
    (while (and todo (not found))
      (let ((x (pop todo)))
        (when (vectorp x) (setq x (append x nil)))
        (when (consp x)
          (let ((tail (and (proper-list-p x) (memq :command x))))
            (if (and tail (cdr tail))
                (setq found (cadr tail))
              ;; Depth first, in order: the entry's own plist comes
              ;; before anything nested in it.
              (setq todo (append (if (proper-list-p x) x (list (car x) (cdr x)))
                                 todo)))))))
    found))

(defun my/transient--record-skip (menu key suffix reason &rest more)
  "Record that SUFFIX was not added to MENU under KEY, for REASON.
MORE is a plist added to the record (:holder, :anchor, :error)."
  (let* ((command (my/transient--command-of suffix))
         ;; `symbol-file' knows a module only once it has finished
         ;; loading; a module still loading is the file being loaded.
         (file (or (and command (symbol-file command 'defun)) load-file-name))
         (record (append (list :menu menu :key key :command command
                               :reason reason
                               :module (if file (file-name-nondirectory file) "?"))
                         more)))
    (unless (member record my/transient-skipped)
      (setq my/transient-skipped (append my/transient-skipped (list record))))
    (message "transient: %s `%s' not added to %s (%s)" command key menu reason)))

(defun my/transient--suffix-key (suffix)
  "Return the key of SUFFIX, or of the first entry when SUFFIX is a group.
A group is a vector such as [\"Spelling\" (\"s\" \"Correct\" cmd) ...]; its
first entry stands for the whole group in the already-there test."
  (if (vectorp suffix)
      (car (seq-find #'consp (append suffix nil)))
    (car suffix)))

(defun my/transient--add (prefix anchor suffix before)
  "Add SUFFIX to PREFIX next to ANCHOR; before it when BEFORE is non-nil.
The shared body of `my/transient-append' and `my/transient-insert'.
SUFFIX may be a group (a vector); ANCHOR is then a coordinate list such
as \='(0 0), the first column."
  (let* ((key (my/transient--suffix-key suffix))
         (existing (and (fboundp prefix)
                        (ignore-errors (transient-get-suffix prefix key)))))
    (cond
     ((not (fboundp prefix))
      (my/transient--record-skip prefix key suffix 'no-prefix))
     (existing
      ;; The same command again: a module re-adding its own entry.
      (let ((holder (my/transient--layout-command existing)))
        (unless (eq holder (my/transient--command-of suffix))
          (my/transient--record-skip prefix key suffix 'taken :holder holder))))
     ((not (ignore-errors (transient-get-suffix prefix anchor)))
      (my/transient--record-skip prefix key suffix 'no-anchor :anchor anchor))
     (t
      (condition-case err
          (if before
              (transient-insert-suffix prefix anchor suffix)
            (transient-append-suffix prefix anchor suffix))
        (error
         (my/transient--record-skip prefix key suffix 'error
                                    :error (error-message-string err))))))))

(defun my/transient-append (prefix anchor suffix)
  "Add SUFFIX to PREFIX after ANCHOR, without ever signalling.

SUFFIX is a transient suffix specification such as
\\='(\"z\" \"Label\" some-command).  Does nothing when PREFIX is not
defined, when ANCHOR is not present in it, or when SUFFIX\\='s key is
already bound there -- the last case making re-evaluation of a module
during development harmless."
  (my/transient--add prefix anchor suffix nil))

(defun my/transient-insert (prefix anchor suffix)
  "Add SUFFIX to PREFIX before ANCHOR, without ever signalling.

As `my/transient-append', for a column whose only fixed entry is its
last one.  The Integrations column of the Tools menu and the Toggle
column of the View menu hold nothing but Quit (\"q\") until modules
insert themselves before it: anchored on a key that belongs to this
file, an entry does not disappear when the module that used to be its
neighbour is turned off.

A whole column is inserted the same way, as a group before a
coordinate: 03-spelling.el puts its Spelling column first in the Tools
menu with ANCHOR \='(0 0) and SUFFIX [\"Spelling\" (\"s\" ...) ...]."
  (my/transient--add prefix anchor suffix t))

(defun my/transient-replace (prefix key suffix)
  "Replace the entry bound to KEY in PREFIX with SUFFIX, without signalling.

SUFFIX is a transient suffix specification such as
\\='(\"g\" \"Label\" some-command).  Does nothing when PREFIX is not
defined, when KEY is not bound in it, or when SUFFIX names a command
that does not exist -- the last case being what stops a half-loaded
feature module from leaving a void command on a key that used to work.

The counterpart of `my/transient-append', for the case where a feature
module supersedes a command declared here rather than adding one beside
it.  The entry declared in this file stays the fallback: it is what the
menu carries when the feature module is absent."
  (let ((command (nth 2 suffix)))
    (cond
     ((not (fboundp prefix))
      (message "transient: no %s, keeping `%s'" prefix key))
     ((not (fboundp command))
      (message "transient: %s is not defined, keeping `%s' in %s"
               command key prefix))
     ((not (ignore-errors (transient-get-suffix prefix key)))
      (message "transient: %s has no `%s' to replace, skipping" prefix key))
     (t
      (condition-case err
          (transient-replace-suffix prefix key suffix)
        (error
         (message "transient: could not replace `%s' in %s: %s"
                  key prefix (error-message-string err))))))))

;; ADDING AND REMOVING WITH A MODULE'S SWITCH.  A module that can be
;; turned on and off while Emacs runs (its `my/<name>-mode') adds its
;; entries when turned on and removes them when turned off, from one
;; list:
;;
;;   (defconst my/x--menu-entries
;;     '((insert my/notes-tools-menu "q" ("x" "Thing →" my/x-menu))))
;;   ... in the mode's body:
;;   (with-eval-after-load '12-transient
;;     (my/transient-entries my/x-mode my/x--menu-entries))
;;
;; `with-eval-after-load' because a module may be switched before this
;; file has loaded; the body then runs once it has, with the switch's
;; value at that moment.

(defun my/transient-remove (prefix key command)
  "Remove the entry on KEY from PREFIX if it runs COMMAND; never signal.
An entry another module put on KEY is left alone: removing it would
take that module's entry away when this one is turned off.  A column
left without entries is not drawn."
  (let ((existing (and (fboundp prefix)
                       (ignore-errors (transient-get-suffix prefix key)))))
    (when (and existing (eq (my/transient--layout-command existing) command))
      (condition-case err
          (transient-remove-suffix prefix key)
        (error (message "transient: could not remove `%s' from %s: %s"
                        key prefix (error-message-string err)))))))

(defun my/transient-entries (on entries)
  "Add ENTRIES to their menus when ON is non-nil, remove them otherwise.
Each entry is (HOW PREFIX ANCHOR SUFFIX): HOW is `insert' (before
ANCHOR, `my/transient-insert') or `append' (after it,
`my/transient-append'); SUFFIX an entry or a column as those take.
Removing takes out every entry of SUFFIX that still runs its own
command.  Adding an entry already there does nothing, so calling this
twice with the same ON is harmless."
  (dolist (entry (if on entries (reverse entries)))
    (pcase-let ((`(,how ,prefix ,anchor ,suffix) entry))
      (if on
          (if (eq how 'insert)
              (my/transient-insert prefix anchor suffix)
            (my/transient-append prefix anchor suffix))
        (dolist (one (if (vectorp suffix)
                         (seq-filter #'consp (append suffix nil))
                       (list suffix)))
          (my/transient-remove prefix (car one) (my/transient--command-of one)))))))

;; Reporting skipped entries: one warning after start-up, a command for
;; the full list.

(defun my/transient--skip-line (record)
  "Return one line describing the skipped entry RECORD."
  (let ((menu (plist-get record :menu))
        (key (plist-get record :key))
        (command (plist-get record :command))
        (module (plist-get record :module)))
    (pcase (plist-get record :reason)
      ('taken (format "%s, key %s: %s (%s) not added -- the key already runs %s"
                      menu key command module
                      (or (plist-get record :holder) "another command")))
      ('no-anchor (format "%s, key %s: %s (%s) not added -- its neighbour %S is missing"
                          menu key command module (plist-get record :anchor)))
      ('no-prefix (format "%s, key %s: %s (%s) not added -- the menu does not exist (its module is off)"
                          menu key command module))
      (_ (format "%s, key %s: %s (%s) not added -- %s"
                 menu key command module (plist-get record :error))))))

(defun my/transient--warn-skipped ()
  "After start-up, warn once about entries left out by mistake.
A taken key or a missing neighbour is a mistake in a module; a missing
menu is a module turned off, and only listed by the report."
  (let ((mistakes (seq-filter (lambda (r) (memq (plist-get r :reason) '(taken no-anchor error)))
                              my/transient-skipped)))
    (when mistakes
      (display-warning
       'menus
       (concat "Menu entries left out:\n\n"
               (mapconcat #'my/transient--skip-line mistakes "\n")
               "\n\nTwo modules want the same key, or an entry's neighbour is gone.  "
               "Change the key in one of the modules; M-x my/transient-skipped-report "
               "lists every entry left out.")
       :warning))))

(add-hook 'emacs-startup-hook #'my/transient--warn-skipped)

(defun my/transient-skipped-report ()
  "List every menu entry modules tried to add and could not, and why."
  (interactive)
  (with-current-buffer (get-buffer-create "*Menu entries left out*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (if my/transient-skipped
                  (mapconcat #'my/transient--skip-line my/transient-skipped "\n")
                "Every menu entry the modules added is in its menu.")
              "\n")
      (special-mode))
    (pop-to-buffer (current-buffer))))

;; ============================================================
;; SUB-MENU: Settings  (C-c n ,)
;; Docs: ~/.emacs.d/function_helper.org::#settings
;; ============================================================
;; "," again opens Customize, so the old key sequence plus one comma
;; still reaches it.  The machine commands come from 00-core.el.

(transient-define-prefix my/settings-menu ()
  "Settings of this configuration and of this machine."
  [["Settings"
    ("," "Open settings (Customize)"            my/settings)
    ("f" "This machine's settings file"         my/host-settings-open)]
   ["Notes folder"
    ("n" "Notes folder and silos settings"      my/notes-open-silo-settings)
    ("o" "Folders with notes not in a silo"     my/silo-report-orphans)]
   ["Machines"
    ("m" "Modules on this machine"              my/modules-toggle)
    ("c" "Copy settings from another machine"   my/host-settings-copy-from)
    ("u" "Use another machine's settings here"  my/host-settings-use)]
   [("q" "Quit" transient-quit-one)]])

(transient-define-prefix my/notes-menu ()
  "Unified menu for all note operations."
  [["Notes"
    ("c" "Create → new/journal/essay/capture"       my/notes-create-menu)
    ("f" "Find → file/grep/backlinks/random"         my/notes-find-menu)
    ("i" "Insert → transclusion/link/time/date"       my/notes-insert-menu)
    ("d" "Document → rename/keywords/delete"     my/notes-doc-menu)
    ("x" "Export → pdf/batch-any/batch-all"       my/notes-export-menu)]
   ["Settings & Tools"
    ("v" "View → center/writing/indent/emphasis"         my/notes-view-menu)
    ("t" "Tools → spelling/integrations"  my/notes-tools-menu)
    ;; After ",": "s" and "a" (spelling, 03-spelling.el), "!"
    ;; (26-maintenance.el); after "t": "l" (19-philosophy-notes.el),
    ;; "z" (22-zettelkasten.el).
    ("," "Settings →"  my/settings-menu)]
   [("h" "Function Help"  my/open-function-helper)
    ("q" "Quit"            transient-quit-one)]])

;; ============================================================
;; KEYBINDING
;; ============================================================

(global-set-key (kbd "C-c n") 'my/notes-menu)

(provide '12-transient)
;;; 12-transient.el ends here
