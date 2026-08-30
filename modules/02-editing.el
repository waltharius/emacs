;;; 02-editing.el --- Modern editing conveniences -*- lexical-binding: t; -*-
;;; Commentary:
;; Modern editor features: line numbers, matching parens, smooth scrolling, etc.

;;; Code:

;; ============================================================
;; MODERN KEYBINDINGS (without CUA conflicts)
;; ============================================================

;; C-a is `move-beginning-of-line', as in stock Emacs.  It was
;; `mark-whole-buffer' until 2026-08: convenient once a week, in the way
;; of a movement command used hundreds of times an hour, and the reason
;; a movement key that every tutorial and every muscle memory expects
;; did something else entirely.  Select-all is `C-x h', which is what
;; the rest of Emacs already calls it.
(global-set-key (kbd "C-f") 'isearch-forward)    ; Find
(global-set-key (kbd "C-s") 'save-buffer)        ; Save
(global-set-key (kbd "C-z") 'undo)               ; Undo

;; Better isearch
(define-key isearch-mode-map (kbd "C-f") 'isearch-repeat-forward)
(define-key isearch-mode-map (kbd "C-g") 'isearch-abort)

;; ============================================================
;; LINE NUMBERS
;; ============================================================
;; LINE NUMBERS — only in programming and config files

(setq display-line-numbers-type 'relative)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'conf-mode-hook #'display-line-numbers-mode)

;; ============================================================
;; HIGHLIGHT CURRENT LINE
;; ============================================================

(global-hl-line-mode t)

;; ============================================================
;; MATCHING PARENTHESES
;; ============================================================

(show-paren-mode t)
(setq show-paren-delay 0)
(setq show-paren-style 'mixed)

;; ============================================================
;; AUTO-PAIRS (Electric pair mode)
;; ============================================================

(electric-pair-mode t)

;; Default pairing for code modes
(setq electric-pair-pairs
      '((?\" . ?\")
        (?' . ?')
        (?\( . ?\))
        (?\[ . ?\])
        (?\{ . ?\})))

;; ============================================================
;; DISABLE QUOTE PAIRING IN ORG-MODE (keep brackets!)
;; ============================================================

(defun my/org-mode-electric-pair-setup ()
  "Configure electric-pair-mode for org-mode.
  Disable quote pairing but keep brackets."
  ;; Make electric-pair-pairs buffer-local and exclude quotes
  (setq-local electric-pair-pairs
              '((?\( . ?\))
                (?\[ . ?\])
                (?\{ . ?\})))
  
  ;; Also set electric-pair-text-pairs for text contexts
  (setq-local electric-pair-text-pairs
              '((?\( . ?\))
                (?\[ . ?\])
                (?\{ . ?\}))))

;; Apply to org-mode
(add-hook 'org-mode-hook 'my/org-mode-electric-pair-setup)

;; ============================================================
;; EXPLANATION
;; ============================================================
;;
;; WHY DISABLE QUOTE PAIRING IN ORG-MODE?
;;
;; In natural language writing (notes, journals):
;; - "don't" should NOT become "don''t"
;; - "it's" should NOT become "it''s"
;; - Quotes for "emphasis" get annoying
;;
;; In code files (.el, .py, .nix):
;; - Auto-pairing quotes IS useful
;; - Prevents syntax errors
;;
;; WHAT STILL PAIRS IN ORG-MODE?
;; - Parentheses: (like this)
;; - Brackets: [like this]
;; - Curly braces: {like this}
;;
;; WHAT PAIRS IN CODE FILES?
;; - Everything: quotes, brackets, parens, braces
;;
;; RESULT: Natural writing in notes, smart pairing in code!

;; ============================================================
;; SMOOTH SCROLLING
;; ============================================================

(setq scroll-step 1)
(setq scroll-conservatively 10000)
(setq auto-window-vscroll nil)

;; Mouse scrolling
(setq mouse-wheel-scroll-amount '(1 ((shift) . 1)))
(setq mouse-wheel-progressive-speed t)
(setq mouse-wheel-follow-mouse 't)

;; ============================================================
;; WHICH-KEY: Show available keybindings
;; ============================================================

(use-package which-key
  :ensure t
  :init
  (which-key-mode 1)
  :config
  (setq which-key-idle-delay 0.3)
  (setq which-key-popup-type 'side-window)
  (setq which-key-side-window-location 'bottom)
  (setq which-key-side-window-max-height 0.25)
  (setq which-key-sort-order 'which-key-key-order-alpha))

;; ============================================================
;; BETTER DEFAULTS
;; ============================================================

(delete-selection-mode t)     ; Replace selection when typing
(column-number-mode t)        ; Show column in modeline
(size-indication-mode t)      ; Show file size

;; Visual line mode for text
(add-hook 'text-mode-hook 'visual-line-mode)
(add-hook 'org-mode-hook 'visual-line-mode)

;; ============================================================
;; IMPROVED SEARCH
;; ============================================================

(setq case-fold-search t)              ; Case-insensitive
(setq isearch-lazy-highlight t)        ; Highlight all matches
(setq lazy-highlight-initial-delay 0)
(setq isearch-wrap-around t)           ; Wrap at buffer edges

;; ============================================================
;; BETTER BUFFER SWITCHING
;; ============================================================

(global-set-key (kbd "C-x C-b") 'ibuffer)

;; IDO mode for fuzzy matching
;;(use-package ido
;;  :ensure nil
;;  :init
;;  (ido-mode t)
;;  :config
;;  (setq ido-enable-flex-matching t)
;;  (setq ido-everywhere t)
;;  (setq ido-create-new-buffer 'always))
;;
;; ============================================================
;; UNIQUIFY: Better duplicate buffer names
;; ============================================================

(use-package uniquify
  :ensure nil
  :config
  (setq uniquify-buffer-name-style 'forward)
  (setq uniquify-separator "/")
  (setq uniquify-after-kill-buffer-p t)
  (setq uniquify-ignore-buffers-re "^\\*"))

;; ============================================================
;; AUTO-REVERT: Reload files when changed externally
;; ============================================================

(global-auto-revert-mode t)
(setq global-auto-revert-non-file-buffers t)
(setq auto-revert-verbose nil)

;; POLLING vs FILE NOTIFICATION
;; ---------------------------
;; With `global-auto-revert-non-file-buffers' on, auto-revert polls every
;; `auto-revert-interval' seconds (5 by default) and reverts Dired
;; buffers, which re-runs `ls' on the directory and re-applies
;; `denote-dired-mode' font-lock to every line.  In ~/notes/journal/
;; that is several thousand long file names, twelve times a minute,
;; whether or not anything changed.
;;
;; `auto-revert-avoid-polling' switches to kernel file-notification
;; watches: buffers revert when a change is reported and stay idle
;; otherwise.  Polling remains as a fallback on filesystems that do not
;; support notification.  This matters more here than in most
;; configurations because Syncthing writes into the notes tree from
;; outside Emacs, so auto-revert is worth keeping -- just not on a timer.
(setq auto-revert-avoid-polling t)

