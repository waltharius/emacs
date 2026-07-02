;;; 20-transclusion.el --- Obsidian-style transclusion for Denote notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Wizard-style transclusion: pick a note (Denote completion), pick whole
;; note or a heading, generate/reuse a CUSTOM_ID for the heading, and
;; insert both:
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
;; INSERT HELPERS: build the transclude + include pair
;; ============================================================

(defun my/--transclusion-insert-whole (file title)
  "Insert transclude + include pair for the WHOLE FILE with TITLE."
  (let ((line-start (point)))
    (insert (format "#+transclude: [[file:%s][%s]] :only-contents\n" file title))
    (insert (format "#+INCLUDE: \"%s\" :only-contents t\n" file))
    (goto-char line-start)
    (org-transclusion-add)
    (goto-char (point-max))))

(defun my/--transclusion-insert-heading (file title custom-id heading-title)
  "Insert transclude + include pair for a HEADING (by CUSTOM-ID) in FILE."
  (let ((line-start (point))
        (link-desc (format "%s — %s" title heading-title)))
    (insert (format "#+transclude: [[file:%s::#%s][%s]] :only-contents\n"
                    file custom-id link-desc))
    (insert (format "#+INCLUDE: \"%s::#%s\" :only-contents t\n" file custom-id))
    (goto-char line-start)
    (org-transclusion-add)
    (goto-char (point-max))))

;; ============================================================
;; MAIN WIZARD: pick note -> pick target -> insert transclude pair
;; Docs: ~/.emacs.d/function_helper.org::#fn-my-denote-transclude-insert
;; ============================================================

(defun my/denote-transclude-insert ()
  "Obsidian-style transclusion wizard for Denote notes.

Steps:
1. Prompt for a note via Denote's completion (title search).
2. Prompt for whole note or a specific heading.
3. If a heading is chosen and has no CUSTOM_ID, generate one from the
   heading title (spaces -> hyphens, non-alnum stripped) and save it
   into the SOURCE file's PROPERTIES drawer.
4. Insert two lines at point in the CURRENT buffer:
   - `#+transclude:' -> live in-buffer transclusion (org-transclusion)
   - `#+INCLUDE:'    -> static pair used only at export time
5. Immediately call `org-transclusion-add' so content is visible
   right away, without a separate keystroke.

Requires the target to be a saved .org file reachable via an absolute
`file:' link. Denote's own `denote:' link type is intentionally NOT
used here because `#+INCLUDE:' needs a real file path, not a custom
link type."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (let* ((file (denote-file-prompt nil "Transclude which note: ")))
    (unless file
      (user-error "No note selected"))
    (let* ((file     (expand-file-name file))
           (title    (my/--org-title-of file))
           (headings (my/--org-file-headings file))
           (choices  (cons "Whole note" (mapcar #'car headings)))
           (choice   (completing-read "Transclude: " choices nil t)))
      (if (string= choice "Whole note")
          (my/--transclusion-insert-whole file title)
        (let* ((pos (cdr (assoc choice headings)))
               (heading-title (string-trim
                                (replace-regexp-in-string "^\\*+[ \t]+" "" choice)))
               (custom-id (my/--ensure-custom-id file pos heading-title)))
          (my/--transclusion-insert-heading file title custom-id heading-title))))))

;; ============================================================
;; SUB-MENU: Transclusion  (C-c n i t)
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-transclusion
;; ============================================================

(transient-define-prefix my/transclusion-menu ()
  "Obsidian-style transclusion for Denote notes."
  [["Insert"
    ("a" "Add transclusion (wizard)" my/denote-transclude-insert)
    ("A" "Add all in buffer"         org-transclusion-add-all)]
   ["Manage"
    ("g" "Refresh at point" org-transclusion-refresh)
    ("r" "Remove at point"  org-transclusion-remove)
    ("T" "Toggle mode"      org-transclusion-mode)]
   ["Advanced"
    ("m" "Full org-transclusion menu" org-transclusion-transient-menu)]
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
