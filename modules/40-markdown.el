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
;; FILES THAT ARE NOT NOTES
;; ============================================================
;; A README, a CHANGELOG, an export from some other program: Markdown
;; with no Denote identifier, no front matter, and no business getting
;; one.  Fontification reaches these already -- headings, links and
;; emphasis are markdown-mode's job and it does not care where a file
;; lives -- but two layers of this configuration are keyed to location
;; and so skip them:
;;
;;   `my/visual-fill-notes-setup' (10-visual-fill.el) turns the text
;;   column OFF outside ~/notes/, on purpose, as a visual signal that
;;   the notes tree has been left.  `visual-line-mode' is still on from
;;   02-editing.el, so the text wraps -- at the window edge, across a
;;   full-width frame.
;;
;;   `my/notes-font-setup' (03b-fonts.el) applies a typeface per SILO.
;;   A file in no silo keeps `default', which is JetBrains Mono, while
;;   its headings still inherit `variable-pitch'.  Proportional
;;   headings over monospaced prose is the mismatch that reads as
;;   "unformatted".
;;
;; Both are corrected below, for Markdown buffers only.  Org files
;; outside the notes tree keep the existing behaviour untouched.

(defcustom my/markdown-outside-notes-layout 'column
  "Text layout for Markdown files outside `my-notes-dir'.

  `column'    Wrapped to `my/markdown-outside-notes-width', left
              aligned, with the leftover space as a right margin.
  `centered'  The same width, centred like a note.
  `plain'     Nothing: full width, as before this module existed.

The default is `column' rather than `centered' deliberately.
10-visual-fill.el makes full width outside ~/notes/ a signal that the
notes tree has been left, and that signal is worth keeping; but
unreadable 300-column lines are a poor way to carry it.  A left-aligned
column reads as well as a centred one and still looks nothing like a
note, so the signal survives in a form that costs nothing.

Set to `centered' for one uniform reading layout everywhere."
  :type '(choice (const column) (const centered) (const plain))
  :group 'my/markdown)

(defcustom my/markdown-outside-notes-width nil
  "Width of the text column for Markdown files outside `my-notes-dir'.
Nil means `my-fill-column', the same width notes use.  As in
10-visual-fill.el this is a count of CHARACTERS in the buffer's default
face, so a proportional body renders the same number narrower."
  :type '(choice (const :tag "Same as notes" nil) integer)
  :group 'my/markdown)

(defcustom my/markdown-unsiloed-body 'proportional
  "Body typeface for a Markdown file that matches no `my/font-silo-styles' entry.

`proportional' turns on `variable-pitch-mode', so prose is set in
`my/font-variable-pitch' while code, tables and markup stay monospaced
through `my/font-fixed-faces'.  `monospace' leaves the buffer in
`default'.

Files that DO match a silo entry are untouched by this: a Markdown
file in docu is meant to be monospaced and stays so."
  :type '(choice (const proportional) (const monospace))
  :group 'my/markdown)

;; ============================================================
;; BUFFERS A SAVED SESSION RESTORED IN THE WRONG MODE
;; ============================================================
;; `desktop-save' records each buffer's MAJOR MODE and `desktop-read'
;; calls that mode function again on restore, rather than consulting
;; `auto-mode-alist' afresh.  That is correct almost always -- it is how
;; a buffer deliberately put into some other mode comes back in it --
;; but it means a buffer whose correct mode CHANGED between sessions
;; comes back in the old one, indefinitely, because every save writes
;; the stale mode out again.
;;
;; Installing markdown-mode is exactly such a change, and Emacs makes it
;; visible in one specific place.  A `.md' file that markdown-mode has
;; no claim on falls through to whatever else matches, and files.el
;; ships this:
;;
;;   ("[cC]hange[lL]og[-.][-0-9a-z]+\\'" . change-log-mode)
;;
;; `set-auto-mode' retries case-insensitively when the case-sensitive
;; pass finds nothing, so CHANGELOG.md matched it and opened in
;; `change-log-mode' -- monospaced, no heading faces, literal `##'.
;; README.md landed in `fundamental-mode' by the same route.  Those
;; modes are now in the desktop file and outlive the fix.
;;
;; Reopening the file does not help: the buffer is already there.  The
;; command below re-runs `normal-mode' on the buffers this applies to,
;; and the hook does it once per session restore so that it does not
;; have to be remembered.

