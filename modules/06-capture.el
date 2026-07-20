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

(require 'org)
(require 'org-capture)
(require 'org-element)
(require 'subr-x)
(require 'seq)
;; This module calls `denote', `denote-retrieve-filename-identifier'
;; and reads `denote-last-path', so declare the dependency explicitly
;; instead of relying on load order of other modules.
(require 'denote)

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
                  (when (and (boundp dir)
                             (symbol-value dir)
                             (file-directory-p (symbol-value dir)))
                    (expand-file-name (symbol-value dir))))
                '(my-notes-journal my-notes-pks my-notes-docu))))

(defun my/--find-notes-by-title-global (title)
  "Return a list of .org files whose #+title matches TITLE across all silos.
Comparison is case-insensitive and ignores surrounding whitespace."
  (let ((wanted (downcase (string-trim title)))
        matches)
    (dolist (dir (my/--all-note-silos))
      (dolist (file (directory-files-recursively dir "\\.org\\'"))
        (let ((file-title (my/--note-get-title file)))
          (when (and file-title
                     (string= (downcase (string-trim file-title)) wanted))
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

;; ============================================================
;; HELPERS: Building and inserting the promoted fragment
;; ============================================================

(defun my/--note-fragment (body source-value)
  "Return the text fragment to insert into a note.
Combines an optional 'Source: ...' line (from SOURCE-VALUE) with
BODY.  Returns an empty string when both are empty."
  (concat
   (when (and source-value (not (string-empty-p source-value)))
     (format "Source: %s\n\n" source-value))
   (when (and body (not (string-empty-p body)))
     (if (string-suffix-p "\n" body) body (concat body "\n")))))

(defun my/--append-to-note (file body source-value)
  "Append BODY to FILE.
Insert SOURCE-VALUE first only when it differs from the last
existing 'Source: ...' line in FILE."
  (let* ((last-source (my/--note-last-source file))
         ;; Suppress the duplicate Source line by passing nil.
         (effective-source
          (unless (and source-value last-source
                       (string= (string-trim source-value)
                                (string-trim last-source)))
            source-value))
         (fragment (my/--note-fragment body effective-source)))
    (unless (string-empty-p fragment)
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (unless (bolp)
          (insert "\n"))
        (unless (looking-back "\n\n" nil)
          (insert "\n"))
        (insert fragment)
        (save-buffer)))))

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

(defun my/--insert-note-body-at-top (body source-value)
  "Insert SOURCE-VALUE and BODY into current Denote note after front matter.
Leaves exactly one blank line between the front matter and the
inserted fragment."
  (save-excursion
    (goto-char (point-min))
    ;; Skip optional blank lines at the very top.
    ;; NOTE: every whitespace-skipping loop below MUST be guarded with
    ;; (not (eobp)).  At end of buffer `looking-at-p' still matches
    ;; \"^[[:space:]]*$\" (an empty line) while `forward-line' can no
    ;; longer move point, so an unguarded loop spins forever.  A fresh
    ;; Denote note contains nothing after the front matter, which is
    ;; exactly the case that used to freeze note creation.
    (while (and (not (eobp)) (looking-at-p "^[[:space:]]*$"))
      (forward-line 1))
    ;; Move across every consecutive front matter line: #+title:,
    ;; #+date:, #+filetags:, #+identifier:, etc.
    (while (and (not (eobp)) (looking-at-p "^#\\+[[:alnum:]_-]+:"))
      (forward-line 1))
    ;; Normalise: delete all blank lines directly after the front
    ;; matter, then insert exactly one separator line ourselves.
    (let ((blank-beg (point)))
      (while (and (not (eobp)) (looking-at-p "^[[:space:]]*$"))
        (forward-line 1))
      (delete-region blank-beg (point)))
    (insert "\n")
    (insert (my/--note-fragment body source-value))))

;; ============================================================
;; HELPERS: Reading the capture heading
;; ============================================================

(defun my/--strip-properties-drawer (text)
  "Return TEXT with a leading :PROPERTIES: drawer removed and trimmed."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (when (looking-at-p ":PROPERTIES:")
      (let ((drawer-beg (point)))
        (when (re-search-forward "^:END:[ \t]*\n?" nil t)
          (delete-region drawer-beg (point)))))
    (string-trim (buffer-string))))

(defun my/--capture-promote-target-point ()
  "Return buffer position of heading that should be promoted.
If point is on a subheading, ask whether to use current heading or parent.
Top-level capture headings are used directly."
  (save-excursion
    (org-back-to-heading t)
    (let ((current-point (point))
          (current-level (org-outline-level)))
      (if (<= current-level 2)
          current-point
        (let ((choice
               (completing-read
                "Promote: "
                '("current heading" "parent heading")
                nil t nil nil "parent heading")))
          (cond
           ((string= choice "current heading")
            current-point)
           ((save-excursion
              (org-up-heading-safe)
              (point)))
           (t current-point)))))))

(defun my/--capture-heading-data-at (pos)
  "Return plist with heading data for subtree at POS.
Result contains :title :source :body :beg :end.
:beg and :end are markers so later buffer edits cannot invalidate them."
  (save-excursion
    (goto-char pos)
    (org-back-to-heading t)
    (let* ((title (org-get-heading t t t t))
           (source (org-entry-get (point) "SOURCE"))
           (beg (copy-marker (point)))
           (end (copy-marker
                 (save-excursion
                   (org-end-of-subtree t)
                   (forward-line 1)
                   (point))))
           (element (org-element-at-point))
           (contents-begin (org-element-property :contents-begin element))
           (contents-end   (org-element-property :contents-end element))
           (body
            (if (and contents-begin contents-end)
                (my/--strip-properties-drawer
                 (buffer-substring-no-properties contents-begin contents-end))
              "")))
      (list :title title
            :source source
            :body body
            :beg beg
            :end end))))

;; ============================================================
;; PROMOTE CAPTURE HEADING TO DENOTE NOTE (create or append)
;; ============================================================

(defun my/--capture-remove-heading (buffer beg end)
  "Delete region BEG..END (markers) in BUFFER and save it."
  (with-current-buffer buffer
    (delete-region beg end)
    (save-buffer))
  ;; Detach markers so they no longer slow down buffer editing.
  (set-marker beg nil)
  (set-marker end nil))

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
  (let* ((target-pos    (my/--capture-promote-target-point))
         (target-data   (my/--capture-heading-data-at target-pos))
         (heading-title (plist-get target-data :title))
         (title         (read-string "Note title: " heading-title))
         (tags-input    (read-string "Tags (space-separated): "))
         (keywords      (unless (string-empty-p tags-input)
                          (split-string tags-input " " t)))
         (silo-key      (read-char-choice
                         "Save in: [j]ournal [p]ks [d]ocu: "
                         '(?j ?p ?d)))
         (silo          (pcase silo-key
                          (?j "journal")
                          (?d "docu")
                          (_  "pks")))
         (target-dir    (pcase silo
                          ("journal" my-notes-journal)
                          ("docu"    my-notes-docu)
                          (_         my-notes-pks)))
         (source-value  (plist-get target-data :source))
         (body          (plist-get target-data :body))
         (captures-buf  (current-buffer))
         (heading-beg   (plist-get target-data :beg))
         (heading-end   (plist-get target-data :end))
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
        (my/--capture-remove-heading captures-buf heading-beg heading-end)
        (message "✓ Appended to existing note: \"%s\"" title)))

     (t
      ;; `denote-directory' is a defcustom (special variable), so a
      ;; dynamic let-binding redirects note creation into the silo.
      (let ((denote-directory target-dir))
        (denote title keywords))
      ;; `denote' leaves the new note buffer current, but do not rely on
      ;; that implicitly: operate on the file it records in
      ;; `denote-last-path'.
      (with-current-buffer (or (and denote-last-path
                                    (find-buffer-visiting denote-last-path))
                               (current-buffer))
        (my/--insert-note-body-at-top body source-value)
        (save-buffer))
      (my/--capture-remove-heading captures-buf heading-beg heading-end)
      (message "✓ Note created: \"%s\" → %s/" title silo)))))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c c") 'org-capture)

(provide '06-capture)
;;; 06-capture.el ends here
