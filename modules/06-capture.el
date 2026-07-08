;;; 06-capture.el --- Org-capture for ideas -*- lexical-binding: t; -*-
;;; Commentary:
;; Quick capture system for ideas and fleeting thoughts.
;;
;; C-c n c    — Ideas capture (opens to the RIGHT of the current window)
;; C-c c      — Standard org-capture menu
;;
;; Processing captures:
;; C-c n m    — Promote heading to Denote note (create or append)
;; C-c C-w    — Refile heading to existing note (standard org-refile)
;;
;; HOW THE RIGHT-SIDE WINDOW WORKS
;; --------------------------------
;; org-capture-mode-hook fires after the capture buffer is created
;; and displayed. At that point we:
;;   1. Remember which window was selected when capture was invoked
;;      (stored in my/capture--origin-window before org-capture runs).
;;   2. In the hook, delete all windows except the origin, then split
;;      right, and display the capture buffer in the new right window.
;; This bypasses display-buffer-alist entirely, which org-capture
;; ignores for its own buffer management.

;;; Code:

;; ============================================================
;; CAPTURE WINDOW: track origin window before capture fires
;; ============================================================

(defvar my/capture--origin-window nil
  "Window that was selected when `my/capture-idea' was invoked.
Used by `my/capture--show-right' to place the capture buffer
to the right of the originating note window.")

(defun my/capture--show-right ()
  "Place the just-created capture buffer to the right of the origin window.
Called from `org-capture-mode-hook'.
Only acts when `my/capture--origin-window' is set (i.e. capture was
started via `my/capture-idea', not the generic org-capture menu)."
  (when (and my/capture--origin-window
             (window-live-p my/capture--origin-window))
    (let ((cap-buf (current-buffer)))
      (delete-other-windows my/capture--origin-window)
      (let ((right-win (split-window my/capture--origin-window nil 'right)))
        (set-window-buffer right-win cap-buf)
        (select-window right-win))
      (setq my/capture--origin-window nil))))

(add-hook 'org-capture-mode-hook #'my/capture--show-right)

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

  (setq org-capture-templates
        '(("j" "Ideas capture" entry
           (file+headline my-journal-captures "Ideas")
           "* \n:PROPERTIES:\n:SOURCE: [[%(my/get-capture-origin-id)][%(my/get-capture-origin-title)]]\n:CAPTURED: %U\n:END:\n\n%?"
           :empty-lines 1
           :prepend nil))))

;; ============================================================
;; DIRECT CAPTURE: C-c n c fires template "j" without menu
;; ============================================================

(defun my/capture-idea ()
  "Directly invoke Ideas capture (template j) — no menu shown.
Opens capture buffer to the RIGHT of the current window.
Records SOURCE link to the originating note automatically."
  (interactive)
  (setq my/capture--origin-window (selected-window))
  (org-capture nil "j"))

;; ============================================================
;; HELPER: Extract SOURCE value from PROPERTIES block
;; ============================================================

(defun my/--capture-extract-source (text)
  "Extract the raw value of :SOURCE: property from TEXT string.
Returns the value string or nil if not found."
  (when (string-match ":SOURCE:[ \t]+\\(.+\\)" text)
    (string-trim (match-string 1))))

;; ============================================================
;; HELPER: Strip PROPERTIES block from TEXT string
;; ============================================================

(defun my/--capture-strip-properties (text)
  "Remove :PROPERTIES:...:END: block from TEXT string.
Uses a safe multiline regex."
  (replace-regexp-in-string
   "\\(:PROPERTIES:\\(?:.\\|\n\\)*?:END:\\)\n?" "" text nil nil 1))

;; ============================================================
;; HELPERS: Note lookup across silos
;; ============================================================

(defun my/--note-get-title (file)
  "Return #+title from FILE, or nil."
  (with-temp-buffer
    (insert-file-contents file nil 0 4096)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title:[ \t]+\\(.+\\)$" nil t)
      (string-trim (match-string 1)))))

(defun my/--all-note-silos ()
  "Return list of note silo directories to search."
  (delq nil
        (mapcar (lambda (dir)
                  (when (and dir (file-directory-p dir))
                    (expand-file-name dir)))
                (list my-notes-journal my-notes-pks my-notes-docu))))

(defun my/--find-notes-by-title-global (title)
  "Return a list of files whose #+title matches TITLE across all silos.
Comparison is case-insensitive and ignores surrounding whitespace."
  (let ((wanted (downcase (string-trim title)))
        matches)
    (dolist (dir (my/--all-note-silos))
      (dolist (file (denote-directory-files dir))
        (let ((file-title (my/--note-get-title file)))
          (when (and file-title
                     (string= (downcase file-title) wanted))
            (push file matches)))))
    (nreverse matches)))

(defun my/--note-last-source (file)
  "Return the last 'Source: ...' line found in FILE, or nil."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (last-source)
      (while (re-search-forward "^Source:[ \t]+\\(.+\\)$" nil t)
        (setq last-source (string-trim (match-string 1))))
      last-source)))

