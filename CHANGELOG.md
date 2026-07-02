# Emacs Configuration — Change Log & Architecture Notes

This document records significant refactoring sessions, commit by commit,
with rationale and lessons learned. Its purpose is to serve as a reference
before adding new code or modifying existing functionality — to avoid
introducing regressions, hook races, or dependency conflicts.

---

## Session 2026-07-02 — Hierarchical Notes Menu, Function Helper, and Transclusion

### Context

The flat notes transient had reached its practical limit: too many top-level
bindings, no scalable place for new integrations, and no local reference
document explaining what each command actually does. At the same time,
transclusion support was added for note composition and export workflows.

---

### G — `modules/12-transient.el` — Hierarchical `C-c n` menu

#### What changed

The notes menu was refactored from a flat transient into a hierarchical router
under `C-c n`, with dedicated submenus for:

- `c` Create / Capture
- `f` Find / Search
- `i` Insert
- `d` Document / File management
- `x` Export
- `v` View
- `t` Tools
- `l` Philosophy (appended dynamically)
- `h` Function Helper

This replaced the previous “one large menu” model with smaller task-oriented
submenus and made room for future integrations without overloading top-level
bindings.

#### Why

The old structure did not scale well. New commands were competing for a small
set of mnemonic letters, and related operations (create, search, export,
view, tools) were mixed together at one level. The new hierarchy makes the
mental model clearer: choose category first, then action.

---

### H — `function_helper.org` — local reference manual for custom commands

#### What changed

Added and then expanded `function_helper.org` as a human-readable reference
for custom commands, transient bindings, and workflow notes. Each documented
command or submenu is anchored with stable `CUSTOM_ID` values so code comments
and helper functions can link to exact sections.

The helper now documents:

- the hierarchical `C-c n` menu,
- create/find/insert/document/export/view/tools/philosophy branches,
- Zotero submenu,
- capture system behaviour,
- global keybindings.

#### Why

As the config grew, discoverability became a real usability problem. The helper
file serves as an internal manual that is readable both in Emacs and as plain
text, while still supporting stable intra-file linking via `CUSTOM_ID`.

---

### I — `modules/20-transclusion.el` — Obsidian-style transclusion for notes

#### What changed

Added a dedicated transclusion module and integrated it into
`C-c n i t` (`Insert` → `Transclusion`).

The main entry point is `my/denote-transclude-insert`, which now supports:

1. Selecting source type:
   - `Denote note`
   - `Any file on disk`

2. Selecting transclusion target:
   - whole note / file
   - heading
   - paragraph

3. Automatic anchor creation when needed:
   - headings get `CUSTOM_ID`
   - paragraphs get `<<target>>` anchors

4. Dual insertion strategy:
   - `#+transclude:` for live in-buffer rendering via `org-transclusion`
   - `#+INCLUDE:` for export-time inclusion in PDF / HTML / other Org exports

The transclusion submenu also exposes operational commands for managing
existing transclusions:

- add all in buffer,
- refresh at point,
- remove at point,
- toggle mode,
- open source,
- move to source,
- live-sync start / exit,
- promote / demote subtree.

#### Why

Plain note links solve navigation, but not composition. Transclusion adds a
reusable-content workflow: larger notes can be built from canonical source
notes or fragments without copy-pasting content.

#### Important risks

This module intentionally writes to source files when anchors are missing.

- Heading mode may add `CUSTOM_ID` to the source heading and save the file.
- Paragraph mode may append a `<<target>>` anchor to the chosen paragraph and
  save the file.

This is powerful, but it means transclusion is not a read-only operation on
first use. Users should commit or otherwise snapshot important notes before
bulk use.

Paragraph selection is implemented with a simple line-based heuristic rather
than a full Org parser. In practice this is sufficient for normal prose
paragraphs, but lists, tables, and source blocks may be grouped less precisely
than headings.

---

### J — Integration lessons

#### L9 — Dynamic transient extensions must target stable suffixes

Modules that append entries into another transient (`transient-append-suffix`)
must target suffix keys that are guaranteed to exist in the current menu
version. After restructuring a menu, all extension modules must be checked for
stale insertion points.

#### L10 — Documentation must track the _final_ menu, not intermediate drafts

