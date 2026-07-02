;;; 20-transclusion.el --- Obsidian-style transclusion for Denote notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Wizard-style transclusion: pick a note (Denote completion, or any file
;; on disk), pick whole note / heading / paragraph, generate a stable
;; anchor (CUSTOM_ID for headings, <<target>> for paragraphs), and insert
;; both:
;;   #+transclude: ...  -> live, editable in-buffer transclusion (org-transclusion)
;;   #+INCLUDE: ...      -> static pair used only at export time (PDF/HTML/etc.)
;;
;; Access: C-c n i t  (Insert -> Transclusion submenu)
;;
;; LOADING: must load AFTER 12-transient.el (appends "t" entry to
;; my/notes-insert-menu, same pattern as 19-philosophy-notes.el).
;;
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-transclusion

;;; Code:

(require 'org)
(require 'denote)
(require 'transient)
(require 'cl-lib)

(use-package org-transclusion
  :ensure t
  :after org
  :custom
  ;; Safer default: do not auto-transclude everything when opening a file
  ;; with many #+transclude keywords — could be slow on large collections.
  (org-transclusion-add-all-on-activate nil))

;; ============================================================
;; HELPER: slugify heading title for CUSTOM_ID
;; ============================================================

(defun my/--transclusion-slugify (title)
  "Turn TITLE into a CUSTOM_ID-safe slug.
Spaces become hyphens; non-alphanumeric characters are stripped.
Falls back to a short random id if TITLE becomes empty after cleanup."
  (let* ((slug (downcase (string-trim title)))
         (slug (replace-regexp-in-string "[ \t]+" "-" slug))
         (slug (replace-regexp-in-string "[^[:alnum:]-]" "" slug))
         (slug (replace-regexp-in-string "-+" "-" slug))
         (slug (string-trim slug "-" "-")))
    (if (string-empty-p slug)
        (format "note-%d" (random 100000))
      slug)))

;; ============================================================
;; HELPER: collect headings from an Org file (display . position)
;; ============================================================

(defun my/--org-file-headings (file)
  "Return a list of (DISPLAY . POSITION) for all headings in FILE.
DISPLAY is prefixed with stars to show heading depth."
  (let (headings)
    (with-temp-buffer
      (insert-file-contents file)
      (org-mode)
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*+\\)[ \t]+\\(.*\\)$" nil t)
        (let* ((stars (match-string 1))
               (title (string-trim (match-string 2)))
               (display (format "%s %s" stars title)))
          (push (cons display (point)) headings))))
    (nreverse headings)))

;; ============================================================
;; HELPER: title of an .org file (from #+title:)
;; ============================================================

(defun my/--org-title-of (file)
  "Return #+title: of FILE, or its base filename if not found."
  (with-temp-buffer
    (insert-file-contents file nil 0 2000)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+title:[ \t]*\\(.+\\)$" nil t)
        (string-trim (match-string 1))
      (file-name-base file))))

;; ============================================================
;; HELPER: ensure a heading has CUSTOM_ID; writes to disk if missing
;; ============================================================

(defun my/--ensure-custom-id (file heading-pos heading-title)
  "Ensure the heading at HEADING-POS in FILE has a CUSTOM_ID property.
Returns the CUSTOM_ID string (existing or newly generated).
Modifies and SAVES FILE if a CUSTOM_ID has to be created — be aware
this is a write side-effect on a file you did not directly open."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char heading-pos)
      (org-back-to-heading t)
      (let ((existing (org-entry-get (point) "CUSTOM_ID")))
        (if existing
            existing
          (let ((new-id (my/--transclusion-slugify heading-title)))
            (org-set-property "CUSTOM_ID" new-id)
            (save-buffer)
            new-id))))))

;; ============================================================
;; PARAGRAPH MODE: extract, browse, and anchor a single paragraph
;; ============================================================

