;;; 08-keybindings.el --- Keybindings reference -*- lexical-binding: t; -*-
;;; Commentary:
;; This file does NOT define most keybindings itself — they live next to
;; the commands they trigger, scattered across modules (that's normal
;; Emacs config style: 07-git.el binds its own magit keys, 01-ui.el binds
;; its own tab-bar/desktop keys, 12-transient.el binds C-c n, etc.).
;;
;; What THIS file provides is `my/show-keybindings-help' (C-c h k): a
;; single accurate reference to every custom binding, including the
;; contents of the transient menus, so you don't have to go hunting
;; through modules to remember a key.
;;
;; TIP: you don't have to memorize any of this. `which-key' is enabled
;; (02-editing.el) — press C-c and wait ~0.3s, and a popup lists every
;; key that can follow. Same inside any transient menu: press C-c n and
;; wait, or press a prefix key and wait, to see the next level.
;;
;; AUDIT NOTE (this revision): the previous version of this file/help
;; text had drifted from the actual bindings — most notably an entire
;; fictional "C-c F ..." spelling section that was never bound anywhere,
;; several Magit and C-c w/C-c a/C-c x bindings missing entirely, and no
;; mention of the transient submenu contents. This revision was built by
;; grepping every module for `global-set-key'/`define-key'/`:bind'/
;; `transient-define-prefix' rather than by memory — if you add or
;; change a binding, re-run that audit (or ask for it) rather than
;; hand-editing this text out of memory, since that's exactly how it
;; drifted last time.
;;
;; Keybinding philosophy:
;; - C-c letter = user commands (your personal functions)
;; - C-c C-letter = mode-specific (org-mode, etc.)
;; - Keep frequently used commands short
;; - Group related commands with same prefix

;;; Code:

;; ============================================================
;; NOTE OPERATIONS - TRANSIENT MENU (C-c n)
;; ============================================================
;;
;; C-c n - Opens full notes menu with all functions
;; See modules/12-transient.el for menu structure, and the help buffer
;; below (or function_helper.org) for the full submenu contents.

;; ============================================================
;; DENOTE QUICK ACCESS (C-c d ...)
;; ============================================================
;; For frequently used Denote functions - faster than opening menu

(global-set-key (kbd "C-c d f") 'denote-open-or-create)      ; Find/create note
(global-set-key (kbd "C-c d l") 'denote-link)                ; Insert link
(global-set-key (kbd "C-c d b") 'denote-backlinks)           ; Show backlinks
(global-set-key (kbd "C-c d r") 'denote-rename-file)         ; Rename note
;; Same command the transient menu uses (C-c n d k), not Denote's raw
;; one: `my/denote-keywords-edit' (05-notes.el) adds the keyword prompt
;; behaviour shared by every tag prompt in this configuration.
(global-set-key (kbd "C-c d t") 'my/denote-keywords-edit)     ; Modify keywords

;; ============================================================
;; PDF EXPORT (C-c p)
;; ============================================================
;; Export current Org buffer to PDF -> ~/notes/pdf/
;; Defined in modules/16-org-export.el

(global-set-key (kbd "C-c p") #'my/org-export-to-pdf)

;; ============================================================
;; ORG-CAPTURE (already defined in 06-capture.el)
;; ============================================================
;; C-c c = org-capture menu

;; ============================================================
;; GIT / MAGIT (already defined in 07-git.el)
;; ============================================================
;; C-x g   = magit-status (global Magit default)
;; C-x M-g = magit-dispatch (global Magit default)
;; C-c g s = magit-status
;; C-c g l = magit-log-current
;; C-c g b = magit-blame
;; C-c v s = notes git status (my/notes-git-status)
;; C-c v c = commit notes now (my/commit-notes-now)
;; C-c v S = config git status (my/config-git-status)
;; C-c v C = commit config now (my/commit-config-now)
;; C-c v d = diff current file (magit-diff-buffer-file)
;; C-c v h = history current file (magit-log-buffer-file)

;; ============================================================
;; DESKTOP/SESSION (already defined in 01-ui.el)
;; ============================================================
;; C-c d s = save desktop now
;; C-c d k = pin/unpin current buffer against desktop trim (📌 in mode line)
;; C-c d p = list what survives the next desktop save (*Desktop Survival*)

;; ============================================================
;; TAB-BAR (already defined in 01-ui.el)
;; ============================================================
;; C-c t n = new tab
;; C-c t c = close tab
;; C-c t o = switch tab
;; C-c t r = rename tab

;; ============================================================
;; WORKSPACE / DASHBOARDS (already defined in 15-workspace.el)
;; ============================================================
;; C-c w d = open notes dashboard
;; C-c w x = notes explore (tag stats)
;; C-c w r = random note
;; Inside the *Notes Dashboard* buffers only: g = refresh, q = close

;; ============================================================
;; TYPING ANALYTICS (already defined in 14-typing-analytics.el)
;; ============================================================
;; C-c a k = keyfreq-show (command frequency stats)
;; C-c a s = keylog-status
;; C-c a t = keylog-disable (temporarily)
;; C-c a T = keylog-enable

;; ============================================================
;; ZETTELKASTEN / FOLGEZETTEL (already defined in 22-zettelkasten.el)
;; ============================================================
;; C-c n z = my/zettelkasten-menu (transient), appended to the main
;; notes menu the same way 19-philosophy-notes.el appends C-c n l.
;; All commands are silo-scoped to ~/notes/pks/ — sequences never
;; land on journal or docu notes.  See the menu tree below.

;; ============================================================
;; READWISE (already defined in 24-readwise.el)
;; ============================================================
;; C-c r s = sync highlights from Readwise (incremental)
;; C-c r r = review books with unprocessed quotes
;; C-c r o = open the import folder (~/Downloads/readwise) in Dired
;; Also under the notes menu: C-c n t r

;; ============================================================
;; ZOTERO / BIBLIOGRAPHY (already defined in 18-zotero-transient.el)
;; ============================================================
;; C-c x = my/zotero-menu (transient) — also reachable via C-c n t z

;; ============================================================
;; SPELLING (already defined in 02-editing.el / 03-spelling.el)
;; ============================================================
;; C-; (in a buffer with flyspell on) = flyspell-correct-wrapper
;; C-c f b = my/spell-check-visible (check visible portion of buffer)
;; Everything else (correct previous, add to dict, check full buffer,
;; toggle) lives in the transient menu only: C-c n t (Tools) or the
;; quick top-level C-c n s / C-c n a — there is no "C-c F ..." prefix,
;; despite what an earlier version of this file claimed.

;; ============================================================
;; REBOUND DEFAULT KEYS (already defined in 02-editing.el)
;; ============================================================
;; C-a = mark-whole-buffer (NOT move-beginning-of-line!)
;; C-f = isearch-forward   (NOT forward-char!)
;; C-s = save-buffer       (matches most other editors)
;; C-z = undo              (NOT suspend-frame!)
;; C-x C-b = ibuffer (instead of plain list-buffers)
;; C-x u = vundo (visual undo tree), NOT the default plain undo
;; C-S-z = undo-redo (redo that does not itself become undoable)
;; M-Q = my/unfill-region (join a paragraph back into one line)

;; ============================================================
;; HELPER KEYBINDINGS
;; ============================================================

;; Quick config access
(global-set-key (kbd "C-c o i") 'open-init-el-bottom-split)

;; Evaluate elisp
(global-set-key (kbd "C-c e b") 'eval-buffer)
(global-set-key (kbd "C-c e r") 'eval-region)

;; ============================================================
;; DOCUMENTATION STRING
;; ============================================================

(defun my/show-keybindings-help ()
  "Show a summary of every custom keybinding, including transient menus."
  (interactive)
  (let ((help-text
         "Keybindings Summary
===================
(Tip: press C-c and wait ~0.3s -- which-key shows this live, always
up to date. This buffer is a hand-maintained snapshot, see AUDIT NOTE
in 08-keybindings.el for how it's kept in sync.)

GLOBAL, OUTSIDE ANY MENU
-------------------------

Notes Menu:
  C-c n   - Open notes transient menu (see tree below)

Denote Quick Access:
  C-c d f - Find/create note
  C-c d l - Insert link
  C-c d b - Show backlinks
  C-c d r - Rename file
  C-c d t - Modify keywords
  C-c d s - Save desktop
  C-c d k - Pin/unpin buffer against desktop trim (pin shows in mode line)
  C-c d p - List what survives the next desktop save

PDF Export:
  C-c p   - Export current Org file to PDF -> ~/notes/pdf/

Capture:
  C-c c   - Org-capture menu

Git / Magit:
  C-x g   - Magit status
  C-x M-g - Magit dispatch
  C-c g s - Magit status
  C-c g l - Magit log (current file)
  C-c g b - Magit blame
  C-c v s - Notes repo status
  C-c v c - Commit notes now
  C-c v S - Config repo status
  C-c v C - Commit config now
  C-c v d - Diff current file
  C-c v h - History of current file

Tabs:
  C-c t n - New tab
  C-c t c - Close tab
  C-c t o - Switch tab
  C-c t r - Rename tab

Workspace / Dashboards:
  C-c w d - Open notes dashboard
  C-c w x - Tag stats (notes explore)
  C-c w r - Random note
  (inside *Notes Dashboard*: g = refresh, q = close)

Typing Analytics:
  C-c a k - Command frequency stats (keyfreq)
  C-c a s - Keylog status
  C-c a t - Disable keylog temporarily
  C-c a T - Re-enable keylog

Bibliography:
  C-c x   - Zotero/bib menu (same as C-c n t z)

Readwise:
  C-c r s - Sync highlights (incremental; C-u for everything)
  C-c r r - Review books with unprocessed quotes
  C-c r o - Open import folder in Dired
  (menu: C-c n t r)

Inbox (notes migrated from Obsidian):
  C-c X   - Extract region/subtree/paragraph to a new note
            (only in ~/notes/inbox files; C-c x stays Zotero)
  (menu: C-c n t i -- review list, extract, open folders)

Spelling:
  C-;     - Correct word at point (needs flyspell on)
  C-c s   - Correct previous misspelling  (also C-c n s, keeps menu open)
  C-c S   - Add previous word to dict     (also C-c n a, keeps menu open)
  C-c f b - Check visible portion of buffer
  (check-full-buffer / toggle: only via the C-c n menu, see below --
   there is no C-c F prefix)

Menus and modes (C-c m ...):
  C-c m c - Create submenu directly (skips C-c n)
  C-c m w - Toggle centred writing mode (same as C-c n v w)
  C-c m k - Modify keywords (duplicate of C-c d t)

Rebound defaults (not the usual Emacs bindings!):
  C-a     - Select all      (mark-whole-buffer)
  C-f     - isearch-forward (NOT move-forward-char)
  C-s     - save-buffer
  C-z     - undo
  C-x C-b - ibuffer
  C-x u   - Visual undo tree (vundo)
  C-S-z   - Redo (undo-redo)
  M-Q     - Unfill (join) region

Other:
  C-c o i - Open init.el
  C-c e b - Eval buffer
  C-c e r - Eval region
  C-c h k - Show this help

C-c n -- NOTES TRANSIENT MENU TREE
-----------------------------------
  c  Create ->
       n  New note        j  Journal today     J  Journal (date)
       e  Essay            L  Linked note
       i  Ideas capture    c  Capture menu      m  Promote to note
  f  Find ->
       f  Find file        g  Grep notes        b  Backlinks
       d  Dashboard         t  Tag stats         r  Random note
       h  History ->  (t/j = this-day-in-history, m/M = same-day-every-month)
  i  Insert ->
       l  Insert link       L  Linked note
       h  Time (HH:MM)      d  Date (YYYY-MM-DD)
       w  Well-being
       t  Transclusion ->
            a  Add (wizard)    A  Add all in buffer
            g  Refresh         r  Remove          T  Toggle mode
            o  Open source     O  Move to source
            e  Live-sync edit  E  Exit live-sync
            P  Promote subtree D  Demote subtree
  d  Document ->
       r  Rename file       k  Add keywords      d  Delete note
       c  Change silo (move note between journal/pks/docu)
  x  Export ->
       p  Export to PDF
       P  Batch PDF - ANY keyword
       Q  Batch PDF - ALL keywords
  v  View ->
       c  Center text       w  Writing mode
       i  Indent headings   e  Emphasis markers
       f  Detach buffer to its own frame
       F  Detach whole tab to its own frame
  t  Tools ->
       z  Zotero/Bib ->  (same submenu as C-c x, see below)
       r  Readwise ->  s Sync (incremental)  S Sync everything
                       r Review books        o Open import folder
          In *Readwise Books*: RET/mouse open, S sort, / filter,
                               C-/ clear filter, g rebuild
          In *Readwise Quotes*: RET note, o note+open, z zettel,
                                a add to existing, g rebuild, q back
       s  Correct previous (transient: stays open)
       a  Add to dict       (transient: stays open)
       S  Check visible     b  Check full buffer   T  Toggle spellcheck
  l  Philosophy ->
       l  Literature        p  Concept            m  Thinker
       b  Problem           i  Map / MOC
  z  Zettelkasten ->  (Folgezettel sequences, pks silo only)
       n  New thread (parent)     c  Child of current
       C  Child of chosen...      s  Sibling of current
       f  Find relative...        j/k  Next/previous sibling
       d  Whole tree (Dired)      p  Filter by prefix...
       P  Prefix + depth...
       l  Link to sequence note   r  Reparent current
       a  Adopt plain note into ZK
       (C-u does NOT work here: transient consumes it, hence p and P)
  s  Correct previous  (top-level shortcut, same as t s)
  a  Add to dict        (top-level shortcut, same as t a)
  h  Function Help (opens function_helper.org in a new tab)
  q  Quit

C-c x -- ZOTERO / BIBLIOGRAPHY MENU  (same as C-c n t z)
---------------------------------------------------------
  n  New note from reference     o  Open existing bib note
  f  Open PDF for this note      e  Open BibTeX entry
  u  Open URL / DOI              i  Insert citation [cite:@key]
  R  Insert full bibliography    S  Insert short reference
  q  Quit

NUPHY AIR75 V2 -- CAPS LOCK LAYER (layer 4, macros M0-M5)
---------------------------------------------------------
Hold Caps Lock and press one key. Each is a firmware macro that types
one of the chords above -- nothing here is Emacs-side, so these do
nothing on the ThinkPad's built-in keyboard.

  M  Create submenu      (C-c m c)   F  Find/create note   (C-c d f)
  S  Correct previous    (C-c s)     A  Add to dict        (C-c S)
  W  Toggle writeroom    (C-c m w)   L  Insert link        (C-c d l)

  Caps Lock  - holds layer 4, does NOT type capitals (use both Shifts)
  Left Ctrl  - an ordinary Control key, unchanged

The macros are stored in the keyboard's EEPROM, not in this repo, and
cannot be read back from Emacs -- this table is the only record.
Reset the keyboard to factory state with Fn + [.
On NixOS the raw-HID access needed by usevia.app comes from
modules/system/hardware/keyboard-qmk.nix in the nixos repo.

Full descriptions of every command: C-c n h, or
~/.emacs.d/function_helper.org
"))
    (with-output-to-temp-buffer "*Keybindings Help*"
      (princ help-text))))

(global-set-key (kbd "C-c h k") 'my/show-keybindings-help)

;; ============================================================
;; DIRECT BINDINGS FOR MENU-ONLY COMMANDS
;; ============================================================
;; Four of these commands previously existed only as suffixes inside a
;; transient prefix, so the only way to reach them was to open a menu
;; first. keyfreq (C-c a k) showed `my/spell-correct-previous' as the
;; second most-invoked command in the whole configuration (1305 calls)
;; with no binding of its own, and `my/spell-add-previous-to-dict'
;; fourth (285) in the same situation — which is what prompted this.
;;
;; The two spelling ones matter for a second reason: their entries in
;; `my/notes-menu' carry :transient t, so the menu stays open after the
;; command runs and has to be dismissed with q. Reaching them directly
;; skips that entirely — visible in keyfreq as `transient-quit-one'
;; (1257 calls), a large part of which was that dismissal.
;;
;; These are ordinary bindings meant to be typed by hand. They are also
;; the targets the NuPhy Air75 V2 macro keys send (see the KEYBOARD
;; LAYER section in the help text below) — the keyboard needs a stable
;; chord to aim at, but nothing here depends on that keyboard being
;; attached, and everything works the same from the ThinkPad's built-in
;; keyboard.
;;
;; Namespace: C-c s / C-c S are short because they are the most used.
;; C-c m is a small grab-bag prefix ("menus and modes") for the rest.

(global-set-key (kbd "C-c s") 'my/spell-correct-previous)   ; Correct previous word
(global-set-key (kbd "C-c S") 'my/spell-add-previous-to-dict) ; Add previous to dict
(global-set-key (kbd "C-c m w") 'my/toggle-writeroom)       ; Centred writing mode
(global-set-key (kbd "C-c m c") 'my/notes-create-menu)      ; Create submenu directly

;; Deliberate duplicate of C-c d t above: same command, reachable under
;; both prefixes. C-c d t stays because it fits the Denote group; C-c m k
;; exists so the keyboard's keyword macro sits in one namespace with the
;; other macro targets. Change or drop either without touching the other.
(global-set-key (kbd "C-c m k") 'my/denote-keywords-edit)   ; Modify keywords

(provide '08-keybindings)
;;; 08-keybindings.el ends here