When a feature evolves across several iterations, `function_helper.org` should
document only the commands that actually remain in the code. Draft commands,
removed submenu items, and speculative package APIs should be deleted promptly
to avoid misleading future edits.

#### L11 — Transclusion anchors are part of the source-of-truth model

If a workflow depends on stable exportable references, generated anchors
(`CUSTOM_ID`, `<<target>>`) should be treated as intentional source metadata,
not temporary editor artefacts. Their presence in files is a design choice,
not accidental noise.

## Session 2026-06-30 — Performance & Warning Cleanup (Session 2)

### Context

After the Quality Control pass (Session 1), three remaining issues were
addressed: runaway desktop file growth causing slow startups, a spurious
face warning on every startup, and a fragile load-order dependency for
`custom.el`.

---

### E — `modules/01-ui.el` — Desktop buffer trimming

**Commits:** `6d5e829`, `59da4c4`

#### What changed

Added `my/desktop-trim-buffers`, a function registered on
`desktop-save-hook`. Before every desktop save it:

1. Collects all file-visiting buffers eligible for desktop-save
   (respecting `desktop-modes-not-to-save` and `desktop-files-not-to-save`).
2. Sorts them by file mtime — newest first.
3. Kills every buffer beyond position 100 in that list.

This prevents the desktop file from growing indefinitely. With 400+
buffers previously persisted, startup was spending significant time
just reading and locking the desktop file. After the fix: 2 buffers
restored on first clean run, startup time stable at ~2.3 s.

The trimming integrates into the existing 3-layer strategy:

| Layer | Mechanism                              | Effect                                        |
| ----- | -------------------------------------- | --------------------------------------------- |
| Trim  | `desktop-save-hook` → kill old buffers | Desktop file stays ≤ 100 entries              |
| Eager | `desktop-restore-eager = 10`           | UI appears after ~2 s regardless of list size |
| Lazy  | Background idle restore                | Remaining buffers load without blocking       |

Also removed a duplicate `custom-set-faces` block for `org-quote`,
`org-block`, `org-block-begin-line`, `org-block-end-line` that had
been left in `01-ui.el` — `custom.el` is the authoritative source
for all Customize-managed face definitions (see F below).

#### How to reset on first use

After `git pull`, delete the old oversized desktop file so the trim
takes effect immediately:

```bash
rm ~/.emacs.d/desktop/desktop
emacs
```

---

### F — `init.el` + `modules/03b-fonts.el` — `org-quote` face warning

**Commits:** `0f205c5`, `7a815e3`

#### What changed

**Root cause:** `03b-fonts.el` called:

```elisp
(set-face-attribute 'org-quote nil
                    :family "Georgia"
                    :slant 'italic
                    :height 1.1
                    :foreground nil)   ; ← invalid
```

`nil` is not a valid face attribute value when passed explicitly to
`set-face-attribute`. Emacs requires `'unspecified` to mean "do not
set this attribute; inherit from parent". This produced on every
startup:

```
Warning: setting attribute ':foreground' of face 'org-quote':
nil value is invalid, use 'unspecified' instead. [2 times]
```

The `[2 times]` came from two separate `with-eval-after-load 'org`
blocks in the same file, both firing when org first loaded.

**Fixes applied:**

1. `03b-fonts.el`: changed `:foreground nil` → `:foreground 'unspecified`;
   merged the two `with-eval-after-load 'org` blocks into one.

2. `init.el`: moved `(load custom-file)` to the **top** of init, before
   all modules. Previously `custom.el` loaded last, meaning org's
   built-in default face (which has no `:foreground`) was applied first
   and only overridden after all modules had loaded. Loading `custom.el`
   early ensures Customize face definitions are in place before any
   package triggers org to load.

#### Rule added (see L8 below)

Never pass `nil` as an explicit face attribute value. Use `'unspecified`
when you want an attribute to be inherited rather than set.

---

## Session 2026-06-30 — Quality Control Pass (Paczki B1, C, D)

### Context

A systematic audit of the configuration revealed several categories of
problems: security issues (hardcoded usernames), dead code (packages
referenced but not installed), and architectural fragmentation (the same
concern handled in multiple files, causing load-order races and duplicated
`setq-default` calls).

---

### B1 — `modules/03-spelling.el`

**Commit:** `b3dd506`

#### What changed