(defun my/--extract-paragraphs (file)
  "Return a list of (TEXT . END-POSITION) for all paragraphs in FILE.
Skips heading lines, property drawers, keyword lines (#+...), and
blank lines. This is a simple line-based heuristic, not a full Org
parser — tables, lists, and source blocks may be grouped imprecisely."
  (let (paragraphs)
    (with-temp-buffer
      (insert-file-contents file)
      (org-mode)
      (goto-char (point-min))
      (while (not (eobp))
        (cond
         ((or (looking-at "^\\*+[ \t]")
              (looking-at "^[ \t]*:\\(PROPERTIES\\|END\\):")
              (looking-at "^[ \t]*$")
              (looking-at "^#\\+"))
          (forward-line 1))
         (t
          (let ((beg (point)))
            (forward-paragraph)
            (let* ((end (point))
                   (text (string-trim (buffer-substring-no-properties beg end))))
              (unless (string-empty-p text)
                (push (cons text end) paragraphs))))))))
    (nreverse paragraphs)))

(defun my/--random-alnum-string (length)
  "Generate a random alphanumeric string of LENGTH characters."
  (let ((chars "abcdefghijklmnopqrstuvwxyz0123456789"))
    (apply #'string
           (cl-loop repeat length
                    collect (aref chars (random (length chars)))))))

(defun my/--unique-paragraph-target (existing-targets)
  "Generate a random paragraph target id not present in EXISTING-TARGETS."
  (let (candidate)
    (while (or (null candidate) (member candidate existing-targets))
      (setq candidate (my/--random-alnum-string 7)))
    candidate))

(defun my/--existing-targets-in-file (file)
  "Return a list of all <<target>> names already present in FILE."
  (let (targets)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward "<<\\([^>]+\\)>>" nil t)
        (push (match-string 1) targets)))
    targets))

