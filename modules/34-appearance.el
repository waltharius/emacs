;;; 34-appearance.el --- Visual layer: padding, faces, motion cues -*- lexical-binding: t; -*-
;;; Commentary:
;; The cosmetic layer that sits on top of the theme.  Nothing here
;; changes what any command does; deleting this file from init.el
;; leaves a working but plainer Emacs.
;;
;; WHAT IT OWNS
;;   1. `spacious-padding'  -- frame borders, window dividers, fringes
;;                             as page margins, hairline mode line.
;;   2. Shared faces        -- the named faces other modules use
;;                             instead of writing hex colours into
;;                             `propertize' calls.
;;   3. `lin'               -- a prominent current-line highlight in
;;                             list buffers, gentle everywhere else.
;;   4. `pulsar'            -- a brief pulse on the line jumped to.
;;   5. Text scaling        -- per-buffer and global size adjustment.
;;   6. Menu entries        -- appended to the View menu (C-c n v).
;;
;; WHY THESE AND NOT OTHERS
;; ------------------------
;; The candidates that were considered and rejected, so the reasoning
;; is not lost and the same ground is not covered twice:
;;
;;   doom-modeline    Would replace the mode line in 01-ui.el, whose
;;                    word-count segment and pin segment would have to
;;                    be rebuilt as doom segments.  Its icon-heavy
;;                    aesthetic also pulls against the direction taken
;;                    here.  spacious-padding's hairline mode line
;;                    reaches the same "not from 1995" impression by
;;                    removing weight rather than adding it.
;;
;;   centaur-tabs     Buffer tabs.  23-fixed-tabs.el builds a workspace
;;                    model on `tab-bar', where a tab is a place.  A
;;                    second row of tabs answering a different question
;;                    would compete with it.  `tab-bar' is instead
;;                    restyled through palette overrides in 09-theme.el.
;;
;;   modern-tab-bar   Would be the right tool -- SVG rendering of the
;;                    existing `tab-bar', no API change.  It is not on
;;                    GNU ELPA or MELPA and needs a VC install, which
;;                    this configuration does not otherwise do.
;;
;;   beacon           Overlaps pulsar, and configures itself with a
;;                    literal hex colour, which is the exact pattern
;;                    this module exists to remove.
;;
;;   mini-frame       Puts the minibuffer in a child frame.  Child
;;                    frames on Wayland/PGTK are the least reliable
;;                    part of that display path, and it would sit
;;                    between which-key and every transient menu in the
;;                    configuration.  High blast radius, cosmetic gain.
;;
;; RELATED MODULES
;;   09-theme.el owns colour.  Faces defined here inherit from faces
;;   the theme styles, so they follow the light/dark toggle without
;;   this module knowing anything about palettes.
;;
;; Docs: ~/.emacs.d/function_helper.org::#appearance

;;; Code:

;; ============================================================
;; SHARED FACES
;; ============================================================
;; Every face here inherits and specifies no colour of its own.  That
;; is the whole point: `propertize' with a literal '(:foreground
;; "#888888") produces text that is correct under one theme and muddy
;; under the other, and there is no way to find such text later except
;; by grepping for hex digits.  A named face is greppable, is listed by
;; `M-x list-faces-display', and can be customised without editing
;; code.
;;
;; Defined here rather than in each consuming module so that a module
;; can be deleted without taking a face another module uses with it.
;; Consumers reference them by symbol, which is harmless when this file
;; is absent -- an undefined face renders as `default' rather than
;; signalling.

