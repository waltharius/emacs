;;; 00-core.el --- Package system and core variables -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: no
;; Docs: ~/.emacs.d/function_helper.org::#settings

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

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ============================================================
;; THE SETTINGS FOLDER, AND THE SETTINGS OF THIS MACHINE
;; ============================================================
;; The settings live outside this repository, in a folder of their own,
;; so that the code holds nothing personal and can be public:
;;
;;   <settings folder>/hosts/<host>/custom.el    what Customize saves
;;   <settings folder>/hosts/<host>/ui-state.el  choices made with keys:
;;                                               theme, font size
;;
;; The settings folder is ~/.config/mypks/ by default -- the usual place
;; for a program's settings on Linux -- and is itself a setting,
;; `my/settings-folder' (C-c n , ,).  It cannot be stored in custom.el,
;; which lives inside it, so it is kept in `my/local-file' in this
;; repository's folder, a file of this installation and not in git.  Put
;; it inside the notes repository (~/notes/.mypks/) and the automatic
;; commits back the settings up with the notes; or make it a git
;; repository of its own, and 07-git.el commits it too.
;;
;; <host> is the machine's short host name, so after a reinstall the
;; same machine finds its settings again, and two machines never write
;; into each other's file.  A value wanted on both is saved on both.
;;
;; First match wins:
;;   settings folder  env MYPKS_DIR, `my/local-file' :directory, ~/.config/mypks/
;;   host             env MYPKS_HOST, `my/local-file' :host, the host name
;;
;; FIRST START WITH A FOLDER.  When this machine has no settings there
;; yet, they are copied, in this order of preference, from: the previous
;; settings folder (after a change of `my/settings-folder'); the folder
;; hosts/ in this repository (where they were in October 2026); the old
;; shared custom.el and ui-state.el here.  Otherwise, when other
;; machines have settings, the user chooses: copy one, or start with the
;; defaults.  Nothing is deleted anywhere.  The outcome is reported once
;; 00-core.el can show reports.
;;
;; Loaded here, at the top of the core, rather than in init.el: the
;; settings must be read before any option is defined below.

(defconst my/settings-default-folder "~/.config/mypks/"
  "Settings folder used when nothing else names one.")

(defconst my/local-file (locate-user-emacs-file "mypks-local.eld")
  "Choices of this installation that cannot live in the settings folder.
A plist: :directory (the settings folder), :previous (the one before a
change, until its settings are copied), :host (another machine's
settings to use).  Not in git.")

(defun my/local--read ()
  "Return the plist in `my/local-file', or nil."
  (when (file-readable-p my/local-file)
    (ignore-errors
      (with-temp-buffer
        (insert-file-contents my/local-file)
        (let ((data (read (current-buffer))))
          (and (listp data) data))))))

(defun my/local--put (key value)
  "Store VALUE under KEY in `my/local-file'; nil removes KEY."
  (let ((data (my/local--read)))
    (setq data (if value
                   (plist-put data key value)
                 (cl-loop for (k v) on data by #'cddr
                          unless (eq k key) append (list k v))))
    (with-temp-file my/local-file
      (insert ";; Written by 00-core.el: choices of this installation, not in git.\n")
      (prin1 data (current-buffer))
      (insert "\n"))))

(defun my/local--env (name)
  "Return the environment variable NAME, or nil when unset or empty."
  (let ((value (getenv name)))
    (and value (not (string-empty-p value)) value)))

(defconst my/settings-directory
  (file-name-as-directory
   (expand-file-name (or (my/local--env "MYPKS_DIR")
                         (plist-get (my/local--read) :directory)
                         my/settings-default-folder)))
  "The settings folder this Emacs uses.  See the commentary above.")

(defconst my/hosts-directory (expand-file-name "hosts/" my/settings-directory)
  "Folder holding one folder of settings per machine.")

(defun my/host--system-name ()
  "Return this machine's short host name, lower case."
  (downcase (car (split-string (system-name) "\\."))))

(defun my/host--read-choice ()
  "Return the host named in `my/local-file', or in the older file `host'."
  (or (plist-get (my/local--read) :host)
      (let ((old (locate-user-emacs-file "host")))
        (when (file-readable-p old)
          (with-temp-buffer
            (insert-file-contents old)
            (let ((name (string-trim (buffer-string))))
              (unless (string-empty-p name) name)))))))

(defconst my/host-name
  (or (my/local--env "MYPKS_HOST")
      (my/host--read-choice)
      (my/host--system-name))
  "Name of the folder in `my/hosts-directory' this Emacs uses.")

(defconst my/host-directory
  (file-name-as-directory (expand-file-name my/host-name my/hosts-directory))
  "This Emacs's settings: <settings folder>/hosts/<host>/.")

