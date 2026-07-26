# Emacs Configuration — Change Log & Architecture Notes

This document records significant refactoring sessions, commit by commit,
with rationale and lessons learned. Its purpose is to serve as a reference
before adding new code or modifying existing functionality — to avoid
introducing regressions, hook races, or dependency conflicts.

---

## Session 2026-07-26 — Zettelkasten / Folgezettel Layer, Silo Moving

### Context

The note collection had no mechanism for expressing that one note
continues or branches from another — only keywords and free-form
links. Denote reserves an optional `SIGNATURE` file name component for
exactly this, and the official `denote-sequence` extension (GNU ELPA,
stable 0.3.0, released 2026-05-20) automates the bookkeeping. This
session adds a Folgezettel layer on top of the existing note system
without disturbing plain notes.

Separately, notes could be created into a chosen silo but never moved
between silos afterwards, so a note filed in the wrong place had to be
relocated by hand outside Emacs.

---

### A — `modules/22-zettelkasten.el` (new) — Folgezettel sequences

#### What changed

New module wrapping `denote-sequence` with a transient submenu at
`C-c n z`, appended to `my/notes-menu` via `transient-append-suffix`
— the same mechanism `19-philosophy-notes.el` uses for `C-c n l`. The
append is guarded by `transient-get-suffix` inside `ignore-errors`, so
re-loading the module does not create a duplicate entry.

Eleven commands, each a thin `my/zettel-*` wrapper: new
parent/child/child-of-current/sibling-of-current, find relative,
next/previous sibling, Folgezettel-ordered Dired, sequence-only
linking, reparent, and adopt (promote a plain note to a parent).
`j`/`k` (sibling paging) are `:transient t` so the menu stays open
while navigating.

`modules/08-keybindings.el` and `function_helper.org` updated to
document the new menu tree, the signature semantics, and the workflow.
`init.el` loads the module after `21-dashboards.el`.

#### Why — silo scoping

Every command is wrapped by the `my/zettel--in-pks` macro, which binds
`denote-directory` to `my-notes-pks` for the duration of the call.
This mirrors the silo-switching pattern already used by
`my/denote-base` in `05-notes.el`.

The effect is that signatures can only ever land on notes in
`~/notes/pks/`, and sequence lookups never offer journal or docu files
as parents. The rationale is structural: a journal is time-ordered and
low-friction, a Zettelkasten is idea-ordered and effortful; letting
sequences span both would make the hierarchy meaningless (a journal
entry is not a continuation of a philosophical argument) and would
pollute journal file names with signatures.

#### Why — alphanumeric scheme

`denote-sequence-scheme` is set to `alphanumeric` (`1`, `1a`, `1a1`)
rather than the package default `numeric` (`1`, `1=1`, `1=1=2`).
Signatures appear in file names, in Dired, and in minibuffer
completion, so compactness directly affects daily readability. The
tradeoff, per the upstream manual, is that large numbers become hard
to reason about (`1zzzv2zx` is the alphanumeric form of `1=100=2=50`).

This is not an irreversible decision: `denote-sequence-convert`
rewrites a whole collection from one scheme to another. Note its
documented limitation — it converts notation only, and does **not**
reparent or check the results for duplicates.

#### Design note — signatures stay optional

Plain Denote notes and sequence notes coexist in the same silo. A
signature is added only when a thought explicitly continues or
branches from another. The upstream manual is explicit that the
extension "is not necessary for such a workflow" — it only streamlines
signature bookkeeping — so no migration or bulk renaming of existing
notes was performed, and none is planned.

---

### B — `modules/05-notes.el` — Move notes between silos (`C-c n d c`)

#### What changed

New command `my/denote-move-to-silo`, added to the Document transient
submenu as `c`. It prompts for a destination silo (the silo the note
already lives in is excluded from the list) and relocates the current
note there.

Supporting helpers, all private: `my/denote--file-title`,
`my/denote--file-identifier`, `my/denote--silo-files`,
`my/denote--current-silo`, `my/denote--titles-equal-p`,
`my/denote--relocate`, `my/denote--remove`. Silo membership comes from
the new `my/denote-silo-alist`, built from the `my-notes-*` variables
in `00-core.el` — a new silo needs one entry there.

#### Conflict handling

Before moving anything, the destination is scanned for notes whose
`#+title:` matches (case- and whitespace-insensitive):

- no match: move proceeds;
- same title, different identifier: prompt offering keep both /
  overwrite / cancel, defaulting to keep both, since two notes sharing
  a title is a legitimate Denote situation as long as the identifiers
  differ;
