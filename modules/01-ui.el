;;; 01-ui.el --- Interface settings and session management -*- lexical-binding: t; -*-
;;; Commentary:
;; UI configuration:
;; - Menu bar, tool bar, tabs
;; - Desktop save mode (session persistence)
;; - Window management
;; - Visual settings

;;; Code:

;; ============================================================
;; BASIC UI
;; ============================================================

(tool-bar-mode 1)   ;; Keep tool bar (you like it)
(menu-bar-mode 1)   ;; Keep menu bar (File, Edit, Options...)
(scroll-bar-mode 1) ;; Keep scroll bar

;; Frame title - show current file
(setq frame-title-format
      '((:eval (if (buffer-file-name)
                   (abbreviate-file-name (buffer-file-name))
                 "%b"))
        " - Emacs"))

;; ============================================================
;; SESSION MANAGEMENT (Desktop Save Mode)
;; ============================================================

(use-package desktop
  :ensure nil
  :init
  (setq desktop-dirname             (expand-file-name "desktop/" user-emacs-directory)
        desktop-base-file-name      "emacs-desktop"
        desktop-base-lock-name      "emacs-desktop.lock"
        desktop-path                (list desktop-dirname)
        desktop-save                t                    ;; Auto-save on exit
        desktop-load-locked-desktop t                    ;; Load even if locked
        desktop-restore-frames      t)                   ;; Restore window layout
  :config
  (unless (file-exists-p desktop-dirname)
    (make-directory desktop-dirname t))
  (desktop-save-mode 1))

;; Don't save certain modes
(add-to-list 'desktop-modes-not-to-save 'fundamental-mode)

;; Don't save temporary files
(setq desktop-files-not-to-save
      (concat desktop-files-not-to-save
              "\\|\\(\\.aux\\|\\.log\\|\\.out\\|\\.toc\\)$"))

;; Manual save command
(defun my/desktop-save-now ()
  "Save desktop session immediately."
  (interactive)
  (desktop-save desktop-dirname)
  (message "✅ Desktop session saved!"))

(global-set-key (kbd "C-c d s") 'my/desktop-save-now)

;; ============================================================
;; CURSOR POSITION MEMORY
;; ============================================================

(save-place-mode 1)
(setq save-place-file (expand-file-name "saveplace" user-emacs-directory))

;; ============================================================
;; TAB BAR (Workspace tabs)
;; ============================================================

(use-package tab-bar
  :ensure nil
  :init
  (tab-bar-mode 1)
  :config
  (setq tab-bar-show t)                        ;; Always show tabs
  (setq tab-bar-new-tab-choice "*scratch*")    ;; New tab opens scratch
  (setq tab-bar-close-button-show t)           ;; Show close button
  (setq tab-bar-new-button-show t)             ;; Show new tab button
  :bind (("C-c t n" . tab-bar-new-tab)         ;; New tab
         ("C-c t c" . tab-bar-close-tab)       ;; Close tab
         ("C-c t o" . tab-bar-switch-to-tab)   ;; Switch tab
         ("C-c t r" . tab-bar-rename-tab)))    ;; Rename tab

;; ============================================================
;; WINDOW MANAGEMENT
;; ============================================================

;; Winner mode - undo/redo window changes
(use-package winner
  :ensure nil
  :init
  (winner-mode 1)
  :bind (("C-c <left>"  . winner-undo)
         ("C-c <right>" . winner-redo)))

;; Unique buffer names when files have same name
(require 'uniquify)
(setq uniquify-buffer-name-style 'forward
      uniquify-separator "/"
      uniquify-after-kill-buffer-p t
      uniquify-ignore-buffers-re "^\\*")

;; ============================================================
;; VISUAL SETTINGS FOR ORG-MODE
;; ============================================================

;; Soft wrap with visual indicator at 80 chars
(add-hook 'org-mode-hook
          (lambda ()
            (visual-line-mode 1)
            (setq fill-column 80)
            (display-fill-column-indicator-mode 1)))

;; Prettier quote blocks
(custom-set-faces
 '(org-quote ((t (:background "#f9f9f9" :slant italic :foreground "#555555"))))
 '(org-block ((t (:background "#fef8e0" :extend t))))
 '(org-block-begin-line ((t (:background "#e0e0e0" :foreground "#999999" :height 0.9))))
 '(org-block-end-line ((t (:background "#e0e0e0" :foreground "#999999" :height 0.9)))))

(setq org-fontify-quote-and-verse-blocks t)

;; Pretty symbols for org blocks
(setq-default prettify-symbols-alist
              '(("#+BEGIN_QUOTE" . "💬")
                ("#+END_QUOTE" . "💬")
                ("#+begin_quote" . "💬")
                ("#+end_quote" . "💬")
                ("#+BEGIN_SRC" . "λ")
                ("#+END_SRC" . "λ")
                ("#+begin_src" . "λ")
                ("#+end_src" . "λ")))

(setq prettify-symbols-unprettify-at-point 'right-edge)
(add-hook 'org-mode-hook 'prettify-symbols-mode)

;; ============================================================
;; MODELINE - Word count for writing
;; ============================================================

(defun my/word-count-modeline ()
  "Show word count in modeline for text files."
  (when (derived-mode-p 'org-mode 'text-mode)
    (let ((words (count-words (point-min) (point-max))))
      (propertize (format "%d words " words)
                  'face '(:foreground "purple" :weight bold)))))

;; Add word count to modeline
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

;; Show column number
(column-number-mode t)

;; ============================================================
;; HELPER FUNCTIONS
;; ============================================================

(defun open-init-el-bottom-split ()
  "Open init.el in bottom split."
  (interactive)
  (split-window-below)
  (other-window 1)
  (find-file (expand-file-name "init.el" user-emacs-directory)))

(provide '01-ui)
;;; 01-ui.el ends here
