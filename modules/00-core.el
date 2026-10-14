;;; 00-core.el --- Package system and core variables -*- lexical-binding: t; -*-
;;; Commentary:
;; Core configuration: package management and essential variables
;; This file MUST be loaded first!

;;; Code:

;; ============================================================
;; PACKAGE MANAGEMENT: use-package + MELPA
;; ============================================================

(require 'package)

;; Add MELPA repository
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

;; Initialize package system
(package-initialize)

;; Install use-package if not present
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

;; Load use-package
(require 'use-package)
(setq use-package-always-ensure t)  ; Auto-install packages

;; ============================================================
;; SETTINGS MENU: one Customize tree for the whole configuration
;; ============================================================
;; Customize arranges options in groups, as folders.  Every module's
;; group hangs under one of the area groups below, and those under
;; `mypks', so `my/settings' (C-c n ,) opens one tree holding every
;; option of this configuration -- instead of options scattered under
;; Emacs's own `convenience', `org' and `faces' among thousands of
;; package options.
;;
;; Named MyPKS rather than PKS: pks/ is already the name of a silo.
;;
;; A module names its parent area with `:group' in its own `defgroup'.
;; Without this file the area group is merely undefined: Customize
;; records the membership and shows nothing, and the module works as
;; before.  Groups carry no values, so moving an option between groups
;; never touches a saved setting.
;;
;; THE TREE, in order of importance rather than of the alphabet:
;;
;;   MyPKS
;;   1. Notes and silos        notes folder and silos first, then tasks
;;                             and habits, then each notes module
;;   2. Writing                capture, export, writing projects, pages
;;   3. Interface and appearance
;;   4. Tools                  git, Hugo sites
;;
;; An area holds sub-areas, so a new module joins the branch it belongs
;; to -- a group of its own with `:group' naming that branch -- without
;; renaming anything above it.  Customize sorts the members of a group
;; alphabetically by symbol name by default
;; (`custom-buffer-sort-alphabetically'), which would put Git before
;; Notes; inside this tree the order of definition is kept instead, see
;; `my/settings--keep-order'.  Everywhere else Customize behaves as set.

(defgroup mypks nil
  "Settings of the MyPKS Emacs configuration: notes, writing, sites."
  :tag "MyPKS"
  :group 'emacs)

(defgroup mypks-notes nil
  "Notes and silos: the notes folder, silos, tasks, search, review, imports."
  :tag "Notes and silos"
  :group 'mypks)

(defgroup mypks-silos nil
  "The notes folder and the silos in it: where notes are, and which collections."
  :tag "Notes folder and silos"
  :group 'mypks-notes)

(defgroup mypks-tasks nil
  "Tasks, the planner and habits."
  :tag "Tasks and habits"
  :group 'mypks-notes)

(defgroup mypks-writing nil
  "Writing: capture, export, writing projects, standard pages."
  :tag "Writing"
  :group 'mypks)

(defgroup mypks-interface nil
  "Interface: theme, fonts, appearance, session."
  :tag "Interface and appearance"
  :group 'mypks)

(defgroup mypks-tools nil
  "Tools: automatic git commits and Hugo sites."
  :tag "Tools"
  :group 'mypks)

(defgroup mypks-git nil
  "Automatic commits of the notes, planner and project repositories."
  :tag "Git"
  :group 'mypks-tools)

(defgroup mypks-publishing nil
  "Hugo sites built from notes and from repositories."
  :tag "Hugo sites"
  :group 'mypks-tools)

(defun my/settings--tree-groups ()
  "Return every group in the MyPKS tree, `mypks' included."
  (let ((todo (list 'mypks)) groups)
    (while todo
      (let ((group (pop todo)))
        (unless (memq group groups)
          (push group groups)
          (dolist (member (get group 'custom-group))
            (when (eq (nth 1 member) 'custom-group)
              (push (car member) todo))))))
    groups))

;; Declared special so that the `let' below binds the real option even
;; though cus-edit.el, which defines it, loads only with Customize.
(defvar custom-buffer-sort-alphabetically)

(defun my/settings--keep-order (fn &optional group &rest args)
  "Around `customize-group': keep the MyPKS tree in definition order.
FN is the original command, GROUP and ARGS its arguments.  For a group
of the tree, `custom-buffer-sort-alphabetically' is nil while the buffer
is built, and stays nil in that buffer, where Customize redraws a group
after a change.  Any other group is shown exactly as before."
  (let* ((symbol (if (stringp group) (intern-soft group) group))
         (ours (and symbol (memq symbol (my/settings--tree-groups)))))
    (if (not ours)
        (apply fn group args)
      ;; Loaded first, so that the binding below is not the one cus-edit
      ;; finds when its `defcustom' runs.
      (require 'cus-edit)
      ;; The DEFAULT value, not a `let': a subgroup is opened from a
      ;; Custom buffer of the tree, where the option is buffer-local, and
      ;; a `let' there would bind only that buffer's value while the new
      ;; buffer reads the global one.
      (cl-letf (((default-value 'custom-buffer-sort-alphabetically) nil))
        (prog1 (apply fn group args)
          (when (derived-mode-p 'Custom-mode)
            (setq-local custom-buffer-sort-alphabetically nil)))))))

(advice-add 'customize-group :around #'my/settings--keep-order)

(defun my/settings ()
  "Open the settings of this configuration in Customize.
Every option of every loaded module, arranged by area in order of
importance.  Values saved with \"Apply and Save\" go to `custom-file'."
  (interactive)
  (customize-group 'mypks))

;; ============================================================
;; DELETION: always asked, unless switched off on purpose
;; ============================================================
;; Every command that can delete a note asks through
;; `my/confirm-deletion-p'.  Asking is the default and stays the default
;; after a restart.  It can be switched off for the rest of the session
;; (`my/confirm-deletion-toggle-session', asked itself) or for good
;; (`my/confirm-deletion' set to `never' in Customize, an explicit
;; choice).  While it is off, the mode line says so in red: deleting
;; without being asked is a state that must not be forgotten.

(defcustom my/confirm-deletion 'ask
  "Whether commands that delete notes ask before deleting.
`ask', the default, asks every time.  `never' deletes without asking,
in every session until changed back here.  To stop the questions only
until Emacs restarts, use `my/confirm-deletion-toggle-session' instead."
  :type '(choice (const :tag "Ask before every deletion (default)" ask)
                 (const :tag "Never ask -- deletes immediately" never))
  :tag "Ask before deleting notes"
  :group 'mypks-notes)

(defvar my/confirm-deletion--session-off nil
  "Non-nil while deletion questions are off for this session only.")

(defun my/confirm-deletion-active-p ()
  "Non-nil when deletions are confirmed by a question."
  (and (not (eq my/confirm-deletion 'never))
       (not my/confirm-deletion--session-off)))

(defun my/confirm-deletion-p (prompt)
  "Ask PROMPT with `yes-or-no-p' unless deletion questions are off.
Returns non-nil when the deletion may go ahead.  When the question is
skipped, *Messages* records what was deleted unasked, so the trail
exists even when the user did not see a prompt."
  (if (my/confirm-deletion-active-p)
      (yes-or-no-p prompt)
    (message "Deleting without confirmation (switched off): %s"
             (string-trim-right prompt "[ ?]+"))
    t))

(defun my/confirm-deletion-toggle-session ()
  "Switch deletion questions off until Emacs restarts, or back on.
Switching off is itself asked: it is the one moment the user can still
change their mind before deletions stop being asked."
  (interactive)
  (cond
   (my/confirm-deletion--session-off
    (setq my/confirm-deletion--session-off nil)
    (force-mode-line-update t)
    (message "Deletion questions are ON again"))
   ((eq my/confirm-deletion 'never)
    (message "Deletion questions are off for good (`my/confirm-deletion'); change it in C-c n ,"))
   ((yes-or-no-p "Delete notes WITHOUT asking until Emacs restarts? ")
    (setq my/confirm-deletion--session-off t)
    (force-mode-line-update t)
    (message "Deletion questions are OFF until restart (M-x my/confirm-deletion-toggle-session to turn back on)"))))

(defvar my/confirm-deletion-mode-line
  '(:eval (unless (my/confirm-deletion-active-p)
            (concat (propertize "!DEL" 'face 'error
                                'help-echo "Deletions are not confirmed: see my/confirm-deletion")
                    " ")))
  "Mode-line warning shown while deletions are not confirmed.")
(put 'my/confirm-deletion-mode-line 'risky-local-variable t)

;; The front seam of the mode line belongs to 01-ui.el, which loads
;; after this file; the symbol is added once init is complete.
(add-hook 'after-init-hook
          (lambda ()
            (when (boundp 'my/mode-line-front-segments)
              (add-to-list 'my/mode-line-front-segments
                           'my/confirm-deletion-mode-line))))

;; ============================================================
;; CORE VARIABLES: Paths and directories
;; ============================================================

(require 'seq)
(require 'subr-x)

;; ONE ROOT, ONE REGISTRY
;; ----------------------
;; Every path under the notes is derived from `my-notes-dir', and every
;; silo is an entry of `my/silos'.  Changing the root moves the whole
;; tree in the configuration at once; renaming a silo's folder is one
;; field of one entry.  Modules ask for a silo by KEY (`my/silo-dir') or
;; by ROLE (`my/silo-dir-by-role'), never by spelling out a path.
;;
;; A key is the silo's stable name in the configuration, chosen once.
;; The folder, the Denote keyword its notes carry and its description
;; can all change without the key changing.  A role says what a silo is
;; FOR, so that a module written for "the journal" works with a silo the
;; user calls `diary':
;;   journal  daily notes (05-notes.el, journal metrics, gaps)
;;   notes    default silo of new notes (the knowledge base)
;;   docs     documentation, monospaced (03b-fonts.el, 10-visual-fill.el)
;;
;; Both options are read when modules load: a change takes effect at the
;; next start of Emacs, and says so when made from Customize.

(defun my/notes--set-needs-restart (symbol value)
  "Customize setter for options that modules read at load time.
Sets SYMBOL to VALUE; when Emacs is already running, says that the
change takes effect after a restart rather than pretending otherwise."
  (set-default-toplevel-value symbol value)
  ;; Not while a file loads: `defcustom' calls this setter itself when
  ;; the module is loaded, and that is no change at all.
  (when (and after-init-time (not load-file-name))
    (message "%s changed: takes effect after restarting Emacs" symbol)))

(defcustom my-notes-dir (expand-file-name "~/notes/")
  "Root of the notes: the folder holding every silo.
Everything under it -- silos with relative directories, planner,
captures, exports, backups -- is derived from this value."
  :type 'directory
  :set #'my/notes--set-needs-restart
  :tag "Notes folder"
  :group 'mypks-silos)

(defcustom my/silos
  '((journal :directory "journal/" :role journal :keyword "journal"
             :private t
             :description "Private daily entries.")
    (pks     :directory "pks/"     :role notes   :keyword nil
             :private nil
             :description "Personal knowledge system: regular notes.")
    (docu    :directory "docu/"    :role docs    :keyword "docu"
             :private nil
             :description "Documentation and technical notes."))
  "The silos: folders of Denote notes, each a separate collection.
In Denote terms a silo is a directory used as `denote-directory' for
its own notes, so that notes, identifiers and keywords of one silo do
not mix with another's.

Each entry is (KEY . PROPERTIES):
  KEY           stable name used by the configuration; never changes
  :directory    folder, relative to `my-notes-dir' or absolute
  :role         journal, notes, docs or nil; see the Commentary
  :keyword      Denote keyword every note of the silo carries, or nil
  :private      non-nil: never published to a site with a server
  :disabled     non-nil: switched off -- see below
  :description  free text, shown here

A disabled silo keeps its entry and its files.  It disappears from
every list of silos, from new-note prompts and from Denote's own
searches and link prompts (`denote-excluded-directories-regexp'), until
:disabled is cleared again.  Deleting an entry instead also leaves the
files alone, but then the folder is just a folder under the root that
Denote still sees; a start-up check reports such folders.

Order matters where a list of silos is shown or scanned."
  :type '(alist :key-type (symbol :tag "Key")
                :value-type
                (plist :tag "Properties"
                       :options
                       ((:directory (string :tag "Directory"))
                        (:role (choice (const :tag "None" nil)
                                       (const journal) (const notes)
                                       (const docs)))
                        (:keyword (choice (const :tag "None" nil) string))
                        (:private boolean)
                        (:disabled boolean)
                        (:description string))))
  :set #'my/notes--set-needs-restart
  :tag "Silos"
  :group 'mypks-silos)

(defun my/notes-path (relative)
  "Return RELATIVE expanded under `my-notes-dir'."
  (expand-file-name relative my-notes-dir))

(defun my/silo-get (key property)
  "Return PROPERTY of the silo KEY in `my/silos', or nil."
  (plist-get (cdr (assq key my/silos)) property))

(defun my/silo-dir (key)
  "Return the absolute directory of the silo KEY, or nil if there is none."
  (when-let* ((dir (my/silo-get key :directory)))
    (file-name-as-directory (expand-file-name dir my-notes-dir))))

(defun my/silo-enabled-p (key)
  "Non-nil when the silo KEY exists and is not disabled."
  (and (assq key my/silos) (not (my/silo-get key :disabled))))

(defun my/silo-keys (&optional predicate include-disabled)
  "Return the keys of the enabled silos, in `my/silos' order.
With PREDICATE, only those for which (PREDICATE KEY) is non-nil.  With
INCLUDE-DISABLED, disabled silos are listed too."
  (seq-filter (lambda (key)
                (and (or include-disabled (my/silo-enabled-p key))
                     (or (null predicate) (funcall predicate key))))
              (mapcar #'car my/silos)))

(defun my/silo-dirs (&optional predicate include-disabled)
  "Return the directories of the silos, filtered like `my/silo-keys'."
  (mapcar #'my/silo-dir (my/silo-keys predicate include-disabled)))

(defun my/silo-folder-name (key)
  "Return the folder of silo KEY relative to `my-notes-dir', without a slash.
Nil for a silo outside the root."
  (let ((dir (my/silo-dir key))
        (root (file-name-as-directory (expand-file-name my-notes-dir))))
    (when (and dir (string-prefix-p root dir) (not (equal dir root)))
      (directory-file-name (substring dir (length root))))))

(defun my/silo-by-role (role)
  "Return the key of the first enabled silo whose role is ROLE, or nil."
  (seq-find (lambda (key) (eq (my/silo-get key :role) role))
            (my/silo-keys)))

(defun my/silo-dir-by-role (role)
  "Return the directory of the silo with ROLE.
Without one, fall back to a folder named after the role under the
root, which is not created, and note it in *Messages*.  A configuration
without, say, a documentation silo is valid: modules that look for one
simply find no notes there.  A pop-up warning on every start would
call it an error."
  (or (when-let* ((key (my/silo-by-role role))) (my/silo-dir key))
      (let ((fallback (file-name-as-directory
                       (my/notes-path (format "%s/" role)))))
        (message "MyPKS: no silo has the role `%s'; modules asking for it use %s"
                 role fallback)
        fallback)))

(defun my/silo-of (file &optional include-disabled)
  "Return the key of the enabled silo FILE is in, or nil.
With INCLUDE-DISABLED, a disabled silo counts too -- for a caller that
must tell \"in a disabled silo\" from \"in no silo\"."
  (let ((path (expand-file-name file)))
    (seq-find (lambda (key) (string-prefix-p (my/silo-dir key) path))
              (my/silo-keys nil include-disabled))))

;; DENOTE'S EXCLUDED DIRECTORIES, SHARED
;; -------------------------------------
;; `denote-excluded-directories-regexp' is one variable, and more than
;; one module needs a folder hidden from Denote: the inbox and its
;; rejects (25-inbox-review.el), disabled silos (here).  A module that
;; set the variable outright would erase what another had set, so each
;; adds a folder with `my/denote-exclude-directory' and the regexp is
;; rebuilt from the whole list.  Folders are relative to `my-notes-dir'
;; (= `denote-directory'); each matches as a whole path component, so
;; excluding pks does not exclude pks-old.

(defvar denote-excluded-directories-regexp)

(defvar my/denote-excluded-directories nil
  "Folders under `my-notes-dir' hidden from Denote, relative, no slash.
Add with `my/denote-exclude-directory'; the regexp follows.")

(defun my/denote--update-excluded-regexp ()
  "Set `denote-excluded-directories-regexp' from the excluded folders.
Each folder matches as a whole path component wherever Denote's version
applies the regexp: to a path relative to `denote-directory', as now,
or to a longer one."
  (setq denote-excluded-directories-regexp
        (when my/denote-excluded-directories
          (concat "\\(?:\\`\\|/\\)"
                  (regexp-opt my/denote-excluded-directories)
                  "\\(?:/\\|\\'\\)"))))

(defun my/denote-exclude-directory (relative)
  "Hide folder RELATIVE (to `my-notes-dir') from Denote's file operations."
  (let ((name (directory-file-name relative)))
    (unless (member name my/denote-excluded-directories)
      (push name my/denote-excluded-directories)
      (my/denote--update-excluded-regexp))))

;; Disabled silos inside the root are hidden from Denote.
(dolist (key (my/silo-keys (lambda (k) (not (my/silo-enabled-p k))) t))
  (when-let* ((name (my/silo-folder-name key)))
    (my/denote-exclude-directory name)))

;; FOLDERS WITH NOTES THAT ARE NOT SILOS
;; -------------------------------------
;; A silo whose entry was deleted rather than disabled is still a folder
;; of notes under the root, and Denote, rooted there, still shows them.
;; Reported once after start-up, so the user can add the entry back
;; (disabled, if that was the intent).  Only top-level folders, only
;; files named the Denote way and ending in .org or .md: attachments
;; carry Denote-like names too, and a deep scan of the whole tree at
;; every start would be slow.

(defconst my/silo--denote-note-regexp
  "\\`[0-9]\\{8\\}T[0-9]\\{6\\}.*\\.\\(?:org\\|md\\)\\'"
  "File names counted as Denote notes by the orphan check.")

(defun my/silo-orphans ()
  "Return top-level folders under `my-notes-dir' holding notes but no silo.
Folders in `my/silos' (disabled ones included), folders hidden from
Denote and dot folders are not reported."
  (let* ((root (file-name-as-directory (expand-file-name my-notes-dir)))
         (known (append (delq nil (mapcar #'my/silo-folder-name
                                          (my/silo-keys nil t)))
                        my/denote-excluded-directories)))
    (when (file-directory-p root)
      (seq-filter
       (lambda (name)
         (and (not (string-prefix-p "." name))
              (not (member name known))
              (file-directory-p (expand-file-name name root))
              (directory-files (expand-file-name name root) nil
                               my/silo--denote-note-regexp t 1)))
       (directory-files root nil directory-files-no-dot-files-regexp t)))))

(defun my/silo-report-orphans ()
  "Say which folders under the root hold notes but are not in `my/silos'."
  (interactive)
  (let ((orphans (my/silo-orphans)))
    (cond
     (orphans
      (message "MyPKS: folders with notes not in my/silos: %s (C-c n , to add them, disabled if unwanted)"
               (string-join orphans ", ")))
     ((called-interactively-p 'interactive)
      (message "MyPKS: every folder with notes is a silo")))))

;; Idle rather than at load: it reads the disk, and the result is a
;; message, which start-up messages would push out of sight.
(add-hook 'emacs-startup-hook
          (lambda () (run-with-idle-timer 3 nil #'my/silo-report-orphans)))

;; MOVING THE NOTES TO A NEW ROOT
;; ------------------------------
;; The root that was used last is kept in `my/notes-root-state-file'.
;; When `my-notes-dir' differs from it at start-up -- changed in
;; Customize, or by hand in the custom file -- the user is asked, before
;; anything is created at the new root:
;;
;;   Copy        copy the old root to the new one (cp -a, a reflink on
;;               btrfs), compare file count and total size, and only then
;;               switch.  The old root is never touched.
;;   Skip        switch without copying: "I will move my files myself".
;;   Ask later   keep using the old root for this session.
;;
;; No question when the new root already holds the notes and the old
;; one does not (a second machine, files moved by hand) -- the switch is
;; simply made -- or when the old root no longer exists.  When BOTH hold
;; notes (switching back after a test copy) the two may have diverged,
;; so the switch is asked, and nothing is copied either way.
;; A new root that is not empty with something else, or that lies
;; inside the old one or around it, is refused.  Without a terminal or
;; frame to ask in (batch, daemon start) the old root is kept for the
;; session and the question waits for the next start.
;;
;; Deleting the old root is a separate command, `my/notes-delete-old-root',
;; and does nothing until `my/notes-allow-delete-old-root' is turned on.

(defcustom my/notes-allow-delete-old-root nil
  "Non-nil enables `my/notes-delete-old-root'.  Off by default, on purpose.
The command moves the PREVIOUS notes root to the trash after a copy.
Until this is turned on it only says that it is disabled."
  :type 'boolean
  :tag "Allow deleting the old notes folder"
  :group 'mypks-silos)

(defconst my/notes-root-state-file (locate-user-emacs-file "notes-root.eld")
  "Where the notes root used last, and the one before it, are kept.
Machine state, not configuration: kept out of git.")

(defconst my/notes-move-buffer "*MyPKS notes move*"
  "Buffer holding the report of the last move of the notes root.")

(defun my/notes--read-root-state ()
  "Return the plist in `my/notes-root-state-file', or nil."
  (when (file-readable-p my/notes-root-state-file)
    (ignore-errors
      (with-temp-buffer
        (insert-file-contents my/notes-root-state-file)
        (read (current-buffer))))))

(defun my/notes--write-root-state (root &optional previous)
  "Record ROOT as the notes root in use, and PREVIOUS as the one before."
  (with-temp-file my/notes-root-state-file
    (insert ";; Written by 00-core.el: the notes root used last.\n")
    (prin1 (list :root root :previous previous) (current-buffer))
    (insert "\n")))

(defun my/notes--same-dir-p (a b)
  "Non-nil when directory names A and B name the same directory."
  (equal (file-name-as-directory (expand-file-name a))
         (file-name-as-directory (expand-file-name b))))

(defun my/notes--tree-stats (dir)
  "Return (FILES . BYTES) for every non-directory entry under DIR.
Dot files and .git included; symbolic links count as files of size 0,
so the comparison does not depend on what they point to."
  (let ((files 0) (bytes 0))
    (dolist (file (directory-files-recursively dir "" nil nil nil))
      (let ((attrs (file-attributes file)))
        (setq files (1+ files))
        (unless (stringp (file-attribute-type attrs))
          (setq bytes (+ bytes (or (file-attribute-size attrs) 0))))))
    (cons files bytes)))

(defun my/notes--holds-notes-p (dir)
  "Non-nil when DIR contains a silo folder of `my/silos' with notes in it."
  (seq-some (lambda (key)
              (let ((rel (my/silo-get key :directory)))
                (and rel (not (file-name-absolute-p rel))
                     (let ((silo (expand-file-name rel dir)))
                       (and (file-directory-p silo)
                            (directory-files silo nil
                                             my/silo--denote-note-regexp t 1))))))
            (my/silo-keys nil t)))

(defun my/notes--empty-dir-p (dir)
  "Non-nil when DIR does not exist or has no entries."
  (or (not (file-exists-p dir))
      (null (directory-files dir nil directory-files-no-dot-files-regexp t 1))))

(defun my/notes--copy-tree (old new)
  "Copy the contents of OLD into NEW.  Return nil on success, else a message.
cp -a keeps modes, times and links; --reflink=auto makes it a
copy-on-write clone where the file system allows (btrfs), nearly
instant and taking no space until a file changes."
  (make-directory new t)
  (if (executable-find "cp")
      (with-temp-buffer
        (let ((status (call-process "cp" nil t nil "-a" "--reflink=auto"
                                    (concat (file-name-as-directory old) ".")
                                    (file-name-as-directory new))))
          (unless (eq status 0)
            (format "cp failed (%s): %s" status (string-trim (buffer-string))))))
    (condition-case err
        (progn (copy-directory old new t t t) nil)
      (error (error-message-string err)))))

(defun my/notes--custom-file-references (old)
  "Return lines of `custom-file' that mention the root OLD."
  (when (and custom-file (file-readable-p custom-file))
    (let ((forms (delete-dups (list (directory-file-name (expand-file-name old))
                                    (directory-file-name (abbreviate-file-name
                                                          (expand-file-name old))))))
          lines)
      (with-temp-buffer
        (insert-file-contents custom-file)
        (dolist (line (split-string (buffer-string) "\n"))
          (when (seq-some (lambda (f) (string-search f line)) forms)
            (push (string-trim line) lines))))
      (nreverse lines))))

(defun my/notes--move-report (lines)
  "Put LINES into `my/notes-move-buffer' and show it after start-up."
  (with-current-buffer (get-buffer-create my/notes-move-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (string-join lines "\n") "\n"))
    (special-mode))
  (add-hook 'emacs-startup-hook
            (lambda () (display-buffer my/notes-move-buffer))))

(defun my/notes--ask-move (old new)
  "Ask what to do about the root change from OLD to NEW.  Return ?c, ?s or ?l."
  (car (read-multiple-choice
        (format "Notes root changed: %s -> %s" (abbreviate-file-name old)
                (abbreviate-file-name new))
        '((?c "copy" "Copy the notes to the new root, verify, switch; the old root is kept")
          (?s "skip, I will move my files myself" "Switch to the new root without copying")
          (?l "ask me next time" "Keep the old root for this session")))))

(defun my/notes-check-root-move ()
  "Handle a change of `my-notes-dir' since the last start.  See above.
Runs at load time of 00-core.el, before any path under the root is
derived or created.  May set `my-notes-dir' back to the old root for
this session; never changes the saved option."
  (let* ((state (my/notes--read-root-state))
         (old (plist-get state :root))
         (new (file-name-as-directory (expand-file-name my-notes-dir))))
    (cond
     ;; First start with this mechanism, or nothing changed.
     ((or (null old) (my/notes--same-dir-p old new))
      (unless (equal old new)
        (my/notes--write-root-state new (plist-get state :previous))))
     ;; The old root is gone: nothing to copy.
     ((not (file-directory-p old))
      (my/notes--write-root-state new old)
      (message "MyPKS: notes root is now %s (the old %s no longer exists)" new old))
     ;; The new root already holds the notes, and the old one does not
     ;; (any more): a second machine, or files moved by hand.  Switch.
     ((and (my/notes--holds-notes-p new) (not (my/notes--holds-notes-p old)))
      (my/notes--write-root-state new old)
      (message "MyPKS: notes root is now %s (the notes are already there; nothing copied)" new))
     ;; Both hold notes -- typically switching back after a test copy.
     ;; The two may have diverged, so nothing happens without a yes.
     ((my/notes--holds-notes-p new)
      (if (and (not noninteractive) (not (daemonp))
               (eq (car (read-multiple-choice
                         (format "Both %s and %s hold notes, possibly different ones."
                                 (abbreviate-file-name old) (abbreviate-file-name new))
                         '((?s "switch" "Use the new root as it is; nothing is copied either way")
                           (?l "ask me next time" "Keep the old root for this session"))))
                   ?s))
          (progn (my/notes--write-root-state new old)
                 (message "MyPKS: notes root is now %s; %s left as it is" new old))
        (setq my-notes-dir old)
        (message "MyPKS: still using %s this session" old)))
     ;; Nested roots: refuse, keep the old one.
     ((or (file-in-directory-p new old) (file-in-directory-p old new))
      (setq my-notes-dir old)
      (my/notes--move-report
       (list (format "Not moved: %s and %s are inside one another." old new)
             "Still using the old root for this session.  Choose another root in C-c n ,")))
     ;; Something else is already there: refuse.
     ((not (my/notes--empty-dir-p new))
      (setq my-notes-dir old)
      (my/notes--move-report
       (list (format "Not moved: %s is not empty and holds no silos." new)
             "Still using the old root for this session.  Empty it, or choose another root.")))
     ;; Nobody to ask: keep the old root, ask next time.
     ((or noninteractive (daemonp))
      (setq my-notes-dir old)
      (message "MyPKS: notes root change to %s postponed: no frame to ask in" new))
     (t
      (pcase (my/notes--ask-move old new)
        (?l (setq my-notes-dir old)
            (message "MyPKS: still using %s this session; asking again next time" old))
        (?s (my/notes--write-root-state new old)
            (my/notes--move-report
             (append
              (list (format "Switched to %s without copying." new)
                    (format "Move your files from %s yourself; the silo folders will be created empty now." old))
              (when-let* ((refs (my/notes--custom-file-references old)))
                (cons "\nSaved settings still pointing at the old root (change them in C-c n ,):"
                      refs)))))
        (?c (message "MyPKS: copying %s to %s..." old new)
            (let* ((failure (my/notes--copy-tree old new))
                   (before (and (not failure) (my/notes--tree-stats old)))
                   (after (and (not failure) (my/notes--tree-stats new))))
              (if (or failure (not (equal before after)))
                  (progn
                    (setq my-notes-dir old)
                    (my/notes--move-report
                     (list "Copy FAILED or incomplete; still using the old root."
                           (or failure
                               (format "Old: %d files, %d bytes.  New: %d files, %d bytes."
                                       (car before) (cdr before) (car after) (cdr after)))
                           (format "Nothing was removed.  The partial copy is in %s." new))))
                (my/notes--write-root-state new old)
                (my/notes--move-report
                 (append
                  (list (format "Copied %s to %s: %d files, %d bytes, identical counts."
                                old new (car after) (cdr after))
                        (format "Now using %s.  The old root is untouched." new))
                  (when-let* ((refs (my/notes--custom-file-references old)))
                    (cons "\nSaved settings still pointing at the old root (change them in C-c n ,):"
                          refs))
                  (list "\nAlso check: Hugo sites (re-export), desktop session and recent files,"
                        "bookmarks, Syncthing folders, and anything outside Emacs using the old path.")))
                (when (and (file-directory-p (expand-file-name ".git" new))
                           (eq (car (read-multiple-choice
                                     "The copy has its own git history with the same remote."
                                     '((?k "keep pushing" "Automatic commits keep pushing from the new root")
                                       (?o "turn push off" "Save my/auto-commit-push = nil (07-git.el)"))))
                               ?o))
                  (customize-save-variable 'my/auto-commit-push nil)
                  (message "MyPKS: automatic push turned off (my/auto-commit-push)"))))))))))

(defun my/notes-delete-old-root ()
  "Move the PREVIOUS notes root to the trash, after a move to a new root.
Disabled until `my/notes-allow-delete-old-root' is turned on, and then
asked twice whatever `my/confirm-deletion' says: it removes every note."
  (interactive)
  (let* ((state (my/notes--read-root-state))
         (previous (plist-get state :previous)))
    (cond
     ((not my/notes-allow-delete-old-root)
      (message "Disabled.  Turn on `my/notes-allow-delete-old-root' in C-c n , to use it"))
     ((or (null previous) (not (file-directory-p previous)))
      (message "No previous notes root to delete"))
     ((my/notes--same-dir-p previous my-notes-dir)
      (message "The previous root is the current one; refusing"))
     ((and (yes-or-no-p (format "Move the OLD notes root %s to the trash? " previous))
           (yes-or-no-p (format "Every note under %s goes to the trash.  Really? " previous)))
      (let ((delete-by-moving-to-trash t))
        (delete-directory previous t t))
      (my/notes--write-root-state (plist-get state :root) nil)
      (message "Moved %s to the trash" previous)))))

;; Must run before anything below derives a path from the root.
(my/notes-check-root-move)

;; The variables every module has used so far, now derived.  Kept so
;; that modules work unchanged while they move to the functions above;
;; they follow the ROLE, not the key.
(defvar my-notes-journal (my/silo-dir-by-role 'journal)
  "Directory of the journal silo (role `journal' in `my/silos').")

(defvar my-notes-pks (my/silo-dir-by-role 'notes)
  "Directory of the default notes silo (role `notes' in `my/silos').")

(defvar my-notes-docu (my/silo-dir-by-role 'docs)
  "Directory of the documentation silo (role `docs' in `my/silos').")

;; Capture file
(defvar my-journal-captures (expand-file-name "captures.org" my-notes-journal)
  "Ideas capture file - thoughts and ideas worth developing later.
Use C-c n c i to add entries, C-c n c m to promote to full Denote note.")

;; JOURNAL METRICS: names shared by 05-notes.el and 05b-journal-metrics.el.
;; They live here so that the journal template does not depend on the
;; optional metrics module: 05b-journal-metrics.el can be deleted and the
;; journal generator still works.
(defvar my-journal-metrics-heading "Metryki"
  "Name of the schema 1 metrics headline.
No longer written: metrics are front-matter keywords as of schema 2.
The name is kept so that 05b-journal-metrics.el and 21-dashboards.el can
still recognise and convert the files that briefly used it.")

(defvar my-journal-schema-version 2
  "Value written as #+schema: into new notes.
  0  no keyword: pre-2026-08 journal, :well-being: in a drawer below the
     front matter, which Org never parsed as properties at all.
  1  metrics in a property drawer under a `my-journal-metrics-heading\='
     headline.  Short-lived; a second drawer in a file that already had
     one under * Uzupełnienie, which proved ambiguous in practice.
  2  metrics as front-matter keywords.  Current.
All three are readable; only 2 is written.")

;; Agenda scans every silo + captures file
(defvar my-tasks-agenda-dirs
  (append (my/silo-dirs) (list my-journal-captures))
  "All locations org-agenda should scan for TODO items.")

;; Backup directories
(defvar my-notes-backups (my/notes-path ".backups/")
  "Backup directory for note files.")

(defvar my-notes-autosaves (my/notes-path ".autosaves/")
  "Autosave directory for note files.")

;; Emacs configuration directories
(defvar my-emacs-backups (expand-file-name "~/.emacs.d/backups/")
  "Backup directory for other files.")

(defvar my-emacs-autosaves (expand-file-name "~/.emacs.d/autosaves/")
  "Autosave directory for other files.")

;; TEXT WRAPPING: Fill column for normal notes
(defvar my-fill-column 95
  "Default text wrapping column for notes.
Notes tagged `:docu:' use `my/fill-column-docu' (10-visual-fill.el).

The unit is CHARACTERS of the buffer's default face, not pixels.  A
silo whose body font is proportional (see `my/font-silo-styles' in
03b-fonts.el) renders the same number narrower than a monospaced one,
so pks and docu at the same value do not produce the same column.
Raised from 80 for that reason.")

;; DENOTE KEYWORDS: Base list (Denote will add more automatically)
(defvar my-denote-keywords
  '("journal" "docu" "wellbeing" "esej" "philosophy"
    "zettel" "osoba" "projekt" "lektura" "filozof"
    "skroty")
  "Base keyword list for Denote.
With denote-infer-keywords enabled, Denote will automatically
add any new keywords found in existing notes.")

;; Create all directories if they don't exist.  A function rather than
;; top-level code so that a step which must run before anything is
;; created -- moving the notes to a new root -- can run first.
(defun my/notes-ensure-directories ()
  "Create the notes root, every silo and the backup directories if missing."
  (dolist (dir (append (list my-notes-dir)
                       (my/silo-dirs)
                       (list my-notes-backups
                             my-notes-autosaves
                             my-emacs-backups
                             my-emacs-autosaves)))
    (unless (file-exists-p dir)
      (make-directory dir t))))

(my/notes-ensure-directories)

;; ============================================================
;; FILE HANDLING: Backups and autosaves
;; ============================================================

;; Separate backups by location (notes vs other files)
(setq backup-directory-alist
      `((,my-notes-dir . ,my-notes-backups)
        (".*" . ,my-emacs-backups)))

;; Separate autosaves by location
(setq auto-save-file-name-transforms
      `((,(concat my-notes-dir ".*") ,my-notes-autosaves t)
        (".*" ,my-emacs-autosaves t)))

;; Backup settings (keep more versions for safety)
(setq version-control t)
(setq kept-new-versions 10)
(setq kept-old-versions 5)
(setq delete-old-versions t)
(setq create-lockfiles nil)  ; Don't create .# lock files

;; ============================================================
;; BASIC EMACS SETTINGS
;; ============================================================

;; UTF-8 everywhere
(prefer-coding-system 'utf-8)
(set-default-coding-systems 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)

;; Better defaults
(setq-default indent-tabs-mode nil)  ; Use spaces, not tabs
(setq-default tab-width 4)
(setq require-final-newline t)       ; Always end files with newline

;; ============================================================
;; RECENTF: Remember recent files
;; ============================================================

(use-package recentf
  :ensure nil
  :init
  (recentf-mode 1)
  :config
  (setq recentf-max-saved-items 100)
  (setq recentf-auto-cleanup 'never)
  (setq recentf-exclude '("\\.git/"
                          "COMMIT_EDITMSG"
                          "\\.elc$"
                          "/elpa/"
                          "^/tmp/"
                          "^#.*#$"
                          "^\\.#")))

;; ============================================================
;; LOAD PREFER NEWER: Always load newest files
;; ============================================================

(setq load-prefer-newer t)

;; ============================================================
;; UI STATE: settings that must outlive a restart
;; ============================================================
;; A plist in one small file.  Used for choices made interactively --
;; the active theme, the base font size, the default text width --
;; which belong to the session rather than to the configuration.
;;
;; NOT `custom-set-variables', which would write custom.el.  That file
;; was emptied on purpose (see the note at its top) and reintroducing
;; machine-written settings there is how the theme became unfixable
;; the first time.  NOT the desktop either: this has to work when no
;; session is restored.
;;
;; Read once at startup, written on every change.  The file is tiny
;; and the writes are rare, so no batching is worth the complexity.

(defconst my/ui-state-file (locate-user-emacs-file "ui-state.el")
  "File holding interactively chosen UI settings.
Safe to delete: every reader falls back to a compiled-in default.")

(defvar my/ui-state nil
  "Plist of persisted UI settings.  See `my/ui-state-file'.")

(defun my/ui-state-load ()
  "Read `my/ui-state-file' into `my/ui-state'.
Returns nil and leaves the state empty when the file is missing,
empty or corrupt.  A UI preference is never worth aborting init for."
  (setq my/ui-state
        (when (file-readable-p my/ui-state-file)
          (with-temp-buffer
            (insert-file-contents my/ui-state-file)
            (let ((data (ignore-errors (read (current-buffer)))))
              (and (listp data) data))))))

(my/ui-state-load)

(defun my/ui-state-get (key &optional default)
  "Return the stored value for KEY, or DEFAULT when there is none."
  (if (plist-member my/ui-state key)
      (plist-get my/ui-state key)
    default))

(defun my/ui-state-set (key value)
  "Store VALUE under KEY and write the state file."
  (setq my/ui-state (plist-put my/ui-state key value))
  (with-temp-file my/ui-state-file
    (insert ";; Written by Emacs.  Interactively chosen UI settings.\n")
    (prin1 my/ui-state (current-buffer))
    (insert "\n"))
  value)

;; ============================================================
;; NOTE KEYWORDS: reading and writing #+key: value front matter
;; ============================================================
;; Denote front matter is a run of `#+keyword:' lines at the top of the
;; file, and this configuration already uses it to carry per-note facts
;; (`#+schema:', `#+project:', `#+wellbeing:').  Per-note appearance
;; settings use the same channel, so a note that should be read wide or
;; large says so in the note itself and travels with it through
;; Syncthing, git and any other editor.
;;
;; Deliberately a regexp scan of the first few kilobytes rather than
;; `org-collect-keywords': these run from `org-mode-hook', before Org
;; has finished setting the buffer up, and must not depend on Org
;; internals being ready.  10-visual-fill.el already scans for
;; `#+filetags:' the same way.

(defconst my/note-front-matter-limit 4096
  "How far into a file to look for `#+keyword:' lines, in characters.")

(defun my/note-keyword (name)
  "Return the value of the file keyword NAME, or nil.
NAME is given without the `#+' and the colon, e.g. \"text_width\".
An empty value counts as absent."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^#\\+%s:[ \t]*\\(.*\\)$" (regexp-quote name))
           (min (point-max) my/note-front-matter-limit) t)
      (let ((value (string-trim (match-string-no-properties 1))))
        (unless (string-empty-p value) value)))))

(defun my/note-keyword-number (name)
  "Return the value of file keyword NAME as a number, or nil.
Returns nil rather than signalling when the value is not a number, so
a typo in a note degrades to the default instead of breaking the
buffer."
  (when-let* ((value (my/note-keyword name)))
    (let ((n (string-to-number value)))
      ;; `string-to-number' returns 0 for junk, so an explicit 0 has to
      ;; be told apart from a failed parse.
      (if (and (= n 0) (not (string-match-p "\\`[+-]?0*\\(\\.0*\\)?\\'" value)))
          nil
        n))))

(defun my/note-keyword-set (name value)
  "Set file keyword NAME to VALUE in the current buffer.
Replaces an existing line, or inserts one after the last front-matter
keyword.  Does not save the buffer."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward (format "^#\\+%s:.*$" (regexp-quote name))
                           (min (point-max) my/note-front-matter-limit) t)
        (replace-match (format "#+%s: %s" name value) t t)
      ;; No such line yet: walk the opening run of `#+keyword:' lines
      ;; and insert after it, so the new key joins the front matter
      ;; rather than landing in the prose.
      (goto-char (point-min))
      (let ((insert-at (point-min)))
        (while (looking-at "^#\\+[a-zA-Z_]+:")
          (forward-line 1)
          (setq insert-at (point)))
        (goto-char insert-at)
        (insert (format "#+%s: %s\n" name value))))))

(provide '00-core)
;;; 00-core.el ends here