- same title *and* identifier: keeping both is impossible because the
  file names would be identical, so prompt for a new title or cancel.

A new title is applied by rewriting the `#+title:` line and then
calling `denote-rename-file-using-front-matter`, which lets Denote
derive the file name itself. This deliberately avoids calling Denote's
sluggifying internals, whose arity has changed across versions.

**Documented limitation:** retitling unblocks the move but does not
resolve the identifier clash it worked around. `denote:` links resolve
by identifier, so two notes sharing one make those links ambiguous.
The duplicate still needs resolving afterwards; the prompt exists to
get unstuck, not to fix the data.

#### Implementation notes

- `git mv` is used when the file is tracked, so history follows the
  file rather than appearing as an unrelated delete plus add; falls
  back to `rename-file` when git refuses or the file is untracked.
  Overwriting uses `git rm` on the same basis, mirroring the git
  handling already present in `my/denote-delete-note`.
- Front matter is parsed with a regexp rather than through Denote's
  retrieval API, matching the approach already used by
  `my/denote-linked-note`, and reading only the first 4000 bytes of
  each candidate file since front matter is always at the top.
- `string-equal-ignore-case` was avoided: it is Emacs 29+, while
  Denote supports 28.1 and this configuration sets no version floor.
- The visiting buffer is repointed with `set-visited-file-name`, so
  the note does not have to be reopened after the move.
- Silo scanning is non-recursive, matching the flat silo layout.

Moving never breaks links: Denote links resolve by identifier, not by
path or file name.

---

### C — Zettelkasten fixes found in first practical use

Three problems surfaced while working through the tutorial exercises.

#### C1 — `C-u` never reached `denote-sequence-dired`

`denote-sequence-dired` is documented to prompt for a sequence prefix
under `C-u` and for prefix plus depth under `C-u C-u`. Through the
transient menu it never did: the Dired buffer was always built with
prefix `ALL` and depth `ALL`.

Cause: a transient prefix consumes the universal argument for its own
purposes, so a `C-u` typed before `C-c n z` is gone by the time the
suffix command runs. The original `my/zettel-dired` just called
`denote-sequence-dired` via `call-interactively` and relied on
`current-prefix-arg` surviving, which it does not.

Fix: `my/zettel-dired` now takes an explicit optional argument and
let-binds `current-prefix-arg` around the inner call, and two new
commands `my/zettel-dired-prefix` and `my/zettel-dired-prefix-depth`
pass `(4)` and `(16)` respectively. The menu binds them as `d`, `p`,
`P`. Invoked directly with `M-x`, `my/zettel-dired` still honours
`C-u` in the normal way.

The tutorial note and `function_helper.org` previously documented the
`C-u` route as working; both corrected.

#### C2 — Dired shows file names rather than titles

Not a bug: Dired lists a directory, so it shows file names. Two
mitigations enabled globally in `04-denote.el`: `denote-dired-mode`
(font-locks identifier, signature, title and keywords in separate
faces) and `dired-hide-details-mode` (drops the permission, owner,
size and date columns). For a genuine title view, a `denote-sequence`
dynamic block renders Org links with titles.

Also worth recording: the Folgezettel ordering was working correctly
all along. The `Dired by name` indicator in the mode line refers to
the underlying `ls` switches, not to the order in which
`denote-sequence-dired` assembled the listing. With short signatures
the two orders coincide, so the difference only becomes visible once
sequences reach two-digit numbers (`1a10` sorts before `1a2`
alphabetically but after it in Folgezettel order).

#### C3 — Renamed titles kept appearing in the title prompt

After renaming a note, the old title stayed on the completion list at
the new-note title prompt, which looked like a duplicate note.

Cause: `denote-history-completion-in-prompts` makes Denote offer past
minibuffer inputs as completion candidates for every prompt listed in
`denote-prompts-with-history-as-completion`. The list is session
minibuffer history, not an index of existing notes, so it keeps every
title ever typed regardless of what happened to the file afterwards.
Nothing was duplicated on disk, and file listings were never affected.

Fix: `denote-title-prompt` is removed from
`denote-prompts-with-history-as-completion` in `04-denote.el`. The
other prompts keep their history, because reusing an existing keyword
is exactly what the keyword prompt is for, whereas reusing a title
verbatim almost never is.

Note that `savehist-mode` is not enabled in this configuration, so
these histories were already session-local — restarting Emacs cleared
them. Enabling `savehist` later would make the same class of staleness
persist across sessions for whichever prompts remain on the list.

