;;; 44-image-display.el --- Hide inline images while writing -*- lexical-binding: t; -*-
;;; Commentary:
;; One command, `my/image-display-toggle', that shows or hides inline
;; images in the whole buffer and records the choice inside the note, so
;; that reopening the note keeps it.
;;
;; WHY A COMMAND AT ALL, GIVEN ORG HAS ONE
;; ---------------------------------------
;; Org's own key is `C-c C-x C-v', and what it does depends on the Org
;; generation: up to 9.7 it runs `org-toggle-inline-images-command',
;; which acts on the current section or the image at point and needs a
;; prefix argument for the whole buffer; from 9.8 it runs
;; `org-link-preview', which previews the current entry and needs
;; `C-u C-u' / `C-u C-u C-u' for the whole buffer.  Neither default is
;; "turn the pictures off while I write this note", which is the only
;; thing wanted here, and neither survives closing the file.
;;
;; WHY THE CHOICE IS WRITTEN INTO `#+startup:'
;; -------------------------------------------
;; Org already reads `#+startup: inlineimages' and `#+startup:
;; noinlineimages' when it opens a file, so recording the decision there
;; needs no state file, no registry keyed by path, and nothing that can
;; drift from the note when the note is renamed -- which Denote does
;; routinely.  The setting travels with the file over Syncthing, into
;; git, and into any other editor.  A token is always written rather
;; than the line being removed, so a note that has been decided on says
;; so explicitly and does not silently fall back to the global default
;; in `11-org-appearance.el'.
;;
;; The buffer is NOT saved, matching `my/text-width-save-to-note' in
;; 10-visual-fill.el: the command changes the note, saving it stays the
;; writer's decision.
;;
;; MARKDOWN IS SESSION-ONLY
;; ------------------------
;; markdown-mode has no startup keyword and its image display is a plain
;; buffer-local list of overlays, so there is nowhere in a `.md' file to
;; record the choice without inventing a convention that only this
;; configuration understands.  The toggle therefore works in Markdown
;; buffers and forgets after they are closed; the global default for
;; those is `my/markdown-display-images-on-open' in 40-markdown.el.
;;
;; WHY NOT INSIDE 31-org-images.el
;; -------------------------------
;; That module owns *producing* images -- copying them into the
;; attachment folder, compressing them, naming them.  This one owns
;; whether they are drawn, in two major modes, and is useful with
;; 31-org-images.el deleted.  It duplicates the three-line version shim
;; instead of calling `my/org-image--preview-region', which is private
;; to that module, so that neither file has to load for the other to
;; work.
;;
;; Keys: `C-c u i', and `m' in the View menu (`C-c n v').
;;
;; Docs: ~/.emacs.d/function_helper.org::#image-display

;;; Code:

(require 'seq)
(require 'subr-x)

(declare-function my/note-keyword "00-core" (name))
(declare-function my/note-keyword-set "00-core" (name value))
(declare-function my/transient-append "12-transient" (prefix anchor suffix))

(defgroup my-image-display nil
  "Showing and hiding inline images in note buffers."
  :group 'convenience)

(defcustom my/image-display-record-choice t
  "When non-nil, write the choice into the note's `#+startup:' line.

Org buffers visiting a file only; Markdown has nowhere to put it.  A
prefix argument to `my/image-display-toggle' suppresses the write for
one call, which is the right thing when the note is only being read."
  :type 'boolean :group 'my-image-display)

(defconst my/image-display-startup-tokens '("inlineimages" "noinlineimages")
  "The two `#+startup:' tokens this module owns.
Any other token on the line is preserved untouched.")

(defvar-local my/image-display--shown nil
  "Fallback record of whether previews are on in this buffer.
Consulted only when neither Org nor markdown-mode exposes its overlay
list, so that the toggle still alternates instead of sticking.")

;; ============================================================
;; CURRENT STATE
;; ============================================================

(defun my/image-display--shown-p ()
  "Return non-nil when inline images are currently drawn in this buffer.

Read from the overlay list the major mode keeps, because that is the
truth: a note opened with images off, then refreshed by some other
command, must not be reported from a flag this module set earlier.
Org 9.8 renamed the list along with the commands, so both names are
tried before the flag is used."
  (cond
   ((derived-mode-p 'org-mode)
    (cond
     ((boundp 'org-link-preview-overlays) (and org-link-preview-overlays t))
     ((boundp 'org-inline-image-overlays) (and org-inline-image-overlays t))
     (t my/image-display--shown)))
   ((derived-mode-p 'markdown-mode)
    (if (boundp 'markdown-inline-image-overlays)
        (and markdown-inline-image-overlays t)
      my/image-display--shown))
   (t my/image-display--shown)))

;; ============================================================
;; APPLYING IT
;; ============================================================

(defun my/image-display--apply (show)
  "Draw inline images in the whole buffer when SHOW, remove them otherwise.

Every command name here is optional: Org 9.8 renamed
`org-display-inline-images' to `org-link-preview-region' and
`org-remove-inline-images' to `org-link-preview-clear', and
markdown-mode may not be installed at all.  All four are called with no
arguments, which every generation reads as \"the accessible portion of
the buffer\", so the widening below is what makes the scope the whole
file rather than the narrowing in force."
  (save-restriction
    (widen)
    (cond
     ((derived-mode-p 'org-mode)
      (if show
          (cond ((fboundp 'org-link-preview-region) (org-link-preview-region))
                ((fboundp 'org-display-inline-images) (org-display-inline-images)))
        (cond ((fboundp 'org-link-preview-clear) (org-link-preview-clear))
              ((fboundp 'org-remove-inline-images) (org-remove-inline-images)))))
     ((derived-mode-p 'markdown-mode)
      (if show
          (when (fboundp 'markdown-display-inline-images)
            (markdown-display-inline-images))
        (when (fboundp 'markdown-remove-inline-images)
          (markdown-remove-inline-images))))))
  (setq my/image-display--shown show))

;; ============================================================
;; RECORDING IT IN THE NOTE
;; ============================================================

(defun my/image-display--record (show)
  "Write the SHOW decision into this buffer's `#+startup:' line.

Returns non-nil when the front matter was changed.  Other tokens on the
line -- `overview', `indent' and the rest -- are kept in the order they
were written in; only the pair this module owns is replaced."
  (when (and my/image-display-record-choice
             (derived-mode-p 'org-mode)
             (buffer-file-name)
             (not buffer-read-only)
             (fboundp 'my/note-keyword-set))
    (let* ((current (or (my/note-keyword "startup") ""))
           (kept (seq-remove (lambda (token)
                               (member token my/image-display-startup-tokens))
                             (split-string current "[ \t]+" t)))
           (wanted (if show "inlineimages" "noinlineimages")))
      (my/note-keyword-set "startup" (string-join (append kept (list wanted)) " "))
      t)))

;; ============================================================
;; THE COMMAND
;; ============================================================

;;;###autoload
(defun my/image-display-toggle (&optional arg)
  "Show or hide inline images in the whole buffer.

In an Org note the decision is also written into `#+startup:', so the
note opens the same way next time; the buffer is left modified and
unsaved.  With a prefix ARG the front matter is not touched and the
change lasts for this session only.

Markdown buffers are always session-only -- see the header of
44-image-display.el for why."
  (interactive "P")
  (unless (derived-mode-p 'org-mode 'markdown-mode)
    (user-error "Inline images are handled here only in Org and Markdown buffers"))
  (let* ((show (not (my/image-display--shown-p)))
         (recorded (and (not arg) (my/image-display--record show))))
    (my/image-display--apply show)
    (message "Inline images: %s%s"
             (if show "on" "off")
             (cond (recorded "  -- written to front matter, buffer not saved")
                   ((derived-mode-p 'markdown-mode) "  -- this session only")
                   (arg "  -- this session only")
                   (t "")))))

;; ============================================================
;; KEYS AND MENU
;; ============================================================

(global-set-key (kbd "C-c u i") #'my/image-display-toggle)

;; Appended after the Emphasis markers entry, in the Toggle column of
;; the View menu.  Skipped with a message when 12-transient.el is
;; absent, so deleting that module costs the menu entry and nothing
;; else -- `C-c u i' keeps working.
(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-view-menu "e"
                         '("m" "Images in buffer" my/image-display-toggle))))

(provide '44-image-display)
;;; 44-image-display.el ends here
