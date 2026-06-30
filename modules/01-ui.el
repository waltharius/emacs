;;; 01-ui.el --- Interface settings and session management -*- lexical-binding: t; -*-
;;; Commentary:
;; UI settings: menu bar, tabs, themes, desktop-save-mode
;; Session management: save/restore open files, window layouts, cursor positions
;; Completion: Vertico + Orderless for fuzzy matching

;;; Code:

;; ============================================================
;; BASIC UI SETTINGS
;; ============================================================

(setq inhibit-startup-screen t)
(tool-bar-mode 1)         ; Keep tool bar (you like it)
(menu-bar-mode 1)         ; Keep menu bar (File, Edit, Options...)
(scroll-bar-mode 1)       ; Keep scroll bar

;; Set locale for Polish time/date formatting
(setq system-time-locale "pl_PL.UTF-8")

;; ============================================================
;; COMPLETION FRAMEWORK: Vertico + Orderless + Marginalia
;; ============================================================

;; Vertico: Better minibuffer (vertical completion)
(use-package vertico
  :ensure t
  :init
  (vertico-mode))

;; Orderless: Fuzzy matching (space-separated, out-of-order matching)
(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; Marginalia: Annotations in minibuffer (shows descriptions)
(use-package marginalia
  :ensure t
  :init
  (marginalia-mode))

;; Enable completion-read-multiple with comma separator
(setq crm-separator ",")

;; ============================================================
;; DESKTOP-SAVE-MODE: Session persistence
;; ============================================================
;; Saves all open files and cursor positions between sessions.
;;
;; LAZY RESTORE STRATEGY
;; ---------------------
;; With 400+ buffers, restoring everything synchronously blocks the UI
;; for several seconds.  `desktop-restore-eager' controls how many
;; buffers are restored synchronously before Emacs shows the first
;; frame.  The remaining buffers are restored lazily in background
;; idle time — Emacs is fully responsive while this happens.
;;
;; Value of 10 means: restore 10 buffers synchronously (fast), then
;; show UI, then restore the rest in the background.

(use-package desktop
  :ensure nil
  :init
  (setq desktop-dirname             "~/.emacs.d/desktop/"
        desktop-base-file-name      "desktop"
        desktop-base-lock-name      "desktop.lock"
        desktop-path               (list desktop-dirname)
        desktop-save               t
        desktop-load-locked-desktop t
        ;; Lazy restore: only 10 buffers block startup, rest load in background
        desktop-restore-eager      10)
  :config
  (unless (file-exists-p desktop-dirname)
    (make-directory desktop-dirname t))
  (add-to-list 'desktop-modes-not-to-save 'pdf-view-mode)
  ;; nov.el (epub reader) buffers trigger 'Version not specified' on restore
  (add-to-list 'desktop-modes-not-to-save 'nov-mode)
  (desktop-save-mode 1))

;; Don't save temporary/auxiliary files
(add-to-list 'desktop-modes-not-to-save 'fundamental-mode)
(setq desktop-files-not-to-save
      (concat desktop-files-not-to-save
              "\\|\\(\\.aux\\|\\.log\\|\\.out\\|\\.toc\\|\\.tex\\|\\.epub\\)$"))

;; Manual save command
(defun my/desktop-save-now ()
  "Save desktop session immediately."
  (interactive)
  (desktop-save desktop-dirname)
  (message "Desktop saved!"))

(global-set-key (kbd "C-c d s") 'my/desktop-save-now)

;; ============================================================
;; SAVE-PLACE-MODE: Remember cursor position
;; ============================================================

(use-package saveplace
  :ensure nil
  :init
  (save-place-mode 1)
  :config
  (setq save-place-file "~/.emacs.d/saveplace"))

;; ============================================================
;; TAB-BAR-MODE: Workspace tabs (like browser tabs)
;; ============================================================

(use-package tab-bar
  :ensure nil
  :init
  (tab-bar-mode 1)
  :bind (("C-c t n" . tab-bar-new-tab)
         ("C-c t c" . tab-bar-close-tab)
         ("C-c t o" . tab-bar-switch-to-tab)
         ("C-c t r" . tab-bar-rename-tab))
  :config
  (setq tab-bar-show t)
  (setq tab-bar-new-tab-choice "*scratch*")
  (setq tab-bar-close-button-show t))

;; ============================================================
;; WINNER-MODE: Undo/redo window configurations
;; ============================================================

(use-package winner
  :ensure nil
  :init
  (winner-mode 1)
  :bind (("C-c <left>"  . winner-undo)
         ("C-c <right>" . winner-redo)))

;; ============================================================
;; ORG-MODE VISUAL SETTINGS
;; ============================================================

;; visual-line-mode and fill-column variable for org files.
;; NOTE: visual-line-mode hook is owned by 02-editing.el.
;; display-fill-column-indicator-mode is owned by 10-visual-fill.el.
(add-hook 'org-mode-hook
          (lambda ()
            (setq fill-column my-fill-column)))

;; Prettify quote blocks.
;; Note: use 'unspecified instead of nil for any face attribute that
;; should be inherited — nil causes "nil value is invalid" warnings.
(custom-set-faces
 '(org-quote ((t (:background "#f9f9f9" :slant italic :foreground "#555555"))))
 '(org-block ((t (:background "#fef8e0" :extend t :family "Georgia"))))
 '(org-block-begin-line ((t (:background "#e0e0e0" :foreground "#999999" :height 0.9))))
 '(org-block-end-line ((t (:background "#e0e0e0" :foreground "#999999" :height 0.9)))))

(setq org-fontify-quote-and-verse-blocks t)

;; Replace block markers with Unicode symbols
(setq-default prettify-symbols-alist
              '(("#+BEGIN_QUOTE" . "\U0001F4AC")
                ("#+END_QUOTE" . "\U0001F4AC")
                ("#+begin_quote" . "\U0001F4AC")
                ("#+end_quote" . "\U0001F4AC")
                ("#+BEGIN_SRC" . "\u03BB")
                ("#+END_SRC" . "\u03BB")
                ("#+begin_src" . "\u03BB")
                ("#+end_src" . "\u03BB")))

(setq prettify-symbols-unprettify-at-point 'right-edge)
(add-hook 'org-mode-hook 'prettify-symbols-mode)

;; ============================================================
;; WORD COUNT IN MODELINE
;; ============================================================

(defun my/word-count-modeline ()
  "Display word count in modeline for text modes."
  (when (derived-mode-p 'org-mode 'text-mode)
    (let ((words (count-words (point-min) (point-max))))
      (propertize (format "%d " words)
                  'face '(:foreground "purple" :weight bold)))))

(setq-default mode-line-format
              '((:eval (my/word-count-modeline))
                "%e"
                mode-line-front-space
                mode-line-mule-info
                mode-line-client
                mode-line-modified
                mode-line-remote
                mode-line-frame-identification
                mode-line-buffer-identification
                "   "
                mode-line-position
                (vc-mode vc-mode)
                "  "
                mode-line-modes
                mode-line-misc-info
                mode-line-end-spaces))

;; ============================================================
;; HELPER FUNCTIONS
;; ============================================================

(defun open-init-el-bottom-split ()
  "Open init.el in bottom window split."
  (interactive)
  (let ((init-file (expand-file-name "~/.emacs.d/init.el")))
    (split-window-below)
    (other-window 1)
    (find-file init-file)))

;; Auto-close auxiliary files (LaTeX exports, etc.)
(defun my/kill-auxiliary-buffers (&rest _args)
  "Kill auxiliary file buffers (.aux, .log, .tex, etc.)."
  (interactive)
  (dolist (buf (buffer-list))
    (let ((name (buffer-file-name buf)))
      (when (and name
                 (or (string-suffix-p ".aux" name)
                     (string-suffix-p ".log" name)
                     (string-suffix-p ".out" name)
                     (string-suffix-p ".toc" name)
                     (string-suffix-p ".tex" name)))
        (kill-buffer buf)))))

(add-hook 'emacs-startup-hook 'my/kill-auxiliary-buffers)
(add-hook 'org-export-before-processing-hook 'my/kill-auxiliary-buffers)

(provide '01-ui)
;;; 01-ui.el ends here
