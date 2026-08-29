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
  ;; Load
  ;; ----------------------------------------------------------
  ;; `modus-themes-load-theme' rather than `load-theme': it runs
  ;; `modus-themes-after-load-theme-hook', which is what
  ;; `my/theme--custom-faces' below hangs on.  Guarded because the
  ;; function arrived in version 4; the fallback loses the hook but
  ;; still produces a themed session rather than an init error.
  (if (fboundp 'modus-themes-load-theme)
      (modus-themes-load-theme (car modus-themes-to-toggle))
    (load-theme (car modus-themes-to-toggle) :no-confirm))

  :bind (("<f5>" . modus-themes-toggle)
         ("C-c u t" . modus-themes-toggle)))

;; ============================================================
;; RESIDUAL FACES: what the overrides cannot reach
;; ============================================================
;; Deliberately short.  Anything that can be said as a palette override
;; belongs above; this function exists for the cases where a face needs
;; an attribute that is not a colour mapping, or belongs to a package
;; the themes do not cover.
;;
;; `modus-themes-with-colors' binds every palette name of the ACTIVE
;; theme, so `bg-dim' below is a light gray in modus-operandi-tinted
;; and a dark one in modus-vivendi-tinted, from the same line of code.
;;
;; `custom-set-faces' at runtime is the documented mechanism here (see
;; the "Add padding to the mode line" section of the Modus manual), not
;; `set-face-attribute'.  The difference matters: `set-face-attribute'
;; changes only the frames that already exist, so a frame created later
;; by `my/detach-buffer-to-frame' (23-fixed-tabs.el) would recompute
;; its faces from the theme and show a different result.  That
;; discrepancy is exactly the bug 11-org-appearance.el documents.

(defun my/theme--custom-faces (&rest _)
  "Apply the faces that palette overrides cannot express.
Run from `modus-themes-after-load-theme-hook', so it re-applies after
every toggle.  Takes and ignores arguments so that it can also be used
with `enable-theme-functions' if needed."
  (when (fboundp 'modus-themes-with-colors)
    (modus-themes-with-colors
      (custom-set-faces
       ;; Quotations: a proportional face and a nuanced background.
       ;; The typeface part is why this is not a palette override --
       ;; the palette has no say over font families.  Inheriting
       ;; `variable-pitch' is what makes a quotation render in the
       ;; handwriting family inside a journal, the text sans in pks and
       ;; the monospaced family in docu, since 03b-fonts.el remaps that
       ;; face per silo rather than globally.
       `(org-quote ((,c :inherit variable-pitch
                        :background ,bg-dim
                        :slant italic
                        :extend t)))
       ;; Denote's file-name components in Dired and in prompts.  The
       ;; themes cover Denote, but the date component was pinned to
       ;; "dark magenta" in custom.el and is restated here so the
       ;; intent survives rather than reverting silently.
       `(denote-faces-date ((,c :foreground ,magenta-faint)))
       ;; Property drawer values: dimmer than the keys, and monospaced
       ;; regardless of the surrounding buffer font.
       `(org-property-value ((,c :inherit fixed-pitch :foreground ,fg-alt)))
       `(org-special-keyword ((,c :inherit fixed-pitch :height 0.85 :foreground ,fg-dim)))))))

(add-hook 'modus-themes-after-load-theme-hook #'my/theme--custom-faces)

;; The hook does not fire for the load performed inside the
;; `use-package' form above when this file is evaluated a second time
;; during development, and on a cold start the function is defined
;; after that load.  Calling it once here makes both paths agree.
(my/theme--custom-faces)

(provide '09-theme)
;;; 09-theme.el ends here
