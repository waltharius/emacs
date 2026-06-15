;;; 06-capture.el --- Org-capture for ideas -*- lexical-binding: t; -*-
;;; Commentary:
;; Quick capture system for ideas and fleeting thoughts.
;;
;; C-c c j  / C-c n c  — Ideas capture with source link (opens right side)
;; C-c c f             — Fleeting note (opens right side)
;;
;; Processing captures:
;; C-c n m  — Promote heading to new Denote note (preserves SOURCE)
;; C-c C-w  — Refile heading to existing note (standard org-refile)

;;; Code:

;; ============================================================
;; HELPER: Get #+title: from ORIGINAL buffer
;; ============================================================

(defun my/get-capture-origin-title ()
  "Get #+title: from the buffer where capture was initiated."
  (let ((orig-buf (org-capture-get :original-buffer)))
    (if orig-buf
        (with-current-buffer orig-buf
          (condition-case nil
              (or (when (eq major-mode 'org-mode)
                    (cadar (org-collect-keywords '("title"))))
                  (when (buffer-file-name)
                    (file-name-base (buffer-file-name)))
                  (buffer-name)
                  "Untitled")
            (error "Untitled")))
      "Untitled")))

;; ============================================================
;; HELPER: Get denote: link from ORIGINAL buffer
;; ============================================================

(defun my/get-capture-origin-id ()
  "Get denote: link from the buffer where capture was initiated."
  (let ((orig-buf (org-capture-get :original-buffer)))
    (if orig-buf
        (with-current-buffer orig-buf
          (condition-case nil
              (let ((file-path (buffer-file-name)))
                (if file-path
                    (let ((id (denote-retrieve-filename-identifier file-path)))
                      (if id
                          (format "denote:%s" id)
                        (format "file:%s" file-path)))
                  "Untitled"))
            (error "Untitled")))
      "Untitled")))

;; ============================================================
;; CAPTURE WINDOW: open capture buffer to the right
;; ============================================================

(defun my/capture-display-right (buffer alist)
  "Display capture BUFFER in a window to the right.
If a right window already exists, reuse it.
Used via `display-buffer-alist'."
  (let* ((origin (selected-window))
         (right  (window-in-direction 'right origin)))
    (if right
        (progn
          (select-window right)
          (switch-to-buffer buffer)
          right)
      (let ((new-win (split-window origin nil 'right)))
        (select-window new-win)
        (switch-to-buffer buffer)
        new-win))))

(add-to-list 'display-buffer-alist
             '("\\*Org Capture\\*"
               (my/capture-display-right)))

;; ============================================================
;; ORG-CAPTURE: Templates
;; ============================================================

(use-package org-capture
  :ensure nil
  :config

  ;; Create captures file if it doesn't exist
  (unless (file-exists-p my-journal-captures)
    (with-temp-file my-journal-captures
      (insert "#+title: Ideas\n")
      (insert "#+filetags: :captures:\n\n")
      (insert "* Ideas\n\n")))

  ;; Create fleeting file if it doesn't exist
  (unless (file-exists-p my-fleeting-file)
    (with-temp-file my-fleeting-file
      (insert "#+title: Fleeting Notes\n")
      (insert "#+filetags: :fleeting:\n\n")
      (insert "* Inbox\n\n")))

  (setq org-capture-templates
        '(("j" "Ideas capture" entry
           (file+headline my-journal-captures "Ideas")
           "* \n:PROPERTIES:\n:SOURCE: [[%(my/get-capture-origin-id)][%(my/get-capture-origin-title)]]\n:CAPTURED: %U\n:END:\n%?"
           :empty-lines 1
           :prepend nil)

          ("f" "Fleeting Note" entry
           (file+headline my-fleeting-file "Inbox")
           "* %?\nCaptured: %U\n"
           :empty-lines 1
           :prepend nil))))

;; ============================================================
;; DIRECT CAPTURE: C-c n c fires template "j" without menu
;; ============================================================

(defun my/capture-idea ()
  "Directly invoke Ideas capture (template j) — no menu shown.
Opens capture buffer to the right of the current window.
Records SOURCE link to the originating note automatically."
  (interactive)
  (org-capture nil "j"))

;; ============================================================
;; OPEN FLEETING NOTES in side window
;; ============================================================

(defun my/open-fleeting-notes ()
  "Open fleeting notes file in a window to the right."
  (interactive)
  (let* ((origin (selected-window))
         (right  (window-in-direction 'right origin))
         (win    (or right (split-window origin nil 'right))))
    (select-window win)
    (find-file my-fleeting-file)
    (goto-char (point-max))))

;; ============================================================
;; HELPER: Extract SOURCE value from PROPERTIES block
;; ============================================================

(defun my/--capture-extract-source (text)
  "Extract the raw value of :SOURCE: property from TEXT string.
Returns the value string or nil if not found."
  (when (string-match ":SOURCE:[ \t]+\\(.+\\)" text)
    (string-trim (match-string 1 text))))

;; ============================================================
;; HELPER: Strip PROPERTIES block from TEXT string
;; ============================================================

(defun my/--capture-strip-properties (text)
  "Remove :PROPERTIES:...:END: block from TEXT string.
Uses a safe multiline regex."
  (replace-regexp-in-string
   "\\(:PROPERTIES:\\(?:.\\|\n\\)*?:END:\\)\n?" "" text nil nil 1))

;; ============================================================
;; PROMOTE CAPTURE HEADING TO NEW DENOTE NOTE
;; ============================================================

(defun my/capture-promote-to-note ()
  "Create a new Denote note from the heading at point in captures.org.

What this does:
- Uses heading text as proposed title (editable)
- Asks for tags and silo — identical prompts to my/denote-base
- Calls (denote title keywords) for consistent front matter
- Adds #+source: to front matter if SOURCE property exists
- Copies subtree body (H3/H4 included, stops before next H2)
- Removes the original heading from captures.org after success

The SOURCE link (reference to the originating note) is preserved
as #+source: in the new note's front matter. Remove it manually
if not needed."
  (interactive)
  (unless (eq major-mode 'org-mode)
    (user-error "Not in org-mode"))
  ;; Validate we are on or inside a heading
  (save-excursion
    (condition-case nil
        (org-back-to-heading t)
      (error (user-error "Not inside an org heading"))))
  (let* (;; -- Collect heading data --
         (heading-title (org-get-heading t t t t))
         (title         (read-string "Note title: " heading-title))
         (tags-input    (read-string "Tags (space-separated): "))
         (keywords      (unless (string-empty-p tags-input)
                          (split-string tags-input " " t)))
         (silo          (completing-read "Save in: " '("pks" "docu") nil t "pks"))
         (target-dir    (if (string= silo "docu") my-notes-docu my-notes-pks))
         ;; -- Extract subtree body (everything under the heading) --
         (subtree-raw
          (save-excursion
            (org-back-to-heading t)
            (forward-line 1)                      ; skip heading line itself
            (let ((beg (point))
                  (end (save-excursion
                         (org-end-of-subtree t)   ; stops before next same-level heading
                         (point))))
              (buffer-substring-no-properties beg end))))
         ;; -- Extract SOURCE before stripping PROPERTIES --
         (source-value  (my/--capture-extract-source subtree-raw))
         ;; -- Clean body: strip PROPERTIES block, trim whitespace --
         (body          (string-trim (my/--capture-strip-properties subtree-raw)))
         ;; -- Remember captures buffer and region for cleanup --
         (captures-buf  (current-buffer))
         (heading-beg   (save-excursion (org-back-to-heading t) (point)))
         (heading-end   (save-excursion
                          (org-end-of-subtree t)
                          (forward-line 1)
                          (point))))

    ;; -- Create Denote note: identical mechanism to my/denote-base --
    (let ((denote-directory target-dir))
      (denote title keywords))

    ;; -- Insert body content with optional source link at top --
    (goto-char (point-max))
    (if source-value
        ;; Source exists: link as first visible line, then body
        (progn
          (insert (format "Source: %s\n" source-value))
          (unless (string-empty-p body)
            (insert "\n" body "\n")))
      ;; No source: just body
      (unless (string-empty-p body)
        (insert "\n\n" body "\n")))
    
    (save-buffer)

    ;; -- Remove original heading from captures.org --
    (with-current-buffer captures-buf
      (delete-region heading-beg heading-end)
      (save-buffer))

    (message "✓ Note created: \"%s\" → %s/" title silo)))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c c")   'org-capture)
(global-set-key (kbd "C-c n c") 'my/capture-idea)
(global-set-key (kbd "C-c n f") 'my/open-fleeting-notes)
(global-set-key (kbd "C-c n m") 'my/capture-promote-to-note)

(provide '06-capture)
;;; 06-capture.el ends here