(defcustom my/markdown-stale-modes
  '(fundamental-mode text-mode change-log-mode)
  "Major modes a Markdown file falls into when markdown-mode is absent.
A restored buffer is re-moded by `my/markdown-restore-modes' only when
its current mode is on this list, so a file deliberately put into some
other mode -- `conf-mode' on a `.md' fixture, say -- is left alone."
  :type '(repeat symbol)
  :group 'my/markdown)

(defcustom my/markdown-restore-modes-on-desktop t
  "Whether to fix up stale Markdown buffers after a session is restored.
Nil leaves `my/markdown-restore-modes' as a manual command."
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

(defun my/markdown--in-notes-p ()
  "Return non-nil when the current buffer visits a file under `my-notes-dir'."
  (when-let* ((file (buffer-file-name)))
    (string-prefix-p (expand-file-name my-notes-dir)
                     (expand-file-name file))))

(defun my/markdown--siloed-p ()
  "Return non-nil when this file matches an entry in `my/font-silo-styles'.

Reads that module's `defcustom' rather than calling its lookup
function, which is private to 03b-fonts.el.  The five lines of
duplication are the price of not reaching across a module boundary;
the list itself has one owner and is not copied."
  (when-let* ((file (buffer-file-name))
              ((boundp 'my/font-silo-styles)))
    (let ((path (expand-file-name file)))
      (and (seq-find (lambda (entry)
                       (string-prefix-p (expand-file-name (car entry)) path))
                     my/font-silo-styles)
           t))))

(defun my/markdown--set-column (width center)
  "Wrap this buffer at WIDTH, centred when CENTER is non-nil."
  (when (fboundp 'visual-fill-column-mode)
    (setq fill-column width)
    (setq-local visual-fill-column-width width)
    (setq-local visual-fill-column-center-text center)
    (visual-line-mode 1)
    (visual-fill-column-mode 1)
    (when (fboundp 'visual-fill-column--adjust-window)
      (visual-fill-column--adjust-window))))

(defun my/markdown--layout-adjust ()
  "Fix up the text column of a Markdown buffer, after the notes rules ran.

Two cases, and neither can be handled by `my/visual-fill-notes-setup'
without changing what that function does for Org.

INSIDE the notes tree, a docu note should get the wider column.  That
function decides by searching for `#+filetags:', which is Org front
matter; here the keyword is read from the Denote FILE NAME instead,
which survives `denote-rename-file'.

OUTSIDE the notes tree, the column is switched off entirely -- see
`my/markdown-outside-notes-layout' for why that is right for Org files
and wrong for Markdown ones.

Runs at depth 90 on `find-file-hook', after the setup it is adjusting,
and again from `my/markdown--setup' so that the layout survives
`revert-buffer' -- which re-runs mode hooks but not `find-file-hook'.
The two together mean the column is briefly set, cleared and set again
when a file is opened; that is invisible and cheaper than a second
copy of the notes rules living here."
  (when (and (derived-mode-p 'markdown-mode) (buffer-file-name))
    (cond
     ((my/markdown--in-notes-p)
      (when (and (bound-and-true-p visual-fill-column-mode)
                 (boundp 'my/fill-column-docu)
                 (my/markdown--docu-note-p))
        (my/markdown--set-column my/fill-column-docu
                                 visual-fill-column-center-text)))
     ((not (eq my/markdown-outside-notes-layout 'plain))
      (my/markdown--set-column
       (or my/markdown-outside-notes-width my-fill-column)
       (eq my/markdown-outside-notes-layout 'centered))))))

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
  ;; A file in no silo got no typeface from that call, so its prose is
  ;; still `default' -- monospaced -- while its headings inherit
  ;; `variable-pitch'.  Turning the mode on here makes body text follow
  ;; the session proportional family, and `my/font-fixed-faces' keeps
  ;; code, tables and markup monospaced as it does in a note.
  ;;
  ;; Tested against `my/font-silo-styles' rather than against
  ;; `variable-pitch-mode' itself: docu SETS that mode off deliberately,
  ;; and "off" would otherwise be indistinguishable from "never
  ;; considered".
  (when (and (eq my/markdown-unsiloed-body 'proportional)
             (not (my/markdown--siloed-p)))
    (variable-pitch-mode 1))
  (setq line-spacing 0.2)
  (electric-indent-local-mode -1)
  (setq-local electric-indent-chars nil)
  (when (and my/markdown-display-images-on-open
             (display-graphic-p)
             (fboundp 'markdown-display-inline-images))
    (ignore-errors (markdown-display-inline-images)))
  ;; The notes column rules, then this module's corrections to them.
  ;; Called here as well as from `find-file-hook' because `revert-buffer'
  ;; re-runs mode hooks only, and without this a revert would leave an
  ;; opened note full width.
  (when (fboundp 'my/visual-fill-notes-setup)
    (my/visual-fill-notes-setup))
  (my/markdown--layout-adjust))

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
  ;;
  ;; The code and table faces are on the list rather than left to
  ;; `modus-themes-mixed-fonts', which covers Org's block faces by name.
  ;; Naming them here costs nothing when the theme already handles them
  ;; -- the remap asks for the same family -- and is what keeps a fenced
  ;; block monospaced in a buffer running `variable-pitch-mode', which
  ;; every unsiloed Markdown file now does.
  (when (boundp 'my/font-fixed-faces)
    (dolist (face '(markdown-metadata-key-face
                    markdown-metadata-value-face
                    markdown-markup-face
                    markdown-language-keyword-face
                    markdown-code-face
                    markdown-inline-code-face
                    markdown-pre-face
                    markdown-table-face))
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
(add-hook 'find-file-hook #'my/markdown--layout-adjust 90)

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
;; RESTORING A MODE THE SESSION GOT WRONG
;; ============================================================

(defun my/markdown--auto-mode-for (file)
  "Return the major mode `auto-mode-alist' would give FILE today."
  (assoc-default (file-name-nondirectory file) auto-mode-alist #'string-match))

(defun my/markdown-restore-modes ()
  "Re-mode buffers that a restored session left out of `markdown-mode'.

Acts on a buffer only when all three hold: it visits a file,
`auto-mode-alist' would give that file `markdown-mode' now, and its
current mode is on `my/markdown-stale-modes'.  The third condition is
what keeps a deliberate mode choice deliberate.

Calls `normal-mode' rather than `markdown-mode' directly, so the
buffer ends up exactly as reopening the file would leave it -- file
local variables re-read, `markdown-mode-hook' run, and this module's
layout applied through it.

Run it once after installing the module; the desktop file keeps the
correct mode from the next save onwards.  Returns the number of
buffers changed."
  (interactive)
  (let ((count 0))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and buffer-file-name
                   (memq major-mode my/markdown-stale-modes)
                   (eq (my/markdown--auto-mode-for buffer-file-name)
                       'markdown-mode))
          (normal-mode)
          (setq count (1+ count)))))
    (when (called-interactively-p 'interactive)
      (message (if (zerop count)
                   "Markdown: nothing to re-mode"
                 (format "Markdown: %d buffer(s) re-moded" count))))
    count))

(defun my/markdown--restore-modes-maybe ()
  "Run `my/markdown-restore-modes' unless the option says not to."
  (when my/markdown-restore-modes-on-desktop
    (my/markdown-restore-modes)))

;; Depth 95: 01-ui.el has its own work on this hook, and re-moding a
;; buffer should happen after the session has finished assembling
;; itself rather than in the middle of it.
(add-hook 'desktop-after-read-hook #'my/markdown--restore-modes-maybe 95)

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
  [["Buffer"
    ("m" "Markup hiding" my/markdown-toggle-markup)
    ("u" "URL hiding"    markdown-toggle-url-hiding)
    ("i" "Inline images" markdown-toggle-inline-images)
    ("R" "Re-mode stale buffers" my/markdown-restore-modes)]
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
