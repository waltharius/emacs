# Emacs Configuration — Change Log & Architecture Notes

This log records significant refactoring sessions, commit by commit,
with rationale and lessons learned. Its purpose is to serve as a reference
before adding new code or modifying existing functionality — to avoid
introducing regressions, hook races, or dependency conflicts.

The sessions are in `changelog/`, one file per month; this file holds
what applies to all of them: where the entries are, the heading
convention, the lessons learned and the file ownership map.

## Where the entries are

| Month   | File                                         |
| ------- | -------------------------------------------- |
| 2026-10 | [changelog/2026-10.md](changelog/2026-10.md) |
| 2026-09 | [changelog/2026-09.md](changelog/2026-09.md) |
| 2026-08 | [changelog/2026-08.md](changelog/2026-08.md) |
| 2026-07 | [changelog/2026-07.md](changelog/2026-07.md) |
| 2026-06 | [changelog/2026-06.md](changelog/2026-06.md) |

Until Session 2026-10-20k the sessions were in this file; at 600 KB the
GitHub mobile app no longer opened it. They were moved unchanged.

## Heading convention

Sessions are listed newest first within each month's file. Every
session heading has the form

    ## Session YYYY-MM-DDx — Title

where `x` is a lower-case letter counting sessions within that day in
chronological order, starting at `a`; after `z` come `za` to `zz`, which
sort after it (2026-10-25 had more than 26). The letter is always present, on
single-session days as well, so that a second session can be appended
without relabelling the first — the relabelling is what the scheme is
there to avoid, and skipping `a` reintroduces it.

A new session goes at the top of the file of the month of its date,
`changelog/YYYY-MM.md`. The first session of a month starts that
month's file -- the title line and the short paragraph pointing here, as
in the other files -- and adds a row at the top of the table above.

Cross-references name the full label, letter included; the month in the
label names the file.

The lint check `changelogs` holds the files to this: every session in
the file of its month, newest first, labels unique and of this form,
every month's file in the table, no session left in this file.

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

### L5 — Hardcoded paths and usernames belong in `000-core.el`

Any value that is machine-specific (paths, usernames, locale strings)
should be defined as a variable in `000-core.el`, not inlined in the
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

### L12 — Bound any set derived from an ever-growing history

When protecting or excluding items based on "recently used in X",
never take X's _full_ history as the criterion. Emacs's own tracking
structures (`buffer-list`, a tab's `wc-bl`, etc.) tend to only grow for
as long as X exists — they don't forget entries just because something
newer came along. If a derived set (e.g. "buffers to protect") is built
from one of these, cap it explicitly — for an MRU-ordered list, take
only the front `N` entries — so the derived set stays bounded
regardless of how long X has been alive. See Session 2026-07-25a, A.

### L13 — Extending a transient from another module creates a load-order dependency

`transient-append-suffix` lets a feature module add its own entry to a
central menu (`419-philosophy-notes.el` adds `C-c n l`,
`422-zettelkasten.el` adds `C-c n z`) instead of the central menu
having to know about every feature. The cost is a hard ordering
constraint: the appending module must load _after_ the module defining
the prefix, or the append targets a prefix that does not exist yet.

Two habits keep this safe: keep the appending modules numbered above
the prefix's module in `init.el`, and guard the append with
`transient-get-suffix` wrapped in `ignore-errors` (it signals when the
key is absent) so re-evaluating a module during development does not
stack duplicate entries. See Session 2026-07-26a, A.

---

### L14 — `\s-` matches newline; use `[ \t]` for same-line matching

`\s-` in an Emacs regexp is the whitespace _syntax_ class, and under
the standard syntax table — which is what a temp buffer gets — newline
has whitespace syntax. A pattern like

```elisp
"^#\\+field:\\s-*\\(.+\\)$"
```

therefore does not stay on its own line: when the field is empty,
`\s-*` eats the line ending and the capture group matches the next
line's content instead. Line-oriented front matter parsing wants
`[ \t]*`, which cannot cross a line.

The companion mistake is using `.+` for a value that may legitimately
be empty. `.+` makes the match fail on the correct line, so the search
succeeds further down the buffer on some unrelated line. Use `.*` and
treat an empty capture as absent. See Session 2026-07-26a, E.

### L15 — One calendar, in one place

A rule every module needs -- here: a day is not always 86400 seconds --
belongs in one function, not in a copy per module.  On 2026-10-25, the
day summer time ended, two tests failed at 23:23; the search for the
cause found the same mistake in 438-habits and 428-writing-projects, and
the month before 835-journal-gaps had skipped a day the same way; three
modules had their own copy of the midday encoding that avoids it.  Each
copy was a place for the bug and for its tests.

Days are counted with the date functions of `000-core.el` (DATES):
`my/date-add-days`, `my/date-days-between`, `my/date-day-number`,
`my/date-to-time`, `my/date-of`, `my/date-weekday`, tested once in
`tests/test-dates.el` on both transition days and at the ends of
months and years.  A module does not add seconds to get a date, nor
encode a date itself; a duration (the last seven days of changes) is
not a date and stays in seconds.  A test's own "today plus N"
(`my/test-date`) is computed independently of the library, so that the
library is checked against something it did not compute.  See Session
2026-10-26a, and TESTING.org rule 16.

## File Ownership Map (current)

| Concern                                             | Owning file              |
| --------------------------------------------------- | ------------------------ |
| Basic UI, completion, session, mode-line            | `101-ui.el`               |
| Editing behaviour, keybindings                      | `102-editing.el`          |
| Spell checking (ispell, flyspell, flyspell-correct) | `303-spelling.el`         |
| Fonts and typography                                | `503b-fonts.el`           |
| Denote core, silo config, org-mode settings         | `204-denote.el`           |
| Notes functions (journal, essay, capture)           | `205-notes.el`            |
| Org-capture templates                               | `306-capture.el`          |
| Git (Magit)                                         | `207-git.el`              |
| Global keybindings                                  | `208-keybindings.el`      |
| Theme                                               | `509-theme.el`            |
| **Visual-fill-column, centering, line wrapping**    | **`510-visual-fill.el`**  |
| Org appearance (faces, prettify, headings)          | `511-org-appearance.el`   |
| Transient menus                                     | `212-transient.el`        |
| Centered writing mode (cursor recentering)          | `313-centered-writing.el` |
| Typing analytics                                    | `114-typing-analytics.el` |
| Workspace / dashboard                               | `815-workspace.el`        |
| Org export (PDF, HTML, LaTeX)                       | `716-org-export.el`       |
| Bibliography (Citar, BibTeX, the menu C-c x)        | `417-bibliography.el`     |
| PDF and EPUB viewers                                | `117b-document-viewers.el` |
| Zotero's attachments folder                         | `417c-zotero.el`          |
| Philosophy note types                               | `419-philosophy-notes.el` |
| Org-transclusion                                    | `420-transclusion.el`     |
| Dashboards                                          | `821-dashboards.el`       |
| Zettelkasten / Folgezettel sequences                | `422-zettelkasten.el`     |
| Fixed tabs (routing buffers to named tabs)          | `323-fixed-tabs.el`       |
| Readwise import and review                          | `424-readwise.el`         |
| **Migrated-notes inbox review, extraction**         | **`425-inbox-review.el`** |
| **Custom file load order, startup perf**            | **`init.el`**            |

**Before adding a new feature:** find the owning file in this table and
add the code there. If no file owns the concern yet, create a new
numbered file and add a row to this table.
