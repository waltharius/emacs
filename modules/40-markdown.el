;;; 40-markdown.el --- Markdown notes alongside Org -*- lexical-binding: t; -*-
;;; Commentary:
;; Markdown files get the same visual treatment as Org notes -- headings,
;; links, emphasis, code blocks, inline images, the centred column, the
;; per-silo typeface -- without changing how Org files are handled.  Org
;; stays the default format for every note this configuration creates.
;;
;; WHY THIS IS ADDITIVE RATHER THAN A REFACTOR
;; -------------------------------------------
;; Most of the integration already exists and needs no code:
;;
;;   - Denote indexes by FILE NAME, not by extension.  Its own
;;     `denote-directory-files' documents that "files only need to have
;;     an identifier" and that the result "may thus include file types
;;     that are not implied by the variable `denote-file-type'".  So
;;     `denote-open-or-create', `denote-link', the keyword prompts and
;;     `consult-denote-grep' already see .md notes.  Nothing to change.
;;
;;   - Keywords live in the file name (`__tag1_tag2'), so the tag
;;     vocabulary is shared between formats by construction.  There is
;;     no second set of tags to keep in step.
;;
;;   - Links resolve by identifier.  An Org note links to a Markdown
;;     note with [[denote:ID]]; a Markdown note links back with
;;     [text](denote:ID).  Denote adds itself to
;;     `markdown-follow-link-functions' as soon as markdown-mode loads,
;;     so following works in both directions.
;;
;;   - `markdown-mode' derives from `text-mode', and both
;;     `my/visual-fill-notes-setup' (10-visual-fill.el, on
;;     `find-file-hook') and the flyspell hook in 03-spelling.el are
;;     gated on `text-mode'.  The centred column and spell checking are
;;     therefore already active in Markdown buffers.
;;
;; What is left for this module is small: install markdown-mode, give it
;; settings that mirror the Org ones, and put the per-silo typeface and
;; the docu width rule on `markdown-mode-hook' too.
;;
;; RELATIONS TO OTHER MODULES (all soft -- every one is guarded)
;; ------------------------------------------------------------
;;   03b-fonts.el      `my/notes-font-setup', `my/font-fixed-faces'
;;   09-theme.el       `my/theme-after-load-hook'
;;   10-visual-fill.el `my/fill-column-docu' for the wider column
;;   12-transient.el   `my/transient-append', Create and Tools menus
;;   05-notes.el       `my/denote-base', wrapped by `my/markdown-new-note'
;;
;; Deleting any of them degrades this module rather than breaking it:
;; missing fonts means session defaults, a missing menu means the entry
;; is skipped with a message, a missing 05-notes.el means
;; `my/markdown-new-note' reports that it has nothing to wrap.
;;
;; WHAT IS DELIBERATELY *NOT* EXTENDED TO MARKDOWN
;; -----------------------------------------------
;; Several modules scan for "\\.org\\'" on purpose, because what they
;; measure or rewrite is Org syntax:
;;
;;   05b-journal-metrics.el, 21-dashboards.el, 35-journal-gaps.el
;;     Journal entries come from an Org template and carry Org front
;;     matter.  A Markdown journal entry is not something this
;;     configuration can produce.
;;   16-org-export.el, 29-writing-export.el, 20-transclusion.el
;;     Export and transclusion run through Org's own exporters.
;;   26-maintenance.el, 27-denote-identifiers.el, 36-notes-stats.el
;;     Integrity checks and statistics read Org front matter.  Markdown
;;     notes are therefore NOT counted by `my/notes-stats' and NOT
;;     checked by `C-c n !'.  That is the cost of the approach and it is
;;     stated here rather than left to be discovered later.
;;   02b-bold-marker.el
;;     The word* auto-wrap stays gated on `org-mode': Markdown bold is
;;     ** and the trigger would produce broken markup.
;;
;; Widening any of those scans is a separate decision per module, not a
;; side effect of turning Markdown editing on.
;;
;; Docs: ~/.emacs.d/function_helper.org::#markdown

