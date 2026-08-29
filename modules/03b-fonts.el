;;; 03b-fonts.el --- Font configuration, per silo -*- lexical-binding: t; -*-
;;; Commentary:
;; Three base faces, and a per-silo override of one of them.
;;
;; THE BASE FACES (session-wide, `my/fonts-apply')
;;
;;   default        `my/font-default'         the buffer text of a note
;;   fixed-pitch    `my/font-default'         anything spacing-sensitive
;;   variable-pitch `my/font-variable-pitch'  headings, quotations, prose
;;
;; THE PER-SILO OVERRIDE (`my/notes-font-setup', buffer-local)
;;
;; Each silo names a family and says whether body text is proportional:
;;
;;   journal/  Playpen Sans Hebrew, body proportional  -> handwritten
;;   pks/      Source Sans 3,       body proportional  -> a book page
;;   docu/     JetBrains Mono,      body monospace     -> a manual
;;
;; Both halves of a silo entry act on the same face.  `variable-pitch'
;; is remapped buffer-locally to the silo family, and `:body
;; proportional' additionally turns on `variable-pitch-mode', which
;; makes `default' inherit `variable-pitch' in that buffer.  So the
;; family reaches headings and quotations in every silo, and reaches
;; body text only where the silo asks for it.
;;
;; docu is the case where that distinction earns its keep: the family
;; is the monospace one, so a docu note is uniformly machine-set --
;; body, headings and code alike -- while a pks note sets the same
;; structure in a text sans.
;;
;; WHY `variable-pitch' AND NOT A NEW FACE
;; ---------------------------------------
;; Because Modus already routes everything through it.
;; `modus-themes-headings' asks for `variable-pitch' at every level,
;; `org-quote' inherits it, and `modus-themes-mixed-fonts' keeps
;; tables, blocks and inline code on `fixed-pitch' regardless.
;; Remapping one face therefore redresses a whole buffer, and a source
;; block inside a handwritten journal entry stays monospaced without
;; anything here saying so.
;;
;; WHAT THIS DOES NOT AFFECT: PDF EXPORT
;; -------------------------------------
;; Nothing.  Faces are a screen concern; `my/org-export-to-pdf' emits
;; LaTeX and hands it to lualatex, which knows about faces not at all.
;; The journal font in a PDF comes from
;; `\\setmainfont{Playpen Sans Hebrew}' in the `journal-article' class
;; built by `my/--latex-preamble' (16-org-export.el), selected from the
;; `:journal:' filetag.  Changing a font here does not change a PDF,
;; and vice versa -- see the note on the two selection criteria below.
;;
;; PREVIOUS BEHAVIOUR THAT IS PRESERVED
;; ------------------------------------
;; Journal entries are set in the handwriting family, body text
;; included.  An earlier revision of this file dropped the
;; `variable-pitch-mode' call on the argument that a journal only
;; wanted its headings handwritten.  That was wrong about the intent:
;; the whole entry is meant to read as handwriting.  The call is back,
;; expressed as `:body proportional'.

;;; Code:

;; ============================================================
;; BASE FAMILIES
;; ============================================================

(defgroup my/fonts nil
  "Typeface configuration for notes."
  :group 'faces)

(defcustom my/font-default "JetBrains Mono"
  "Monospaced family for `default' and `fixed-pitch'.
This is the body text of any buffer that does not turn on
`variable-pitch-mode', and the family of every spacing-sensitive
element (tables, source blocks, inline code) in every buffer."
  :type 'string :group 'my/fonts)

(defcustom my/font-variable-pitch "Source Sans 3"
  "Proportional family for `variable-pitch'.
The session-wide default, used wherever no silo entry applies --
headings in a buffer outside the notes tree, `*Help*', and so on.
Notes inside a silo override it per buffer, see `my/font-silo-styles'.

NOT the journal handwriting family; that is a silo entry."
  :type 'string :group 'my/fonts)

(defcustom my/font-default-height 120
  "Height of the `default' face, in units of 1/10 pt.
120 means 12 pt.  This is the only absolute height in the
configuration; every other face is relative to it, which is what lets
`text-scale-adjust' and `default-text-scale-mode' (34-appearance.el)
scale a buffer coherently instead of moving one face out from under
the others."
  :type 'integer :group 'my/fonts)

;; ============================================================
;; PER-SILO STYLES
;; ============================================================

(defcustom my/font-silo-styles
  (list
   (list my-notes-journal
         :family "Playpen Sans Hebrew" :body 'proportional :height 1.05)
   (list my-notes-pks
         :family "Source Sans 3"       :body 'proportional :height 1.0)
   (list my-notes-docu
         :family "JetBrains Mono"      :body 'monospace    :height 1.0))
  "How each silo is set, as a list of (DIRECTORY . PLIST).

DIRECTORY is matched against the start of the visited file name, so a
note *about* journalling that lives in `pks' is not mistaken for a
journal entry.  The previous test was a substring search for
\"journal\" anywhere in the path, which matched
~/notes/pks/20260101T090000--journal-app.org.

PLIST keys:

  :family   Family remapped onto `variable-pitch' in this buffer.
            Reaches headings and quotations in every silo, and body
            text as well when :body is `proportional'.

  :body     `proportional' turns on `variable-pitch-mode', so body
            text is set in :family.  `monospace' leaves body text in
            `default' -- which is `my/font-default', a monospaced
            family -- so with a monospaced :family the whole buffer is
            machine-set.

  :height   Relative height for :family, as a float.  A proportional
            face at the same nominal size as a monospaced one usually
            reads smaller; this compensates.  1.0 means no change.

The first matching entry wins.  A note in no listed silo -- the
~/notes/ root, captures.org -- keeps the session defaults.

A LARGER DISTINCTION FOR docu is a matter of installing one more
family and changing :family here: a condensed technical sans such as
\"IBM Plex Sans Condensed\" would keep docu headings visibly
engineered while leaving the body monospaced.  The default reuses
`my/font-default' so that nothing new has to be installed.

NOTE ON PDF EXPORT.  This variable has no effect on exported PDFs, and
it selects by DIRECTORY while 16-org-export.el selects its LaTeX class
by the `:journal:' FILETAG.  For a journal note the two agree, because
journal notes carry that tag.  For pks and docu there is currently no
distinction to disagree about: both export through the `article'
class.  Giving them distinct PDF fonts is a change to
`my/--latex-preamble', not to this list."
  :type '(alist :key-type directory :value-type plist)
  :group 'my/fonts)

;; ============================================================
;; APPLYING THE BASE FACES
;; ============================================================
;; `:height' is absolute on `default' and relative (1.0) elsewhere.  An
;; absolute height on `fixed-pitch' or `variable-pitch' would pin those
;; faces to a fixed size and break text scaling in exactly the buffers
;; where it is most wanted.
;;
;; An uninstalled family falls back silently rather than signalling, so
;; a typo produces a wrong-looking session, not an error.  Check with
;; `C-u C-x =' over the text in question.

(defun my/fonts-apply ()
  "Apply the three base font faces.
Idempotent, and safe to call again after changing any `my/font-*'
variable or after attaching a new display."
  (interactive)
  (set-face-attribute 'default nil
                      :family my/font-default
                      :height my/font-default-height
                      :weight 'normal)
  (set-face-attribute 'fixed-pitch nil
                      :family my/font-default
                      :height 1.0)
  (set-face-attribute 'variable-pitch nil
                      :family my/font-variable-pitch
                      :height 1.0
                      :weight 'normal))

(my/fonts-apply)

;; A theme reassigns the faces it covers when it loads, and `default'
;; is one of them.  Re-applying afterwards keeps the font choice from
;; being reset by a light/dark toggle (<f5>).
(add-hook 'modus-themes-after-load-theme-hook #'my/fonts-apply)

;; ============================================================
;; APPLYING A SILO STYLE
;; ============================================================

(defvar-local my/font--silo-cookie nil
  "Cookie returned by the buffer's `variable-pitch' remap, if any.
Kept so that a second run of `my/notes-font-setup' -- which happens on
`revert-buffer', and after `denote-rename-file' moves a note between
silos -- replaces the remap instead of stacking another one on top of
it.  Stacked relative remaps do not simply override: they compose, and
the visible result depends on how many times the hook has run.")

(defun my/font--silo-style (file)
  "Return the plist of the first `my/font-silo-styles' entry matching FILE."
  (let ((path (expand-file-name file)))
    (cdr (seq-find (lambda (entry)
                     (string-prefix-p (expand-file-name (car entry)) path))
                   my/font-silo-styles))))

(defun my/notes-font-setup ()
  "Set the current buffer's typeface from its silo.
Added to `org-mode-hook'.  Buffers outside every listed silo are left
with the session defaults, which is why this does nothing rather than
resetting them."
  (when my/font--silo-cookie
    (face-remap-remove-relative my/font--silo-cookie)
    (setq my/font--silo-cookie nil))
  (when-let* ((file (buffer-file-name))
              (style (my/font--silo-style file)))
    (setq my/font--silo-cookie
          (face-remap-add-relative 'variable-pitch
                                   :family (plist-get style :family)
                                   :height (or (plist-get style :height) 1.0)))
    ;; `variable-pitch-mode' remaps `default' to inherit
    ;; `variable-pitch', which the line above has already redirected to
    ;; the silo family -- so body text follows without naming a family
    ;; twice.  Order does not matter: face remapping resolves the
    ;; inheritance chain at redisplay, not at the time the remap is added.
    (if (eq (plist-get style :body) 'proportional)
        (variable-pitch-mode 1)
      (variable-pitch-mode -1))))

(add-hook 'org-mode-hook #'my/notes-font-setup)

;; ============================================================
;; ORG FACES ARE NOT SET HERE
;; ============================================================
;; This module used to reach into a dozen Org faces with
;; `set-face-attribute'.  It no longer does.  Which Org face uses which
;; of the three base faces is decided by the theme
;; (`modus-themes-mixed-fonts'), so changing a family above changes
;; every face that follows it.  Colour and heading size live in
;; 09-theme.el.

;; ============================================================
;; FONT CACHE COMPACTION
;; ============================================================
;; Emacs never compacts font caches while images are on screen, and on
;; some builds the compaction itself is a visible pause.  Notes here
;; routinely display inline images (see `org-image-actual-width' in
;; 11-org-appearance.el), so the compaction buys nothing and costs a
;; stutter.

(setq inhibit-compacting-font-caches t)

(provide '03b-fonts)
;;; 03b-fonts.el ends here
