;;; 09-theme.el --- Theme configuration and light/dark switching -*- lexical-binding: t; -*-
;;; Commentary:
;; Two themes, one switch: `modus-operandi-tinted' (light, ochre base)
;; and `modus-vivendi-tinted' (dark, night-sky base).  Toggle with
;; C-c u t toggles; F4 and F5 walk the light and dark sets.
;; The transient entries are added by 34-appearance.el.
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
;; THEME PACKAGES TO BROWSE
;; ============================================================
;; Four collections, roughly a hundred themes between them.  All are
;; `:demand t' for the reason spelled out on the Modus form below: a
;; deferred theme package is one that never configures itself, and
;; more to the point here, one whose themes never appear in
;; `custom-available-themes' and so never turn up in the cycle.
;;
;;   ef-themes        Prot.  Colourful, opinionated, still legible.
;;                    The closest match to a stated preference for
;;                    light and pastel.
;;   standard-themes  Prot.  The stock Emacs look, made consistent.
;;   doric-themes     Prot.  Minimalist: very few colours, structure
;;                    carried by weight and spacing instead.
;;   doom-themes      Around sixty ports of themes from other editors.
;;                    Uneven, and the widest net by far.
;;
;; Dropping one is a matter of deleting its `use-package' form: the
;; lists below are filtered through `custom-available-themes', so a
;; theme from an uninstalled package disappears from the cycle rather
;; than signalling.

(use-package ef-themes       :ensure t :demand t)
(use-package standard-themes :ensure t :demand t)
(use-package doric-themes    :ensure t :demand t)
(use-package doom-themes     :ensure t :demand t)

;; ============================================================
;; WHICH THEMES ARE LIGHT AND WHICH ARE DARK
;; ============================================================
;; Three sources, merged:
;;
;;   1. The lists a package publishes (`ef-themes-light-themes' and
;;      friends), read through `boundp' so a renamed or absent
;;      variable is skipped rather than breaking startup.
;;   2. The curated lists below, for packages that publish nothing --
;;      doom-themes in particular.
;;   3. Anything filed by hand with `my/theme-classify', stored in
;;      `my/ui-state-file'.
;;
;; Everything is then filtered through `custom-available-themes', which
;; is what makes a wrong or stale name harmless: it is simply dropped.
;; That filter is the reason the curated lists can afford to be
;; generous rather than verified one by one.
;;
;; A theme that ends up on neither list still appears in
;; `my/theme-cycle-all' and can be filed from there.

(defcustom my/theme-known-light
  '(modus-operandi modus-operandi-tinted
    modus-operandi-deuteranopia modus-operandi-tritanopia
    standard-light standard-light-tinted
    doric-light
    doom-one-light doom-solarized-light doom-nord-light
    doom-opera-light doom-tomorrow-day doom-acario-light
    doom-flatwhite doom-homage-white doom-earl-grey
    doom-ayu-light doom-gruvbox-light doom-plain
    doom-oksolar-light doom-bluloco-light doom-feather-light)
  "Light themes not published by a package variable.
Names that do not exist are ignored, so this list may be generous."
  :type '(repeat symbol) :group 'faces)

(defcustom my/theme-known-dark
  '(modus-vivendi modus-vivendi-tinted
    modus-vivendi-deuteranopia modus-vivendi-tritanopia
    standard-dark standard-dark-tinted
    doric-dark
    doom-one doom-vibrant doom-nord doom-dracula doom-gruvbox
    doom-palenight doom-tomorrow-night doom-solarized-dark
    doom-city-lights doom-horizon doom-moonlight doom-oceanic-next
    doom-material doom-monokai-pro doom-zenburn doom-henna
    doom-badger doom-old-hope doom-ir-black doom-nova
    doom-oksolar-dark doom-bluloco-dark doom-feather-dark)
  "Dark themes not published by a package variable.
Names that do not exist are ignored, so this list may be generous."
  :type '(repeat symbol) :group 'faces)