;;; Code:

(require 'transient)

;; Denote's, declared here so that the `let' in `my/markdown-new-note'
;; binds it DYNAMICALLY.  Without this the file compiles the binding as
;; a lexical one -- a local variable nothing reads -- and the wrapper
;; silently produces Org notes.  Same pattern as the `vertico-preselect'
;; declaration in 05-notes.el, and the reason `duplicates' in
;; hooks/lint.py has an exception list for valueless `defvar'.
(defvar denote-use-file-type)

;; ============================================================
;; OPTIONS
;; ============================================================

(defgroup my/markdown nil
  "Markdown notes living beside Org notes."
  :group 'convenience)

(defcustom my/markdown-denote-file-type 'markdown-yaml
  "File type `my/markdown-new-note' asks Denote for.

`markdown-yaml' produces the YAML front matter that Obsidian, Hugo,
Pandoc and most static site generators read.  `markdown-toml' is the
same idea with TOML delimiters and is only worth choosing when
something downstream requires it.

This is NOT `denote-file-type', which stays nil (Org) so that every
other creation command in this configuration keeps producing Org."
  :type '(choice (const markdown-yaml) (const markdown-toml))
  :group 'my/markdown)

(defcustom my/markdown-front-matter-language "pl"
  "Value written to the `language:' key of a new Markdown note.
Nil writes nothing.  The Org counterpart is `#+language:', added by
`my/note-add-front-matter-extras' in 05-notes.el, which does nothing in
a Markdown buffer because it is gated on `org-mode'.

`#+schema:' has no counterpart here on purpose: it records which
generation of the JOURNAL template produced a file, and that template
only ever emits Org."
  :type '(choice string (const nil))
  :group 'my/markdown)

(defcustom my/markdown-display-images-on-open t
  "Whether to show inline images when a Markdown note is opened.
Parity with `org-startup-with-inline-images', which is t in
11-org-appearance.el.  Set to nil if opening image-heavy Markdown files
feels slow."
  :type 'boolean
  :group 'my/markdown)

;; ============================================================
;; BUFFER SETUP
;; ============================================================
;; Defined before the `use-package' form because its `:config' calls
;; `my/markdown--update-header-faces'.

(defun my/markdown--update-header-faces ()
  "Re-apply `markdown-header-scaling-values' to the header faces.
No-op until markdown-mode is loaded, so it is safe on a startup hook."
  (when (fboundp 'markdown-update-header-faces)
    (markdown-update-header-faces markdown-header-scaling
                                  markdown-header-scaling-values)))

(defun my/markdown--docu-note-p ()
  "Return non-nil when the current Markdown note carries the docu keyword.

Reads the FILE NAME first: Denote keeps keywords there, so this works
whatever the front matter looks like and keeps working after
`denote-rename-file'.  Falls back to the YAML or TOML `tags' line for
files that have front matter but not yet a Denote file name -- which is
what an Obsidian export looks like before it is renamed."
  (let ((file (buffer-file-name)))
    (or (and file
             (fboundp 'denote-extract-keywords-from-path)
             (member "docu" (denote-extract-keywords-from-path file))
             t)
        (save-excursion
          (goto-char (point-min))
          (let ((case-fold-search t))
            (and (re-search-forward "^tags\\s-*[:=].*\\bdocu\\b" 2000 t) t))))))

(defun my/markdown--visual-fill-adjust ()
  "Give docu Markdown notes the wider text column.

`my/visual-fill-notes-setup' (10-visual-fill.el) already turns the
centred column on in every notes buffer, Markdown included, because it
tests for `text-mode' and markdown-mode derives from it.  What it
cannot do is recognise a docu note: it looks for `#+filetags:', which
is Org front matter.

Rather than teaching that function a second syntax -- and putting the
Org path at risk for the sake of the Markdown one -- this widens the
column afterwards, and only in Markdown buffers.  Runs at depth 90 on
`find-file-hook' so that it lands after the setup it is adjusting."
  (when (and (derived-mode-p 'markdown-mode)
             (buffer-file-name)
             (bound-and-true-p visual-fill-column-mode)
             (boundp 'my/fill-column-docu)
             (string-prefix-p (expand-file-name my-notes-dir)
                              (expand-file-name (buffer-file-name)))
             (my/markdown--docu-note-p))
    (setq-local visual-fill-column-width my/fill-column-docu)
    (setq fill-column my/fill-column-docu)
    (when (fboundp 'visual-fill-column--adjust-window)
      (visual-fill-column--adjust-window))))

(defun my/markdown--setup ()
  "Bring a Markdown buffer in line with how Org buffers are set up.

Typeface per silo, the same line spacing, no electric indent, and
inline images when the display is graphical.  Every step is guarded, so
this degrades to plain markdown-mode rather than signalling when a
module it borrows from has been removed -- and an error here would be
expensive: a signal inside a mode hook aborts `run-mode-hooks' before
font-lock is switched on, leaving the buffer with no fontification at
all.  Same reasoning as the org-modern note in 11-org-appearance.el.

`my/notes-font-setup' is written against `org-mode-hook' but reads only
`buffer-file-name', so it is format-agnostic in practice.  The
`#+text_scale:' lookup inside it finds nothing in a Markdown file and
falls through, which is the intended degradation rather than an
oversight."
  (when (fboundp 'my/notes-font-setup)
    (my/notes-font-setup))
  (setq line-spacing 0.2)
  (electric-indent-local-mode -1)
  (setq-local electric-indent-chars nil)
  (when (and my/markdown-display-images-on-open
             (display-graphic-p)
             (fboundp 'markdown-display-inline-images))
    (ignore-errors (markdown-display-inline-images))))

;; ============================================================
;; PACKAGE
;; ============================================================
;; markdown-mode is on NonGNU ELPA, which Emacs 28 and later carry in
;; the default `package-archives', so nothing has to be added to
;; 00-core.el.  Its autoloads register the .md extensions themselves,
;; which is why there is no `:mode' here.
;;
;; SETTINGS GO IN `:init', NOT `:custom'.  Two reasons, both real:
;;
;;   1. `markdown-header-face-1' .. `-6' come from a `defface' whose
;;      spec READS `markdown-header-scaling' at load time.  The value
;;      has to be in place before the package loads, and `:init' is the
;;      phase that runs before the load.  A `defcustom' initialised with
;;      `custom-initialize-default' leaves an already-bound value alone,
;;      so setting it early is safe rather than fragile.
;;
;;   2. `:custom' expands to `customize-set-variable', which calls
;;      `custom-load-symbol' -- and that pulls the defining library in
;;      at startup, defeating the deferral this form asks for.

(use-package markdown-mode
  :ensure t
  :defer t
  :init
  ;; The counterpart of `org-hide-emphasis-markers' (11-org-appearance.el).
  ;; Global in upstream, as the Org one is here, and toggled the same
  ;; way -- see `my/markdown-toggle-markup'.
  (setq markdown-hide-markup t)

  ;; Heading sizes, matching `modus-themes-headings' in 09-theme.el:
  ;; level 1 is 1.3, level 2 is 1.2, level 3 is 1.1, the rest 1.0.  The
  ;; same figures mean an Org note and a Markdown note of the same depth
  ;; are set at the same size, which is the point of the exercise.
  (setq markdown-header-scaling t)
  (setq markdown-header-scaling-values '(1.3 1.2 1.1 1.0 1.0 1.0))

  ;; Fenced code fontified by the language's own major mode, the way Org
  ;; fontifies a #+begin_src block.
  (setq markdown-fontify-code-blocks-natively t)

  ;; LaTeX fragments fontified rather than left as plain text.  Affects
  ;; fontification only, never the file on disk.
  (setq markdown-enable-math t)

  ;; "- " rather than the upstream "  * ": it is what Denote's Markdown
  ;; examples use, what Obsidian writes, and what the notes imported
  ;; from Obsidian already contain.
  (setq markdown-unordered-list-item-prefix "- ")

  ;; Scale images once, for the reason `org-image-actual-width' is 1100
  ;; in 11-org-appearance.el: a 4000 px phone photo makes Emacs
  ;; recompute window metrics on every scroll past it.  The height is
  ;; nil so the aspect ratio is kept.  ImageMagick is used when the
  ;; build has it and `create-image' does the scaling natively when it
  ;; does not, so this works either way.
  (setq markdown-max-image-size '(1100 . nil))

  ;; `[[wiki links]]' stay OFF.  They are Obsidian's link syntax, they
  ;; carry no Denote identifier, and they break the moment a note is
  ;; renamed -- which `denote-rename-file' does routinely.  Imported
  ;; notes that still contain them are converted with
  ;; `denote-markdown-convert-obsidian-links-to-denote-type'
  ;; (Tools -> Markdown), not read in place.
  (setq markdown-enable-wiki-links nil)
  :config
  ;; Structure stays monospaced in every silo, prose does not.  The Org
  ;; face list lives in 03b-fonts.el; these are the Markdown faces that
  ;; play the same role -- front matter keys and values, the markup
  ;; characters themselves, and the language tag on a fenced block.
  ;;
  ;; `add-to-list' on that module's `defcustom' rather than a private
  ;; copy: one list, one owner, and this module contributes to it.
  (when (boundp 'my/font-fixed-faces)
    (dolist (face '(markdown-metadata-key-face
                    markdown-metadata-value-face
                    markdown-markup-face
                    markdown-language-keyword-face))
      (add-to-list 'my/font-fixed-faces face)))

  ;; A theme reassigns every face it covers when it loads, heading faces
  ;; included, so the scaling has to be re-applied afterwards.  Same
  ;; reasoning and same hook as `my/fonts-apply' in 03b-fonts.el.
  (when (boundp 'my/theme-after-load-hook)
    (add-hook 'my/theme-after-load-hook #'my/markdown--update-header-faces))
  (my/markdown--update-header-faces))

;; ============================================================
;; DENOTE LINK CONVERSION (optional package)
;; ============================================================
;; denote-markdown is on GNU ELPA, by Denote's own author.  It converts
;; between the three ways a Markdown link can point at a note -- a
;; `denote:' link, a file path, and an Obsidian `[[wiki]]' link -- which
;; is exactly what is needed when a file has to leave Emacs and come
;; back.  Reused rather than reimplemented as regexps here.
;;
;; `:defer t' with `:commands': nothing loads until one of the four is
;; invoked, and if the package is absent the Links group of the menu
;; below hides itself instead of binding void commands.

(use-package denote-markdown
  :ensure t
  :defer t
  :commands (denote-markdown-convert-links-to-file-paths
             denote-markdown-convert-links-to-denote-type
             denote-markdown-convert-links-to-obsidian-type
             denote-markdown-convert-obsidian-links-to-denote-type))

;; ============================================================
;; HOOKS
;; ============================================================

(add-hook 'markdown-mode-hook #'my/markdown--setup)

;; Depth 90: `my/visual-fill-notes-setup' is on the same hook at the
;; default depth, and this adjusts what that function decided.
(add-hook 'find-file-hook #'my/markdown--visual-fill-adjust 90)

;; ============================================================
;; CREATING A MARKDOWN NOTE
;; ============================================================

(defun my/markdown--add-front-matter-language ()
  "Write `language:' into the YAML front matter of the current note.
Does nothing when `my/markdown-front-matter-language' is nil, when the
key is already present, or when the buffer has no front matter block --
which is the case for `markdown-toml' and for the markdown-obsidian
type, neither of which uses this key."
  (when (and my/markdown-front-matter-language
             buffer-file-name
             (derived-mode-p 'markdown-mode))
    (save-excursion
      (goto-char (point-min))
      (when (looking-at "^---[ \t]*$")
        (forward-line 1)
        (let ((end (save-excursion
                     (when (re-search-forward "^---[ \t]*$" nil t)
                       (line-beginning-position)))))
          (when (and end
                     (not (save-excursion
                            (re-search-forward "^language\\s-*:" end t))))
            (goto-char end)
            (insert (format "language:   %s\n"
                            my/markdown-front-matter-language))
            (save-buffer)))))))

(defun my/markdown-new-note ()
  "Create a Denote note in Markdown instead of Org.

Everything except the file type is `my/denote-base': the same title
prompt, the same keyword completion, the same silo choice.  Only
`denote-use-file-type' is bound, which is the variable Denote
documents for exactly this case -- a wrapper command that fixes one
piece of the note data and leaves the rest to the prompts.

`denote-file-type' itself is NOT touched.  It stays nil, so every other
creation command in this configuration goes on producing Org.

Afterwards `language:' is added to the front matter, mirroring what
`my/note-add-front-matter-extras' does for Org notes."
  (interactive)
  (unless (fboundp 'my/denote-base)
    (user-error "05-notes.el is not loaded, so there is no note command to wrap"))
  (let ((denote-use-file-type my/markdown-denote-file-type))
    (call-interactively #'my/denote-base))
  (my/markdown--add-front-matter-language))

;; ============================================================
;; TOGGLES
;; ============================================================

(defun my/markdown-toggle-markup ()
  "Toggle Markdown markup hiding.

The counterpart of `my/toggle-emphasis-markers' (11-org-appearance.el).
Hidden -- the default here -- means `**bold**' renders as bold with the
asterisks invisible.  Visible means the raw syntax is shown, which is
what to reach for when a line will not fontify and the reason is a
stray character.

Like the Org toggle, this changes a GLOBAL variable, so it affects
every Markdown buffer rather than only this one.  That is upstream's
design for `markdown-toggle-markup-hiding' and matching it is
preferable to reimplementing a buffer-local version."
  (interactive)
  (unless (derived-mode-p 'markdown-mode)
    (user-error "Not a Markdown buffer"))
  (markdown-toggle-markup-hiding)
  (message (if markdown-hide-markup
               "✨ Markup HIDDEN — pretty rendering active"
             "👁 Markup VISIBLE — raw syntax: **bold** _italic_")))

;; ============================================================
;; MENU  (C-c n t m)
;; Docs: ~/.emacs.d/function_helper.org::#menu-markdown
;; ============================================================
;; The Links group carries an `:if', so the whole column disappears when
;; denote-markdown is absent rather than offering four entries that
;; would signal on invocation.

(transient-define-prefix my/markdown-menu ()
  "Markdown display toggles and link conversions."
  [["Display"
    ("m" "Markup hiding" my/markdown-toggle-markup)
    ("u" "URL hiding"    markdown-toggle-url-hiding)
    ("i" "Inline images" markdown-toggle-inline-images)]
   ["Links"
    :if (lambda () (fboundp 'denote-markdown-convert-links-to-denote-type))
    ("d" "→ denote: links"    denote-markdown-convert-links-to-denote-type)
    ("p" "→ file paths"       denote-markdown-convert-links-to-file-paths)
    ("o" "→ Obsidian links"   denote-markdown-convert-links-to-obsidian-type)
    ("O" "Obsidian → denote:" denote-markdown-convert-obsidian-links-to-denote-type)]
   [("q" "Quit" transient-quit-one)]])

;; Appended rather than declared in 12-transient.el, so that deleting
;; this file removes the entries with it.  `my/transient-append' itself
;; degrades when the prefix or anchor is missing, but calling it
;; unguarded would need 12-transient.el to have loaded first -- same
;; pattern as 22-zettelkasten.el.
(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-create-menu "L"
                         '("M" "Markdown note" my/markdown-new-note))
    (my/transient-append 'my/notes-tools-menu "z"
                         '("m" "Markdown →" my/markdown-menu))))

(provide '40-markdown)
;;; 40-markdown.el ends here
