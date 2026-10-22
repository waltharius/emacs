;;; 03-spelling.el --- Spell checking configuration -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; Docs: ~/.emacs.d/function_helper.org::#menu-spelling

;;; Commentary:
;;
;; Description: Hunspell (Polish and English, the dictionaries installed) for spelling
;;              Flyspell for highlighting errors AS YOU TYPE
;;
;; STARTUP BEHAVIOUR
;; -----------------
;; ispell variables are set immediately at load time.
;; The Hunspell subprocess is blocked during desktop-restore via
;; `my/flyspell-desktop-restoring' flag.  Once the session is up,
;; `my/desktop-after-startup-hook' (01-ui.el) runs
;; `my/flyspell--recheck-all-buffers', which clears the flag and
;; re-enables flyspell in every open buffer.  Hunspell then starts
;; once, on demand, for the first buffer checked.
;;
;; While the flag is set, `flyspell-mode' reports itself as on but
;; nothing is checked while typing (only the explicit checks work).
;; If that state outlives startup, `my/toggle-flyspell' (C-c n t T)
;; releases the guard by hand.
;;
;; PERSONAL DICTIONARY
;; -------------------
;; Kept in the settings folder, shared by every machine; see the section
;; "Personal dictionary" below.
;;
;;; Code:

(require 'filenotify)
(require 'seq)
(require 'subr-x)

;; Declared for the byte compiler: ispell.el loads on demand, after
;; this file sets some of its variables.
(defvar ispell-personal-dictionary)
(defvar ispell-process)
(declare-function ispell-kill-ispell "ispell" (&optional no-error clear))
(declare-function ispell-send-string "ispell" (string))

;; ============================================================
;; ISPELL CORE VARIABLES  (set immediately — flyspell reads these
;;                          before the subprocess is ever needed)
;; ============================================================

(setq ispell-program-name "hunspell")
;; The dictionaries themselves are chosen once ispell loads, from those
;; installed (`my/spell-languages', below); this is the wish.
(setq ispell-dictionary "pl_PL,en_GB-large")
(setenv  "LANG"   "pl_PL.UTF-8")
(setenv  "LC_ALL" "pl_PL.UTF-8")
(setq ispell-silently-savep t)

;; ============================================================
;; PERSONAL DICTIONARY: one file for every machine
;; ============================================================
;; The words added with `a' (C-c S) are kept in the settings folder
;; rather than in ~/.hunspell_personal, so that they travel with the
;; settings from machine to machine:
;;
;;   <settings folder>/dictionaries/hunspell_personal  the words
;;   <settings folder>/dictionaries/.gitattributes     merge=union
;;   <settings folder>/hosts/<host>/spelling.eld       which old files this
;;                                                     machine brought in
;;
;; Data shared by all machines, so at the root of the settings folder
;; and not under hosts/<host>/.  07-git.el commits and pushes the
;; settings folder when it is a repository, or lies in the notes
;; repository; otherwise nothing carries the file to another machine,
;; and the report says so.
;;
;; WHY TWO MACHINES DO NOT LOSE EACH OTHER'S WORDS.  Hunspell appends
;; the words added during a session to the file (`save_privdic' in
;; hunspell.cxx opens it with "a"); it never rewrites the file from
;; memory, so words pulled from another machine in the meantime stay.
;; Two machines appending at once give a git conflict at the end of the
;; file; the attribute `merge=union' (gitattributes(5), built into git)
;; keeps the lines of both sides instead, also during `pull --rebase'.
;; A word added on both machines then appears twice, which Hunspell
;; ignores.
;;
;; BRINGING THE OLD WORDS IN.  The lines an old file holds and the new
;; one lacks are added to the new one, in their order.  Sources: the
;; file this machine used last (after a change of the settings folder
;; or of `my/spell-personal-dictionary'), then ~/.hunspell_personal,
;; once per machine.  Nothing is deleted; the old files stay as they
;; are and are no longer read.
;;
;; WHEN.  After 07-git.el's start-up pull, so that the second machine
;; adds its words to the file the first one pushed instead of creating
;; an untracked file of the same name, which would make the pull refuse
;; to update the folder.  The pull runs in the background, so
;; `my/spell--dictionary-startup' (from `my/desktop-after-startup-hook')
;; hands the work to `my/auto-commit-after-startup-pull', which runs it
;; when the pull is done -- or at once, without 07-git.el or with
;; pulling turned off.  Hunspell may have started by then (the start-up
;; guard is released at -90): it already uses the file (named at load,
;; below).  `my/spell--dictionary-setup' stops it only when words were
;; brought in from an old file or the file is another one; what the pull
;; changed is passed on as for any change on disk (next paragraph).
;;
;; A FILE CHANGED ON DISK -- by a pull, or by editing it (`e' in the
;; Spelling column) -- is noticed by a file watch on its folder.  New
;; words are passed to the running Hunspell as "@word", the ispell pipe
;; command that accepts a word for the session: the file already holds
;; them, and Hunspell reads it at its next start.  A removed word, a
;; forbidden one (*word) or one with affix flags (word/FLAGS) cannot be
;; passed that way; Hunspell is stopped instead and starts again, with
;; the file as it is, at the next check.

(defgroup my/spelling nil
  "Spell checking: Hunspell, live underlining, the personal dictionary."
  :tag "Spelling"
  :group 'mypks-writing)

(defconst my/spell--legacy-dictionary (expand-file-name "~/.hunspell_personal")
  "Personal dictionary used before it moved to the settings folder.")

(defvar my/spell--reports nil
  "Reports about the personal dictionary, waiting to be shown.
Each is (KIND TITLE LINES), the arguments of `my/notes-report'.")

(defcustom my/spell-personal-dictionary
  (expand-file-name "dictionaries/hunspell_personal" my/settings-directory)
  "File holding the words added to the dictionary, shared by every machine.
In the settings folder by default, so that it is committed and pushed
with the settings.  Hunspell's format: one word per line; *word forbids
a word; word/FLAGS adds it with affix flags.

A change applies at once: the words of the file used until now are
added to the new one, and the old file stays as it is."
  :type 'file
  :tag "Personal dictionary"
  :set (my/settings-apply-on-set #'my/spell--dictionary-apply)
  :group 'my/spelling)

;; --- what this machine already brought in ---------------------------

(defun my/spell--state-file ()
  "Return the file recording which dictionaries this machine brought in."
  (expand-file-name "spelling.eld" my/host-directory))

(defun my/spell--state-read ()
  "Return the plist in `my/spell--state-file', or nil.
Keys: :dictionary, the file used last; :imported, old files whose
words were added once."
  (let ((file (my/spell--state-file)))
    (when (file-readable-p file)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (let ((data (read (current-buffer))))
              (and (listp data) data)))
        (error nil)))))

(defun my/spell--state-write (data)
  "Store the plist DATA in `my/spell--state-file'."
  (let ((file (my/spell--state-file)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert ";; Written by 03-spelling.el: personal dictionary of this machine.\n")
      (prin1 data (current-buffer))
      (insert "\n"))))

;; --- reading, writing and merging dictionary files ------------------

(defun my/spell--dictionary-lines (file)
  "Return the entries of the personal dictionary FILE, in order.
Trailing whitespace is dropped; empty lines are left out, and so is an
aspell header (personal_ws-1.1 ...), which earlier versions of this
module wrote and Hunspell reads as one more word."
  (when (file-readable-p file)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents file))
      (seq-remove (lambda (line)
                    (or (string-empty-p line)
                        (string-prefix-p "personal_ws-" line)))
                  (mapcar #'string-trim-right
                          (split-string (buffer-string) "\n"))))))