---

### D — `modules/22-zettelkasten.el` — Work around stale `denote-sequence-dired` listings

#### Symptom

After C1 made the prefix and depth prompts reachable, the prompts
worked but the listing did not follow them. Requesting prefix `1`
produced the unfiltered listing; then requesting prefix `3` produced
the `1` branch; requesting `3` a second time finally produced the `3`
branch. The buffer name always showed the prefix just entered, so name
and contents disagreed and the listing ran exactly one invocation
behind.

#### Cause

Upstream, in buffer reuse. `denote-sequence-dired` ends in

```elisp
(denote-sort-dired--prepare-buffer directory files-fn dired-name buffer-name)
```

`directory` is the same for every invocation within one silo, and
`files-fn` is a lambda that computes the file list. When a Dired
buffer for that directory already exists, it is reused and renamed
instead of being rebuilt from `files-fn`.

This is not caused by the wrappers in this module: the prompts fire
correctly and the entered value reaches the buffer name. It reproduces
with `C-u M-x denote-sequence-dired` called directly.

#### Fix

`my/zettel--kill-stale-dired-buffers` kills every Dired buffer whose
name matches `my/zettel--dired-buffer-regexp` — the literal `prefix
...; depth` wording that `denote-sequence-dired` puts in its buffer
names — and `my/zettel-dired` calls it before each invocation. With
nothing left to reuse, every invocation computes its listing fresh.

The regexp deliberately matches only the literal words around the two
values, not the quotes around them, because that quoting follows
`text-quoting-style` and is curly by default.

Killing the current buffer is expected here, since narrowing a view
usually happens from inside the previous listing. A replacement Dired
buffer is created and displayed immediately afterwards.

#### Note on the earlier version-compatibility hedges

This configuration targets Emacs 30.2, so the Emacs 29+ functions
avoided earlier (`string-equal-ignore-case` in `my/denote--titles-equal-p`)
would in fact have been available. The portable formulations are kept
anyway: they cost nothing, and Denote itself still supports 28.1.

---

### E — `modules/15-workspace.el` — Signature and tag columns in the dashboard

#### What changed

Dashboard lines went from `<date>  <title>` to

```
<date>  <signature>  <title>                    :tag:tag:
```

`my/denote-file-signature` extracts the Folgezettel component from the
file name (the segment between `==` and the `--` that starts the
title), returning nil for notes that have none. The column is padded
to `my/dashboard-signature-width` so titles stay aligned in sections
that mix sequence notes with plain ones.

Tags come from `#+filetags:` and start at `my/dashboard-tag-column`.
Four new variables tune the result: `my/dashboard-signature-width`,
`my/dashboard-show-tags`, `my/dashboard-tag-column`,
`my/dashboard-hidden-tags`.

#### Why a fixed tag column

The buffer is rendered before it is displayed — `my/open-notes-dashboard`
passes `(my/render-notes-dashboard)` to `switch-to-buffer` — so window
width is not reliably known at render time, which rules out
right-aligning to the window edge. A title running past the column
gets two spaces before its tags instead: the tags stay readable, they
just stop lining up for that line.

#### Why `my/dashboard-hidden-tags`

The Journal and Documentation sections are already labelled as such,
so `:journal:` on every line of the Journal section carries no
information while pushing the informative tags further right. The
default suppresses exactly those two silo tags.

#### Performance: one read instead of two

Every line now needs both title and tags, and
`my/denote-file-title` and `my/denote-file-tags` each open the file
separately — so naively adding tags would have doubled dashboard I/O.
New `my/denote-file-metadata` returns `(TITLE . TAGS)` from a single
800-byte read, and the renderer uses it. The two single-purpose
helpers are untouched for callers that need only one value.

#### Bug fixed on first run: `%-*s` is not Emacs `format`

The first version padded the signature with `(format "  %s  %-*s%s" date
width sig title)`, which fails at runtime with `Invalid format
operation %*` and prevented the dashboard from rendering at all.
Emacs's `format` has no dynamic field width — `%-*s` is C `printf`
syntax, not Elisp. Only literal widths such as `%-5s` are accepted.

The padding is now built explicitly with `make-string`, using
`(max 1 (- width (length sig)))` so that a signature longer than the
column keeps one separating space and pushes its own line right rather
than colliding with the title.

#### Second bug: front matter regexps crossed line boundaries

With tags now displayed, a note showed `:#+identifier:20260726T150901:`
where its tags should be. The note in question had an empty
`#+filetags:` line.

