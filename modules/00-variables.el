;;; 00-variables.el --- Central configuration variables -*- lexical-binding: t; -*-
;;
;; Description: Global variables and paths used across all modules
;;              LOAD THIS FIRST before any other module!
;;
;;; Commentary:
;;
;; Single source of truth for all paths, settings, and customizable variables.
;; Edit this file to change system-wide settings.
;;
;; Benefits:
;; - One place to change paths (portable across machines!)
;; - Clear overview of all customizable settings
;; - Easy Windows compatibility (just change paths here)
;; - No duplicate definitions scattered across files
;;
;;; Code:

;; ============================================================
;; DIRECTORY PATHS
;; ============================================================

(defvar my/notes-dir (expand-file-name "~/notes/")
  "Main directory for all Denote notes.
Used by: Denote core, Dashboard, Folgezettel, all note functions.")

(defvar my/notes-backups-dir (expand-file-name "~/notes/.backups/")
  "Backup directory for notes files (separate from Emacs config backups).")

(defvar my/notes-autosaves-dir (expand-file-name "~/notes/.autosaves/")
  "Autosave directory for notes files.")

(defvar my/emacs-backups-dir (expand-file-name "~/.emacs.d/backups/")
  "Backup directory for Emacs config files.")

(defvar my/emacs-autosaves-dir (expand-file-name "~/.emacs.d/autosaves/")
  "Autosave directory for Emacs config files.")

(defvar my/emacs-undo-tree-dir
  (expand-file-name "undo-tree-history/" user-emacs-directory)
  "Persistent undo history directory.")

(defvar my/project-files
  (list (expand-file-name "20251009--PKM-refactoring__project.org" my/notes-dir))
  "List of Org files to include in agenda.
Add new project files here to track them in Org-agenda.")


;; ============================================================
;; DENOTE CONFIGURATION
;; ============================================================

(defvar my/denote-keywords
  '("zettel" "osoba" "projekt" "journal" "lektura" "filozof"
    "fleeting" "esej" "skroty")
  "Available keywords (tags) for Denote notes.
Used by: denote-known-keywords, Dashboard statistics.")

(defvar my/fill-column 84
  "Text wrapping column for notes (auto-fill-mode).
Default: 84 characters.")

;; ============================================================
;; DASHBOARD & STATISTICS
;; ============================================================

(defvar my/daily-goals-file
  (expand-file-name "daily-goals.el" user-emacs-directory)
  "File storing daily writing goals (persistent across sessions).")

(defvar my/dashboard-cache-ttl 300
  "Dashboard cache time-to-live in seconds.
Default: 300 (5 minutes).  Set to 0 to disable caching.")

(defvar my/project-daily-goals
  '(("kant" . 300)
    ("hume" . 200)
    ("sartre" . 250))
  "Daily writing goals per project tag.
Format: ((TAG . WORDS) ...)")

;; ============================================================
;; BACKUP SETTINGS
;; ============================================================

(defvar my/backup-kept-new-versions 10
  "Number of newest backup versions to keep per file.")

(defvar my/backup-kept-old-versions 5
  "Number of oldest backup versions to keep per file.")

(defvar my/backup-by-copying t
  "Backup files by copying (preserves permissions and links).
Set to nil for faster backups via renaming (may break links).")

(defvar my/vc-make-backup-files t
  "Create Emacs backups even for Git-tracked files.
Recommended: t (double safety with Git + Emacs backups).")

;; ============================================================
;; UNDO LIMITS
;; ============================================================

(defvar my/undo-limit 800000
  "Undo memory limit in bytes (800KB, 10x default).")

(defvar my/undo-strong-limit 1200000
  "Strong undo limit (1.2MB, 10x default).")

(defvar my/undo-outer-limit 120000000
  "Outer undo limit (120MB, 10x default).")

;; ============================================================
;; UI SETTINGS
;; ============================================================

(defvar my/line-numbers-type 'relative
  "Line number display type: 'relative, 'absolute, or t.
- 'relative: shows distance from current line (Vim-style)
- 'absolute: shows actual line numbers
- t: same as 'absolute")

(defvar my/which-key-idle-delay 0.3
  "Delay before which-key popup appears (seconds).
Default: 0.3 (faster than default 1.0).")

(defvar my/theme-default 'gruvbox
  "Default theme to load on startup.
Options: 'gruvbox, 'doom-one, 'zenburn, etc.")

;; ============================================================
;; WELL-BEING TRACKING
;; ============================================================

(defvar my/well-being-file
  (expand-file-name "well-being.org" my/notes-dir)
  "Main well-being tracking file.")

(defvar my/well-being-history-days 30
  "Number of days to show in well-being history.
Default: 30 days.")

;; ============================================================
;; SPELL CHECKING
;; ============================================================

(defvar my/hunspell-dictionaries '("pl_PL" "en_GB")
  "List of Hunspell dictionaries to use.
Format: (LANG1 LANG2 ...) e.g., (\"pl_PL\" \"en_GB\")")

(defvar my/languagetool-path "/usr/bin/languagetool"
  "Path to LanguageTool command-line jar.
Linux: /usr/bin/languagetool
macOS: /usr/local/bin/languagetool
Windows: C:/Program Files/LanguageTool/languagetool-commandline.jar")

;; ============================================================
;; ORG-MODE SETTINGS
;; ============================================================

(defvar my/org-startup-folded 'overview
  "Org-mode default folding on file open.
Options: 'overview (fold all), 'content (show headings), 'showall (expand all).")

(defvar my/org-columns-format
  "%40ITEM(Tytuł) %10STATUS %8YEAR %6PAGES %10PROJECT"
  "Org columns display format for properties view.")

;; ============================================================
;; WINDOWS COMPATIBILITY
;; ============================================================

(defvar my/system-type system-type
  "System type for platform-specific config.
Values: 'gnu/linux, 'windows-nt, 'darwin (macOS)")

;; Conditional paths for Windows
(when (eq my/system-type 'windows-nt)
  ;; Windows uses different path separators and locations
  (setq my/notes-dir (expand-file-name "C:/Users/YourName/Documents/notes/"))
  (setq my/notes-backups-dir (expand-file-name "C:/Users/YourName/Documents/notes/.backups/"))
  (setq my/notes-autosaves-dir (expand-file-name "C:/Users/YourName/Documents/notes/.autosaves/"))
  (setq my/languagetool-path "C:/Program Files/LanguageTool/languagetool-commandline.jar"))

;; ============================================================
;; CREATE DIRECTORIES (ensure all paths exist)
;; ============================================================

;; Create all directories if they don't exist
(dolist (dir (list my/notes-dir
                   my/notes-backups-dir
                   my/notes-autosaves-dir
                   my/emacs-backups-dir
                   my/emacs-autosaves-dir
                   my/emacs-undo-tree-dir))
  (make-directory dir t))

;; ============================================================
;; DEPRECATED VARIABLES (for backward compatibility)
;; ============================================================

;; Old variable names - redirect to new ones
(defvaralias 'my-notes-dir 'my/notes-dir)
(defvaralias 'my-notes-backups 'my/notes-backups-dir)
(defvaralias 'my-notes-autosaves 'my/notes-autosaves-dir)
(defvaralias 'my-emacs-backups 'my/emacs-backups-dir)
(defvaralias 'my-emacs-autosaves 'my/emacs-autosaves-dir)

;; This ensures old code using `my-notes-dir` still works!

;; ============================================================
;; VERIFICATION
;; ============================================================

(message "✅ Variables loaded: notes=%s" my/notes-dir)

(provide '00-variables)
;;; 00-variables.el ends here
