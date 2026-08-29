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

(defcustom my/font-default-height 130
  "Height of the `default' face, in units of 1/10 pt.
130 means 13 pt.  This is the only absolute height in the
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
         :family "Source Sans 3"       :body 'proportional :height 1.15)
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
;; being reset by a theme change.  `my/theme-after-load-hook'
;; (09-theme.el) rather than a Modus-specific hook, because F4 and F5
;; also load Ef themes.
(add-hook 'my/theme-after-load-hook #'my/fonts-apply)

;; ============================================================
;; FACES THAT STAY MONOSPACED IN EVERY SILO
;; ============================================================
;; Prose changes typeface per silo; structure does not.
;;
;; `variable-pitch-mode' works by remapping `default' to inherit
;; `variable-pitch', so every face that does not name a family of its
;; own follows it -- including the property drawer and the front
;; matter.  The result was that `:PROPERTIES:' and `#+filetags:'
;; rendered as handwriting in a journal, as a text sans in pks and as
;; monospace in docu: the same structural markup in three typefaces,
;; for no reason a reader could infer.
;;
;; These faces are remapped back to `my/font-default'.  A buffer-local
;; remap rather than a theme hook, because the requirement has nothing
;; to do with the palette and everything to do with the buffer: it
;; exists only where `variable-pitch-mode' is on, and it disappears
;; with the buffer.  Nothing is written to the `user' theme.

(defcustom my/font-fixed-faces
  '(org-drawer
    org-special-keyword
    org-property-value
    org-meta-line
    org-document-info-keyword
    org-tag
    org-todo
    org-done
    org-checkbox)
  "Faces that use `my/font-default' regardless of the silo.
Structural markup, as opposed to prose.  A face listed here keeps the
monospaced family even in a buffer whose body text is proportional."
  :type '(repeat face) :group 'my/fonts)

(defcustom my/font-fixed-faces-height 1.0
  "Height of `my/font-fixed-faces', relative to body text.
1.0 renders structure at the same size as prose.  Lower it -- 0.9 is a
reasonable first try -- to make front matter and property drawers
recede, which is what \"more condensed\" usually means in practice:
the same information taking less vertical room and drawing less
attention than the prose it describes."
  :type 'number :group 'my/fonts)

(defvar-local my/font--fixed-cookies nil
  "Remap cookies for `my/font-fixed-faces' in this buffer.")

