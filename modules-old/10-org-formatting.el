;;; 10-org-formatting.el --- Org-mode formatting and visual enhancements -*- lexical-binding: t; -*-

;;; Commentary:
;; Text formatting shortcuts + emphasis markers hiding + centered cursor

;;; Code:

;; ============================================================
;; ORG-MODE FORMATTING SHORTCUTS
;; ============================================================

(defun my/org-toggle-bold ()
  "Toggle bold formatting on region or word at point."
  (interactive)
  (if (region-active-p)
      (let ((beg (region-beginning))
            (end (region-end)))
        (if (and (eq (char-before end) ?*)
                 (eq (char-after beg) ?*))
            ;; Remove bold
            (progn
              (goto-char end)
              (delete-char -1)
              (goto-char beg)
              (delete-char 1))
          ;; Add bold
          (goto-char end)
          (insert "*")
          (goto-char beg)
          (insert "*")))
    ;; No region - operate on word
    (let ((bounds (bounds-of-thing-at-point 'word)))
      (when bounds
        (let ((beg (car bounds))
              (end (cdr bounds)))
          (goto-char end)
          (insert "*")
          (goto-char beg)
          (insert "*"))))))

(defun my/org-toggle-italic ()
  "Toggle italic formatting on region or word at point."
  (interactive)
  (if (region-active-p)
      (let ((beg (region-beginning))
            (end (region-end)))
        (if (and (eq (char-before end) ?/)
                 (eq (char-after beg) ?/))
            ;; Remove italic
            (progn
              (goto-char end)
              (delete-char -1)
              (goto-char beg)
              (delete-char 1))
          ;; Add italic
          (goto-char end)
          (insert "/")
          (goto-char beg)
          (insert "/")))
    ;; No region - operate on word
    (let ((bounds (bounds-of-thing-at-point 'word)))
      (when bounds
        (let ((beg (car bounds))
              (end (cdr bounds)))
          (goto-char end)
          (insert "/")
          (goto-char beg)
          (insert "/"))))))

(defun my/org-toggle-strikethrough ()
  "Toggle strikethrough formatting on region or word at point."
  (interactive)
  (if (region-active-p)
      (let ((beg (region-beginning))
            (end (region-end)))
        (if (and (eq (char-before end) ?+)
                 (eq (char-after beg) ?+))
            ;; Remove strikethrough
            (progn
              (goto-char end)
              (delete-char -1)
              (goto-char beg)
              (delete-char 1))
          ;; Add strikethrough
          (goto-char end)
          (insert "+")
          (goto-char beg)
          (insert "+")))
    ;; No region - operate on word
    (let ((bounds (bounds-of-thing-at-point 'word)))
      (when bounds
        (let ((beg (car bounds))
              (end (cdr bounds)))
          (goto-char end)
          (insert "+")
          (goto-char beg)
          (insert "+"))))))

(defun my/org-toggle-uppercase ()
  "Toggle UPPERCASE on region or word at point."
  (interactive)
  (if (region-active-p)
      (let ((beg (region-beginning))
            (end (region-end))
            (text (buffer-substring beg end)))
        (if (string= text (upcase text))
            ;; Already uppercase - convert to lowercase
            (progn
              (delete-region beg end)
              (insert (downcase text)))
          ;; Convert to uppercase
          (progn
            (delete-region beg end)
            (insert (upcase text)))))
    ;; No region - operate on word
    (let ((bounds (bounds-of-thing-at-point 'word)))
      (when bounds
        (let* ((beg (car bounds))
               (end (cdr bounds))
               (text (buffer-substring beg end)))
          (if (string= text (upcase text))
              (progn
                (delete-region beg end)
                (insert (downcase text)))
            (progn
              (delete-region beg end)
              (insert (upcase text)))))))))

;; Keybindings (org-mode specific)
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-x b") 'my/org-toggle-bold)
  (define-key org-mode-map (kbd "C-c C-x i") 'my/org-toggle-italic)
  (define-key org-mode-map (kbd "C-c C-x s") 'my/org-toggle-strikethrough)
  (define-key org-mode-map (kbd "C-c C-x u") 'my/org-toggle-uppercase))

;; ============================================================
;; PREVIEW MODE (hide emphasis markers)
;; ============================================================

;; Hide emphasis markers (*bold*, /italic/, etc.) by default
(setq org-hide-emphasis-markers t)

;; org-appear: show markers when cursor is on them
(use-package org-appear
  :ensure t
  :hook (org-mode . org-appear-mode)
  :config
  (setq org-appear-autolinks t)           ; Also show link URLs on hover
  (setq org-appear-autosubmarkers t)      ; Show sub/superscript markers
  (setq org-appear-autoentities t)        ; Show special entities
  (setq org-appear-autokeywords t)        ; Show #+KEYWORDS
  (setq org-appear-inside-latex t))       ; Show LaTeX markers

;; ============================================================
;; CENTERED CURSOR (scroll offset)
;; ============================================================

;; Keep cursor centered at 1/3 from bottom (scrolloff)
;; This means cursor stays at roughly 2/3 of screen height
(setq scroll-margin 0)                    ; No margin at edges
(setq scroll-conservatively 101)          ; Never recenter
(setq scroll-preserve-screen-position t)  ; Keep cursor position
(setq auto-window-vscroll nil)            ; Don't scroll windows automatically

;; Centered cursor mode (optional - only if you want STRICT centering)
;; Uncomment if you want cursor ALWAYS in center:
;; (use-package centered-cursor-mode
;;   :ensure t
;;   :hook (org-mode . centered-cursor-mode))

;; Simple scroll offset (keeps cursor at 1/3 from bottom)
(defun my/recenter-on-move ()
  "Recenter window to keep cursor at 1/3 from bottom."
  (let ((target-line (- (window-height) (/ (window-height) 3))))
    (when (> (count-lines (window-start) (point)) target-line)
      (recenter target-line))))

;; Enable for org-mode (optional - enable if you like it!)
;; (add-hook 'post-command-hook #'my/recenter-on-move nil t)

;; RECOMMENDED: Use native scroll-margin instead (simpler!)
(setq scroll-margin 8)  ; Keep 8 lines visible above/below cursor

;; Ukryj gwiazdki na początku nagłówków (*** → •)
(setq org-hide-leading-stars t)
(setq org-superstar-leading-bullet ?\s)  ; Spacja zamiast gwiazdek

;; Ładne kropki zamiast gwiazdek
(use-package org-superstar
  :ensure t
  :hook (org-mode . org-superstar-mode)
  :config
  (setq org-superstar-headline-bullets-list '("◉" "○" "◆" "◇" "▶" "▷"))
  (setq org-superstar-item-bullet-alist
        '((?* . ?•) (?+ . ?➤) (?- . ?–))))

(provide '10-org-formatting)
;;; 10-org-formatting.el ends here
