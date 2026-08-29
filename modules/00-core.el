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
;; CORE VARIABLES: Paths and directories
;; ============================================================

;; Notes directories (multi-silo structure)
(defvar my-notes-dir (expand-file-name "~/notes/")
  "Main notes directory (parent of all silos).")

(defvar my-notes-journal (expand-file-name "~/notes/journal/")
  "Journal notes - private daily entries.")

(defvar my-notes-pks (expand-file-name "~/notes/pks/")
  "Personal Knowledge System - regular notes.")

(defvar my-notes-docu (expand-file-name "~/notes/docu/")
  "Documentation and technical notes.")

;; Capture file
(defvar my-journal-captures (expand-file-name "~/notes/journal/captures.org")
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

;; Agenda scans all three silos + captures file
(defvar my-tasks-agenda-dirs
  (list my-notes-journal
        my-notes-pks
        my-notes-docu
        my-journal-captures)
  "All locations org-agenda should scan for TODO items.")

;; Backup directories
(defvar my-notes-backups (expand-file-name "~/notes/.backups/")
  "Backup directory for note files.")

(defvar my-notes-autosaves (expand-file-name "~/notes/.autosaves/")
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

;; Create all directories if they don't exist
(dolist (dir (list my-notes-dir
                   my-notes-journal
                   my-notes-pks
                   my-notes-docu
                   my-notes-backups
                   my-notes-autosaves
                   my-emacs-backups
                   my-emacs-autosaves))
  (unless (file-exists-p dir)
    (make-directory dir t)))

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
