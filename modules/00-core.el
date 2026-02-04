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

;; Capture files
(defvar my-fleeting-file (expand-file-name "~/notes/fleeting.org")
  "Quick capture file for fleeting thoughts.")

(defvar my-journal-captures (expand-file-name "~/notes/journal/captures.org")
  "Journal captures - ideas worth developing later.")

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
(defvar my-fill-column 80
  "Default text wrapping column for notes.
Documentation notes (:docu: tag) use 100 instead.")

;; DENOTE KEYWORDS: Base list (Denote will add more automatically)
(defvar my-denote-keywords
  '("journal" "docu" "wellbeing" "esej" "philosophy"
    "zettel" "osoba" "projekt" "lektura" "filozof"
    "fleeting" "skroty")
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

;; Don't create lockfiles
(setq create-lockfiles nil)

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

(provide '00-core)
;;; 00-core.el ends here
