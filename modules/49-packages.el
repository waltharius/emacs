;;; 49-packages.el --- Upgrade the installed packages, with a copy to go back to -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; MyPKS-Switch: my/packages-mode
;; MyPKS-Writes: elpa-backups/ and elpa-replaced-*/ beside the package folder

;;; Commentary:
;; package.el, Emacs's own package manager, installs whatever the
;; archives hold at the time and keeps no record to go back to: an
;; upgrade that breaks something cannot be undone from within it.  This
;; module upgrades the installed packages in one step with that missing
;; half:
;;
;;   1. the package list is refreshed and the packages with a newer
;;      version in an archive are listed -- name, installed version, new
;;      version -- and nothing happens without a yes;
;;   2. the whole package folder (`package-user-dir', ~/.emacs.d/elpa)
;;      is copied first, to `my/packages-backup-directory', a folder per
;;      upgrade named by its date and time; beside the copy, a text file
;;      of the same name ending in -RESTORE.txt says how to go back,
;;      from Emacs or -- when Emacs no longer starts -- from a shell;
;;   3. each package is upgraded with package.el's own `package-upgrade'
;;      (Emacs 29); one that fails does not stop the others.
;;      `package-upgrade' deletes the old version before it installs the
;;      new one, so a package whose install failed may be gone -- the
;;      report says so, and the copy has it;
;;   4. a report lists what changed, what failed, where the copy is and
;;      how to go back, and advises a restart and the weekly check
;;      (bash hooks/check-weekly).
;;
;; Going back (`my/packages-restore'): a copy is chosen; the current
;; package folder is MOVED aside, to elpa-replaced-DATE beside it, never
;; deleted; the copy is copied into its place; Emacs is to be restarted.
;; Nothing here deletes a copy: they are listed with their size, and
;; removed by hand when no longer wanted.
;;
;; Built-in packages and packages installed from version control
;; (`package-vc') are left alone: the first come with Emacs, the second
;; follow their own repository.
;;
;; Pinned versions -- a lock file like flake.lock -- are another matter,
;; for a change of package manager (Elpaca, straight.el) or packages
;; from Nix: BACKLOG.org, *Packages pinned*.
;;
;; MENU: the Maintenance menu (C-c n !), column "Emacs packages":
;;   U  upgrade packages (copy first)    B  go back to a copy
;; 26-maintenance.el owns that menu; without it the entries are skipped,
;; and the commands remain for M-x.
;;
;; Docs: ~/.emacs.d/function_helper.org::#packages-upgrade

;;; Code:

(require 'package)
(require 'seq)
(require 'subr-x)

(defgroup my/packages nil
  "Upgrading the installed packages, with a copy to go back to."
  :tag "Package upgrades"
  :group 'mypks-tools)

(defcustom my/packages-backup-directory
  (expand-file-name "elpa-backups/"
                    (file-name-directory (directory-file-name package-user-dir)))
  "Folder holding a copy of the package folder per upgrade.
By default beside the package folder (`package-user-dir'), whose copies
they are -- installation, like it, not state: not in the settings
folder, which may be synced, nor in the notes; a copy is as large as
the package folder.  Not inside the package folder, which a restore
replaces."
  :type 'directory
  :group 'my/packages)

(defconst my/packages-report-buffer "*Package upgrade*"
  "Buffer of the last upgrade's report.")

(defconst my/packages--backup-regexp
  "\\`elpa-[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}-[0-9]\\{6\\}\\'"
  "Names of the copies this module makes.")

;; ============================================================
;; WHAT CAN BE UPGRADED
;; ============================================================

(defun my/packages--newest-in-archives (name)
  "Return the newest description of package NAME in the archives, or nil."
  (car (sort (copy-sequence (cdr (assq name package-archive-contents)))
             (lambda (a b) (version-list-< (package-desc-version b)
                                           (package-desc-version a))))))

(defun my/packages--upgradable ()
  "Return (NAME INSTALLED NEWEST) for each package an archive has newer.
INSTALLED and NEWEST are package descriptions.  Built-in packages are
not in `package-alist'; packages installed from version control are
skipped."
  (let ((found '()))
    (dolist (entry package-alist)
      (let* ((installed (cadr entry))
             (newest (my/packages--newest-in-archives (car entry))))
        (when (and newest
                   (not (eq (package-desc-kind installed) 'vc))
                   (version-list-< (package-desc-version installed)
                                   (package-desc-version newest)))
          (push (list (car entry) installed newest) found))))
    (sort found (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b)))))))

(defun my/packages--version (desc)
  "Return the version of package description DESC as a string."
  (package-version-join (package-desc-version desc)))

;; ============================================================
;; COPIES
;; ============================================================

(defun my/packages--elpa ()
  "Return the package folder as a directory name."
  (file-name-as-directory (expand-file-name package-user-dir)))

(defun my/packages--backups ()
  "Return the copies made by this module, newest first, as directory names."
  (let ((dir (file-name-as-directory (expand-file-name my/packages-backup-directory))))
    (when (file-directory-p dir)
      (mapcar #'file-name-as-directory
              (sort (seq-filter #'file-directory-p
                                (directory-files dir t my/packages--backup-regexp))
                    (lambda (a b) (string> a b)))))))

(defun my/packages--size (dir)
  "Return the size of the files under DIR, in bytes."
  (apply #'+ (mapcar (lambda (f) (or (file-attribute-size (file-attributes f)) 0))
                     (directory-files-recursively dir "" nil))))

(defun my/packages--restore-text (backup)
  "Return how to go back to BACKUP, for the report and RESTORE.txt."
  (let ((elpa (directory-file-name (my/packages--elpa)))
        (copy (directory-file-name backup)))
    (format "How to go back to the packages as they were before this upgrade

From Emacs: M-x my/packages-restore (C-c n ! B), choose
  %s
then restart Emacs.  The current package folder is moved aside, not
deleted.

From a shell, when Emacs no longer starts -- quit Emacs first:
  mv %s %s-replaced-$(date +%%F-%%H%%M%%S)
  cp -a %s %s
then start Emacs.
"
            (file-name-nondirectory copy)
            (shell-quote-argument elpa) (shell-quote-argument elpa)
            (shell-quote-argument copy) (shell-quote-argument elpa))))

(defun my/packages--make-backup ()
  "Copy the package folder to a new folder of the backups; return it.
Also writes how to go back, in a text file beside the copy."
  (let* ((root (file-name-as-directory (expand-file-name my/packages-backup-directory)))
         (backup (file-name-as-directory
                  (expand-file-name (format-time-string "elpa-%Y-%m-%d-%H%M%S") root))))
    (when (file-exists-p backup)
      (user-error "A copy of that name exists already: %s" backup))
    (make-directory root t)
    ;; Copied under a name the list of copies does not match, renamed
    ;; once complete: a copy cut short (a full disk, Emacs closed) is
    ;; never offered for going back (outside audits of 2026-10-24).
    ;; COPY-CONTENTS: the folder's contents become the copy, not a
    ;; subfolder elpa/ inside it.
    (let ((partial (concat (directory-file-name backup) ".partial")))
      (copy-directory (my/packages--elpa) partial t t t)
      (rename-file partial (directory-file-name backup)))
    ;; Beside the copy, not in it: what is in it goes back into the
    ;; package folder on a restore.
    (with-temp-file (concat (directory-file-name backup) "-RESTORE.txt")
      (insert (my/packages--restore-text backup)))
    backup))

;; ============================================================
;; UPGRADE
;; ============================================================

(defun my/packages--write-report (backup upgraded failed)
  "Show the report of an upgrade into BACKUP: UPGRADED and FAILED.
UPGRADED is a list of (NAME OLD NEW), FAILED of (NAME . MESSAGE)."
  (with-current-buffer (get-buffer-create my/packages-report-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format-time-string "Package upgrade, %Y-%m-%d %H:%M\n\n"))
      (insert (format "Upgraded (%d):\n" (length upgraded)))
      (dolist (u upgraded)
        (insert (format "  %-28s %s -> %s\n" (nth 0 u) (nth 1 u) (nth 2 u))))
      (when failed
        (insert (format "\nFailed (%d) -- package.el deletes the old version before installing\nthe new one, so these may be missing now; the copy has them:\n"
                        (length failed)))
        (dolist (f failed)
          (insert (format "  %-28s %s\n" (car f) (cdr f)))))
      (insert (format "\nCopy of the package folder before the upgrade:\n  %s\n\n" backup))
      (insert "Next: restart Emacs, then run the weekly check in the\n"
              "configuration folder: bash hooks/check-weekly\n\n")
      (insert (my/packages--restore-text backup)))
    (special-mode)
    (goto-char (point-min)))
  (display-buffer my/packages-report-buffer))

;;;###autoload
(defun my/packages-upgrade ()
  "Upgrade the installed packages that have a newer version, copy first.
Lists them and asks; on yes, copies the package folder to
`my/packages-backup-directory', upgrades each, and reports what changed
and how to go back."
  (interactive)
  (unless (fboundp 'package-upgrade)
    (user-error "Needs Emacs 29 or newer (package-upgrade)"))
  (message "Refreshing the package list...")
  (package-refresh-contents)
  (let ((todo (my/packages--upgradable)))
    (if (null todo)
        (message "Every package is up to date")
      (when (yes-or-no-p
             (format "Upgrade %d package(s): %s?  The package folder is copied to %s first. "
                     (length todo)
                     (mapconcat (lambda (p) (format "%s %s->%s" (car p)
                                                    (my/packages--version (nth 1 p))
                                                    (my/packages--version (nth 2 p))))
                                todo ", ")
                     (abbreviate-file-name my/packages-backup-directory)))
        (let ((backup (my/packages--make-backup))
              (upgraded '())
              (failed '()))
          (dolist (p todo)
            (condition-case err
                (progn
                  (package-upgrade (car p))
                  (push (list (car p) (my/packages--version (nth 1 p))
                              (my/packages--version (nth 2 p)))
                        upgraded))
              (error (push (cons (car p) (error-message-string err)) failed))))
          (my/packages--write-report backup (nreverse upgraded) (nreverse failed))
          (message "Packages: %d upgraded, %d failed; copy in %s -- restart Emacs"
                   (length upgraded) (length failed) (abbreviate-file-name backup)))))))

;; ============================================================
;; GOING BACK
;; ============================================================

;;;###autoload
(defun my/packages-restore (backup)
  "Put the packages back as they were in BACKUP, a copy of this module.
The current package folder is moved aside to elpa-replaced-DATE beside
it, never deleted; BACKUP is copied into its place.  Restart Emacs
afterwards."
  (interactive
   (let ((copies (my/packages--backups)))
     (unless copies
       (user-error "No copies in %s" my/packages-backup-directory))
     (list (completing-read
            "Go back to the packages of: "
            (mapcar (lambda (c) (cons (file-name-nondirectory (directory-file-name c)) c))
                    copies)
            nil t nil nil
            (file-name-nondirectory (directory-file-name (car copies)))))))
  (let* ((copies (my/packages--backups))
         (chosen (seq-find (lambda (c)
                             (or (equal c (file-name-as-directory backup))
                                 (equal (file-name-nondirectory (directory-file-name c))
                                        backup)))
                           copies)))
    (unless chosen
      (user-error "Not a copy made by this module: %s" backup))
    (let* ((elpa (directory-file-name (my/packages--elpa)))
           (aside (concat elpa (format-time-string "-replaced-%Y-%m-%d-%H%M%S"))))
      (when (yes-or-no-p
             (format "Replace the packages with the copy %s?  The current folder is moved to %s. "
                     (file-name-nondirectory (directory-file-name chosen))
                     (abbreviate-file-name aside)))
        (when (file-exists-p aside)
          (user-error "%s exists already" aside))
        (when (file-exists-p elpa)
          (rename-file elpa aside))
        (copy-directory chosen elpa t t nil)
        (message "Packages back as in %s; the previous ones in %s -- restart Emacs"
                 (file-name-nondirectory (directory-file-name chosen))
                 (abbreviate-file-name aside))))))

;;;###autoload
(defun my/packages-list-backups ()
  "Show the copies of the package folder, newest first, with their size."
  (interactive)
  (let ((copies (my/packages--backups)))
    (if (null copies)
        (message "No copies in %s" my/packages-backup-directory)
      (message "%s"
               (mapconcat (lambda (c)
                            (format "%s (%s)"
                                    (file-name-nondirectory (directory-file-name c))
                                    (file-size-human-readable (my/packages--size c))))
                          copies ", ")))))

;; ============================================================
;; SWITCH AND MENU
;; ============================================================

(defconst my/packages--menu-entries
  '((insert my/notes-maintenance-menu (0 2)
            ["Emacs packages"
             ("U" "Upgrade (copy first)" my/packages-upgrade)
             ("B" "Go back to a copy"    my/packages-restore)
             ("L" "List the copies"      my/packages-list-backups)]))
  "Menu entries of this module, for `my/transient-entries'.
A column of the Maintenance menu of 26-maintenance.el, before its third
column, Quit.  A coordinate, not the key q: put before the key, the
column did not appear (tried with transient 0.13); the menu's three
columns form one group, (0 0) to (0 2).")

(define-minor-mode my/packages-mode
  "Package upgrades as a module: the entries in the Maintenance menu.
Off, they are gone; the commands remain for M-x.  Customize saves the
position in this machine's settings."
  :global t
  :init-value t
  :group 'my/packages
  (with-eval-after-load '12-transient
    (when (fboundp 'my/transient-entries)
      (my/transient-entries my/packages-mode my/packages--menu-entries))))

(my/packages-mode (if my/packages-mode 1 -1))

(provide '49-packages)
;;; 49-packages.el ends here