(defun my/theme--available (themes)
  "Return the members of THEMES that are actually installed, deduplicated."
  (let ((available (custom-available-themes)))
    (seq-uniq (seq-filter (lambda (theme) (memq theme available)) themes))))

(defun my/theme-light-themes ()
  "Return every light theme available."
  (my/theme--available
   (append my/theme-known-light
           (and (boundp 'ef-themes-light-themes) ef-themes-light-themes)
           (and (boundp 'standard-themes-light-themes) standard-themes-light-themes)
           (and (boundp 'doric-themes-light-themes) doric-themes-light-themes)
           (my/ui-state-get :themes-light))))

(defun my/theme-dark-themes ()
  "Return every dark theme available."
  (my/theme--available
   (append my/theme-known-dark
           (and (boundp 'ef-themes-dark-themes) ef-themes-dark-themes)
           (and (boundp 'standard-themes-dark-themes) standard-themes-dark-themes)
           (and (boundp 'doric-themes-dark-themes) doric-themes-dark-themes)
           (my/ui-state-get :themes-dark))))

(defun my/theme-light-p (&optional theme)
  "Non-nil when THEME (default: the active one) is known to be light."
  (memq (or theme (car custom-enabled-themes)) (my/theme-light-themes)))

;; ============================================================
;; LOADING, AND WHAT RUNS AFTERWARDS
;; ============================================================

(defvar my/theme-after-load-hook nil
  "Run after any theme is loaded, whatever family it belongs to.

A theme reassigns every face it covers, so anything set outside the
theme has to be re-applied afterwards.  Modus and Ef each provide
their own post-load hook; this one exists so that a module wanting to
react does not have to know which family is active.

03b-fonts.el adds `my/fonts-apply' here.  Add sparingly: a face that
INHERITS from a face the theme styles needs no hook at all.")

(defun my/theme-load (theme)
  "Disable all active themes and load THEME, remembering the choice.

Deliberately plain `load-theme' rather than `modus-themes-load-theme'
or `ef-themes-select': those work only for their own family, and this
has to handle four.  What the family loaders add is their post-load
hook, which `my/theme--after-load' replaces with one that fires for
any theme.

PADDING IS TURNED OFF ACROSS THE LOAD, NOT REFRESHED AFTER IT
-------------------------------------------------------------
spacious-padding builds its border and mode-line faces from the
palette current when it is enabled, and among other things writes a
`:box' onto the mode line.  Leaving it enabled while a theme loads
means it computes from whichever palette is half in place, and a theme
that leaves a colour `unspecified' -- which the Modus and Ef themes do
not, and several doom-themes and the built-in themes do -- yields an
invalid box specification.  The resulting `face-spec-set' error aborts
`enable-theme' partway, so the theme applies to some faces and not
others: the \"loads but not completely\" symptom.

Off, load, on again puts the computation after a complete palette.

BOTH STEPS ARE GUARDED
----------------------
A theme that still cannot be combined with padding reports itself and
leaves padding off, rather than signalling out of a keypress and
leaving the frame in whatever state the error interrupted.  Browsing a
hundred themes means meeting a few broken ones; that is a reason to
survive them, not to stop browsing."
  (let ((padding (bound-and-true-p spacious-padding-mode)))
    (when padding (spacious-padding-mode -1))
    (mapc #'disable-theme custom-enabled-themes)
    (condition-case err
        (load-theme theme :no-confirm)
      (error (message "%s loaded with errors: %s"
                      theme (error-message-string err))))
    (when padding
      (condition-case err
          (spacious-padding-mode 1)
        (error (message "%s: padding left off, it does not combine with this theme (%s)"
                        theme (error-message-string err))))))
  ;; Remembered per side, so `my/theme-toggle' can return to the last
  ;; light AND the last dark rather than to a fixed pair.
  (my/ui-state-set (if (my/theme-light-p theme) :theme-light :theme-dark) theme)
  (my/ui-state-set :theme theme)
  (message "%s" theme)
  theme)

(defun my/theme--after-load (&rest _)
  "Re-apply everything a theme load has just overwritten.

Padding is deliberately NOT handled here.  This runs from
`enable-theme-functions', which fires DURING `load-theme', when the
palette is only partly in place -- exactly the condition that produces
an invalid `:box'.  `my/theme-load' handles padding after the load has
finished."
  (run-hooks 'my/theme-after-load-hook))

(defun my/theme-repair ()
  "Clear accumulated face overrides and load the active theme again.

For when a theme keeps loading wrong even after switching away and
back.  `custom-set-faces' -- used by Custom, and by some packages at
runtime -- writes the `user' theme, which outranks every real theme
and is re-applied on every `enable-theme'.  A single invalid
specification stored there therefore breaks EVERY subsequent theme
load, not just the one that produced it.

Disabling the `user' theme drops those overrides for this session.
Nothing in this configuration relies on them: colour lives in the
palette overrides below, and the faces defined by 34-appearance.el
inherit rather than override."
  (interactive)
  (disable-theme 'user)
  (my/theme-load (or (car custom-enabled-themes)
                     (my/ui-state-get :theme)
                     (car (my/theme-light-themes))))
  (message "Cleared `user' face overrides and reloaded %s"
           (car custom-enabled-themes)))

;; `enable-theme-functions' (Emacs 29+) fires for every theme from
;; every family, which is exactly the abstraction wanted here.  The
;; fallback covers older Emacs at the cost of only reacting to Modus.
(if (boundp 'enable-theme-functions)
    (add-hook 'enable-theme-functions #'my/theme--after-load)
  (add-hook 'modus-themes-after-load-theme-hook #'my/theme--after-load))

;; ============================================================
;; CYCLING, TOGGLING, PICKING
;; ============================================================

(defun my/theme--cycle (themes)
  "Load the theme after the active one in THEMES, wrapping around.
Starts at the beginning when the active theme is not in the list,
which is what lets F4 and F5 jump between families instead of
refusing to move."
  (let* ((current (car custom-enabled-themes))
         (position (seq-position themes current))
         (next (if position
                   (nth (mod (1+ position) (length themes)) themes)
                 (car themes))))
    (my/theme-load next)))

(defun my/theme-cycle-light ()
  "Step to the next light theme, announcing its name.
Press repeatedly to walk the whole set in a fixed order -- which is
the point: comparing themes needs a sequence that can be retraced,
not a random draw."
  (interactive)
  (my/theme--cycle (my/theme-light-themes)))

(defun my/theme-cycle-dark ()
  "Step to the next dark theme.  See `my/theme-cycle-light'."
  (interactive)
  (my/theme--cycle (my/theme-dark-themes)))

(defun my/theme-toggle ()
  "Switch between light and dark, keeping the last choice of each.
Unlike `modus-themes-toggle' this works across families: browse the
light themes with F4 and the dark ones with F5, and this returns to
whichever was last active on the other side."
  (interactive)
  (my/theme-load
   (if (my/theme-light-p)
       (my/ui-state-get :theme-dark (car (my/theme-dark-themes)))
     (my/ui-state-get :theme-light (car (my/theme-light-themes))))))

(defun my/theme-cycle-all ()
  "Step through every installed theme, classified or not.
The escape hatch for the classification above: a theme that landed on
neither list, or on the wrong one, still turns up here and can be
filed with `my/theme-classify'."
  (interactive)
  (my/theme--cycle (my/theme--available (custom-available-themes))))

(defun my/theme-cycle-favourites ()
  "Step through the themes marked with `my/theme-favourite-toggle'.
The point of browsing a hundred themes is to end up with four."
  (interactive)
  (if-let* ((favourites (my/theme--available (my/ui-state-get :themes-favourite))))
      (my/theme--cycle favourites)
    (user-error "No favourites yet -- mark one with `my/theme-favourite-toggle'")))

(defun my/theme-favourite-toggle ()
  "Add the active theme to the favourites, or remove it."
  (interactive)
  (let* ((theme (car custom-enabled-themes))
         (favourites (my/ui-state-get :themes-favourite))
         (member (memq theme favourites)))
    (my/ui-state-set :themes-favourite
                     (if member
                         (delq theme (copy-sequence favourites))
                       (cons theme favourites)))
    (message "%s %s favourites (%d total)"
             theme (if member "removed from" "added to")
             (length (my/ui-state-get :themes-favourite)))))

(defun my/theme-classify (side)
  "File the active theme as light or dark.
For themes the lists above did not know about, or got wrong.  The
choice is remembered in `my/ui-state-file', so it applies to F4 and F5
from now on without editing this file."
  (interactive
   (list (intern (completing-read "Classify current theme as: "
                                  '("light" "dark") nil t))))
  (let* ((theme (car custom-enabled-themes))
         (key (if (eq side 'light) :themes-light :themes-dark))
         (other (if (eq side 'light) :themes-dark :themes-light)))
    (my/ui-state-set key (cons theme (my/ui-state-get key)))
    (my/ui-state-set other (delq theme (copy-sequence (my/ui-state-get other))))
    (message "%s filed as %s" theme side)))

(defun my/theme-select ()
  "Pick any installed theme by name, with completion.
Favourites first, then everything else."
  (interactive)
  (let ((favourites (my/theme--available (my/ui-state-get :themes-favourite))))
    (my/theme-load
     (intern (completing-read
              "Theme: "
              (append favourites
                      (seq-difference (my/theme--available (custom-available-themes))
                                      favourites))
              nil t)))))

(defun my/theme--startup-load ()
  "Load the remembered theme, once, at the end of startup."
  (let ((theme (my/ui-state-get :theme)))
    (my/theme-load
     (if (and theme (memq theme (append (my/theme-light-themes)
                                        (my/theme-dark-themes))))
         theme
       (car (my/theme-light-themes))))))

(use-package modus-themes
  :ensure t
  ;; `:demand t' IS THE WHOLE FIX -- do not remove it.
  ;;
  ;; `:bind' at the bottom of this form makes `use-package' DEFER the
  ;; package: it writes autoloads for `modus-themes-toggle' and waits
  ;; for something to call one before loading `modus-themes' itself.
  ;; Deferring is the right default for a package whose commands are
  ;; the point, and exactly wrong for a theme, because everything below
  ;; lives in `:config' -- and `:config' runs only after the package
  ;; loads.
  ;;
  ;; Without `:demand t', a fresh Emacs starts with NO theme enabled:
  ;; `custom-enabled-themes' is empty, none of the options below have
  ;; been set, and neither hook has been added.  The frame still looks
  ;; roughly right because the desktop frameset restores
  ;; `background-color' from the last session, which is why the failure
  ;; reads as "the theme loaded badly" rather than "no theme loaded".
  ;;
  ;; Pressing <f5> then triggers the autoload: `modus-themes' loads,
  ;; `:config' finally runs, and the session repairs itself in one
  ;; step.  Opening the View transient did the same thing for the same
  ;; reason -- it is the only transient in the configuration that names
  ;; `modus-themes-toggle' as a suffix, and transient resolves an
  ;; autoloaded suffix command while building the menu.  That is why
  ;; ONE menu appeared to fix the appearance and the others did not.
  ;;
  ;; Same class of mistake as the `:hook' on org-modern in
  ;; 11-org-appearance.el: `use-package' keyword implies deferral,
  ;; deferral means `:config' may never run, and the symptom surfaces
  ;; far from the cause.
  :demand t
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
  ;; (C-c u t twice) -- overrides take effect on load, not on assignment.
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
  ;; Load LAST, not here
  ;; ----------------------------------------------------------
  ;; The options above are set at module position 09.  The theme
  ;; itself is loaded from `emacs-startup-hook', which is the last
  ;; point in startup: after init.el has loaded modules 10 through 34,
  ;; and after `after-init-hook', where `desktop-save-mode' restores
  ;; the frameset.
  ;;
  ;; A theme is the last word on how a face looks, so it should get
  ;; the last word chronologically too.  Loading it at 09 put it
  ;; BEFORE two dozen modules that define faces, enable minor modes
  ;; that build faces from the current palette, and -- in the case of
  ;; spacious-padding (34-appearance.el) -- rewrite frame parameters.
  ;; It also put it before the desktop frameset, which carries
  ;; `background-color', `foreground-color' and `font' from whenever
  ;; the session was last written.  Loading last makes the theme the
  ;; final assignment rather than one of several competing ones.
  ;;
  ;; This is why the appearance repaired itself the moment anything
  ;; reloaded the theme, and why loading it at 09 and then again on
  ;; `desktop-after-read-hook' was not enough: the second load still
  ;; happened before `emacs-startup-hook', so whatever ran later got
  ;; the last word again.
  ;;
  ;; NOT `after-init-hook': that is where the desktop restore itself
  ;; runs, and hook order within it is not something this module
  ;; should have to reason about.  `emacs-startup-hook' runs strictly
  ;; after all of `after-init-hook'.
  (add-hook 'emacs-startup-hook #'my/theme--startup-load)

  ;; F4 walks the light themes, F5 the dark ones, both wrapping around
  ;; and both announcing the name so a good one can be written down.
  ;; The light/dark toggle keeps `C-c u t' and the View menu.
  ;; F4 walks the light themes, F5 the dark ones, both wrapping around
  ;; and both announcing the name so a good one can be written down.
  ;; Shift walks everything installed, for themes the classification
  ;; missed.  `C-c u m' marks a keeper; `C-c u M' then walks only those.
  :bind (("<f4>"      . my/theme-cycle-light)
         ("<f5>"      . my/theme-cycle-dark)
         ("S-<f4>"    . my/theme-cycle-all)
         ("S-<f5>"    . my/theme-cycle-all)
         ("C-c u t"   . my/theme-toggle)
         ("C-c u T"   . my/theme-select)
         ("C-c u m"   . my/theme-favourite-toggle)
         ("C-c u M"   . my/theme-cycle-favourites)
         ("C-c u C"   . my/theme-classify)
         ("C-c u R"   . my/theme-repair)))

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

;; ============================================================
;; DIAGNOSTIC
;; ============================================================
;; For the case where the frame looks wrong until something reloads
;; the theme.  Run it, note the output, do whatever makes the
;; appearance snap into place, run it again, and compare the two
;; lines.  Whichever field changed is the one being set behind the
;; theme's back.
;;
;; `background-color' as a FRAME PARAMETER and the background of the
;; `default' FACE are two different things that normally agree.  When
;; they disagree, something has written the frame parameter directly
;; -- a frameset restore is the usual culprit -- and the frame shows
;; that colour under faces computed from the theme.

(defun my/theme-debug ()
  "Report the state that decides how the frame looks.
Output goes to the echo area and to *Messages*."
  (interactive)
  (message
   (concat
    "theme=%s | frame-bg=%s | default-face-bg=%s | frame-font=%s\n"
    "variable-pitch=%s | default-height=%s | padding=%s | org-modern=%s")
   (or (car custom-enabled-themes) "NONE")
   (frame-parameter nil 'background-color)
   (face-attribute 'default :background nil t)
   (or (frame-parameter nil 'font) "-")
   (face-attribute 'variable-pitch :family nil t)
   (face-attribute 'default :height nil t)
   (if (bound-and-true-p spacious-padding-mode) "on" "off")
   (if (fboundp 'org-modern-mode) "loaded" "MISSING")))

(provide '09-theme)
;;; 09-theme.el ends here
