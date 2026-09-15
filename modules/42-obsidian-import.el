;;; 42-obsidian-import.el --- Import notes written in Obsidian -*- lexical-binding: t; -*-
;;; Commentary:
;; A front end for tools/obsidian_import.py, which pulls notes written in
;; Obsidian on the phone into the org/Denote silos: daily notes are merged
;; into the journal note for that date under an `* Obsidian' heading,
;; everything else lands in ~/notes/inbox for review by
;; 25-inbox-review.el.  The markdown file then moves to
;; Imported2Emacs/<year> in the vault, which is also what keeps a second
;; run from importing it twice.
;;
;; WHY THE CONVERSION IS NOT WRITTEN IN ELISP
;; ------------------------------------------
;; The conversion itself is pandoc's, and the flags it needs were found
;; the hard way during the 2026-07 migration.  Re-implementing markdown
;; parsing here would mean re-discovering them.  The module therefore
;; owns only what Emacs is better at: knowing which buffers are dirty,
;; and putting the result in front of the user.
;;
;; WHY BUFFERS ARE SAVED FIRST
;; ---------------------------
;; The script appends to journal files that are very likely open right
;; now.  A buffer holding unsaved changes to today's journal would
;; overwrite the imported material the next time it is saved -- the same
;; failure mode the auto-commit in 07-git.el guards against, and it is
;; guarded the same way: save every modified note buffer before the
;; process starts, revert the affected files after it ends.
;;
;; The list of files to revert comes from the script's own --touched
;; output rather than from a timer or a file-notify watch.  The script
;; knows exactly what it wrote; anything else would be a guess about it.
;;
;; MENU (C-c n t o)
;; ----------------
;;   d  dry run -- reports what would happen, writes nothing
;;   i  import -- writes, copies attachments, moves the markdown
;;   l  show the last report again
;;   o  open the vault inbox folder in Dired
;;
;; Requires pandoc and PyYAML on the system running Emacs; both are
;; checked before the process starts, and a missing one is reported as a
;; message rather than as a backtrace.
;;
;; Docs: ~/.emacs.d/function_helper.org::#obsidian-import

;;; Code:

(require 'subr-x)   ; string-join, string-trim
(require 'transient nil t)

;; ============================================================
;; SETTINGS
;; ============================================================

;; Named `my/obsidian' rather than `my/obsidian-import': the command
;; below is `my/obsidian-import', and one symbol cannot be both a
;; customization group and a command.  `hooks/lint.py' reports the
;; collision as a duplicate definition, which is what it is.
(defgroup my/obsidian nil
  "Import notes written in Obsidian into the notes tree."
  :group 'my/notes)

(defcustom my/obsidian-vault-directory
  (expand-file-name "~/syncthing/Obsidian/")
  "Obsidian vault shared with the phone by Syncthing."
  :type 'directory
  :group 'my/obsidian)

(defcustom my/obsidian-inbox-subdir "10 Emacs Inbox"
  "Folder inside the vault the script reads, relative to its root.
Matches the New file location of Obsidian's Daily notes plugin; the
script has the same default and is told this value explicitly so that
changing it in one place is enough."
  :type 'string
  :group 'my/obsidian)

(defcustom my/obsidian-import-script
  (expand-file-name "tools/obsidian_import.py" user-emacs-directory)
  "Path to obsidian_import.py."
  :type 'file
  :group 'my/obsidian)

(defcustom my/obsidian-python "python3"
  "Python interpreter used to run the import script."
  :type 'string
  :group 'my/obsidian)

(defcustom my/obsidian-import-settle 60
  "Skip markdown files modified in the last N seconds.
Syncthing may still be writing a note that the phone saved a moment
ago; importing half of one and moving it out of the inbox would lose
the other half.  Zero disables the check."
  :type 'integer
  :group 'my/obsidian)

(defconst my/obsidian-import-buffer "*Obsidian import*"
  "Buffer holding the report of the last run.")

(defvar my/obsidian-import--touched-file nil
  "Temporary file the running process writes its touched paths to.")

;; ============================================================
;; PRECONDITIONS
;; ============================================================

(defun my/obsidian-import--check ()
  "Return nil when everything needed is present, else a message string."
  (cond
   ((not (file-exists-p my/obsidian-import-script))
    (format "Import script not found: %s" my/obsidian-import-script))
   ((not (executable-find my/obsidian-python))
    (format "Python not found: %s" my/obsidian-python))
   ((not (executable-find "pandoc"))
    "pandoc not found on PATH")
   ((not (file-directory-p my/obsidian-vault-directory))
    (format "Vault not found: %s" my/obsidian-vault-directory))
   ((let ((proc (get-buffer-process my/obsidian-import-buffer)))
      (and proc (process-live-p proc)))
    "An import is already running")
   (t nil)))

;; ============================================================
;; BUFFER HYGIENE
;; ============================================================

(defun my/obsidian-import--notes-root ()
  "Return the notes tree, falling back when 00-core.el is absent."
  (expand-file-name (if (boundp 'my-notes-dir) my-notes-dir "~/notes/")))

(defun my/obsidian-import--save-notes ()
  "Save every modified buffer visiting a file in the notes tree.
Returns the number of buffers saved, for the report."
  (let ((root (my/obsidian-import--notes-root))
        (saved 0))
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (and buffer-file-name
                   (buffer-modified-p)
                   (string-prefix-p root (expand-file-name buffer-file-name)))
          (save-buffer)
          (setq saved (1+ saved)))))
    saved))

(defun my/obsidian-import--revert (paths)
  "Revert buffers visiting PATHS, leaving modified ones alone.
A modified buffer here would mean something was typed into a note while
the script was writing to it; reverting would throw that away, so it is
reported instead."
  (let ((skipped '()))
    (dolist (path paths)
      (let ((buf (get-file-buffer (expand-file-name path))))
        (when buf
          (with-current-buffer buf
            (if (buffer-modified-p)
                (push (buffer-name) skipped)
              (revert-buffer t t t))))))
    skipped))

(defun my/obsidian-import--touched-paths ()
  "Return the paths the last run wrote, from its --touched file."
  (when (and my/obsidian-import--touched-file
             (file-exists-p my/obsidian-import--touched-file))
    (with-temp-buffer
      (insert-file-contents my/obsidian-import--touched-file)
      (split-string (buffer-string) "\n" t))))

;; ============================================================
;; RUNNING
;; ============================================================

(defun my/obsidian-import--sentinel (proc event)
  "Finish the run: show the report, revert what changed."
  (when (memq (process-status proc) '(exit signal))
    (let ((write (process-get proc 'write))
          (status (process-exit-status proc)))
      (with-current-buffer (process-buffer proc)
        (goto-char (point-min))
        ;; The report is an org table; org-mode makes it readable and
        ;; leaves the buffer navigable with the usual keys.
        (when (fboundp 'org-mode) (org-mode))
        (setq buffer-read-only t))
      (display-buffer my/obsidian-import-buffer)
      (if (/= status 0)
          (message "Obsidian import failed (%s) - see %s"
                   (string-trim event) my/obsidian-import-buffer)
        (let* ((paths (and write (my/obsidian-import--touched-paths)))
               (skipped (and paths (my/obsidian-import--revert paths))))
          (when my/obsidian-import--touched-file
            (ignore-errors (delete-file my/obsidian-import--touched-file))
            (setq my/obsidian-import--touched-file nil))
          (cond
           (skipped
            (message "Import done; %d note(s) reverted, modified buffers left alone: %s"
                     (- (length paths) (length skipped))
                     (string-join skipped ", ")))
           (write
            (message "Import done: %d note(s) written" (length paths)))
           (t (message "Dry run finished - nothing written"))))))))

(defun my/obsidian-import--run (write)
  "Run the import script.  With WRITE non-nil it actually writes."
  (let ((problem (my/obsidian-import--check)))
    (when problem (user-error "%s" problem)))
  (let* ((saved (my/obsidian-import--save-notes))
         (buffer (get-buffer-create my/obsidian-import-buffer))
         (args (list "--vault" (expand-file-name my/obsidian-vault-directory)
                     "--notes" (my/obsidian-import--notes-root)
                     "--settle" (number-to-string my/obsidian-import-settle))))
    (when write
      (setq my/obsidian-import--touched-file
            (make-temp-file "obsidian-import-touched"))
      (setq args (append args (list "--write" "--touched"
                                    my/obsidian-import--touched-file))))
    (with-current-buffer buffer
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert (format "Running %s %s\n\n" my/obsidian-python
                      (string-join args " ")))
      (when (> saved 0)
        (insert (format "Saved %d modified note buffer(s) first.\n\n" saved))))
    (let ((proc (make-process
                 :name "obsidian-import"
                 :buffer buffer
                 :command (append (list my/obsidian-python
                                        (expand-file-name
                                         my/obsidian-import-script))
                                  args)
                 :noquery t
                 :sentinel #'my/obsidian-import--sentinel)))
      (process-put proc 'write write))
    (message "Obsidian import: %s..." (if write "importing" "dry run"))))

;;;###autoload
(defun my/obsidian-import-dry-run ()
  "Report what an import would do, without writing anything."
  (interactive)
  (my/obsidian-import--run nil))

;;;###autoload
(defun my/obsidian-import ()
  "Import notes from the Obsidian inbox into the notes tree."
  (interactive)
  (my/obsidian-import--run t))

;;;###autoload
(defun my/obsidian-import-show-report ()
  "Show the report of the last run."
  (interactive)
  (if (get-buffer my/obsidian-import-buffer)
      (display-buffer my/obsidian-import-buffer)
    (message "No import has been run in this session")))

;;;###autoload
(defun my/obsidian-import-open-inbox ()
  "Open the vault folder the phone writes into."
  (interactive)
  (let ((dir (expand-file-name my/obsidian-inbox-subdir
                               my/obsidian-vault-directory)))
    (if (file-directory-p dir)
        (dired dir)
      (message "Vault inbox not found: %s" dir))))

;; ============================================================
;; MENU  (C-c n t o)
;; Docs: ~/.emacs.d/function_helper.org::#menu-obsidian-import
;; ============================================================

(transient-define-prefix my/obsidian-import-menu ()
  "Import notes written in Obsidian on the phone."
  [["Run"
    ("d" "Dry run (writes nothing)" my/obsidian-import-dry-run)
    ("i" "Import" my/obsidian-import)]
   ["Look"
    ("l" "Last report" my/obsidian-import-show-report)
    ("o" "Vault inbox in Dired" my/obsidian-import-open-inbox)]
   [("q" "Quit" transient-quit-one)]])

;; Appended rather than declared in 12-transient.el, so that deleting
;; this file removes the entry with it -- same pattern as 40-markdown.el.
(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-tools-menu "z"
                         '("o" "Obsidian import →" my/obsidian-import-menu))))

(provide '42-obsidian-import)
;;; 42-obsidian-import.el ends here