(defun my/font--apply-fixed-faces (&optional correction)
  "Remap `my/font-fixed-faces' to `my/font-default' in this buffer.

CORRECTION is a height multiplier, and it is the part that matters.

FIXING THE FAMILY WAS NOT ENOUGH
--------------------------------
The first version of this function set only `:family', on the
assumption that the silos differed in typeface.  They differ in SIZE
as well.  Each silo gives `variable-pitch' a `:height' -- 1.05 in
journal, 1.15 in pks, 1.0 in docu -- and `variable-pitch-mode' makes
`default' inherit `variable-pitch', so the height reaches every face
in the buffer that does not state one.  Front matter therefore came
out at three sizes in the same monospaced family, which reads as
three different fonts even though it is one.

CORRECTION cancels that: pass the reciprocal of the silo height and
structure lands at the same size everywhere, matching docu, which is
the one that looked right.

Removes any previous remaps first.  `org-mode-hook' runs again on
`revert-buffer' and after `denote-rename-file' moves a note between
silos, and relative remaps compose rather than replace -- without
this, the correction would be applied twice and structure would end
up smaller than prose."
  (mapc #'face-remap-remove-relative my/font--fixed-cookies)
  (setq my/font--fixed-cookies
        (mapcar (lambda (face)
                  (face-remap-add-relative
                   face
                   :family my/font-default
                   :height (* (or correction 1.0) my/font-fixed-faces-height)))
                my/font-fixed-faces)))

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
Added to `org-mode-hook'.  Buffers outside every listed silo keep the
session defaults for prose, but still get the structural faces pinned:
the reason for pinning them does not depend on which silo a note is
in."
  (when my/font--silo-cookie
    (face-remap-remove-relative my/font--silo-cookie)
    (setq my/font--silo-cookie nil))
  (let* ((file  (buffer-file-name))
         (style (and file (my/font--silo-style file)))
         (height (or (plist-get style :height) 1.0))
         (proportional (eq (plist-get style :body) 'proportional)))
    (when style
      (setq my/font--silo-cookie
            (face-remap-add-relative 'variable-pitch
                                     :family (plist-get style :family)
                                     :height height))
      ;; `variable-pitch-mode' remaps `default' to inherit
      ;; `variable-pitch', which the line above has already redirected
      ;; to the silo family -- so body text follows without naming a
      ;; family twice.  Order does not matter: face remapping resolves
      ;; the inheritance chain at redisplay, not when the remap is added.
      (if proportional
          (variable-pitch-mode 1)
        (variable-pitch-mode -1)))
    ;; Structure at one size in one family, in every silo.  The
    ;; correction only applies where the silo height actually reached
    ;; the buffer, which is where body text is proportional.
    (my/font--apply-fixed-faces (if proportional (/ 1.0 height) 1.0)))
  ;; And the note's own size preference, if it states one.
  (when-let* ((scale (my/note-keyword-number "text_scale")))
    (text-scale-set (truncate scale))))

(add-hook 'org-mode-hook #'my/notes-font-setup)

;; ============================================================
;; PER-NOTE TEXT SIZE
;; ============================================================
;; `#+text_scale: 2' in a note's front matter enlarges that note by two
;; steps of `text-scale-adjust'.  Negative values shrink it.
;;
;; Relative steps rather than an absolute point size, so a note that
;; wants to be a little larger stays a little larger after the global
;; size changes.  An absolute value would have to be revisited every
;; time `my/font-default-height' moved.

(defun my/text-scale-save-to-note ()
  "Write the current text scale into this note's front matter.
Experiment with `C-c u f', then run this to make the size a property
of the note rather than of the session."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer"))
  (let ((amount (or (bound-and-true-p text-scale-mode-amount) 0)))
    (my/note-keyword-set "text_scale" amount)
    (message "#+text_scale: %s written to front matter (buffer not saved)" amount)))

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
;; CHANGING THE BASE SIZE, INTERACTIVELY AND FOR GOOD
;; ============================================================
;; `C-c u f' enters a small repeat map: `+' and `-' resize every buffer
;; in every frame, `0' returns to the compiled-in default, and RET or
;; any other key leaves.  The chosen size is written to
;; `my/ui-state-file' immediately, so it survives a restart without
;; editing this file.
;;
;; This changes `my/font-default-height', the size everything else is
;; relative to -- distinct from `text-scale-adjust', which scales one
;; buffer and leaves the rest alone.  Both are useful and they compose:
;; a note carrying `#+text_scale: 2' stays two steps above whatever the
;; base becomes.

(defconst my/font-size-step 5
  "Change in `my/font-default-height' per keypress, in units of 1/10 pt.")



(defun my/font-size--apply (height)
  "Set the base font HEIGHT, apply it, remember it, and report."
  (setq my/font-default-height (max 60 (min 400 height)))
  (my/fonts-apply)
  (my/ui-state-set :font-height my/font-default-height)
  (message "Base font %.1f pt   [+ - 0]  any other key to finish"
           (/ my/font-default-height 10.0))
  (set-transient-map my/font-size-repeat-map t))

(defun my/font-size-increase ()
  "Make the base font one step larger."
  (interactive)
  (my/font-size--apply (+ my/font-default-height my/font-size-step)))

(defun my/font-size-decrease ()
  "Make the base font one step smaller."
  (interactive)
  (my/font-size--apply (- my/font-default-height my/font-size-step)))

(defun my/font-size-reset ()
  "Return the base font to the value compiled into this file."
  (interactive)
  (my/font-size--apply (default-value 'my/font-default-height)))

(defvar my/font-size-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "+") #'my/font-size-increase)
    (define-key map (kbd "=") #'my/font-size-increase)
    (define-key map (kbd "-") #'my/font-size-decrease)
    (define-key map (kbd "0") #'my/font-size-reset)
    map)
  "Transient map active while adjusting the base font size.")

(defun my/font-size-adjust ()
  "Adjust the base font size, then keep adjusting with + and -."
  (interactive)
  (my/font-size--apply my/font-default-height))

(global-set-key (kbd "C-c u f") #'my/font-size-adjust)
(global-set-key (kbd "C-c u s") #'my/text-scale-save-to-note)

;; Apply the remembered size, if there is one.  After the `defcustom'
;; so that `default-value' still reports the compiled-in figure and
;; `my/font-size-reset' has something to return to.
(when-let* ((height (my/ui-state-get :font-height)))
  (setq my/font-default-height height)
  (my/fonts-apply))

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