Cause: the existing readers used `"^#\\+filetags:\\s-*\\(.+\\)$"`.
`\s-` is the whitespace *syntax* class, and in a temp buffer
(fundamental mode, standard syntax table) a newline has whitespace
syntax — so `\s-*` consumed the end of the empty line and `\(.+\)`
captured the *following* line. `[ \t]` would not have done this.

The bug predates this session; it was latent because tags were never
displayed and only became visible now. It also affected
`my/denote-all-tags`, and therefore the dashboard's Tags section,
which was collecting `#+identifier` and raw identifier strings as if
they were tags — for every note with an empty `#+filetags:`.

Fix: both patterns moved into shared constants,
`my/denote-title-regexp` and `my/denote-filetags-regexp`, matching
`[ \t]*` instead of `\s-*` and capturing `.*` instead of `.+`. The
`.+`-to-`.*` change matters for the same reason: with `.+`, an empty
value makes the match fail on its own line and lets a later line
satisfy the search instead.

Parsing also moved into `my/denote--parse-title` and
`my/denote--parse-tags`, so the three readers (`my/denote-file-title`,
`my/denote-file-tags`, `my/denote-file-metadata`) share one
implementation and cannot drift apart again.

#### Known scaling limit

The dashboard is static text rebuilt in full on every `g`, reading the
head of every file in three silos each time. At the current collection
size this is imperceptible. If it ever becomes slow, the structural
answer is `tabulated-list-mode`, which would also provide column
sorting and alignment for free instead of the manual padding used
here — noted as a future option, not a current need.

---

## Session 2026-07-25 — Desktop Trim Tab/Pin Protection, Keybinding Audit, Org Markup Styling

### Context

Desktop-save's buffer trimming was killing buffers still open in
inactive tab-bar tabs, because trimming ranked buffers purely by
global recency with no awareness of tab-bar state at all. The first
fix protected a tab's full buffer history, which turned out to grow
unbounded over a tab's lifetime and needed a second pass. Separately,
`08-keybindings.el` and `function_helper.org` had drifted
significantly from the actual bindings defined in the repo. A small
styling addition for org-mode verbatim/code markup closes out the
session.

---

### A — `modules/01-ui.el` — Desktop trim now protects tab-open and pinned buffers, bounded per tab

#### What changed

`my/desktop-trim-buffers` ranked buffers purely by global recency
(`buffer-list` MRU order), so a buffer sitting open in an inactive
tab-bar tab could fall outside the top-`my/desktop-max-buffers` window
and get killed even though it was still visibly open.

Added two protection layers, computed in
`my/desktop--protected-buffers` and excluded entirely from both the
kill list and the recency count:

1. **Tab-open buffers** (`my/desktop--tab-buffers`): for the active
   tab, whatever's actually shown in a window right now; for every
   *other* tab, only the front `my/desktop-tab-protect-depth` (default
   3) entries of that tab's own MRU buffer list (`wc-bl`, restored by
   `tab-bar` on tab switch — see `tab-bar--tab` in `tab-bar.el`).
2. **Manually pinned buffers**: new buffer-local
   `my/desktop-keep-buffer`, toggled with `C-c d k`, shown as a 📌 in
   `mode-line-misc-info`. Can also be set per-file via a
   `Local Variables` block.

#### Why — and a design correction

The first implementation protected a tab's *entire* `wc-bl`/`wc-bbl`
history. This was wrong: `wc-bl` is Emacs's own most-recently-used
buffer list for that tab, and it only ever grows for as long as the
tab lives — it never forgets a buffer just because the user moved on
to something else in that tab. A month-old tab would eventually
protect hundreds of stale buffers, defeating the purpose of trimming.

The fix: since `wc-bl` is documented to be MRU-ordered, take only its
front `N` entries (`my/desktop-tab-protect-depth`) instead of the
whole list. This keeps the protected set bounded to roughly
`(number of tabs) × N`, independent of tab age, while still covering
the buffer(s) actually being used in that tab. Also dropped `wc-bbl`
(buried-buffer list) from protection — a buried buffer is a signal
it's *not* important, so it should stay eligible for trimming.

Closing a tab does not itself kill any buffers — it only removes that
tab's protection, so its buffers become ordinary trim candidates again
on the next `desktop-save`.

**Approach considered and rejected:** walking `window-state-get`'s
tree to find buffers exactly displayed in each inactive tab's windows
was considered (more precise than the MRU-head approximation) but
rejected — the Elisp manual documents `window-state-get`'s return
value only as an opaque object meant to round-trip through
`window-state-put`, not a structure with a stable, documented shape
for external parsing.