(defvar my/host--reports nil
  "Reports about the settings folder, shown once reports can be shown.
Each is (KIND TITLE LINES).")

(defconst my/host--custom-header
  ";;; custom.el --- Settings of this machine, saved by Customize -*- lexical-binding: t; -*-

;; Written by Customize (C-c n , ,).  One file per machine, in
;; <settings folder>/hosts/<host>/; see \"The settings folder\" in
;; function_helper.org.
"
  "Start of a new, empty settings file.")

(defun my/host--other-hosts ()
  "Return the names of other machines that have a settings file."
  (when (file-directory-p my/hosts-directory)
    (seq-filter (lambda (name)
                  (and (not (equal name my/host-name))
                       (file-readable-p
                        (expand-file-name "custom.el"
                                          (expand-file-name name my/hosts-directory)))))
                (directory-files my/hosts-directory nil
                                 directory-files-no-dot-files-regexp t))))

(defun my/host--copy-hosts-from (old-hosts)
  "Copy every machine's folder in OLD-HOSTS that the settings folder lacks."
  (make-directory my/hosts-directory t)
  (dolist (name (directory-files old-hosts nil directory-files-no-dot-files-regexp t))
    (let ((from (expand-file-name name old-hosts))
          (to (expand-file-name name my/hosts-directory)))
      (when (and (file-directory-p from) (not (file-exists-p to)))
        (copy-directory from to t t t)))))

(defun my/host--backup-note ()
  "Return report lines on how the settings folder is backed up."
  (if (locate-dominating-file my/settings-directory ".git")
      (list "It is inside a git repository, so it is committed with it.")
    (list "It is in no git repository: nothing backs it up yet.  Either set"
          "\"Folder of these settings\" (C-c n , ,) to a folder in the notes"
          "repository, e.g. ~/notes/.mypks/, or run git init in it -- then the"
          "automatic commits include it.")))

(defun my/host--prepare ()
  "Make sure this machine's settings exist in the settings folder.  See above."
  (let* ((custom (expand-file-name "custom.el" my/host-directory))
         (state (expand-file-name "ui-state.el" my/host-directory))
         (local (my/local--read))
         (previous (plist-get local :previous))
         (previous-hosts (and previous (expand-file-name "hosts/" previous)))
         (repo-hosts (locate-user-emacs-file "hosts/"))
         (legacy-custom (locate-user-emacs-file "custom.el"))
         (legacy-state (locate-user-emacs-file "ui-state.el"))
         (short (abbreviate-file-name my/settings-directory))
         (from nil))
    (unless (file-exists-p custom)
      (cond
       ;; After a change of the settings folder: bring the settings along.
       ((and previous-hosts (file-directory-p previous-hosts)
             (not (equal (file-name-as-directory (expand-file-name previous))
                         my/settings-directory)))
        (my/host--copy-hosts-from previous-hosts)
        (setq from (abbreviate-file-name previous-hosts)))
       ;; From hosts/ in this repository, where they were first.
       ((file-directory-p repo-hosts)
        (my/host--copy-hosts-from repo-hosts)
        (setq from (abbreviate-file-name repo-hosts)))))
    (make-directory my/host-directory t)
    (cond
     ((file-exists-p custom)
      (when from
        (push (list 'done (format "Settings now in %s" short)
                    (append
                     (list (format "Copied from %s, which is no longer read and stays as it is." from))
                     (when (equal from (abbreviate-file-name repo-hosts))
                       (list "In ~/.emacs.d: git rm -r hosts custom.el ui-state.el, then commit,"
                             "once every machine has started once."))
                     (list "")
                     (my/host--backup-note)))
              my/host--reports)))
     ;; The move from the shared files, once per machine.
     ((file-readable-p legacy-custom)
      (copy-file legacy-custom custom)
      (push (list 'done (format "Settings of %s now in %s" my/host-name short)
                  (append
                   (list (format "Copied from %s, which is no longer read."
                                 (abbreviate-file-name legacy-custom))
                         "Customize saves to the new place from now on."
                         "")
                   (my/host--backup-note)))
            my/host--reports))
     ;; A new machine, other machines known: ask.
     ((and (my/host--other-hosts) (not noninteractive))
      (let* ((others (my/host--other-hosts))
             (defaults "start with the defaults")
             (answer (completing-read
                      (format "No settings for this machine (%s) yet.  Copy from: "
                              my/host-name)
                      (append (mapcar (lambda (h) (concat "copy from " h)) others)
                              (list defaults))
                      nil t nil nil defaults)))
        (if (string-prefix-p "copy from " answer)
            (let ((other (substring answer (length "copy from "))))
              (copy-file (expand-file-name "custom.el"
                                           (expand-file-name other my/hosts-directory))
                         custom)
              (push (list 'done (format "Settings of %s copied to %s" other my/host-name)
                          (list (format "%s now starts from %s's settings; from here on"
                                        (abbreviate-file-name my/host-directory) other)
                                "each machine changes only its own file."))
                    my/host--reports))
          (with-temp-file custom (insert my/host--custom-header))
          (push (list 'done (format "%s starts with the default settings" my/host-name)
                      (list (format "Settings saved in C-c n , , go to %scustom.el."
                                    (abbreviate-file-name my/host-directory))))
                my/host--reports))))
     ;; A first machine, or no one to ask.
     (t
      (with-temp-file custom (insert my/host--custom-header))
      (push (list 'done (format "%s starts with the default settings" my/host-name)
                  (append
                   (list (format "Settings saved in C-c n , , go to %scustom.el."
                                 (abbreviate-file-name my/host-directory))
                         "")
                   (my/host--backup-note)))
            my/host--reports)))
    (when (and (not (file-exists-p state)) (file-readable-p legacy-state))
      (copy-file legacy-state state))
    (when previous
      (my/local--put :previous nil))
    (setq my/host--reports (nreverse my/host--reports))))

(defun my/host--load-settings ()
  "Prepare and load this machine's settings file; never stop start-up."
  (condition-case err
      (my/host--prepare)
    (error (push (list 'failed "Preparing this machine's settings failed"
                       (list (error-message-string err)
                             "Emacs starts with the defaults; nothing was removed."))
                 my/host--reports)))
  (setq custom-file (expand-file-name "custom.el" my/host-directory))
  (when (file-exists-p custom-file)
    (condition-case err
        (load custom-file nil t)
      (error (push (list 'failed (format "Reading %s failed" (abbreviate-file-name custom-file))
                         (list (error-message-string err)
                               "Settings saved there are not applied this session."
                               "M-x check-parens in that file finds an unbalanced parenthesis."))
                   my/host--reports)))))

(my/host--load-settings)

(defun my/host--show-reports ()
  "Show the reports collected while preparing this machine's settings."
  (dolist (report my/host--reports)
    (apply #'my/notes-report report))
  (setq my/host--reports nil))

;; Committed with the other repositories when the settings folder is a
;; repository of its own; inside the notes repository it is committed
;; with the notes, and 07-git.el skips a folder that is no repository.
(defun my/settings--repository-directories ()
  "Return the settings folder, for 07-git.el's automatic commits."
  (list my/settings-directory))

(with-eval-after-load '07-git
  (add-hook 'my/auto-commit-repository-sources
            #'my/settings--repository-directories t))

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

;; THE SETTINGS FOLDER AND THIS MACHINE'S FILE, FROM THE MENU (C-c n ,)

(defun my/settings--folder-set (symbol value)
  "Customize setter of `my/settings-folder': remember VALUE for the next start.
Stored in `my/local-file', with the folder now in use as :previous so
that the next start copies the settings over.  While a file loads
\(custom.el), nothing happens: the folder in use is decided before
custom.el is read, and the value there is only what was shown."
  (set-default-toplevel-value symbol value)
  (when (my/settings--live-p)
    (let ((new (file-name-as-directory (expand-file-name value))))
      (unless (equal new my/settings-directory)
        (my/local--put :directory (abbreviate-file-name new))
        (my/local--put :previous (abbreviate-file-name my/settings-directory))
        (my/notes-report
         'done (format "From the next start the settings are read from %s"
                       (abbreviate-file-name new))
         (append
          (list (format "At that start this machine's settings are copied there from %s,"
                        (abbreviate-file-name my/settings-directory))
                "which stays as it is.")
          (when (my/local--env "MYPKS_DIR")
            (list "" (format "But MYPKS_DIR=%s is set, and wins over this setting."
                             (getenv "MYPKS_DIR"))))))))))

(defcustom my/settings-folder my/settings-default-folder
  "Folder holding the settings of every machine: hosts/<host>/custom.el.
~/.config/mypks/ by default.  Inside the notes repository (for example
~/notes/.mypks/) the settings are committed and pushed with the notes.

Takes effect at the next start, which copies this machine's settings to
the new folder; the old folder is left as it is.  Kept outside
custom.el (in `my/local-file'), since custom.el lives in this folder.
The environment variable MYPKS_DIR overrides it."
  :type 'directory
  :tag "Folder of these settings"
  :get (lambda (_symbol) (abbreviate-file-name my/settings-directory))
  :set #'my/settings--folder-set
  :initialize #'custom-initialize-default
  :group 'mypks)

(defun my/host-settings-open ()
  "Open this machine's settings file."
  (interactive)
  (find-file custom-file))

(defun my/host--read-other (prompt)
  "Ask with PROMPT for another machine that has settings; return its name."
  (let ((others (my/host--other-hosts)))
    (unless others
      (user-error "No other machine has settings in %s"
                  (abbreviate-file-name my/hosts-directory)))
    (completing-read prompt others nil t)))

(defun my/host-settings-copy-from (host)
  "Copy the settings file of HOST over this machine's, and apply it.
This machine's file is replaced -- after a question.  Values HOST does
not set keep their current value until Emacs restarts."
  (interactive (list (my/host--read-other "Copy the settings of: ")))
  (let ((from (expand-file-name "custom.el" (expand-file-name host my/hosts-directory))))
    (when (yes-or-no-p (format "Replace this machine's settings (%s) with %s's? "
                               my/host-name host))
      (copy-file from custom-file t)
      (load custom-file nil t)
      (my/notes-report 'done (format "Settings of %s copied to %s" host my/host-name)
                       (list (format "%s now holds %s's settings, applied."
                                     (abbreviate-file-name custom-file) host)
                             "Values set before but not in that file are back to their"
                             "defaults after a restart.")))))

(defun my/host-settings-use (host)
  "Make this Emacs read and save HOST's settings, from the next start.
Kept in `my/local-file', not in git: the choice belongs to this
installation.  Choosing this machine's own name removes the choice.
The environment variable MYPKS_HOST overrides both."
  (interactive
   (list (completing-read "Use the settings of: "
                          (delete-dups (cons (my/host--system-name)
                                             (my/host--other-hosts)))
                          nil nil nil nil (my/host--system-name))))
  (my/local--put :host (unless (equal host (my/host--system-name)) host))
  (let ((old (locate-user-emacs-file "host")))
    (when (file-exists-p old) (delete-file old)))
  (my/notes-report 'done (format "From the next start this Emacs uses the settings of %s" host)
                   (list (format "Read from and saved to %s"
                                 (abbreviate-file-name
                                  (expand-file-name "custom.el"
                                                    (expand-file-name host my/hosts-directory)))))))

;; WHEN A CHANGE TAKES EFFECT
;; --------------------------
;; Most options are read when they are used, so a change made in
;; Customize works at once.  The ones a module reads only while it loads
;; -- a key binding, a timer, a capture template, a list derived from the
;; silos -- are given a setter that applies the new value immediately:
;;
;;   (defcustom my/x ... :set (my/settings-apply-on-set #'my/x--apply))
;;
;; The setter stores the value and, once Emacs is up, calls the module's
;; apply function.  While Emacs starts, `defcustom' itself calls the
;; setter; the module then applies its options once, at the end of its
;; own load, so nothing runs before the module is complete.
;;
;; Only the notes folder (`my-notes-dir') still needs a restart: changing
;; it means moving the notes, which is done at start-up, before anything
;; under the folder is opened.  Its setter says so.
;;
;; Options whose DEFAULT is computed from another option -- every list of
;; silo folders, the per-silo font styles -- are recomputed when that
;; other option changes, unless the user has set them explicitly; see
;; `my/settings-reevaluate-dependents'.

(defun my/settings--live-p ()
  "Non-nil when a setter runs for a change made in a running Emacs.
Not during init, and not while a file loads: `defcustom' calls the
setter itself when its module is loaded, and that is no change at all."
  (and after-init-time (not load-file-name)))

(defun my/settings-apply-on-set (function)
  "Return a Customize setter that stores the value and calls FUNCTION.
FUNCTION, of no arguments, runs only for a change in a running Emacs
\(`my/settings--live-p'), and only when it is defined: during start-up
the module applies its options itself."
  (lambda (symbol value)
    (set-default-toplevel-value symbol value)
    (when (and (my/settings--live-p) (fboundp function))
      (funcall function))))

(defun my/settings-set-needs-restart (symbol value)
  "Customize setter for an option that cannot change while Emacs runs.
Sets SYMBOL to VALUE; when Emacs is already running, says that the
change takes effect at the next start rather than pretending otherwise."
  (set-default-toplevel-value symbol value)
  (when (my/settings--live-p)
    (message "%s: saved; takes effect at the next start of Emacs"
             (or (get symbol 'custom-tag) symbol))))

;; Two things modules set from options at load, given one helper each so
;; that a change can undo the previous value: a global key, and a
;; capture template.

(defvar my/settings--bound-keys nil
  "Alist of (COMMAND . KEY) bound by `my/settings-bind-key'.")

(defun my/settings-bind-key (command key)
  "Bind KEY, a `kbd' string or nil, globally to COMMAND.
The key COMMAND received from an earlier call is released first, if it
still runs COMMAND; a key rebound to something else since is left as
it is."
  (let ((old (alist-get command my/settings--bound-keys)))
    (when (and old (eq (global-key-binding (kbd old)) command))
      (global-unset-key (kbd old))))
  (when key
    (global-set-key (kbd key) command))
  (setf (alist-get command my/settings--bound-keys) key))

(defvar org-capture-templates)

(defun my/settings-capture-template (template)
  "Add TEMPLATE to `org-capture-templates', now or once Org capture loads.
An existing template with the same target (its fourth element, such as
\\='(function my/x--target)) is removed first, so a changed key replaces
the template instead of adding a second one."
  (with-eval-after-load 'org-capture
    (setq org-capture-templates
          (seq-remove (lambda (entry)
                        (and (consp entry) (equal (nth 3 entry) (nth 3 template))))
                      org-capture-templates))
    (add-to-list 'org-capture-templates template t)))

(defun my/settings--tree-options ()
  "Return every option in the MyPKS tree."
  (let (options)
    (dolist (group (my/settings--tree-groups))
      (dolist (member (get group 'custom-group))
        (when (eq (nth 1 member) 'custom-variable)
          (push (car member) options))))
    (delete-dups options)))

(defun my/settings--form-mentions-p (form symbols)
  "Non-nil when FORM contains one of SYMBOLS anywhere."
  (cond ((symbolp form) (memq form symbols))
        ((consp form)
         (or (my/settings--form-mentions-p (car form) symbols)
             (my/settings--form-mentions-p (cdr form) symbols)))
        ((vectorp form)
         (seq-some (lambda (x) (my/settings--form-mentions-p x symbols)) form))))

(defun my/settings-reevaluate-dependents (symbols)
  "Recompute options whose default refers to one of SYMBOLS.
Only options of the MyPKS tree the user has not set (no saved and no
customized value): a value chosen by hand is never replaced.  The
option's own setter is used, so a dependent that applies itself does.
Returns the options recomputed."
  (let (done)
    (dolist (option (my/settings--tree-options))
      (let ((standard (car (get option 'standard-value))))
        (when (and standard
                   (not (get option 'saved-value))
                   (not (get option 'customized-value))
                   (my/settings--form-mentions-p standard symbols))
          (condition-case err
              (progn
                (funcall (or (get option 'custom-set) #'set-default)
                         option (eval standard t))
                (push option done))
            (error (message "MyPKS: could not recompute %s: %s"
                            option (error-message-string err)))))))
    (nreverse done)))

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
;; A change of the root takes effect at the next start of Emacs, where
;; moving the notes is offered.  A change of the silos takes effect at
;; once (`my/silos-apply').

(defcustom my-notes-dir (expand-file-name "~/notes/")
  "Root of the notes: the folder holding every silo.
Everything under it -- silos with relative directories, captures,
exports, backups -- is derived from this value.

Takes effect at the next start of Emacs, which first offers to copy the
notes to the new folder; see `my/notes-check-root-move'."
  :type 'directory
  :set #'my/settings-set-needs-restart
  :tag "Notes folder"
  :group 'mypks-silos)

(defun my/silos--set (symbol value)
  "Customize setter of `my/silos': ask about removals, then apply.
At start-up only stores VALUE in SYMBOL.  Defined before the option,
which calls it when it is defined; the functions it calls once Emacs
is up are defined further down (removal question, `my/silos-apply')."
  (let* ((old (and (default-boundp symbol) (default-value symbol)))
         (live (my/settings--live-p))
         (adjusted (if (and live old)
                       (my/silos--confirm-removals old value)
                     value)))
    (set-default-toplevel-value symbol adjusted)
    (when live
      (my/silos-apply))
    (unless (equal adjusted value)
      (run-at-time 0 nil #'my/silos--sync-customize value adjusted))))

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

Order matters where a list of silos is shown or scanned.

Takes effect at once: lists of silos, Denote's hidden folders and the
options derived from the silos are recomputed (`my/silos-apply')."
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
  :set #'my/silos--set
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
;; rejects (25-inbox-review.el), the attachments (31-org-images.el),
;; disabled silos (here).  A module that set the variable outright would
;; erase what another had set, so the regexp is always rebuilt from all
;; of them:
;;
;;   `my/denote-exclude-directory'            a folder, once
;;   `my/denote-excluded-directory-functions' a function returning folders,
;;                                            asked again on every rebuild,
;;                                            for folders that follow an
;;                                            option (the inbox, the silos)
;;
;; Folders are relative to `my-notes-dir' (= `denote-directory'); each
;; matches as a whole path component, so excluding pks does not exclude
;; pks-old.  A folder outside the root needs no hiding and is dropped.

(defvar denote-excluded-directories-regexp)

(defvar my/denote-excluded-directories nil
  "Folders under `my-notes-dir' hidden from Denote, relative, no slash.
Add with `my/denote-exclude-directory'; the regexp follows.")

(defvar my/denote-excluded-directory-functions nil
  "Functions of no arguments returning folders to hide from Denote.
Each returns a list of directories, absolute or relative to
`my-notes-dir'.  Called on every rebuild of the regexp, so a folder
that follows an option is hidden where the option points now.")

(defun my/notes-relative-folder (dir)
  "Return DIR relative to `my-notes-dir', without a trailing slash.
DIR may be absolute or already relative.  Nil when DIR is outside the
root or is the root itself."
  (let* ((root (file-name-as-directory (expand-file-name my-notes-dir)))
         (abs (file-name-as-directory (expand-file-name dir root))))
    (when (and (string-prefix-p root abs) (not (equal abs root)))
      (directory-file-name (substring abs (length root))))))

(defun my/denote-excluded-names ()
  "Return every folder hidden from Denote, relative to the root."
  (delete-dups
   (delq nil
         (mapcar #'my/notes-relative-folder
                 (append my/denote-excluded-directories
                         (seq-mapcat (lambda (fn)
                                       (condition-case nil (funcall fn)
                                         (error nil)))
                                     my/denote-excluded-directory-functions))))))

(defun my/denote-update-excluded-regexp ()
  "Set `denote-excluded-directories-regexp' from the excluded folders.
Each folder matches as a whole path component wherever Denote's version
applies the regexp: to a path relative to `denote-directory', as now,
or to a longer one."
  (let ((names (my/denote-excluded-names)))
    (setq denote-excluded-directories-regexp
          (when names
            (concat "\\(?:\\`\\|/\\)"
                    (regexp-opt names)
                    "\\(?:/\\|\\'\\)")))))

(defun my/denote-exclude-directory (relative)
  "Hide folder RELATIVE (to `my-notes-dir') from Denote's file operations."
  (let ((name (directory-file-name relative)))
    (unless (member name my/denote-excluded-directories)
      (push name my/denote-excluded-directories)
      (my/denote-update-excluded-regexp))))

(defun my/denote-exclude-directory-function (function)
  "Hide from Denote the folders FUNCTION returns, now and after changes.
FUNCTION takes no arguments; see `my/denote-excluded-directory-functions'."
  (add-hook 'my/denote-excluded-directory-functions function)
  (my/denote-update-excluded-regexp))

(defun my/silo--disabled-folders ()
  "Return the folders of the disabled silos."
  (mapcar #'my/silo-dir
          (my/silo-keys (lambda (k) (not (my/silo-enabled-p k))) t)))

;; Disabled silos inside the root are hidden from Denote.
(my/denote-exclude-directory-function #'my/silo--disabled-folders)

;; REPORTS THAT WAIT FOR AN ANSWER
;; ---------------------------------
;; A change of the notes folder or of the silos is made expecting a
;; result.  Whether it happened is said in a window that stays until it
;; is answered -- not in *Messages*, where the line scrolls away among
;; start-up messages and the user goes on working in the old folder
;; believing it is the new one.  Three outcomes, told apart in words and
;; colour:
;;
;;   DONE     what was asked happened
;;   REFUSED  a safeguard stopped it on purpose; nothing changed
;;   FAILED   something unexpected went wrong; nothing was removed
;;
;; Without a frame to ask in (batch, a daemon with no client frame) the
;; report goes to *Messages* and stays in its buffer, and the answer is
;; nil, which every caller treats as "change nothing".

(defconst my/notes-report-buffer "*MyPKS report*"
  "Buffer holding the last report about the notes folder or the silos.")

(defface my/notes-report-done '((t :inherit success :weight bold))
  "Heading of a report whose change was made."
  :group 'mypks-silos)

(defface my/notes-report-refused '((t :inherit warning :weight bold))
  "Heading of a report whose change a safeguard stopped."
  :group 'mypks-silos)

(defface my/notes-report-failed '((t :inherit error :weight bold))
  "Heading of a report whose change failed unexpectedly."
  :group 'mypks-silos)

(defun my/notes-report (kind title lines &optional choices)
  "Show a report of KIND with TITLE and LINES; return the answer's key.
KIND is `done', `refused' or `failed'.  CHOICES is a list for
`read-multiple-choice'; by default one answer, ?o \"ok\".  The report
stays in `my/notes-report-buffer' after the answer.  Returns nil when
there is no frame to ask in."
  (let* ((label (pcase kind ('done "DONE") ('refused "REFUSED") (_ "FAILED")))
         (face (pcase kind
                 ('done 'my/notes-report-done)
                 ('refused 'my/notes-report-refused)
                 (_ 'my/notes-report-failed)))
         (choices (or choices '((?o "ok" "Close the report"))))
         (buffer (get-buffer-create my/notes-report-buffer)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "%s  %s" label title) 'face face) "\n\n"
                (string-join lines "\n") "\n")
        (pcase kind
          ('refused (insert "\nA safeguard, not an error: nothing was changed.\n"))
          ('failed (insert "\nNothing was removed.  Details above; *Messages* has the rest.\n"))))
      (special-mode))
    (if (or noninteractive
            ;; A daemon whose only frame is the initial, invisible one.
            (and (daemonp) (eq (selected-frame) terminal-frame)))
        (progn
          (message "MyPKS %s: %s -- %s" label title (string-join lines " "))
          nil)
      (let ((window (display-buffer buffer '((display-buffer-pop-up-window
                                              display-buffer-use-some-window)))))
        (unwind-protect
            (progn
              (redisplay t)
              (car (read-multiple-choice (format "%s: %s" label title) choices)))
          (when (window-live-p window)
            (quit-restore-window window 'bury)))))))

(defun my/notes-open-silo-settings ()
  "Open the settings of the notes folder and the silos."
  (interactive)
  (customize-group 'mypks-silos))

;; FOLDERS WITH NOTES THAT ARE NOT SILOS
;; -------------------------------------
;; A silo whose entry was deleted rather than disabled is still a folder
;; of notes under the root, and Denote, rooted there, still shows them.
;; Shortly after start-up each such folder is shown in a report that
;; waits for an answer: add it back as a disabled silo (hidden, nothing
;; lost), add it as a silo, ask again next time, or never ask about it.
;; Only top-level folders, only files named the Denote way and ending in
;; .org or .md: attachments carry Denote-like names too, and a deep scan
;; of the whole tree at every start would be slow.

(defconst my/silo--denote-note-regexp
  "\\`[0-9]\\{8\\}T[0-9]\\{6\\}.*\\.\\(?:org\\|md\\)\\'"
  "File names counted as Denote notes by the orphan check.")

(defcustom my/silo-orphans-ignored nil
  "Folders under the notes folder that hold notes and are deliberately not silos.
Names relative to `my-notes-dir', without a slash.  Not reported at
start-up.  Filled by the answer \"never ask\" of that report."
  :type '(repeat string)
  :tag "Folders with notes that are not silos"
  :group 'mypks-silos)

(defun my/silo-orphans ()
  "Return top-level folders under `my-notes-dir' holding notes but no silo.
Folders in `my/silos' (disabled ones included), folders hidden from
Denote, `my/silo-orphans-ignored' and dot folders are not reported."
  (let* ((root (file-name-as-directory (expand-file-name my-notes-dir)))
         (known (append (delq nil (mapcar #'my/silo-folder-name
                                          (my/silo-keys nil t)))
                        (my/denote-excluded-names)
                        my/silo-orphans-ignored)))
    (when (file-directory-p root)
      (seq-filter
       (lambda (name)
         (and (not (string-prefix-p "." name))
              (not (member name known))
              (file-directory-p (expand-file-name name root))
              (directory-files (expand-file-name name root) nil
                               my/silo--denote-note-regexp t 1)))
       (directory-files root nil directory-files-no-dot-files-regexp t)))))

(defun my/silo--new-key (name)
  "Return a key for a silo in folder NAME, not yet used in `my/silos'."
  (let* ((base (intern (replace-regexp-in-string "[^[:alnum:]-]" "-" name)))
         (key base) (n 1))
    (while (assq key my/silos)
      (setq n (1+ n) key (intern (format "%s-%d" base n))))
    key))

(defun my/silo--add-folder (name disabled)
  "Add folder NAME as a silo, DISABLED or not, and save `my/silos'."
  (customize-save-variable
   'my/silos
   (append my/silos
           (list (list (my/silo--new-key name)
                       :directory (concat name "/") :role nil :keyword nil
                       :private nil :disabled disabled
                       :description "Added from a folder with notes that was not a silo.")))))

(defun my/silo-report-orphans ()
  "Ask about each folder under the root that holds notes but is not a silo."
  (interactive)
  (let ((orphans (my/silo-orphans)))
    (if (null orphans)
        (when (called-interactively-p 'interactive)
          (message "MyPKS: every folder with notes is a silo"))
      (dolist (name orphans)
        (pcase (my/notes-report
                'refused
                (format "Folder %s/ holds notes but is not a silo" name)
                (list (format "Folder: %s" (expand-file-name name my-notes-dir))
                      "Its entry in the silos was deleted, or it was made by hand."
                      "Denote still shows its notes in searches and link prompts."
                      ""
                      "  d  add it as a DISABLED silo: hidden, nothing lost, one checkbox to bring back"
                      "  a  add it as a silo: its notes are used like any other"
                      "  l  ask me again at the next start"
                      "  n  never ask about this folder (my/silo-orphans-ignored)")
                '((?d "disabled silo" "Add as a disabled silo: hidden, nothing lost")
                  (?a "add as silo" "Add as an enabled silo")
                  (?l "later" "Ask again at the next start")
                  (?n "never ask" "Do not report this folder again")))
          (?d (my/silo--add-folder name t))
          (?a (my/silo--add-folder name nil))
          (?n (customize-save-variable 'my/silo-orphans-ignored
                                       (append my/silo-orphans-ignored (list name))))
          (_ nil))))))

;; Shortly after start-up rather than at load: it reads the disk, and
;; the frame should be drawn before a question appears in it.
(defun my/silo--report-orphans-soon ()
  "Run `my/silo-report-orphans' once Emacs is idle after start-up."
  (run-with-idle-timer 1 nil #'my/silo-report-orphans))

(add-hook 'emacs-startup-hook #'my/silo--report-orphans-soon)

;; REMOVING A SILO IN CUSTOMIZE
;; ----------------------------
;; Deleting an entry from `my/silos' leaves its folder alone, but the
;; folder then becomes an unregistered folder of notes.  When the folder
;; holds anything, the change is asked about before it is made: keep the
;; silo as disabled (the default answer), remove the entry, or cancel.
;; The answer is written back to Customize, so that the value shown --
;; and saved, when "Apply and Save" was used -- is the one in effect.

(defun my/silos--holds-files-p (key value)
  "Non-nil when the folder of silo KEY in VALUE exists and is not empty."
  (when-let* ((dir (plist-get (cdr (assq key value)) :directory))
              (abs (expand-file-name dir my-notes-dir)))
    (and (file-directory-p abs)
         (directory-files abs nil directory-files-no-dot-files-regexp t 1))))

(defun my/silos--confirm-removals (old new)
  "Return NEW, adjusted by the answers about silos of OLD missing from it.
A silo counts as removed when neither its key nor its folder is in NEW
-- renaming a key keeps the folder -- and is asked about only when its
folder holds files."
  (let ((result new))
    (dolist (entry old)
      (let* ((key (car entry))
             (dir (plist-get (cdr entry) :directory)))
        (unless (or (assq key new)
                    (seq-find (lambda (e) (equal (plist-get (cdr e) :directory) dir))
                              new)
                    (not (my/silos--holds-files-p key old)))
          (pcase (my/notes-report
                  'refused
                  (format "Silo %s removed from the list" key)
                  (list (format "Its folder %s still holds files; nothing deletes them."
                                (expand-file-name dir my-notes-dir))
                        ""
                        "  d  keep the silo, DISABLED: hidden everywhere, nothing lost (recommended)"
                        "  r  remove the entry: the folder stays, Denote still shows its notes,"
                        "     and the start-up check will ask about it"
                        "  c  cancel: keep the silo as it was")
                  '((?d "disable" "Keep it as a disabled silo")
                    (?r "remove" "Remove the entry; the folder stays")
                    (?c "cancel" "Keep the silo unchanged")))
            (?r nil)
            (?c (setq result (append result (list entry))))
            ;; ?d, and no answer at all: nothing is lost either way.
            (_ (setq result (append result
                                    (list (cons key (plist-put (copy-sequence (cdr entry))
                                                               :disabled t))))))))))
    result))

(declare-function custom-redraw "cus-edit" (widget))
(declare-function custom-variable-state-set-and-redraw "cus-edit" (widget))
(defvar custom-options)

(defun my/silos--sync-customize (asked adjusted)
  "Make Customize hold ADJUSTED where the user had set ASKED.
Runs after the Customize command that set `my/silos' has finished: a
saved value equal to ASKED is saved again as ADJUSTED, a customized one
set again, and open Custom buffers are redrawn."
  (cond
   ((and (get 'my/silos 'saved-value)
         (equal (ignore-errors (eval (car (get 'my/silos 'saved-value)) t)) asked))
    (customize-save-variable 'my/silos adjusted))
   ((get 'my/silos 'customized-value)
    (customize-set-variable 'my/silos adjusted)))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'Custom-mode) (boundp 'custom-options))
        (dolist (widget custom-options)
          (when (eq (widget-value widget) 'my/silos)
            (custom-redraw widget)
            (custom-variable-state-set-and-redraw widget)))))))

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
;; Every outcome is shown by `my/notes-report' and waits for an answer:
;; DONE (switched, copied), REFUSED (a safeguard), FAILED (the copy, or
;; an unexpected error -- which keeps the old root and never stops the
;; rest of Emacs from starting).
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
  "Non-nil when DIR does not exist or holds nothing but this system's own.
The backup and autosave folders Emacs creates in a notes folder do not
make it someone else's: switching back to a new, still empty notes
folder must not be refused because of them."
  (or (not (file-exists-p dir))
      (null (seq-remove (lambda (name) (member name '(".backups" ".autosaves")))
                        (directory-files dir nil directory-files-no-dot-files-regexp t)))))

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

(defun my/notes--old-root-lines (old)
  "Return report lines about saved settings that still name OLD."
  (when-let* ((refs (my/notes--custom-file-references old)))
    (cons "\nSaved settings still pointing at the old folder (change them in C-c n ,):"
          refs)))

(defun my/notes--refuse-move (old new reason)
  "Keep OLD as the root for this session and report the refusal of NEW.
REASON is one line.  The answer may open the settings once Emacs is up."
  (setq my-notes-dir old)
  (when (eq (my/notes-report
             'refused
             (format "Notes folder NOT changed to %s" (abbreviate-file-name new))
             (list reason
                   (format "Still using %s for this session." (abbreviate-file-name old))
                   "The setting stays as saved; this check runs again at the next start.")
             '((?o "ok, keep the old folder" "Keep working in the old folder")
               (?s "open settings" "Choose another folder once Emacs has started")))
            ?s)
    (add-hook 'emacs-startup-hook #'my/notes-open-silo-settings)))

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
      (my/notes-report 'done (format "Notes folder is now %s" (abbreviate-file-name new))
                       (list (format "The old folder %s no longer exists, so nothing was copied."
                                     (abbreviate-file-name old)))))
     ;; The new root already holds the notes, and the old one does not
     ;; (any more): a second machine, or files moved by hand.  Switch.
     ((and (my/notes--holds-notes-p new) (not (my/notes--holds-notes-p old)))
      (my/notes--write-root-state new old)
      (my/notes-report 'done (format "Notes folder is now %s" (abbreviate-file-name new))
                       (list "The notes were already there; nothing was copied."
                             (format "%s holds no notes and was left as it is."
                                     (abbreviate-file-name old)))))
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
                 (my/notes-report 'done (format "Notes folder is now %s" (abbreviate-file-name new))
                                  (list (format "Nothing was copied; %s was left as it is."
                                                (abbreviate-file-name old)))))
        (setq my-notes-dir old)
        (message "MyPKS: still using %s this session" old)))
     ;; Nested roots: refuse, keep the old one.
     ((or (file-in-directory-p new old) (file-in-directory-p old new))
      (my/notes--refuse-move
       old new (format "%s and %s lie inside one another: a copy would copy itself."
                       (abbreviate-file-name old) (abbreviate-file-name new))))
     ;; Something else is already there: refuse.
     ((not (my/notes--empty-dir-p new))
      (my/notes--refuse-move
       old new (format "%s is not empty and holds no silos: its files are not notes of this system."
                       (abbreviate-file-name new))))
     ;; Nobody to ask: keep the old root, ask next time.
     ((or noninteractive (daemonp))
      (setq my-notes-dir old)
      (message "MyPKS: notes root change to %s postponed: no frame to ask in" new))
     (t
      (pcase (my/notes--ask-move old new)
        (?l (setq my-notes-dir old)
            (message "MyPKS: still using %s this session; asking again next time" old))
        (?s (my/notes--write-root-state new old)
            (my/notes-report
             'done (format "Notes folder is now %s" (abbreviate-file-name new))
             (append
              (list "Switched without copying, as asked."
                    (format "Move your files from %s yourself." (abbreviate-file-name old)))
              (my/notes--old-root-lines old))))
        (?c (message "MyPKS: copying %s to %s..." old new)
            (let* ((failure (my/notes--copy-tree old new))
                   (before (and (not failure) (my/notes--tree-stats old)))
                   (after (and (not failure) (my/notes--tree-stats new))))
              (if (or failure (not (equal before after)))
                  (progn
                    (setq my-notes-dir old)
                    (my/notes-report
                     'failed (format "Copy to %s failed or is incomplete" (abbreviate-file-name new))
                     (list (or failure
                               (format "Old: %d files, %d bytes.  New: %d files, %d bytes."
                                       (car before) (cdr before) (car after) (cdr after)))
                           (format "Still using %s.  The partial copy is in %s."
                                   (abbreviate-file-name old) (abbreviate-file-name new)))))
                (my/notes--write-root-state new old)
                (my/notes-report
                 'done (format "Notes copied; the notes folder is now %s" (abbreviate-file-name new))
                 (append
                  (list (format "Copied %s to %s: %d files, %d bytes, identical counts."
                                old new (car after) (cdr after))
                        (format "The old folder %s is untouched." (abbreviate-file-name old)))
                  (my/notes--old-root-lines old)
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

(defun my/notes--check-root-move-safely ()
  "Run `my/notes-check-root-move'; on an unexpected error keep the old root.
An error here must not stop Emacs from starting: every module loads
after this, and none would load at all."
  (condition-case err
      (my/notes-check-root-move)
    (error
     (let ((old (plist-get (my/notes--read-root-state) :root)))
       (when old (setq my-notes-dir old))
       ;; The report itself must not be what stops start-up either.
       (condition-case nil
           (my/notes-report
            'failed "Checking the notes folder failed"
            (list (format "Unexpected error: %s" (error-message-string err))
                  (format "Using %s for this session." my-notes-dir)))
         (error (message "MyPKS: checking the notes folder failed: %s; using %s"
                         (error-message-string err) my-notes-dir)))))))

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

;; Reports about this machine's settings first: they say which settings
;; the rest of start-up uses.
(my/host--show-reports)

;; Must run before anything below derives a path from the root.
(my/notes--check-root-move-safely)

;; The variables every module has used so far, now derived.  Kept so
;; that modules work unchanged while they move to the functions above;
;; they follow the ROLE, not the key.  Set by `my/silos--derive-variables'
;; below, again whenever `my/silos' changes.
(defvar my-notes-journal nil
  "Directory of the journal silo (role `journal' in `my/silos').")

(defvar my-notes-pks nil
  "Directory of the default notes silo (role `notes' in `my/silos').")

(defvar my-notes-docu nil
  "Directory of the documentation silo (role `docs' in `my/silos').")

;; Capture file
(defvar my-journal-captures nil
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
(defvar my-tasks-agenda-dirs nil
  "Every enabled silo and the captures file: \"all notes\" for scans.")

(defun my/silos--derive-variables ()
  "Set the variables derived from `my/silos' and the root."
  (setq my-notes-journal (my/silo-dir-by-role 'journal)
        my-notes-pks (my/silo-dir-by-role 'notes)
        my-notes-docu (my/silo-dir-by-role 'docs)
        my-journal-captures (expand-file-name "captures.org" my-notes-journal)
        my-tasks-agenda-dirs (append (my/silo-dirs) (list my-journal-captures))))

(my/silos--derive-variables)

(defconst my/silos--dependency-symbols
  '(my/silos my-notes-journal my-notes-pks my-notes-docu my-journal-captures
    my-tasks-agenda-dirs my/silo-dir my/silo-dirs my/silo-keys
    my/silo-dir-by-role my/silo-by-role)
  "Symbols whose presence in an option's default makes it follow the silos.")

(defvar my/silos-changed-hook nil
  "Hook run after `my/silos' changed and was applied while Emacs runs.
For a module that keeps something derived from the silos outside an
option -- an option's default is recomputed without it.")

(defun my/silos-apply ()
  "Apply a changed `my/silos' at once.
Derived variables, Denote's hidden folders and every option whose
default is computed from the silos (unless set by hand) follow; then
`my/silos-changed-hook' runs.  No folder is created: a silo's folder
appears with its first note."
  (my/silos--derive-variables)
  (my/denote-update-excluded-regexp)
  (let ((recomputed (my/settings-reevaluate-dependents
                     my/silos--dependency-symbols)))
    (run-hooks 'my/silos-changed-hook)
    (message "Silos applied: %s%s"
             (mapconcat #'symbol-name (my/silo-keys) ", ")
             (if recomputed
                 (format "; recomputed %d dependent option(s)" (length recomputed))
               ""))))

;; Backup directories
(defvar my-notes-backups (my/notes-path ".backups/")
  "Backup directory for note files.")

(defvar my-notes-autosaves (my/notes-path ".autosaves/")
  "Autosave directory for note files.")

;; Emacs configuration directories
(defvar my-emacs-backups (locate-user-emacs-file "backups/")
  "Backup directory for other files.")

(defvar my-emacs-autosaves (locate-user-emacs-file "autosaves/")
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
(defcustom my-denote-keywords
  '("journal" "docu" "wellbeing" "esej" "philosophy"
    "zettel" "osoba" "projekt" "lektura" "filozof"
    "skroty")
  "Keywords Denote offers before any note uses them.
Passed to `denote-known-keywords'.  With `denote-infer-keywords'
enabled, Denote also offers every keyword found in the file names of
existing notes, so the list matters mostly for a new notes folder.

A keyword added here is offered at once; a removed one stays offered
until the next start, and longer if a note still carries it."
  :type '(repeat (string :tag "Keyword"))
  :tag "Starting keywords"
  :group 'mypks-notes
  :set (lambda (symbol value)
         (set-default symbol value)
         (when (and (my/settings--live-p)
                    (boundp 'denote-known-keywords))
           (setq denote-known-keywords
                 (delete-dups (append value denote-known-keywords))))))

;; FOLDERS ARE CREATED WHEN SOMETHING GOES INTO THEM
;; -------------------------------------------------
;; At start-up only the notes folder itself and the backup and autosave
;; folders are created.  A silo's folder appears with its first note: a
;; new, empty notes folder -- a separate collection, kept apart from the
;; main one on disk like a second Obsidian vault -- stays empty until
;; something is written, instead of filling with journal/, pks/ and
;; docu/ it may never use.
;;
;; Three helpers make that safe for the modules:
;;   `my/notes--create-missing-directory'  on `before-save-hook': saving a
;;                                         file under the notes folder
;;                                         creates its folder (a new note,
;;                                         a capture, the first journal)
;;   `my/notes-ensure-directory-of'        for code writing a file without
;;                                         a buffer (`with-temp-file',
;;                                         `rename-file')
;;   `my/notes-files'                      lists a folder that may not
;;                                         exist yet, as empty
;; Denote creates the folder it is let-bound to by itself.

(defun my/notes-ensure-directories ()
  "Create the notes root and the backup and autosave folders if missing.
Silo folders are not created here; see the commentary above."
  (dolist (dir (list my-notes-dir
                     my-notes-backups
                     my-notes-autosaves
                     my-emacs-backups
                     my-emacs-autosaves))
    (unless (file-exists-p dir)
      (make-directory dir t))))

(my/notes-ensure-directories)

(defun my/notes-ensure-directory-of (file)
  "Create the folder FILE goes into, when FILE is under the notes folder.
Returns FILE.  Outside the notes folder nothing is created: Emacs's own
question about a missing folder stays where it is."
  (let ((dir (file-name-directory (expand-file-name file))))
    (when (and dir
               (not (file-directory-p dir))
               (file-in-directory-p dir (expand-file-name my-notes-dir)))
      (make-directory dir t)))
  file)

(defun my/notes--create-missing-directory ()
  "Before saving a file under the notes folder, create its folder if missing."
  (when buffer-file-name
    (my/notes-ensure-directory-of buffer-file-name)))

(add-hook 'before-save-hook #'my/notes--create-missing-directory)

(defun my/notes-files (dir regexp &optional recursive)
  "Return the files in DIR whose names match REGEXP, as absolute names.
With RECURSIVE, the files in its sub-folders too.  A folder that does
not exist -- a silo without its first note -- has no files, rather
than signalling an error."
  (when (and dir (file-directory-p dir))
    (if recursive
        (directory-files-recursively dir regexp)
      (directory-files dir t regexp))))

;; ============================================================
;; FILE HANDLING: Backups and autosaves
;; ============================================================

;; Separate backups and autosaves by location (notes vs other files).
;; Both alists hold REGEXPS matched against the absolute file name, so
;; the notes folder goes in expanded, with a slash, and quoted.  The
;; option itself may hold "~/notes" -- Customize saves what was typed --
;; and a key of "~/notes/" never matched "/home/<user>/notes/...": notes
;; were then backed up and autosaved under ~/.emacs.d/ instead.
(defun my/notes--root-regexp ()
  "Return a regexp matching file names under the notes folder."
  (concat "\\`" (regexp-quote (file-name-as-directory (expand-file-name my-notes-dir)))))

(setq backup-directory-alist
      `((,(my/notes--root-regexp) . ,my-notes-backups)
        (".*" . ,my-emacs-backups)))

(setq auto-save-file-name-transforms
      `((,(concat (my/notes--root-regexp) ".*") ,my-notes-autosaves t)
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

(defconst my/ui-state-file (expand-file-name "ui-state.el" my/host-directory)
  "File holding interactively chosen UI settings, per machine.
In hosts/<host>/, next to that machine's custom.el, so that a reinstall
finds them again.  Safe to delete: every reader falls back to a
compiled-in default.")

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
