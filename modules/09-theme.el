;;; 09-theme.el --- Theme configuration and light/dark switching -*- lexical-binding: t; -*-
;;; Commentary:
;; Two themes, one switch: `modus-operandi-tinted' (light, ochre base)
;; and `modus-vivendi-tinted' (dark, night-sky base).  Toggle with
;; <f5> or C-c u t; the transient entry is added by 34-appearance.el.
;;
;; WHY THE DARK THEME WORKS NOW
;; ----------------------------
;; It did not before, and the reason was never the theme.  custom.el
;; carried a `custom-set-faces' block pinning a dozen Org faces to
;; literal light colours (org-block on #fef8e0, org-link on #555555,
;; org-quote on #f9f9f9).  `custom-set-faces' writes the `user' theme,
;; which outranks every other theme by design, so loading a dark theme
;; produced light blocks on a dark background.  Those pins are gone;
;; everything they expressed is now stated once, here, in terms that
;; each theme resolves for itself.
;;
;; THE THREE LAYERS, AND WHICH ONE TO EDIT
;; ---------------------------------------
;;   1. Palette overrides -- COLOUR.  Semantic mappings such as
;;      `fg-heading-1' or `bg-prose-block-contents' are given the name
;;      of a palette entry (`blue-warmer', `bg-yellow-nuanced'), never
;;      a hex string.  Each theme owns the actual value behind that
;;      name, so one override is correct in both light and dark.
;;      -> Change colours here.
;;
;;   2. `modus-themes-headings' -- SIZE, WEIGHT, TYPEFACE of headings.
;;      Heading heights used to live in custom.el and silently beat
;;      the theme.  They live here now, and heading colours are layer 1.
;;      -> Change heading sizes here.
;;
;;   3. `my/theme--custom-faces' -- the residue.  A handful of faces
;;      that no override reaches.  Runs from
;;      `modus-themes-after-load-theme-hook', so it survives a toggle.
;;      A theme reassigns every face it covers when it loads, which is
;;      why this cannot be a one-off call at startup.
;;      -> Add here only what layers 1 and 2 genuinely cannot express.
;;
;; WHAT IS NOT HERE
;; ----------------
;; Colours used by this configuration's own buffers (dashboard lines,
;; mode-line indicators) are not theme settings and are not listed
;; here.  They are `defface' declarations that inherit from faces the
;; theme already styles -- see 34-appearance.el.  No module should
;; write a hex colour into a `propertize' call again.
;;
;; TWO SETTINGS WERE REMOVED, NOT MOVED
;; ------------------------------------
;; `modus-themes-org-blocks' was deleted from the package in version
;; 4.4.0 and had been doing nothing.  Its replacement is the
;; `bg-prose-block-*' overrides below.  The `rainbow' property in
;; `modus-themes-headings' is likewise no longer part of the option in
;; version 5; per-level heading colour is now `fg-heading-N' in the
;; overrides, which is strictly more capable -- background and overline
;; can be set per level too.
;;
;; Docs: ~/.emacs.d/function_helper.org::#theme

;;; Code:

;; ============================================================
;; MODUS THEMES
;; ============================================================
;; Every option must be set BEFORE the theme loads, which is why the
;; whole configuration sits in `:config' ahead of the load call rather
;; than being split across `:init' and `:custom'.

;; ============================================================
;; REMEMBERING WHICH THEME WAS ACTIVE
;; ============================================================
;; The choice is written to a one-line file and read back at startup.
;; Deliberately NOT stored through `custom-set-variables' (which would
;; put it in custom.el, the file this session emptied on purpose) and
;; NOT through the desktop (which is the thing that has been failing).
;; One fact, one small file, no dependency on anything else working.

(defcustom my/theme-state-file (locate-user-emacs-file "theme-state.el")
  "File holding the name of the theme that was last active."
  :type 'file :group 'faces)

(defun my/theme--save-state (&rest _)
  "Record the active theme in `my/theme-state-file'."
  (when-let* ((theme (car custom-enabled-themes)))
    (with-temp-file my/theme-state-file
      (prin1 theme (current-buffer)))))

(defun my/theme--read-state ()
  "Return the remembered theme, or nil.
Returns nil rather than signalling on a missing, empty or corrupt
file, and refuses any value that is not one of the two themes the
toggle knows about -- a stale name from an uninstalled theme would
otherwise abort init."
  (when (file-readable-p my/theme-state-file)
    (with-temp-buffer
      (insert-file-contents my/theme-state-file)
      (let ((theme (ignore-errors (read (current-buffer)))))
        (and (symbolp theme)
             (memq theme modus-themes-to-toggle)
             theme)))))