(defgroup my/appearance nil
  "Faces and settings for the visual layer."
  :group 'faces)

(defface my/dashboard-title
  '((t :inherit (bold variable-pitch) :height 1.3))
  "Face for the dashboard's own title line."
  :group 'my/appearance)

(defface my/dashboard-section
  '((t :inherit (bold) :underline t))
  "Face for dashboard section headers."
  :group 'my/appearance)

(defface my/dashboard-note
  '((t :inherit link :underline nil))
  "Face for a clickable note entry in the dashboard.
Inherits `link' because that is what it is -- clicking opens the note."
  :group 'my/appearance)

(defface my/dashboard-tag-button
  '((t :inherit (bold link) :underline nil))
  "Face for a clickable tag entry in the dashboard."
  :group 'my/appearance)

(defface my/dashboard-tags
  '((t :inherit shadow))
  "Face for the inline :tag:list: shown after a note title."
  :group 'my/appearance)

(defface my/dashboard-hint
  '((t :inherit shadow))
  "Face for dashboard hints, timestamps and truncation notices."
  :group 'my/appearance)

;; ============================================================
;; SPACIOUS-PADDING: the single biggest visual change here
;; ============================================================
;; Emacs draws text hard against the frame edge, stacks windows with a
;; one-pixel divider, and fills the mode line as a solid bar.  Padding
;; is the difference between "a terminal application" and "an
;; application", and none of it is available as a plain setting --
;; internal border, divider widths, fringe widths and a boxed mode line
;; have to be set together and re-set after every theme load.  That is
;; what this package does; the Modus manual points at it in preference
;; to hand-rolling the mode-line `:box' trick.
;;
;; INTERACTION WITH 10-visual-fill.el -- CHECK THIS ONE
;; ----------------------------------------------------
;; visual-fill-column centres note text by widening the window margins,
;; and with `visual-fill-column-fringes-outside-margins' nil it puts
;; the fringes between the margin and the text.  The fringe widths set
;; here therefore add to the gap on both sides of a centred column.
;; The values below are conservative for that reason.  If notes read as
;; too narrow after this change, lower the two fringe widths before
;; touching `my-fill-column'.

(use-package spacious-padding
  :ensure t
  :config
  (setq spacious-padding-widths
        '( :internal-border-width 16
           :header-line-width 4
           :mode-line-width 4
           :tab-width 4
           :right-divider-width 20
           :scroll-bar-width 8
           :fringe-width 10))

  ;; Mode line as a hairline overline instead of a filled bar.
  ;;
  ;; `t', not the face plist.  The plist form names
  ;; `spacious-padding-line-active' and `-line-inactive' and takes
  ;; their foregrounds, which works while the Modus and Ef themes are
  ;; in play and produces `unspecified' under themes that leave those
  ;; foregrounds unset -- several doom-themes and the built-in ones.
  ;; An `unspecified' colour inside a `:box' is an invalid face
  ;; specification, and the error aborts `enable-theme' partway, which
  ;; is why such a theme applied to some faces and not others.  `t'
  ;; lets the package derive the colour itself and has no such gap.
  ;;
  ;; `my/theme-load' (09-theme.el) additionally disables this mode
  ;; across a theme load, so nothing here computes from a palette that
  ;; is only half in place.
  (setq spacious-padding-subtle-mode-line t)

  (spacious-padding-mode 1))

(defun my/toggle-spacious-padding ()
  "Toggle frame and window padding.
Useful when screen space is tight -- on a laptop panel, or with four
windows open -- since the padding costs real estate that a centred
text column then has to give back."
  (interactive)
  (if (bound-and-true-p spacious-padding-mode)
      (progn (spacious-padding-mode -1) (message "Padding off"))
    (spacious-padding-mode 1)
    (message "Padding on")))

;; ============================================================
;; LIN: current-line highlight that knows what kind of buffer it is in
;; ============================================================
;; 02-editing.el enables `global-hl-line-mode', so every buffer has a
;; current-line highlight of the same intensity.  Those are two
;; different jobs: in a note the highlight is a reminder of where point
;; is and should barely register, while in the review queue
;; (25-inbox-review.el), the maintenance reports (26-maintenance.el),
;; the Readwise lists (24-readwise.el) and the dashboards the line IS
;; the selection and has to be unambiguous.
;;
;; lin remaps the highlight face buffer-locally in the modes listed
;; below and leaves prose buffers to `hl-line' as configured by the
;; theme.  `lin-face' is a palette-aware face from the Modus themes'
;; supported set, so it follows the light/dark toggle.

(use-package lin
  :ensure t
  :config
  (setq lin-face 'lin-cyan)
  (setq lin-mode-hooks
        '(dired-mode-hook
          git-rebase-mode-hook
          grep-mode-hook
          ibuffer-mode-hook
          log-view-mode-hook
          magit-log-mode-hook
          occur-mode-hook
          org-agenda-mode-hook
          tabulated-list-mode-hook))
  (lin-global-mode 1))

;; ============================================================
;; PULSAR: where did point just go
;; ============================================================
;; Navigation here is mostly jumps rather than scrolling -- a denote:
;; link, a backlink, a dashboard entry, a search hit -- and each one
;; lands point somewhere in a window that has just been redrawn.  A
;; brief pulse on the destination line answers "where am I now" without
;; leaving anything on screen afterwards.
;;
;; Emacs has no animation engine; this is a timer redrawing one line's
;; background a few times. That is the honest ceiling for motion here,
;; and it is why nothing in this module promises transitions.

(use-package pulsar
  :ensure t
  :config
  (setq pulsar-pulse t
        pulsar-delay 0.055
        pulsar-iterations 8
        pulsar-face 'pulsar-cyan
        pulsar-highlight-face 'pulsar-yellow)
  (pulsar-global-mode 1)

  ;; Denote and Org navigation, guarded: these hooks only exist once
  ;; the respective package has loaded, and this module must not
  ;; require either of them.
  (with-eval-after-load 'denote
    (add-hook 'denote-after-new-note-hook #'pulsar-pulse-line))
  (with-eval-after-load 'org
    (add-hook 'org-follow-link-hook #'pulsar-pulse-line)))

;; ============================================================
;; TEXT SCALING
;; ============================================================
;; Two scopes, deliberately.  `text-scale-adjust' resizes the current
;; buffer only, which is what a long reading session in one note wants.
;; `default-text-scale' resizes every buffer in every frame by changing
;; the height of the `default' face, which is what tired eyes at the
;; end of a day want.
;;
;; visual-fill-column recomputes margins from the scaled text size, so
;; a centred column stays centred at any zoom level.

(use-package default-text-scale
  :ensure t
  :config
  (default-text-scale-mode 1))

(defun my/text-scale-reset ()
  "Reset the current buffer's text scale to the default size."
  (interactive)
  (text-scale-set 0))

;; ============================================================
;; KEYBINDINGS
;; ============================================================
;; `C-c u' -- "UI" -- was free.  Theme keys live in 09-theme.el and
;; text-width keys in 10-visual-fill.el, each next to the code they
;; drive; this module only owns what it defines itself.
;;
;; The full prefix, wherever the pieces are defined:
;;   C-c u t  theme light/dark      C-c u f  base font size
;;   C-c u T  pick a theme          C-c u s  save text scale in note
;;   C-c u p  padding               C-c u w  text width
;;   C-c u + - 0   text scale, this buffer only
;;   <f4> <f5>     walk light / dark themes

(global-set-key (kbd "C-c u p") #'my/toggle-spacious-padding)
(global-set-key (kbd "C-c u +") #'text-scale-increase)
(global-set-key (kbd "C-c u -") #'text-scale-decrease)
(global-set-key (kbd "C-c u 0") #'my/text-scale-reset)

;; ============================================================
;; TRANSIENT MENU: View  (C-c n v)
;; ============================================================
;; Appended through `my/transient-append' (12-transient.el), which
;; skips rather than signals when the menu or the anchor is missing.
;; The anchor "e" is defined by 12-transient.el itself, not by another
;; feature module, so this append does not couple two optional modules
;; to each other.

(when (fboundp 'my/transient-append)
  ;; NOTE ON KEYS.  30-link-tooltips.el appends "T" to this same menu,
  ;; and `my/transient-append' skips an already-bound key silently -- so a collision here would produce a menu entry
  ;; that is simply absent, with nothing said about it.  "t" and "p"
  ;; were checked against the menu as 12-transient.el defines it and
  ;; against every other module that appends to it.
  ;;
  ;; Text scaling is deliberately not in this menu.  A transient
  ;; closes and reopens around each invocation, which is the wrong
  ;; shape for a command pressed repeatedly; `C-c u +' and `C-c u -'
  ;; repeat cleanly.
  (my/transient-append 'my/notes-view-menu "e"
                       '("t" "Theme light/dark" my/theme-toggle))
  ;; "y", not "T": 30-link-tooltips.el already owns "T" in this menu,
  ;; and an append onto a taken key is dropped without a word.
  (my/transient-append 'my/notes-view-menu "t"
                       '("y" "Pick a theme" my/theme-select))
  (my/transient-append 'my/notes-view-menu "y"
                       '("p" "Padding" my/toggle-spacious-padding))
  (my/transient-append 'my/notes-view-menu "p"
                       '("W" "Text width" my/text-width-adjust))
  (my/transient-append 'my/notes-view-menu "W"
                       '("S" "Font size" my/font-size-adjust)))

(provide '34-appearance)
;;; 34-appearance.el ends here