1. **SEC-5: Removed hardcoded username `marcin`** from the hunspell
   dictionary path. The path was previously:

   ```elisp
   "/etc/profiles/per-user/marcin/share/hunspell"
   ```

   Replaced with a runtime-computed path using `(user-login-name)`:

   ```elisp
   (let* ((login     (user-login-name))
          (nix-path  (format "/etc/profiles/per-user/%s/share/hunspell" login))
          (fallback  "/usr/share/hunspell")
          (dict-path (if (file-directory-p nix-path) nix-path fallback)))
     ...)
   ```

2. **QC-5: Removed `flyspell-correct-ivy`** block entirely. The package
   was referenced but never installed (`ivy` is not part of this config —
   `vertico` is used instead). Changed the interface to the
   `completing-read` backend, which `vertico` intercepts automatically:
   ```elisp
   (setq flyspell-correct-interface #'flyspell-correct-completing-read)
   ```

#### Why

- A hardcoded username in a public repository is a minor but unnecessary
  information leak and breaks portability to any other machine or user.
- `flyspell-correct-ivy` was causing a silent load failure: `ivy` is not
  installed, so the `use-package` block either errored or loaded nothing.
  The `completing-read` interface is the correct choice for a
  `vertico`-based setup and requires no extra package.

---

### C+D — `modules/01-ui.el`, `modules/04-denote.el`, `modules/10-visual-fill.el`

**Commits:** `e947548`, `6c2a87d`, `cc43e7d`

#### What changed

Visual-fill-column logic was previously fragmented across three files:

| File                | What it did                                                                                                                                                     |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `01-ui.el`          | `use-package visual-fill-column` with `setq-default` calls; `display-fill-column-indicator-mode 1` in org-mode hook                                             |
| `04-denote.el`      | `my/denote-visual-wrap-setup`: per-note width logic (`:docu:` → 100, others → 80); `my/toggle-visual-fill-column-center`                                        |
| `10-visual-fill.el` | `setq-default visual-fill-column-center-text t` (conflicting with `01-ui.el`); hooks on `org-mode` and `text-mode`; disabled the indicator line in its own hook |

This caused two concrete problems:

**Hook race:** `01-ui.el` enabled `display-fill-column-indicator-mode`
in `org-mode-hook`. `10-visual-fill.el` disabled it inside
`visual-fill-column-mode-hook`. Whether the indicator line appeared or
not depended on hook execution order, which is not guaranteed to be
stable.

**Conflicting `setq-default`:** `01-ui.el` set `visual-fill-column-center-text`
to `nil`; `10-visual-fill.el` set it to `t`. Whichever loaded last won.
This made the global default non-deterministic.

#### New architecture

`10-visual-fill.el` is now the **single source of truth** for all
visual-fill-column behaviour. The decision tree is:

```
buffer has a file path AND is org-mode or text-mode?
  NO  -> do nothing  (code files: .el, .py, .nix — full width)
  YES -> is the path inside ~/notes/ ?
          NO  -> visual-fill-column-mode -1
                 (intentional: full-width is a visual signal
                  that you are editing a file outside the notes tree)
          YES -> does #+filetags contain :docu: ?
                   YES -> width=100, center=t
                   NO  -> width=80,  center=t
                 activate visual-fill-column-mode + visual-line-mode
                 disable display-fill-column-indicator-mode
```

`my/toggle-visual-fill-column-center` (used by transient menu `C-c n y`)
was moved from `04-denote.el` to `10-visual-fill.el` to keep all
related functions in one place.

`01-ui.el` org-mode hook now only sets `visual-line-mode` and
`fill-column` — nothing that touches column indicators or centering.

`04-denote.el` contains no visual-fill logic whatsoever.

---

## Lessons Learned

### L1 — One concern, one file

Before writing a `setq`, `setq-default`, `add-hook`, or `use-package`
for a given feature (e.g. visual wrapping, spelling, completion),
**search the entire `modules/` directory first** to see if that feature
is already configured elsewhere.

If it is:

- Extend the existing block in its owning file, or
- Remove the old code and replace it entirely.

Never split the same concern across two files. Two files touching the
same variables or the same hooks will eventually fight each other.

### L2 — `setq-default` is global state

`setq-default` sets the buffer-local variable's default for all future
buffers. Any subsequent `setq-default` for the same variable in a later
file silently wins. There is no warning, no error. This is the most
common source of "why does this setting sometimes not apply?" bugs.