(defun my/--append-to-note (file body source-value)
  "Append BODY to FILE.
Insert SOURCE-VALUE first only when it differs from the last
existing 'Source: ...' line in FILE."
  (let ((last-source (my/--note-last-source file)))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (unless (bolp)
        (insert "\n"))
      (unless (looking-back "\n\n" nil)
        (insert "\n"))
      (when (and source-value
                 (not (string= (string-trim source-value)
                               (string-trim (or last-source "")))))
        (insert (format "Source: %s\n\n" source-value)))
      (unless (string-empty-p body)
        (insert body)
        (unless (bolp)
          (insert "\n")))
      (save-buffer))))

(defun my/--move-note-to-silo (file target-dir)
  "Move FILE to TARGET-DIR and return the new absolute path.
If FILE is visited by a buffer, update that buffer too."
  (let* ((target-dir (file-name-as-directory (expand-file-name target-dir)))
         (old-path   (expand-file-name file))
         (new-path   (expand-file-name (file-name-nondirectory old-path) target-dir))
         (buf        (find-buffer-visiting old-path)))
    (unless (file-equal-p (file-name-directory old-path) target-dir)
      (rename-file old-path new-path 1)
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (set-visited-file-name new-path t t))))
    new-path))

;; ============================================================
;; PROMOTE CAPTURE HEADING TO DENOTE NOTE (create or append)
;; ============================================================

(defun my/capture-promote-to-note ()
  "Promote capture heading to a Denote note.

Behavior:
- Ask for title, tags, and preferred silo.
- Search all silos for an existing note with the same #+title.
- If none exists, create a new note in the chosen silo.
- If exactly one exists in the same silo, append to it.
- If exactly one exists in another silo, ask whether to move it to the
  chosen silo before appending.
- If multiple notes with the same title exist, abort with a warning.

Only the capture body is copied. The PROPERTIES drawer is stripped.
A 'Source: ...' line is inserted before the appended fragment only if it
differs from the last Source: line already present in the target note."
  (interactive)
  (unless (eq major-mode 'org-mode)
    (user-error "Not in org-mode"))
  (save-excursion
    (condition-case nil
        (org-back-to-heading t)
      (error (user-error "Not inside an org heading"))))
  (let* ((heading-title (org-get-heading t t t t))
         (title         (read-string "Note title: " heading-title))
         (tags-input    (read-string "Tags (space-separated): "))
         (keywords      (unless (string-empty-p tags-input)
                          (split-string tags-input " " t)))
         (silo          (completing-read "Save in: " '("journal" "pks" "docu") nil t "pks"))
         (target-dir    (pcase silo
                          ("journal" my-notes-journal)
                          ("docu"    my-notes-docu)
                          (_         my-notes-pks)))
         (subtree-raw
          (save-excursion
            (org-back-to-heading t)
            (forward-line 1)
            (let ((beg (point))
                  (end (save-excursion
                         (org-end-of-subtree t)
                         (point))))
              (buffer-substring-no-properties beg end))))
         (source-value  (my/--capture-extract-source subtree-raw))
         (body          (string-trim (my/--capture-strip-properties subtree-raw)))
         (captures-buf  (current-buffer))
         (heading-beg   (save-excursion
                          (org-back-to-heading t)
                          (point)))
         (heading-end   (save-excursion
                          (org-end-of-subtree t)
                          (forward-line 1)
                          (point)))
         (matches       (my/--find-notes-by-title-global title)))

    (cond
     ((> (length matches) 1)
      (user-error
       "Found %d notes with title \"%s\". Resolve duplicates first."
       (length matches) title))

     ((= (length matches) 1)
      (let* ((existing-file (car matches))
             (existing-dir  (file-name-directory existing-file))
             (same-silo
              (file-equal-p
               (file-name-as-directory (expand-file-name existing-dir))
               (file-name-as-directory (expand-file-name target-dir))))
             (final-file
              (if same-silo
                  existing-file
                (if (y-or-n-p
                     (format
                      "Note exists in %s, not %s. Move it to %s and append? "
                      (abbreviate-file-name existing-dir)
                      silo
                      silo))
                    (my/--move-note-to-silo existing-file target-dir)
                  existing-file))))
        (my/--append-to-note final-file body source-value)
        (with-current-buffer captures-buf
          (delete-region heading-beg heading-end)
          (save-buffer))
        (message "✓ Appended to existing note: \"%s\"" title)))

     (t
      (let ((denote-directory target-dir))
        (denote title keywords))
      (goto-char (point-max))
      (unless (bolp)
        (insert "\n"))
      (unless (looking-back "\n\n" nil)
        (insert "\n"))
      (when source-value
        (insert (format "Source: %s\n\n" source-value)))
      (unless (string-empty-p body)
        (insert body)
        (unless (bolp)
          (insert "\n")))
      (save-buffer)
      (with-current-buffer captures-buf
        (delete-region heading-beg heading-end)
        (save-buffer))
      (message "✓ Note created: \"%s\" → %s/" title silo)))))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c c") 'org-capture)

(provide '06-capture)
;;; 06-capture.el ends here
