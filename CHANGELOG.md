# Emacs Configuration — Change Log & Architecture Notes

This document records significant refactoring sessions, commit by commit,
with rationale and lessons learned. Its purpose is to serve as a reference
before adding new code or modifying existing functionality — to avoid
introducing regressions, hook races, or dependency conflicts.

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

| File | What it did |
|---|---|
| `01-ui.el` | `use-package visual-fill-column` with `setq-default` calls; `display-fill-column-indicator-mode 1` in org-mode hook |
| `04-denote.el` | `my/denote-visual-wrap-setup`: per-note width logic (`:docu:` → 100, others → 80); `my/toggle-visual-fill-column-center` |
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

### L7 — Document the *why*, not just the *what*

Comments that say `(visual-fill-column-mode -1) ; disable centering` are
less useful than comments that say *why* centering is disabled here and
not elsewhere. When the reason is architectural ("this file owns this
concern"), say so explicitly. It prevents future editors (including
yourself six months later) from "fixing" working code because the
rationale was invisible.

---

## File Ownership Map (current)

| Concern | Owning file |
|---|---|
| Basic UI, completion, session, mode-line | `01-ui.el` |
| Editing behaviour, keybindings | `02-editing.el` |
| Spell checking (ispell, flyspell, flyspell-correct) | `03-spelling.el` |
| Fonts and typography | `03b-fonts.el` |
| Denote core, silo config, org-mode settings | `04-denote.el` |
| Notes functions (journal, essay, capture) | `05-notes.el` |
| Org-capture templates | `06-capture.el` |
| Git (Magit) | `07-git.el` |
| Global keybindings | `08-keybindings.el` |
| Theme | `09-theme.el` |
| **Visual-fill-column, centering, line wrapping** | **`10-visual-fill.el`** |
| Org appearance (faces, prettify, headings) | `11-org-appearance.el` |
| Transient menus | `12-transient.el` |
| Centered writing mode (cursor recentering) | `13-centered-writing.el` |
| Typing analytics | `14-typing-analytics.el` |
| Workspace / dashboard | `15-workspace.el` |
| Org export (PDF, HTML, LaTeX) | `16-org-export.el` |
| Bibliography (Citar, BibTeX) | `17-bibliography.el` |
| Zotero transient menu | `18-zotero-transient.el` |

**Before adding a new feature:** find the owning file in this table and
add the code there. If no file owns the concern yet, create a new
numbered file and add a row to this table.