Rule: **each variable should have exactly one `setq-default` call in the
entire config**, in the file that owns that concern.

### L3 — Hook order is not guaranteed

Hooks in the same hook list run in the order they were added, but the
order modules are loaded controls when hooks are registered. If two
modules add conflicting hooks to the same hook variable (e.g. one enables
a mode, another disables it), the final state depends on load order.

Rule: **never enable something in one module and disable it in another
via the same hook**. Instead, decide once (in the owning module) what
the final state should be, and do it there.

### L4 — Test symbol existence before using it

Calling a function that may not be defined yet (because its package
hasn't loaded) causes silent failures or hard errors. Always guard with:

```elisp
(when (fboundp 'some-function) ...)
(when (boundp 'some-variable) ...)
(bound-and-true-p some-mode-variable)
```

This applies especially to toggle functions in transient menus, which
can be called interactively before the owning package has initialised.

### L5 — Hardcoded paths and usernames belong in `00-core.el`

Any value that is machine-specific (paths, usernames, locale strings)
should be defined as a variable in `00-core.el`, not inlined in the
module that uses it. This keeps modules portable and makes it obvious
where to change system-specific values when moving to a new machine.

### L6 — Check package availability before configuring it

Before adding a `use-package` block for package `X`, verify that `X` is
listed in `packages.nix` (or the equivalent package manager manifest).
A `use-package` block for a package that is not installed will either
silently do nothing (`:ensure nil`) or log a warning. Neither is
obvious. Dead configuration code accumulates and confuses future edits.

### L7 — Document the _why_, not just the _what_

Comments that say `(visual-fill-column-mode -1) ; disable centering` are
less useful than comments that say _why_ centering is disabled here and
not elsewhere. When the reason is architectural ("this file owns this
concern"), say so explicitly. It prevents future editors (including
yourself six months later) from "fixing" working code because the
rationale was invisible.

### L8 — Use `'unspecified` not `nil` for face attributes

When calling `set-face-attribute` and you want an attribute to be
inherited from the parent face rather than explicitly set, always use
`'unspecified` — never `nil`. Passing `nil` explicitly is invalid and
generates a warning on every startup. `nil` as a _default_ in
`defface` is different — there it means "attribute not specified in
this spec" — but in a direct `set-face-attribute` call the value is
always passed through and `nil` is rejected.

```elisp
;; Wrong — generates warning
(set-face-attribute 'org-quote nil :foreground nil)

;; Correct — inherits foreground from parent face
(set-face-attribute 'org-quote nil :foreground 'unspecified)
```

---

## File Ownership Map (current)

| Concern                                             | Owning file              |
| --------------------------------------------------- | ------------------------ |
| Basic UI, completion, session, mode-line            | `01-ui.el`               |
| Editing behaviour, keybindings                      | `02-editing.el`          |
| Spell checking (ispell, flyspell, flyspell-correct) | `03-spelling.el`         |
| Fonts and typography                                | `03b-fonts.el`           |
| Denote core, silo config, org-mode settings         | `04-denote.el`           |
| Notes functions (journal, essay, capture)           | `05-notes.el`            |
| Org-capture templates                               | `06-capture.el`          |
| Git (Magit)                                         | `07-git.el`              |
| Global keybindings                                  | `08-keybindings.el`      |
| Theme                                               | `09-theme.el`            |
| **Visual-fill-column, centering, line wrapping**    | **`10-visual-fill.el`**  |
| Org appearance (faces, prettify, headings)          | `11-org-appearance.el`   |
| Transient menus                                     | `12-transient.el`        |
| Centered writing mode (cursor recentering)          | `13-centered-writing.el` |
| Typing analytics                                    | `14-typing-analytics.el` |
| Workspace / dashboard                               | `15-workspace.el`        |
| Org export (PDF, HTML, LaTeX)                       | `16-org-export.el`       |
| Bibliography (Citar, BibTeX)                        | `17-bibliography.el`     |
| Zotero transient menu                               | `18-zotero-transient.el` |
| **Custom file load order, startup perf**            | **`init.el`**            |

**Before adding a new feature:** find the owning file in this table and
add the code there. If no file owns the concern yet, create a new
numbered file and add a row to this table.