---

### B — `modules/08-keybindings.el`, `function_helper.org` — Keybinding documentation audit

#### What changed

Rebuilt `my/show-keybindings-help` (`C-c h k`) and the corresponding
sections of `function_helper.org` from a grep of every
`global-set-key` / `define-key` / `:bind` / `transient-define-prefix`
in the repo, rather than from the previous hand-maintained text.

Found and fixed:

- An entire `C-c F ...` spelling section that was fully fictional —
  never bound anywhere. Real spelling access is `C-;`
  (`flyspell-mode-map`), `C-c f b`, and the `C-c n` transient menu.
- Missing bindings: all of Magit (`C-x g`, `C-x M-g`, `C-c g s/l/b`),
  `C-c x` (Zotero), `C-c w d/x/r` (dashboards), `C-c a k/s/t/T`
  (typing analytics), and the rebound Emacs defaults
  (`C-a`/`C-f`/`C-s`/`C-z`/`C-x C-b`/`M-Q`).
- No documentation anywhere of the transient menu *contents*
  (submenu keys), only their existence.

The help buffer now includes the full `C-c n` and `C-c x` menu trees.
`function_helper.org`'s Session Management section documents the new
`C-c d k` pin command and `my/desktop-tab-protect-depth`; its Global
Keybindings table was rebuilt to match the audit.

#### Why

Discoverability had degraded to the point of actively misleading — a
help command that documents bindings which don't exist, and omits
ones that do, is worse than no help command. Both files now carry an
explicit note that future changes should re-run the same grep-based
audit rather than hand-editing the reference from memory, since that's
exactly how it drifted the first time.

---

### C — `custom.el` — Org markup styling for `~verbatim~` and `=code=`

#### What changed

Added two `custom-set-faces` entries:

```elisp
'(org-code ((t (:foreground "peru" :weight bold))))
'(org-verbatim ((t (:foreground "dark green" :weight bold))))
```

`=code=` markup maps to the `org-code` face; `~verbatim~` maps to
`org-verbatim`. Final styling is bold + colored text, no background —
a background-box variant and a bold-only variant were the two
alternatives considered and dropped.

#### Why

Per the existing architecture (documented in `11-org-appearance.el`),
all org-mode face *colors* live exclusively in `custom.el` — it's the
Customize-authoritative source and always takes precedence over
theme-applied faces (the `'user` pseudo-theme is kept at the front of
`custom-enabled-themes` by Emacs regardless of `load-theme` order).
`11-org-appearance.el` already left `:foreground` as `'unspecified`
for both faces via `set-face-attribute`, specifically so a `custom.el`
color could pass through untouched — no changes were needed there.

Editing `custom.el` directly was used instead of `M-x customize-face`:
the interactive UI reported setting `:background` but the visible
result matched a foreground-color change instead — an unresolved
discrepancy, not chased further since the direct edit is the same
one-entry-per-face pattern already used throughout this file (see
`org-block`, `org-quote`).

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

### L12 — Bound any set derived from an ever-growing history

When protecting or excluding items based on "recently used in X",
never take X's *full* history as the criterion. Emacs's own tracking
structures (`buffer-list`, a tab's `wc-bl`, etc.) tend to only grow for
as long as X exists — they don't forget entries just because something
newer came along. If a derived set (e.g. "buffers to protect") is built
from one of these, cap it explicitly — for an MRU-ordered list, take
only the front `N` entries — so the derived set stays bounded
regardless of how long X has been alive. See Session 2026-07-25, A.

### L13 — Extending a transient from another module creates a load-order dependency

`transient-append-suffix` lets a feature module add its own entry to a
central menu (`19-philosophy-notes.el` adds `C-c n l`,
`22-zettelkasten.el` adds `C-c n z`) instead of the central menu
having to know about every feature. The cost is a hard ordering
constraint: the appending module must load *after* the module defining
the prefix, or the append targets a prefix that does not exist yet.

Two habits keep this safe: keep the appending modules numbered above
the prefix's module in `init.el`, and guard the append with
`transient-get-suffix` wrapped in `ignore-errors` (it signals when the
key is absent) so re-evaluating a module during development does not
stack duplicate entries. See Session 2026-07-26, A.

---

### L14 — `\s-` matches newline; use `[ \t]` for same-line matching

`\s-` in an Emacs regexp is the whitespace *syntax* class, and under
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
treat an empty capture as absent. See Session 2026-07-26, E.

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