;; Even with notifications, a very large Dired buffer is expensive to
;; re-fontify, so do not re-read the directory merely because the buffer
;; regained focus.
(setq dired-auto-revert-buffer nil)

;; ============================================================
;; FONT-LOCK: defer highlighting of off-screen text
;; ============================================================
;; Notes are long and `org-hide-emphasis-markers' (11-org-appearance.el)
;; plus the Denote name faces make fontification non-trivial.  Deferring
;; it slightly means scrolling shows text immediately and highlights it a
;; fraction of a second later, instead of blocking the scroll.

(setq jit-lock-defer-time 0.05)

;; ============================================================
;; MISC IMPROVEMENTS
;; ============================================================

(defun my/unfill-region (beg end)
  "Join lines in region, replacing hard newlines with spaces."
  (interactive "r")
  (let ((fill-column most-positive-fixnum))
    (fill-region beg end)))

(global-set-key (kbd "M-Q") 'my/unfill-region)

(setq visible-bell t)                ; Flash instead of beep
(setq echo-keystrokes 0.1)           ; Show keystrokes immediately
(setq undo-limit 80000000)           ; Large undo limit
(setq undo-strong-limit 120000000)
(setq undo-outer-limit 960000000)    ; Ceiling for a single huge change

;; ============================================================
;; UNDO: visualise the tree, and keep it across restarts
;; ============================================================
;; Emacs' built-in undo is already a tree: unlike the usual undo/redo
;; found elsewhere, it can recover *any* previous buffer state, because
;; undoing an undo is itself recorded rather than discarding the branch
;; you undid.  What it lacks is a way to see that tree, and any memory
;; of it after Emacs exits.  These two packages add exactly those,
;; without replacing the undo system itself.
;;
;; That is the reason for choosing this pair over `undo-tree', which
;; substitutes its own undo implementation.  Note also that undo-tree
;; defines its own data structures and *cannot* be used together with
;; undo-fu-session; the leftover ~/.emacs.d/undo-tree-history directory
;; from an earlier configuration is inert and safe to delete.

(use-package vundo
  :ensure t
  :bind ("C-x u" . vundo)              ; replaces the plain `undo' binding
  :config
  ;; Box-drawing characters instead of ASCII; the tree is much easier
  ;; to read, and this frame already renders other non-ASCII glyphs.
  (setq vundo-glyph-alist vundo-unicode-symbols)
  (setq vundo-compact-display t))

;; Redo, without changing what C-z does.  `undo-redo' only undoes
;; undos and does not record itself as undoable, which is what makes
;; stepping back and forth along one branch behave predictably.
(global-set-key (kbd "C-S-z") 'undo-redo)

(use-package undo-fu-session
  :ensure t
  :init
  ;; Kept inside .emacs.d rather than next to the notes: this is
  ;; machine-local state, and syncing it between devices would produce
  ;; conflicts over files that are meaningless on the other machine.
  (setq undo-fu-session-directory
        (expand-file-name "undo-fu-session/" user-emacs-directory))
  :config
  ;; Buffers whose content is regenerated each time and whose undo
  ;; history would be misleading if restored.
  (setq undo-fu-session-incompatible-files
        '("/COMMIT_EDITMSG\\'" "/git-rebase-todo\\'"))
  ;; Undo data accumulates one file per edited file, indefinitely,
  ;; unless capped.  Oldest are removed first.
  (setq undo-fu-session-file-limit 2000)
  (undo-fu-session-global-mode 1))

;; Keep point at the same screen row when paging with PgUp/PgDn,
;; so a full-screen scroll doesn't lose the cursor position.
(setq scroll-preserve-screen-position t)

;; Confirm before quit
(setq confirm-kill-emacs 'yes-or-no-p)

;; y/n instead of yes/no
(defalias 'yes-or-no-p 'y-or-n-p)

;; Pretty symbols
(global-prettify-symbols-mode t)

(provide '02-editing)
;;; 02-editing.el ends here