(defun my/spell--dictionary-table (file)
  "Return a hash table of the entries of the dictionary FILE."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (line (my/spell--dictionary-lines file) table)
      (puthash line t table))))

(defun my/spell--dictionary-write (file lines)
  "Write LINES to FILE, one per line, through a temporary file and a rename.
An interrupted write leaves the old FILE whole."
  (make-directory (file-name-directory file) t)
  (let ((temp (concat file ".tmp"))
        (coding-system-for-write 'utf-8-unix))
    (with-temp-file temp
      (dolist (line lines)
        (insert line "\n")))
    (rename-file temp file t)))

(defun my/spell--dictionary-merge (from to)
  "Add to the dictionary TO the entries of FROM it lacks; return how many.
TO is created when missing.  The entries of TO stay first, in their
order, followed by the new ones in the order of FROM.  FROM is only read."
  (let ((have (my/spell--dictionary-lines to))
        (seen (make-hash-table :test #'equal))
        (added '()))
    (dolist (line have)
      (puthash line t seen))
    (dolist (line (my/spell--dictionary-lines from))
      (unless (gethash line seen)
        (puthash line t seen)
        (push line added)))
    (setq added (nreverse added))
    (when (or added (not (file-exists-p to)))
      (my/spell--dictionary-write to (append have added)))
    (length added)))

(defun my/spell--dictionary-gitattributes (file)
  "Make git merge FILE by keeping the lines of both sides (merge=union).
Creates or extends .gitattributes in the folder of FILE.  A file name
with whitespace would need quoting there and is left alone."
  (let* ((name (file-name-nondirectory file))
         (attributes (expand-file-name ".gitattributes" (file-name-directory file)))
         (line (format "%s merge=union" name)))
    (unless (or (string-match-p "[ \t]" name)
                (and (file-readable-p attributes)
                     (with-temp-buffer
                       (insert-file-contents attributes)
                       (re-search-forward
                        (concat "^" (regexp-quote line) "[ \t]*$") nil t))))
      (with-temp-buffer
        (if (file-readable-p attributes)
            (progn
              (insert-file-contents attributes)
              (goto-char (point-max))
              (unless (bolp) (insert "\n")))
          (insert "# Written by 03-spelling.el: words added on two machines are both kept.\n"))
        (insert line "\n")
        (write-region nil nil attributes nil 'silent)))))

;; --- bringing the old words in --------------------------------------

(defun my/spell--dictionary-prepare ()
  "Bring the words of earlier dictionaries into `my/spell-personal-dictionary'.
Return report lines when an old file was read, else nil.  See
\"BRINGING THE OLD WORDS IN\" in the commentary of this section."
  (let* ((target (expand-file-name my/spell-personal-dictionary))
         (state (my/spell--state-read))
         (previous (plist-get state :dictionary))
         (imported (plist-get state :imported))
         (lines '()))
    ;; The file this machine used last, when the dictionary has moved.
    (when (and previous
               (not (equal (expand-file-name previous) target))
               (file-readable-p previous))
      (push (format "%d word(s) added from %s, used until now; that file stays as it is."
                    (my/spell--dictionary-merge previous target)
                    (abbreviate-file-name previous))
            lines))
    ;; ~/.hunspell_personal, once per machine.
    (when (and (not (member my/spell--legacy-dictionary imported))
               (not (equal my/spell--legacy-dictionary target))
               (file-readable-p my/spell--legacy-dictionary))
      (push (format "%d word(s) added from %s, which stays as it is and is no longer read."
                    (my/spell--dictionary-merge my/spell--legacy-dictionary target)
                    (abbreviate-file-name my/spell--legacy-dictionary))
            lines)
      (push my/spell--legacy-dictionary imported))
    (unless (file-exists-p target)
      (my/spell--dictionary-write target nil))
    (my/spell--dictionary-gitattributes target)
    (unless (and (equal previous target)
                 (equal imported (plist-get state :imported)))
      (my/spell--state-write (list :dictionary target :imported imported)))
    (nreverse lines)))

(defun my/spell--dictionary-backup-line (file)
  "Return a report line saying whether git carries FILE to other machines."
  (if (locate-dominating-file file ".git")
      (concat "It is in a git repository, committed and pushed with it; words added "
              "on two machines at once are both kept (merge=union in .gitattributes).")
    (concat "It is in no git repository: nothing carries it to another machine yet.  "
            "The settings folder inside a repository takes it along; see "
            "\"The settings folder\" in function_helper.org.")))

;; --- watching the file ----------------------------------------------

(defvar my/spell--dictionary-descriptor nil
  "Descriptor of the file watch on the folder of the personal dictionary.")

(defvar my/spell--dictionary-known nil
  "Hash table of the dictionary entries the running Hunspell knows.")

(defvar my/spell--dictionary-timer nil
  "Idle timer of a pending `my/spell--dictionary-sync'.")

(defun my/spell--dictionary-watch (file)
  "Watch the folder of FILE, so that changes made on disk reach Hunspell.
The folder rather than the file: git replaces a file by renaming a new
one over it, which a watch on the file itself would not follow."
  (when my/spell--dictionary-descriptor
    (file-notify-rm-watch my/spell--dictionary-descriptor)
    (setq my/spell--dictionary-descriptor nil))
  (setq my/spell--dictionary-known (my/spell--dictionary-table file))
  (let ((dir (file-name-directory file)))
    (when (file-directory-p dir)
      (condition-case err
          (setq my/spell--dictionary-descriptor
                (file-notify-add-watch dir '(change) #'my/spell--dictionary-event))
        (error
         (message "03-spelling: no file watch on %s (%s); changes on disk reach Hunspell at its next start"
                  (abbreviate-file-name dir) (error-message-string err)))))))

(defun my/spell--dictionary-event (event)
  "Schedule `my/spell--dictionary-sync' when EVENT concerns the dictionary.
Waits for one second of idleness, so that a pull writing several times
causes one sync."
  (let ((target (expand-file-name ispell-personal-dictionary))
        (file (nth 2 event))
        (file1 (nth 3 event)))
    (when (or (and (stringp file) (equal (expand-file-name file) target))
              (and (stringp file1) (equal (expand-file-name file1) target)))
      (when (timerp my/spell--dictionary-timer)
        (cancel-timer my/spell--dictionary-timer))
      (setq my/spell--dictionary-timer
            (run-with-idle-timer 1 nil #'my/spell--dictionary-sync)))))

(defun my/spell--dictionary-sync ()
  "Tell the running Hunspell about entries changed in the personal dictionary.
New plain words are accepted for the session (\"@word\"); anything else
stops Hunspell, which reads the file again at its next start.  The
words this session added itself come back here too, as already known."
  (setq my/spell--dictionary-timer nil)
  (let ((now (my/spell--dictionary-table ispell-personal-dictionary))
        (known (or my/spell--dictionary-known (make-hash-table :test #'equal)))
        (added '())
        (removed nil))
    (maphash (lambda (entry _) (unless (gethash entry known) (push entry added))) now)
    (maphash (lambda (entry _) (unless (gethash entry now) (setq removed t))) known)
    (setq my/spell--dictionary-known now)
    (when (and (or added removed)
               (boundp 'ispell-process)
               (process-live-p ispell-process))
      (if (or removed
              (seq-some (lambda (entry) (string-match-p "\\`\\*\\|/" entry)) added))
          (progn
            (ispell-kill-ispell t)
            (message "Personal dictionary changed: Hunspell restarts at the next check"))
        (dolist (word added)
          (ispell-send-string (concat "@" word "\n")))))))

;; --- putting it together --------------------------------------------

(defun my/spell--dictionary-use (file)
  "Point Hunspell at the personal dictionary FILE and watch it."
  (setq ispell-personal-dictionary file)
  ;; WORDLIST is the variable Hunspell itself reads in place of -p
  ;; (hunspell.cxx); ispell.el passes -p anyway, so this only gives a
  ;; hunspell started from a shell inside Emacs the same words.
  (setenv "WORDLIST" file)
  (my/spell--dictionary-watch file))

(defun my/spell--dictionary-setup ()
  "Bring the old words in, point Hunspell at the dictionary, report.
Never signals: a failure is reported, and Hunspell keeps
~/.hunspell_personal when the new file cannot be written."
  (let ((target (expand-file-name my/spell-personal-dictionary))
        (running-with (and (boundp 'ispell-process) (process-live-p ispell-process)
                           ispell-personal-dictionary))
        (imported nil))
    (condition-case err
        (let ((lines (my/spell--dictionary-prepare)))
          (setq imported lines)
          (when lines
            (push (list 'done
                        (format "Personal dictionary now in %s" (abbreviate-file-name target))
                        (append lines (list "" (my/spell--dictionary-backup-line target))))
                  my/spell--reports)))
      (error
       (push (list 'failed "Preparing the personal dictionary failed"
                   (list (error-message-string err)
                         (format "Wanted: %s" (abbreviate-file-name target))))
             my/spell--reports)))
    (let ((file (if (file-writable-p target) target my/spell--legacy-dictionary)))
      (when running-with
        (if (or imported (not (equal (expand-file-name running-with) file)))
            ;; Words were brought in from an old file, or Hunspell read
            ;; another file: it starts again at the next check.
            (ispell-kill-ispell t)
          ;; Same file, and nothing imported: what the start-up pull
          ;; changed reaches the running Hunspell as any change on disk
          ;; does -- new words by "@word", a restart only for a removed
          ;; or flagged entry.  Before the watch is renewed, which
          ;; takes the file as known.  (Until 2026-10-22 Hunspell was
          ;; stopped here at every start, after the desktop had started
          ;; it: "Ispell process killed" in *Messages*.)
          (my/spell--dictionary-sync)))
      (my/spell--dictionary-use file))))

(defun my/spell--show-reports ()
  "Show the reports collected by `my/spell--dictionary-setup'."
  (dolist (report (reverse my/spell--reports))
    (apply #'my/notes-report report))
  (setq my/spell--reports nil))

(defun my/spell--dictionary-startup-now ()
  "Prepare and watch the personal dictionary, and report."
  (my/spell--dictionary-setup)
  (my/spell--show-reports))

(defun my/spell--dictionary-startup ()
  "Prepare the personal dictionary once the session is up and pulled.
From `my/desktop-after-startup-hook'; the work waits for the start-up
pull of 07-git.el when one runs (see WHEN in the commentary)."
  (if (fboundp 'my/auto-commit-after-startup-pull)
      (my/auto-commit-after-startup-pull #'my/spell--dictionary-startup-now)
    (my/spell--dictionary-startup-now)))

(defun my/spell--dictionary-apply ()
  "Use a changed `my/spell-personal-dictionary' at once."
  (my/spell--dictionary-setup)
  (my/spell--show-reports))

;; Until the session is up, the file is only named: creating it before
;; the start-up pull would make that pull refuse to run (see WHEN).
(my/spell--dictionary-use (expand-file-name my/spell-personal-dictionary))

(if (boundp 'my/desktop-after-startup-hook)
    (add-hook 'my/desktop-after-startup-hook #'my/spell--dictionary-startup -95)
  (add-hook 'after-init-hook #'my/spell--dictionary-startup 90))

(defvar-local my/spell--editing-dictionary nil
  "Non-nil in a buffer opened by `my/spell-edit-personal-dictionary'.
Changes typed there are asked about on quit like any other buffer's.")

(defun my/spell-edit-personal-dictionary ()
  "Open the personal dictionary, to remove a word added by mistake.
One word per line; *word forbids a word.  Saving is picked up at once:
Hunspell restarts with the file as saved."
  (interactive)
  (find-file ispell-personal-dictionary)
  (setq my/spell--editing-dictionary t)
  ;; The file watch catches the save as well; this covers a system
  ;; without file notifications.  A second sync finds nothing new.
  (add-hook 'after-save-hook #'my/spell--dictionary-sync nil t))

;; ============================================================
;; WHICH DICTIONARIES: THE FIRST INSTALLED OF EACH LANGUAGE
;; ============================================================
;; Until 2026-10-20 the dictionaries were named outright,
;; "pl_PL,en_GB-large": names of the NixOS packages.  Fedora's
;; hunspell-en-GB installs en_GB only, Debian's and Ubuntu's the same,
;; and Hunspell asked for en_GB-large fails -- spell checking was off on
;; any machine but the owner's, with an error at start-up.  Now each
;; language lists the dictionaries that will do, best first, and the
;; first one Hunspell has is used.  What Hunspell has is what Emacs's
;; own `ispell-find-hunspell-dictionaries' finds (`hunspell -D').

(defcustom my/spell-languages
  '(("pl_PL")
    ("en_GB-large" "en_GB" "en_US"))
  "The languages to check, each a list of dictionaries, best first.
For each language the first dictionary Hunspell has is used, and all
of them together, as one combined dictionary.  A language none of whose
dictionaries is installed is left out, and said so once at start-up.
Takes effect at the next start of Emacs."
  :type '(repeat (repeat :tag "Language: dictionaries, best first" string))
  :tag "Spelling languages"
  :group 'my/spelling)

(defun my/spell--choose (languages available)
  "Return, for each of LANGUAGES, its first dictionary in AVAILABLE.
LANGUAGES as `my/spell-languages'; a language with none is left out."
  (delq nil (mapcar (lambda (choices) (seq-find (lambda (d) (member d available)) choices))
                    languages)))

(defun my/spell--missing (languages available)
  "Return the LANGUAGES (their lists) none of whose dictionaries is AVAILABLE."
  (seq-remove (lambda (choices) (seq-some (lambda (d) (member d available)) choices))
              languages))

(defun my/spell--dictionary-entry (name)
  "An `ispell-hunspell-dictionary-alist' entry for dictionary NAME, in UTF-8."
  (list name "[[:alpha:]]" "[^[:alpha:]]" "[']" nil (list "-d" name "-i" "utf-8") nil 'utf-8))

(defun my/spell--use-installed-dictionaries ()
  "Point ispell at the installed dictionaries `my/spell-languages' asks for.
Returns the combined dictionary name, or nil when none is installed."
  (let* ((available (progn
                      (ignore-errors (ispell-find-hunspell-dictionaries))
                      (mapcar #'car ispell-hunspell-dict-paths-alist)))
         (chosen (my/spell--choose my/spell-languages available))
         (missing (my/spell--missing my/spell-languages available))
         (combined (and chosen (string-join chosen ","))))
    (when missing
      (display-warning
       'my/spelling
       (format "No Hunspell dictionary for: %s.  Install one (Fedora: sudo dnf install hunspell-pl hunspell-en-GB), or change \"Spelling languages\" in C-c n , ,.%s"
               (mapconcat (lambda (choices) (string-join choices " or ")) missing "; ")
               (if chosen (format "  Checking with %s meanwhile." combined)
                 "  Spell checking is off."))
       :warning))
    (setq ispell-hunspell-dictionary-alist
          (append (mapcar #'my/spell--dictionary-entry chosen)
                  (when (cdr chosen) (list (my/spell--dictionary-entry combined)))))
    (setq ispell-dictionary combined)
    combined))

;; ============================================================
;; HUNSPELL DICT PATH REGISTRATION
;; ============================================================
;; Every dictionary must be UTF-8: Emacs runs Hunspell with `-i UTF-8',
;; and on NixOS Hunspell cannot convert an ISO8859-2 dictionary for it
;; ("error - iconv: ISO8859-2 -> UTF-8" in *Messages*, followed by
;; "Error enabling Flyspell mode").  hunspellDicts.pl_PL is ISO8859-2, so
;; the NixOS repository converts it at build time and installs only the
;; UTF-8 copy (modules/groups/emacs/home.nix, `hunspellPlUtf8').
;;
;; Both dictionaries come from the user profile.  `hunspell.withDicts'
;; wraps the binary with its own DICPATH prepended, so whatever is set
;; here is searched after the profile's dictionaries anyway; it only
;; matters for a Hunspell without that wrapper.  An older setup kept a
;; converted copy in ~/.local/share/hunspell; the wrapper never reached
;; it, which is how the ISO8859-2 file came back into use.
;;
;; DICPATH alone is not enough for Emacs: ispell-phaf resolves dictionary
;; paths from `ispell-hunspell-dict-paths-alist'.  The names used in
;; `ispell-dictionary' are registered explicitly -- en_GB-large is
;; installed as en_GB.aff -- BEFORE ispell-set-spellchecker-params reads
;; the alist.

(with-eval-after-load 'ispell
  (let* ((login    (user-login-name))
         (nix-path (format "/etc/profiles/per-user/%s/share/hunspell" login)))

    ;; DICPATH: used by a Hunspell without the withDicts wrapper.
    (setenv "DICPATH" nix-path)

    ;; pl_PL -- UTF-8, converted at build time (hunspellPlUtf8).
    (when (file-exists-p (expand-file-name "pl_PL.aff" nix-path))
      (add-to-list 'ispell-hunspell-dict-paths-alist
                   (list "pl_PL"
                         (expand-file-name "pl_PL.aff" nix-path))))

    ;; en_GB-large -- UTF-8 upstream, installed as en_GB.aff/.dic.
    (when (file-exists-p (expand-file-name "en_GB.aff" nix-path))
      (add-to-list 'ispell-hunspell-dict-paths-alist
                   (list "en_GB-large"
                         (expand-file-name "en_GB.aff" nix-path)))))

  ;; Choose among what is installed, then rebuild ispell's state; a
  ;; combined dictionary needs `ispell-hunspell-add-multi-dic' too.
  (let ((combined (my/spell--use-installed-dictionaries)))
    (ispell-set-spellchecker-params)
    (when (and combined (string-match-p "," combined))
      (ispell-hunspell-add-multi-dic combined))))

;; ============================================================
;; E6 — SUPPRESS "Save <personal dictionary>?" ON QUIT
;; ============================================================

(defun my/spell--personal-dict-buffer-p ()
  "Return t if current buffer is the hunspell personal dictionary.
Not for a buffer opened to edit it on purpose: its unsaved changes are
the user's, and quitting asks about them."
  (when (and (buffer-file-name) (not my/spell--editing-dictionary))
    (string= (file-truename (buffer-file-name))
             (file-truename ispell-personal-dictionary))))

(add-to-list 'save-some-buffers-action-alist
             (list #'my/spell--personal-dict-buffer-p
                   (lambda (_buf) (ignore))
                   "skip hunspell personal dictionary"))

;; ============================================================
;; DESKTOP-RESTORE GUARD
;; ============================================================
;; During desktop-restore Emacs opens all saved .org buffers.
;; Each fires org-mode-hook -> flyspell-mode -> flyspell-mode-on
;; -> Hunspell starts N times -> 17-second hang.
;;
;; Solution: while this flag is t, the flyspell-mode advice below
;; enables the mode variable but skips flyspell-mode-on (which is
;; the function that actually starts the subprocess).  Once the session
;; is up, the flag is cleared and flyspell-mode-on is called on every
;; open buffer, which is the first moment Hunspell is allowed to start.
;;
;; That "once the session is up" moment comes from
;; `my/desktop-after-startup-hook' (01-ui.el), which fires whether or not
;; a desktop was restored.  This module registers itself at the bottom of
;; this section.  It used to be 15-workspace.el that made the call, which
;; meant that removing the dashboard module silently left spell checking
;; disabled for the whole session.  Nothing outside this file decides
;; when spelling starts any more.

(defvar my/flyspell-desktop-restoring t
  "Non-nil during desktop-restore to prevent Hunspell from starting.
Set to nil by `my/flyspell--recheck-all-buffers' after restore.")

(defun my/flyspell--block-during-restore (orig-fun &rest args)
  "Advice around `flyspell-mode'.
When `my/flyspell-desktop-restoring' is non-nil and ARG enables
the mode (arg >= 0 or nil), enable the mode variable but skip
`flyspell-mode-on' to prevent Hunspell from starting during
desktop-restore.  Pass through normally in all other cases."
  (let ((arg (car args)))
    (if (and my/flyspell-desktop-restoring
             (or (null arg) (> arg 0)))
        ;; Enable mode flag silently, skip the subprocess start.
        (setq flyspell-mode t)
      ;; Normal path: call the real flyspell-mode.
      (apply orig-fun args))))

(advice-add 'flyspell-mode :around #'my/flyspell--block-during-restore)

(defun my/flyspell--recheck-all-buffers ()
  "Clear the desktop-restore guard and activate flyspell on all live buffers.
Runs from `my/desktop-after-startup-hook', and from `my/toggle-flyspell'
when the guard is still up.  This is the first moment Hunspell is
allowed to start.

Each buffer is re-enabled with `(flyspell-mode 1)' rather than a bare
`flyspell-mode-on': the minor-mode wrapper installs the same
per-buffer hooks, and on failure turns the mode off with a message
instead of leaving it reported as on with nothing checking.  A failure
in one buffer is reported and does not stop the others.

Buffers where flyspell could not be enabled are counted and reported
once through `display-warning': a broken dictionary breaks every
buffer at once, and an echo-area message per buffer scrolls away
unread."
  (setq my/flyspell-desktop-restoring nil)
  ;; Remove the blocking advice — no longer needed after first restore.
  (advice-remove 'flyspell-mode #'my/flyspell--block-during-restore)
  ;; Re-enable flyspell in every buffer that had it switched on during
  ;; restore (mode variable is t, but the subprocess never started and
  ;; the per-buffer hooks were never installed).
  (let ((failed '()))
    (dolist (buf (buffer-list))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when (and flyspell-mode
                     (derived-mode-p 'text-mode 'org-mode))
            (condition-case-unless-debug err
                (flyspell-mode 1)
              (error
               (message "03-spelling: flyspell failed in %s: %s"
                        (buffer-name) (error-message-string err))))
            ;; `flyspell-mode' turns itself off when enabling fails.
            (unless flyspell-mode
              (push (buffer-name) failed))))))
    (when failed
      (display-warning
       'my/spelling
       (format "Spell checking could not start in %d buffer(s): %s.
Errors are NOT underlined there.  See *Messages* for the Hunspell output
(an `iconv' error means a dictionary that is not UTF-8)."
               (length failed)
               (string-join (nreverse failed) ", "))
       :error))))

;; Unblock as soon as the session is ready.  `my/desktop-after-startup-hook'
;; is defined in 01-ui.el, which init.el loads first; the guard keeps this
;; working even if that module is ever absent, in which case spelling
;; simply stays blocked until `my/flyspell--recheck-all-buffers' is run by
;; hand -- which is visible, rather than silent.
;;
;; Depth -90 puts the release ahead of every consumer added at the default
;; depth.  `add-hook' prepends, so without it 15-workspace.el (loaded
;; later) ran first, and an error in the dashboard used to stop the
;; release from ever running.  01-ui.el now also isolates each consumer's
;; errors; the depth keeps spelling independent of that as well.
(if (boundp 'my/desktop-after-startup-hook)
    (add-hook 'my/desktop-after-startup-hook #'my/flyspell--recheck-all-buffers -90)
  (message "03-spelling: no `my/desktop-after-startup-hook'; Hunspell stays blocked"))

;; ============================================================
;; SAFE HELPER: Check if process is alive
;; ============================================================

(defun my/spell-check-can-run-p ()
  "Return t if flyspell-mode is on AND Hunspell process is running."
  (and flyspell-mode
       (boundp 'ispell-process)
       (process-live-p ispell-process)))

;; ============================================================
;; PROCESS STARTER: Ensure Hunspell is running and ready
;; ============================================================

(defun my/spell-ensure-process ()
  "Ensure Hunspell is running.  No-op in steady state.
Returns t if process is ready, nil if it could not be started."
  (unless (and (boundp 'ispell-process) (process-live-p ispell-process))
    (message "Starting Hunspell…")
    (condition-case nil (ispell-set-spellchecker-params) (error nil))
    (condition-case nil (ispell-init-process)            (error nil))
    (sit-for 0.3))
  (and (boundp 'ispell-process)
       (process-live-p ispell-process)))

;; ============================================================
;; HELPER: Find previous spelling error
;; ============================================================

(defun my/flyspell-goto-previous-error ()
  "Go to previous spelling error.  Returns position or nil."
  (let ((min (point-min))
        (found nil))
    (save-excursion
      (backward-word 1)
      (while (and (> (point) min) (not found))
        (let ((overlays (overlays-at (point))))
          (if (seq-some #'flyspell-overlay-p overlays)
              (setq found (point))
            (backward-word 1)))))
    (when found
      (goto-char found)
      found)))

;; ============================================================
;; SPELL CORRECTION - Returns to start position
;; ============================================================

(defun my/spell-correct-previous ()
  "Jump to previous spelling error, show correction menu, return to start."
  (interactive)
  (let ((start-pos (point)))
    (condition-case err
        (cond
         ((not flyspell-mode)
          (message "⚠️ Spell-checking not active. Toggle with C-c n T"))
         ((not (my/spell-ensure-process))
          (message "⚠️ Could not start Hunspell. Check dictionary configuration."))
         ((not (my/flyspell-goto-previous-error))
          (message "No spelling errors found backward from cursor"))
         (t
          (flyspell-correct-wrapper)
          (goto-char start-pos)))
      (error
       (goto-char start-pos)
       (message "Error in spell correction: %s" (error-message-string err))))))

;; ============================================================
;; ADD WORD TO PERSONAL DICTIONARY - Returns to start position
;; ============================================================

(defun my/spell-add-previous-to-dict ()
  "Add previous misspelled word to personal dictionary, return to start."
  (interactive)
  (let ((start-pos (point)))
    (condition-case err
        (cond
         ((not flyspell-mode)
          (message "⚠️ Spell-checking not active. Toggle with C-c n T"))
         ((not (my/spell-ensure-process))
          (message "⚠️ Could not start Hunspell. Check dictionary configuration."))
         ((not (my/flyspell-goto-previous-error))
          (message "No spelling errors found"))
         (t
          (let ((word (downcase (thing-at-point 'word t))))
            (when word
              (ispell-send-string (concat "*" word "\n"))
              (setq ispell-pdict-modified-p '(t))
              (ispell-pdict-save t t)
              (dolist (o (overlays-at (point)))
                (when (flyspell-overlay-p o)
                  (delete-overlay o)))
              (goto-char start-pos)
              (message "✓ Added to personal dictionary: %s" word)))))
      (error
       (goto-char start-pos)
       (message "Error adding word: %s" (error-message-string err))))))

;; ============================================================
;; TOGGLE FLYSPELL MODE
;; ============================================================

(defun my/toggle-flyspell ()
  "Toggle flyspell-mode on/off.
If the desktop-restore guard is still up, toggling could not work:
the mode would be reported as on while nothing is checked.  In that
case the guard is released instead, which re-enables flyspell in
every open text buffer."
  (interactive)
  (cond
   (my/flyspell-desktop-restoring
    (my/flyspell--recheck-all-buffers)
    (message "✓ Spell-checking released (startup guard was still active)"))
   (flyspell-mode
    (flyspell-mode -1) (message "✗ Spell-checking OFF"))
   (t
    (flyspell-mode 1)  (message "✓ Spell-checking ON"))))

;; ============================================================
;; CHECK VISIBLE REGION (manual, fast)
;; ============================================================

(defun my/spell-check-visible ()
  "Check spelling in visible region only."
  (interactive)
  (condition-case err
      (progn
        (unless flyspell-mode (flyspell-mode 1) (message "✓ Flyspell enabled"))
        (message "Checking visible region...")
        (flyspell-region (window-start) (window-end))
        (message "✓ Visible region checked"))
    (error (message "Error checking visible region: %s" (error-message-string err)))))

;; ============================================================
;; CHECK ENTIRE BUFFER (manual, slower)
;; ============================================================

(defun my/spell-check-buffer-full ()
  "Check spelling in ENTIRE buffer.  May take a few seconds on large files."
  (interactive)
  (condition-case err
      (let ((word-count (count-words (point-min) (point-max))))
        (unless flyspell-mode (flyspell-mode 1) (message "✓ Flyspell enabled"))
        (message "Checking entire buffer (%d words)..." word-count)
        (flyspell-buffer)
        (message "✓ Buffer checked (%d words)" word-count))
    (error (message "Error checking buffer: %s" (error-message-string err)))))

;; ============================================================
;; FLYSPELL CONFIGURATION — INCREMENTAL CHECKING
;; ============================================================

(use-package flyspell
  :ensure nil
  :hook ((text-mode . flyspell-mode)
         (org-mode  . flyspell-mode))
  :config
  (setq flyspell-issue-message-flag nil)
  (setq flyspell-issue-welcome-flag nil)
  (setq flyspell-delay 3)
  (setq flyspell-delete-overlays nil)
  (setq flyspell-consider-dash-as-word-delimiter-flag t))

;; ============================================================
;; ENSURE FLYSPELL STAYS ON (priority 100 — runs last)
;; ============================================================

;; Named rather than a lambda (review B2), so that
;; (remove-hook 'org-mode-hook #'my/spell--ensure-on) can undo it and
;; `describe-variable' shows what runs.
(defun my/spell--ensure-on ()
  "Turn flyspell on in this buffer if something earlier turned it off."
  (unless flyspell-mode
    (flyspell-mode 1)))

(add-hook 'org-mode-hook #'my/spell--ensure-on 100)
(add-hook 'text-mode-hook #'my/spell--ensure-on 100)

;; ============================================================
;; PREVENT OVERLAY DELETION
;; ============================================================

(defun my/flyspell-prevent-overlay-deletion (orig-fun &rest args)
  "Prevent flyspell from deleting overlays unnecessarily."
  (when (and flyspell-mode (called-interactively-p 'any))
    (apply orig-fun args)))

(advice-add 'flyspell-delete-all-overlays
            :around #'my/flyspell-prevent-overlay-deletion)

;; ============================================================
;; FLYSPELL-CORRECT: Interactive corrections via Vertico
;; ============================================================

(use-package flyspell-correct
  :ensure t
  :after flyspell
  :config
  (setq flyspell-correct-interface #'flyspell-correct-completing-read)
  (define-key flyspell-mode-map (kbd "C-;") 'flyspell-correct-wrapper))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c f b") 'my/spell-check-visible)

;; The two most used commands of the whole configuration (keyfreq:
;; correct previous second, add to dictionary fourth), each with a
;; short binding of its own.  Moved here from 08-keybindings.el
;; (2026-10-16e) so that the keys go with the module.
(global-set-key (kbd "C-c s") 'my/spell-correct-previous)    ; Correct previous word
(global-set-key (kbd "C-c S") 'my/spell-add-previous-to-dict) ; Add previous to dict

;; ============================================================
;; MENU
;; ============================================================
;; Inserted from here rather than declared in 12-transient.el, so that
;; without this module the menus lose these entries and nothing else.
;;
;; Tools (C-c n t): the Spelling column, first, before Integrations.
;; Main menu (C-c n): "s" and "a" again, after Settings.  :transient t
;; keeps the menu open, for correcting several words in a row; the
;; direct keys above are for the single fix.
(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-insert)
    (my/transient-insert
     'my/notes-tools-menu '(0 0)
     ["Spelling"
      ("s" "Correct previous"  my/spell-correct-previous  :transient t)
      ("a" "Add to dict"       my/spell-add-previous-to-dict :transient t)
      ("S" "Check visible"     my/spell-check-visible)
      ("b" "Check full buffer" my/spell-check-buffer-full)
      ("T" "Toggle spellcheck" my/toggle-flyspell)
      ("e" "Edit personal dict" my/spell-edit-personal-dictionary)]))
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-menu ","
                         '("s" "Correct previous" my/spell-correct-previous
                           :transient t))
    (my/transient-append 'my/notes-menu "s"
                         '("a" "Add to dict" my/spell-add-previous-to-dict
                           :transient t))))

(provide '03-spelling)
;;; 03-spelling.el ends here