(defun my/--pick-paragraph-in-file (file)
  "Browse paragraphs of FILE one at a time in a preview window.
n/p cycle through paragraphs, RET confirms the one shown, q/C-g cancels.
Returns the target id string (existing or newly created), or nil if
the user cancelled."
  (let* ((paragraphs (my/--extract-paragraphs file))
         (total (length paragraphs)))
    (unless paragraphs
      (user-error "No paragraphs found in %s" file))
    (let* ((idx 0)
           (preview-buf (get-buffer-create "*Transclusion Paragraph Preview*"))
           (preview-win (display-buffer preview-buf
                                         '(display-buffer-at-bottom
                                           (window-height . 0.35))))
           (confirmed nil)
           (done nil))
      (unwind-protect
          (progn
            (while (not done)
              (with-current-buffer preview-buf
                (erase-buffer)
                (insert (format "Paragraph %d/%d — n=next p=prev RET=select q=cancel\n"
                                (1+ idx) total))
                (insert (make-string 60 ?-) "\n\n")
                (insert (car (nth idx paragraphs))))
              (with-selected-window preview-win
                (goto-char (point-min)))
              (let ((key (read-key)))
                (cond
                 ((eq key ?n) (setq idx (mod (1+ idx) total)))
                 ((eq key ?p) (setq idx (mod (1- idx) total)))
                 ((memq key '(13 return)) (setq done t confirmed t))
                 ((memq key (list ?q 7)) (setq done t confirmed nil)))))
            (when confirmed
              (let* ((chosen (nth idx paragraphs))
                     (end-pos (cdr chosen)))
                (with-current-buffer (find-file-noselect file)
                  (save-excursion
                    (goto-char end-pos)
                    (skip-chars-backward " \t\n")
                    (if (looking-back "<<\\([^>]+\\)>>" (line-beginning-position))
                        (match-string 1)
                      (let ((new-id (my/--unique-paragraph-target
                                     (my/--existing-targets-in-file file))))
                        (insert (format " <<%s>>" new-id))
                        (save-buffer)
                        new-id)))))))
        (when (window-live-p preview-win)
          (delete-window preview-win))
        (kill-buffer preview-buf)))))

;; ============================================================
;; INSERT HELPERS: build the transclude + include pair
;; ============================================================

(defun my/--transclusion-insert-whole (file title)
  "Insert transclude + include pair for the WHOLE FILE with TITLE."
  (let ((line-start (point)))
    (insert (format "#+transclude: [[file:%s][%s]] \n" file title))
    (insert (format "#+INCLUDE: \"%s\"  t\n" file))
    (goto-char line-start)
    (org-transclusion-add)
    (goto-char (point-max))))

(defun my/--transclusion-insert-heading (file title custom-id heading-title)
  "Insert transclude + include pair for a HEADING (by CUSTOM-ID) in FILE."
  (let ((line-start (point))
        (link-desc (format "%s — %s" title heading-title)))
    (insert (format "#+transclude: [[file:%s::#%s][%s]] \n"
                    file custom-id link-desc))
    (insert (format "#+INCLUDE: \"%s::#%s\"  t\n" file custom-id))
    (goto-char line-start)
    (org-transclusion-add)
    (goto-char (point-max))))

(defun my/--transclusion-insert-paragraph (file title target-id)
  "Insert transclude + include pair for a PARAGRAPH (by TARGET-ID) in FILE."
  (let ((line-start (point))
        (link-desc (format "%s — paragraph" title)))
    (insert (format "#+transclude: [[file:%s::%s][%s]] \n"
                    file target-id link-desc))
    (insert (format "#+INCLUDE: \"%s::%s\"  t\n" file target-id))
    (goto-char line-start)
    (org-transclusion-add)
    (goto-char (point-max))))

;; ============================================================
;; MAIN WIZARD: pick source -> pick target -> insert transclude pair
;; Docs: ~/.emacs.d/function_helper.org::#fn-my-denote-transclude-insert
;; ============================================================

(defun my/denote-transclude-insert ()
  "Obsidian-style transclusion wizard.

Steps:
1. Choose source: a Denote note (title search) or any file on disk.
2. Choose target: whole note, a heading, or a specific paragraph.
   - Heading: CUSTOM_ID is generated from the title if missing, and
     saved into the SOURCE file's PROPERTIES drawer.
   - Paragraph: browse paragraphs one at a time (n/p/RET/q), a
     <<target>> anchor is generated and saved if missing.
3. Insert two lines at point in the CURRENT buffer:
   - `#+transclude:' -> live in-buffer transclusion (org-transclusion)
   - `#+INCLUDE:'    -> static pair used only at export time
4. Immediately call `org-transclusion-add' so content is visible
   right away.

Warning: heading and paragraph modes WRITE to the source file on disk
(adding CUSTOM_ID or <<target>>) if the anchor does not already exist.
Commit your notes before heavy first use."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (let* ((source-kind (completing-read "Source: " '("Denote note" "Any file on disk") nil t))
         (file (if (string= source-kind "Denote note")
                   (denote-file-prompt nil "Transclude which note: ")
                 (read-file-name "Transclude which file: " nil nil t))))
    (unless file
      (user-error "No file selected"))
    (let* ((file     (expand-file-name file))
           (title    (my/--org-title-of file))
           (headings (my/--org-file-headings file))
           (choices  (append '("Whole note" "Paragraph") (mapcar #'car headings)))
           (choice   (completing-read "Transclude: " choices nil t)))
      (cond
       ((string= choice "Whole note")
        (my/--transclusion-insert-whole file title))
       ((string= choice "Paragraph")
        (let ((target-id (my/--pick-paragraph-in-file file)))
          (if target-id
              (my/--transclusion-insert-paragraph file title target-id)
            (message "Paragraph selection cancelled"))))
       (t
        (let* ((pos (cdr (assoc choice headings)))
               (heading-title (string-trim
                                (replace-regexp-in-string "^\\*+[ \t]+" "" choice)))
               (custom-id (my/--ensure-custom-id file pos heading-title)))
          (my/--transclusion-insert-heading file title custom-id heading-title)))))))

;; ============================================================
;; SUB-MENU: Transclusion  (C-c n i t)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-transclusion
;; ============================================================

(transient-define-prefix my/transclusion-menu ()
  "Obsidian-style transclusion for Denote notes and arbitrary files."
  [["Insert"
    ("a" "Add transclusion (wizard)" my/denote-transclude-insert)
    ("A" "Add all in buffer"         org-transclusion-add-all)]
   ["Manage"
    ("g" "Refresh at point" org-transclusion-refresh)
    ("r" "Remove at point"  org-transclusion-remove)
    ("T" "Toggle mode"      org-transclusion-mode)]
   ["Advanced"
    ("o" "Open source at point" org-transclusion-open-source)
    ("O" "Move to source"       org-transclusion-move-to-source)
    ("e" "Live-sync edit"       org-transclusion-live-sync-start)
    ("E" "Exit live-sync"       org-transclusion-live-sync-exit)
    ("P" "Promote subtree"      org-transclusion-promote-subtree)
    ("D" "Demote subtree"       org-transclusion-demote-subtree)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; HOOK INTO INSERT SUBMENU (C-c n i)
;; ============================================================

(with-eval-after-load '12-transient
  (ignore-errors (transient-remove-suffix 'my/notes-insert-menu "t"))
  (transient-append-suffix 'my/notes-insert-menu "w"
    '("t" "Transclusion →" my/transclusion-menu)))

(provide '20-transclusion)
;;; 20-transclusion.el ends here
