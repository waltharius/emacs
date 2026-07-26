;;; 04-denote.el --- Denote configuration with multi-silo support -*- lexical-binding: t; -*-
;;; Commentary:
;; Denote note-taking system with 3 silos:
;; - ~/notes/journal/ - Private daily notes
;; - ~/notes/pks/     - Personal Knowledge System
;; - ~/notes/docu/    - Documentation and technical notes
;;
;; Updated to use new Denote 4.1.0 API (no deprecation warnings)
;;
;; NOTE: Visual-fill-column setup is handled entirely by 10-visual-fill.el.
;; Do not add visual-fill or fill-column hooks here.

;;; Code:

;; ============================================================
;; DENOTE: Core package
;; ============================================================

(use-package denote
  :ensure t
  :custom
  (denote-directory my-notes-dir)
  (denote-known-keywords my-denote-keywords)
  (denote-infer-keywords t)
  (denote-sort-keywords t)
  (denote-file-type nil)
  (denote-prompts '(title keywords)))

;; ============================================================
;; CONSULT-DENOTE: Better search integration
;; ============================================================

(use-package consult-denote
  :ensure t
  :after (denote consult)
  :config
  (consult-denote-mode 1))

;; ============================================================
;; HOW MULTI-SILO SEARCH WORKS
;; ============================================================
;;
;; KEY INSIGHT: denote-directory is set to ~/notes/ (root)
;;
;; This means ALL denote functions automatically search:
;; - ~/notes/journal/
;; - ~/notes/pks/
;; - ~/notes/docu/
;; - Any other subdirectories
;;
;; Individual note creation functions explicitly set target directory.

;; ============================================================
;; DENOTE CONVENIENCE SETTINGS
;; ============================================================

;; Enable buffer renaming for Denote notes once, at startup.
;; NOTE: previously this was added to `denote-after-new-note-hook',
;; which meant the (global) mode only became active after the first
;; note created in a session, and the hook re-ran the mode function on
;; every subsequent note.  Enabling it here is the intended usage.
(denote-rename-buffer-mode 1)
(setq denote-link-button-action 'find-file)

;; ============================================================
;; ORG-MODE SETTINGS FOR DENOTE
;; ============================================================

;; Disable auto-indent in org-mode (controlled separately)
(add-hook 'org-mode-hook
          (lambda ()
            (electric-indent-local-mode -1)
            (setq-local electric-indent-chars nil)))

(setq org-list-allow-alphabetical t)
(setq org-list-demote-modify-bullet
      '(("+" . "-") ("-" . "+") ("*" . "-") ("1." . "a.")))
(setq org-columns-default-format
      "%40ITEM(Title) %10STATUS %8YEAR %6PAGES %10PROJECT")
(setq org-return-follows-link t)
(setq org-mouse-1-follows-link t)

;; Confirm before executing elisp links (security: external .org files)
(setq org-confirm-elisp-link-function #'y-or-n-p)

;; ============================================================
;; E4 — DISABLE ORG-CLOCK PERSISTENCE
;; ============================================================
;; org-clock-persist is enabled by default in modern Emacs.
;; It writes ~/.emacs.d/.org-clock.save.el on every quit and reads
;; it on every startup, causing a noticeable delay even when you
;; never use org-clock.  Disabled here because org-agenda and
;; time-clocking are not part of this workflow.

(setq org-clock-persist nil)
(setq org-clock-persist-file nil)

;; ============================================================
;; TITLE PROMPT: do not offer past titles as completion candidates
;; ============================================================
;; `denote-history-completion-in-prompts' makes Denote offer previous
;; minibuffer inputs as completion candidates for every prompt listed
;; in `denote-prompts-with-history-as-completion'.
;;
;; For KEYWORDS that is exactly right: reusing an existing keyword is
;; the whole point, and it keeps the vocabulary consistent.
;;
;; For TITLES it is actively misleading.  Every title ever typed stays
;; on the suggestion list for the rest of the session, including titles
;; that were later renamed away.  The list then advertises notes that
;; no longer exist under that name, which looks like duplicate notes
;; even though nothing is duplicated on disk.  Titles are also rarely
;; worth reusing verbatim, so the completion buys nothing in exchange.
;;
;; Only the title prompt is removed; the rest keep their history.

(with-eval-after-load 'denote
  (when (boundp 'denote-prompts-with-history-as-completion)
    (setq denote-prompts-with-history-as-completion
          (remq 'denote-title-prompt
                denote-prompts-with-history-as-completion))))

;; ============================================================
;; DIRED: highlight the parts of Denote file names
;; ============================================================
;; `denote-dired-mode' font-locks the components of a Denote file name
;; (identifier, signature, title, keywords) in different faces, which
;; makes long file names far easier to scan.  Harmless in directories
;; without Denote files: names that do not match are left alone.
;;
;; `dired-hide-details-mode' removes the permissions/owner/size/date
;; columns, leaving the file names themselves as the only content.

(add-hook 'dired-mode-hook #'denote-dired-mode)
(add-hook 'dired-mode-hook #'dired-hide-details-mode)

(provide '04-denote)
;;; 04-denote.el ends here