(defun my/theme-load (theme)
  "Load THEME through the Modus API, falling back to `load-theme'.
`modus-themes-load-theme' is preferred because it runs
`modus-themes-after-load-theme-hook', which is what re-applies fonts
\(03b-fonts.el) and records the choice."
  (if (fboundp 'modus-themes-load-theme)
      (modus-themes-load-theme theme)
    (load-theme theme :no-confirm)))

(defun my/theme-reload ()
  "Load the active theme again.

Needed after a desktop restore, and useful by hand.

WHY A RESTORED SESSION NEEDS THIS
---------------------------------
`desktop-save-mode' saves a frameset, and a frameset carries frame
parameters -- among them `background-color', `foreground-color' and
`cursor-color'.  Restoring it re-applies the colours from whenever the
desktop was last written, on top of whatever theme init had already
loaded.  The frame then shows one theme's background under the other
theme's faces: dark canvas, light-theme text, or the reverse.  That is
the \"broken\" startup, and it is the same failure as the tool bar
coming back (see the desktop block in 01-ui.el) -- a frameset
overriding a setting made earlier in init.

It also explains why the appearance repaired itself the moment
anything reloaded the theme.  Loading a theme reassigns the frame
colour parameters, which is exactly what the stale frameset had got
wrong.

The alternative would be to filter those three parameters out of
`frameset-filter-alist' so the frameset never carries them.  Reloading
is chosen instead because it is one call, it needs no knowledge of
which parameters a future Emacs might add, and it doubles as the point
where the remembered theme is applied."
  (interactive)
  (my/theme-load (or (car custom-enabled-themes)
                     (car modus-themes-to-toggle))))

(use-package modus-themes
  :ensure t
  :config

  ;; ----------------------------------------------------------
  ;; Which two themes the toggle alternates between
  ;; ----------------------------------------------------------
  (setq modus-themes-to-toggle '(modus-operandi-tinted modus-vivendi-tinted))

  ;; ----------------------------------------------------------
  ;; General options
  ;; ----------------------------------------------------------
  (setq modus-themes-italic-constructs t
        modus-themes-bold-constructs t
        ;; Spacing-sensitive faces (tables, blocks, inline code) always
        ;; inherit `fixed-pitch'.  This is what keeps code monospaced
        ;; inside journal buffers running the handwriting font, and it
        ;; is why custom.el no longer needs a dozen `:inherit
        ;; fixed-pitch' specs of its own.
        modus-themes-mixed-fonts t
        ;; Mode line, header line and tab bar keep the default
        ;; monospaced family.  Proportional UI text next to a
        ;; monospaced buffer reads as an accident rather than a choice.
        modus-themes-variable-pitch-ui nil
        ;; Loading a Modus theme disables any other active theme.
        ;; Without this, toggling would blend light and dark.
        modus-themes-disable-other-themes t)

  ;; ----------------------------------------------------------
  ;; Headings: size, weight, typeface (NOT colour -- see overrides)
  ;; ----------------------------------------------------------
  ;; `variable-pitch' here means the `variable-pitch' face, which
  ;; 03b-fonts.el remaps per silo: the handwriting family in journal,
  ;; a text sans in pks, the monospaced family in docu.  So one
  ;; property in this list produces three different heading typefaces
  ;; without this file knowing that silos exist.
  ;;
  ;; Setting the global `variable-pitch' face to the handwriting font
  ;; -- which is what happened before -- put every heading in every
  ;; note into it, docu and thesis chapters included.
  (setq modus-themes-headings
        '((0 . (variable-pitch semibold 1.4))   ; #+title
          (1 . (variable-pitch semibold 1.3))
          (2 . (variable-pitch semibold 1.2))
          (3 . (variable-pitch medium 1.1))
          (agenda-date . (semibold 1.2))
          (agenda-structure . (variable-pitch light 1.5))
          (t . (variable-pitch medium 1.0))))

  ;; ----------------------------------------------------------
  ;; Palette overrides: colour
  ;; ----------------------------------------------------------
  ;; The base is the `faint' preset the package ships: grays are toned
  ;; down, gray backgrounds are dropped in several contexts, and accent
  ;; colours are desaturated.  That is the pastel register, arrived at
  ;; by the theme author rather than by hand-picking hex values, and it
  ;; stays coherent across both themes.
  ;;
  ;; The entries above `,@' refine it.  Backtick and `,@' rather than a
  ;; plain quote: the preset has to be spliced in, not quoted as a
  ;; symbol.  Later entries do NOT win over earlier ones, so anything
  ;; that must beat the preset belongs above the splice, which is where
  ;; it is.
  ;;
  ;; To audition alternatives, replace the preset with
  ;; `modus-themes-preset-overrides-cooler' or `...-warmer', or drop it
  ;; and keep only the explicit entries.  Reload the theme afterwards
  ;; (<f5> twice) -- overrides take effect on load, not on assignment.
  (setq modus-themes-common-palette-overrides
        `(;; -- Mode line: no border.  The line reads as a band rather
          ;; than a boxed widget, which is the shape spacious-padding
          ;; then turns into a hairline overline.
          (border-mode-line-active unspecified)
          (border-mode-line-inactive unspecified)

          ;; -- Links: coloured, never underlined.  Notes are dense
          ;; with denote: links and a rule under each one turns a page
          ;; into a ladder.  This is what org-link's `:underline nil'
          ;; in custom.el used to do, minus the light-only foreground.
          (underline-link unspecified)
          (underline-link-visited unspecified)
          (underline-link-symbolic unspecified)
          (fg-link cyan-cooler)
          (fg-link-visited magenta-faint)

          ;; -- Headings: a cool-to-warm progression, desaturated.
          (fg-heading-0 blue-faint)
          (fg-heading-1 blue-warmer)
          (fg-heading-2 magenta-cooler)
          (fg-heading-3 cyan-cooler)
          (fg-heading-4 yellow-cooler)

          ;; -- Org blocks: a soft ochre wash, echoing the #fef8e0 that
          ;; custom.el used to pin, but resolved per theme.  Delimiter
          ;; lines share the contents background so a block reads as
          ;; one object.
          (bg-prose-block-contents bg-yellow-nuanced)
          (bg-prose-block-delimiter bg-yellow-nuanced)
          (fg-prose-block-delimiter yellow-faint)

          ;; -- Inline code and verbatim: foreground only, no boxes.
          (bg-prose-code unspecified)
          (fg-prose-code green-cooler)
          (bg-prose-verbatim unspecified)
          (fg-prose-verbatim magenta-warmer)

          ;; -- Dates and agenda, kept quiet.  `date-common' is what
          ;; org-date renders in; custom.el pinned it to firebrick.
          (date-common cyan-faint)
          (date-deadline red-faint)
          (date-scheduled yellow-faint)
          (date-weekday fg-alt)
          (date-weekend fg-dim)
          (prose-todo yellow-warmer)
          (prose-done fg-alt)

          ;; -- Tab bar: the bar itself vanishes into the frame, the
          ;; current tab is the only thing carrying a background.  With
          ;; 23-fixed-tabs.el a tab is a place, so "which place am I
          ;; in" is the only question the bar has to answer.
          (bg-tab-bar bg-main)
          (bg-tab-current bg-lavender)
          (bg-tab-other bg-dim)

          ;; -- Fringe invisible.  spacious-padding widens the fringes
          ;; to act as page margins; a fringe with a distinct colour
          ;; would then read as a visible gutter instead of whitespace.
          (fringe unspecified)

          ;; -- Line numbers recede.
          (fg-line-number-inactive "gray50")
          (fg-line-number-active fg-main)
          (bg-line-number-inactive unspecified)
          (bg-line-number-active unspecified)

          ,@modus-themes-preset-overrides-faint))

  ;; ----------------------------------------------------------
  ;; Load, and keep the choice
  ;; ----------------------------------------------------------
  ;; The remembered theme, or the light one on a first run.  Before
  ;; this, startup always loaded `(car modus-themes-to-toggle)', so a
  ;; session left in dark came back light -- the toggle worked but did
  ;; not persist, which is not what a toggle is for.
  (my/theme-load (or (my/theme--read-state)
                     (car modus-themes-to-toggle)))

  ;; Record on every load, including the ones the toggle performs.
  (add-hook 'modus-themes-after-load-theme-hook #'my/theme--save-state)

  ;; And load again once the desktop's frameset is in place, because
  ;; the frameset brings stale frame colours with it.  See the doc
  ;; string of `my/theme-reload'.  Harmless when no desktop is
  ;; restored: the hook simply never runs.
  (add-hook 'desktop-after-read-hook #'my/theme-reload)

  :bind (("<f5>" . modus-themes-toggle)
         ("C-c u t" . modus-themes-toggle)))

;; ============================================================
;; WHY THERE IS NO RUNTIME FACE BLOCK HERE ANY MORE
;; ============================================================
;; An earlier revision ran `custom-set-faces' from
;; `modus-themes-after-load-theme-hook' to set four faces the palette
;; overrides did not reach: org-quote, denote-faces-date,
;; org-property-value, org-special-keyword.
;;
;; That was a mistake, and it is the likely reason colours differed
;; between the light theme at startup and the light theme after a
;; toggle.  `custom-set-faces' writes the `user' theme -- the same
;; mechanism that made dark mode impossible from custom.el, only now
;; written from code and therefore invisible in any file.  Once
;; written, those four faces outrank whatever theme is loaded.  As
;; long as the hook fires on every load the values are refreshed and
;; nothing shows; the moment one load happens without the hook -- the
;; first one at startup, before the hook is even attached -- the
;; `user' theme keeps a value from the other palette and the two
;; directions of the toggle stop agreeing.
;;
;; None of the four was necessary:
;;
;;   org-quote            Modus styles it, and `modus-themes-italic-
;;                        constructs' already makes it italic.
;;   denote-faces-date    Modus covers Denote's faces.
;;   org-property-value   `modus-themes-mixed-fonts' already gives it
;;   org-special-keyword  `fixed-pitch'.
;;
;; If a face ever genuinely needs an attribute no palette override can
;; express, prefer a `defface' that INHERITS from a face the theme
;; styles -- see the shared faces in 34-appearance.el.  An inheriting
;; face follows the theme for free and writes nothing to the `user'
;; theme.  Reach for `custom-set-faces' only when inheritance cannot
;; work, and then know that the result is permanent.

(provide '09-theme)
;;; 09-theme.el ends here
