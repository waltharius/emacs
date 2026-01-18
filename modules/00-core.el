;;; 00-core.el --- Package management and core variables -*- lexical-binding: t; -*-
;;; Commentary:
;; Core configuration that must load first:
;; - Package management (use-package)
;; - Directory variables
;; - Essential settings

;;; Code:

;; ============================================================
;; PACKAGE MANAGEMENT
;; ============================================================

;; Set up package archives
(require 'package)
(setq package-archives
      '(("melpa" . "https://melpa.org/packages/")
        ("elpa"  . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")))

;; Initialize package system
(package-initialize)

;; Bootstrap use-package if not installed
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)  ;; Auto-install packages

;; ============================================================
;; DIRECTORY VARIABLES
;; ============================================================

;; Main notes directory
(defvar my-notes-dir (expand-file-name "~/notes/")
  "Root directory for all notes.")

;; Denote silos (multiple note directories)
(setq denote-directory my-notes-dir)
(defvar denote-silo-directories
  (list (expand-file-name "journal/" my-notes-dir)
        (expand-file-name "pks/" my-notes-dir)
        (expand-file-name "docu/" my-notes-dir))
  "Separate directories for different note types.")

;; Capture files for quick notes
(defvar my-fleeting-file (expand-file-name "fleeting.org" my-notes-dir)
  "File for quick fleeting notes and ideas.")

(defvar my-journal-captures-file 
  (expand-file-name "journal/captures.org" my-notes-dir)
  "File for capturing ideas from journal entries.")

;; Templates directory
(defvar my-templates-dir (expand-file-name "templates/" user-emacs-directory)
  "Directory for note templates.")

;; Create directories if they don't exist
(dolist (dir (append (list my-notes-dir my-templates-dir)
                     denote-silo-directories))
  (unless (file-exists-p dir)
    (make-directory dir t)))

;; ============================================================
;; ESSENTIAL SETTINGS
;; ============================================================

;; Load newer .el files (prevent stale cache issues)
(setq load-prefer-newer t)

;; UTF-8 everywhere
(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(prefer-coding-system 'utf-8)

;; Increase read buffer for faster LSP/large files
(setq read-process-output-max (* 1024 1024)) ;; 1MB

;; Better startup
(setq inhibit-startup-screen t)
(setq initial-scratch-message nil)

;; Polish locale for dates
(setq system-time-locale "pl_PL.UTF-8")

;; Recent files mode
(recentf-mode 1)
(setq recentf-max-saved-items 100
      recentf-auto-cleanup 'never
      recentf-exclude '("\\.git/"
                        "COMMIT_EDITMSG"
                        "\\.elc$"
                        "/elpa/"
                        "^/tmp/"
                        "^#.*#$"
                        "^\\.#"))

;; Better defaults
(setq-default
 cursor-type 'bar                    ;; Bar cursor (not block)
 indent-tabs-mode nil                ;; Spaces, not tabs
 tab-width 2                         ;; 2 spaces per tab
 fill-column 80)                     ;; 80 char width

;; Confirm before quit
(setq confirm-kill-emacs 'yes-or-no-p)

;; y/n instead of yes/no
(defalias 'yes-or-no-p 'y-or-n-p)

;; No lock files
(setq create-lockfiles nil)

;; No backup clutter in note directories
(setq backup-directory-alist
      `((,(expand-file-name "~/notes/") . ,(expand-file-name "~/notes/.backups/"))
        ("." . ,(expand-file-name "backups/" user-emacs-directory))))

(setq auto-save-file-name-transforms
      `((,(expand-file-name "~/notes/.*") 
         ,(expand-file-name "~/notes/.autosaves/") t)
        (".*" ,(expand-file-name "autosaves/" user-emacs-directory) t)))

;; Create backup directories
(make-directory (expand-file-name "~/notes/.backups/") t)
(make-directory (expand-file-name "~/notes/.autosaves/") t)
(make-directory (expand-file-name "backups/" user-emacs-directory) t)
(make-directory (expand-file-name "autosaves/" user-emacs-directory) t)

(provide '00-core)
;;; 00-core.el ends here
