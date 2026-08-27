# Emacs Configuration — Change Log & Architecture Notes

This document records significant refactoring sessions, commit by commit,
with rationale and lessons learned. Its purpose is to serve as a reference
before adding new code or modifying existing functionality — to avoid
introducing regressions, hook races, or dependency conflicts.

---

## Session 2026-08-28 — A day worth asking for, and hub notes

### The day-of-month dashboards were stuck on today

All four commands under `C-c n f h` collected notes whose day-of-month
matched the current day. That is the right default and the wrong only
option: the view is useful precisely when looking back at a day that is
not today, and the alternative was waiting a month for the calendar to
come round to it.

`my/dashboards--read-day-of-month` now supplies the number to `t`, `j`,
`m` and `M` alike. `RET` on an empty prompt returns
`(nth 3 (decode-time))`, so the existing keystroke sequence produces the
existing result and nothing about the habit changes.

Validation stops at the range. Non-numeric input and anything outside
1–31 raise a `user-error`; 30 February does not. Rejecting it would
require deciding which year the day is being asked about, and the query
spans every year on purpose — a day that no month has simply matches
nothing, which is the accurate answer rather than a failure.

Only the day is read. The "years" pair keeps the current month, so `t`
with `14` asks what was written on the 14th of this month in earlier
years; the "every month" pair spans all months as it did. Prompting for
a month as well would be a second decision, and neither view was asking
for one.

Both collectors gained an optional `DAY` argument defaulting to today,
which keeps their old zero-argument calls valid. Filtering, sorting, the
exclusion of the current year in one and of today's own date in the
other, and the `*Note History*` layout are untouched: the only thing
that changed is where the number comes from.

### Hub notes

New module `33-denote-hubs.el` and one command, `my/denote-add-to-hub`
(`C-c n i H`). It appends

```org
- [[denote:IDENTIFIER][TITLE]] — description
```

to a hub note, where identifier and title belong to the note in the
current buffer.

A hub is an ordinary Denote note with the `hub` keyword in the
`__keyword` component of its file name. That choice is what makes the
candidate scan free: `denote-directory-files` filtered through
`denote-extract-keywords-from-path` reads file names and opens nothing,
the same reasoning that put the `journal` keyword test ahead of the
content fallback in `my/dashboards--journal-p`. A `#+hub:` front-matter
keyword would have read every note in the collection on every
invocation to answer a question the file name already answers. It also
means `denote-rename-file` is the whole promotion and demotion
mechanism, with no second record to drift.

The link description is the `#+title:` value verbatim.
`denote-get-link-description` was available and was not used: it
composes signature and title itself, which would print the signature
twice for notes that already carry it in the title, and this
collection has such notes.

Choosing `[Nowy HUB]` — pinned last by declaring `identity` as the
completion table's sort function, since otherwise the frontend files it
somewhere alphabetical — creates the hub in `my/denote-hub-directory`
(pks) with only a title prompt. Every remaining prompt is answered
before `denote` is called, so `C-g` partway through leaves no half-built
note on disk.

A hub already open in a buffer is written to there and left open; one
that was not open is visited, written, saved and killed. Trailing
whitespace is stripped before the entry is inserted rather than assumed
absent, so the separator is exactly one blank line regardless of how the
file ended.

The menu entry anchors on `L`, which `12-transient.el` defines itself.
Anchoring on a key contributed by another optional module is what cost
the Insert menu four entries in August; the anchor is part of the
interface between modules, and only keys owned by the menu's own file
are safe ones.

`my/denote-hub--*` deliberately does not overlap with
`my/writing--hub-*` in `28-writing-projects.el`. Those hubs are
scaffolding files under `~/projects/`, not Denote notes, and the shared
English word is the only thing the two have in common — the
`my/denote--silo-files` collision earlier this year came from exactly
this kind of near-miss.

---

## Session 2026-08-25 (evening) — Three small corrections

### The no-entry prompt fired on today's entry

Creating a journal at 18:21 and recording metrics at 18:22 asked why
there was no entry. The prose check runs before you have written
anything, so a freshly created file always looks like a day that was
never written up.

The condition gained `past-day`. Today is never a missing entry: the day
is not over, and on a file created seconds ago the question is absurd.
`C-c n c W` on a past date with no prose still asks, which is the case
the field was added for.

### metrics_added lost its clock

`[2026-08-25 wto 18:22]` next to an entry timestamped 18:21 carries no
information. The field feeds `lag_days`, measured in days; a minute
resolution is finer than the unit of analysis and reads as noise dressed
as precision. Now `[2026-08-25 wto]`.

The handful of files with the old form are left alone — the parser takes
the date part either way, and a second whole-tree rewrite to normalise a
cosmetic difference is not worth the diff.

### Metrics are not bound to journal creation

Considered and rejected: prompting for metrics from `C-c n c j`.

`j` is used several times a day to append entries, so it would re-ask on
every append — friction at exactly the moment of sitting down to write.
Worse, it inverts the order. `WELLBEING` is defined as an assessment of
the whole day made in the evening; asking for it while creating the
morning entry would reliably produce a morning mood wearing a whole-day
label, and quietly change what a decade-long series means.

Instead `my/journal-metrics-reminder` prints a line in the echo area
when `j` appends to an entry that already exists and today's well-being
is still empty. A message, not a prompt; only on the append path, so it
arrives later in the day; and it costs nothing to ignore. `05-notes.el`
calls it behind `fboundp`, so deleting the metrics module deletes the
nudge with it.

---

## Session 2026-08-25 (later) — Metrics as keywords, and a menu chain I broke

### The regression from the previous commit

Removing the Insert menu's `w` entry took four other entries with it.
`20-transclusion.el`, `31-org-images.el` and `32-web-links.el` anchored
their own suffixes to it in a chain — `w` → `t`, `w` → `i` → `I` → `u` —
and `my/transient-append` did exactly what it is for: reported and
skipped rather than signalling.

```
transient: my/notes-insert-menu has no 'w' to append after, skipping 't'
transient: my/notes-insert-menu has no 'w' to append after, skipping 'i'
transient: my/notes-insert-menu has no 'i' to append after, skipping 'I'
transient: my/notes-insert-menu has no 'I' to append after, skipping 'u'
```

Transclusion, image insertion, the attachments folder and web links all
vanished from `C-c n i`. The commands still worked under `M-x`, which is
why this is the kind of breakage that survives a week unnoticed.

Both anchors moved to `d` (Insert date), which is defined in
`12-transient.el` itself and is not going anywhere. The lesson is not
"do not remove menu entries" but "before removing one, grep for it as an
anchor" — a suffix key is part of the interface between modules, not a
private detail of the menu.

### Why keywords replaced the headline

Schema 1 lasted about a day. The `* Metryki` headline parsed correctly,
but it put a second `:PROPERTIES:` drawer into files that already had one
under `* Uzupełnienie`, and a file did appear with the full metrics set
written into both. The exact sequence was never reproduced, which is its
own argument: a design where the write target has to be located by
searching for a headline can put data in the wrong drawer, and a design
with one uniquely named keyword per metric cannot.

Schema 2 stores metrics as front-matter keywords:

```org
#+identifier: 20260111T000000
#+language:   pl
#+schema:     2
#+wellbeing:  6
#+alcohol_u:  0
#+illness:    none
#+metrics_added: [2026-08-25 wto 03:26]
```

The remaining alternative — a true file-level property drawer — has to
sit above `#+title:` with only comments above it, which fights Denote's
front-matter tooling for the sake of an Org property API that this setup
does not use: the query layer is an external DuckDB index, and editing
goes through `my/journal-set-metrics`. `org-set-property`, `org-columns`
and `org-ql` are given up knowingly.

Read and write both go through one regexp over the region above the first
headline. Two mechanisms for one format is how `:well-being:` came to be
readable by eye and by nothing else.

### Atomicity, this time actually

The schema 1 command created its headline before the first prompt, so
`C-g` left a modified buffer. Claiming otherwise in the previous entry
was wrong; the ERT test written to prove it aborted on the `quit` signal
instead of failing, because `ignore-errors` does not catch `quit`.

`my/journal-set-metrics` now runs read → prompt → write, with no buffer
modification before the last phase, and the test uses `condition-case`
with a `quit` handler.

### Batch conversion

`my/journal-migrate-metrics-format` converts schema 0 and 1 files to
keywords. It is a pure translation — every value carried across
unchanged, nothing invented, an empty legacy drawer becoming no metrics
rather than empty metrics — so it needs no prompting and is idempotent.

Dry run by default, `C-u` to write, `C-u C-u` to include schema 0. The
default scope is schema 1 only: those are the handful of files this
configuration created in one day. The 3500 schema 0 files stay
opportunistic, because reading their legacy value is a regexp in the
indexer, an operation that cannot lose data, while rewriting them is one
that can.

### The blank line the migration ate

`my/journal--legacy-drawer-bounds` swallows one trailing blank line so
that removing a drawer from the middle of a file leaves no gap. When the
drawer is the last thing before the first headline, that blank line is
the separator between front matter and body, and converting a schema 0
note welded the first prose headline to the last keyword.

Rather than special-casing the bounds, `my/journal--normalize-front-matter-gap`
runs on every write and enforces one empty line after the front matter,
so a file comes out right regardless of which format it arrived in. It
is a no-op on correct files and returns nil, which is what the batch
command uses to avoid rewriting them.

`my/notes-normalize-front-matter-gap` applies it across all three silos,
one file at a time, dry run unless given a prefix. It guards on the file
actually having front matter: without that check it would strip leading
blank lines from any file it was pointed at.

### Auto-commit split

`my/auto-commit-all` no longer commits the configuration repository;
`my/auto-commit-config-enabled` defaults to nil. Notes are a working log
and "Auto-commit: <date>" describes what happened to them accurately.
Configuration changes are deliberate, each has a reason worth writing
down, and an exit-hook commit both buries that reason and silently
absorbs half-finished edits. `my/commit-config-now` is unchanged.

### Also

- `my/denote-base` gained `my/note-add-front-matter-extras`, which adds
  `#+language: pl` and `#+schema:` after Denote has written its own four
  lines. Overriding `denote-org-front-matter` was rejected: it would make
  this configuration responsible for tracking that format string
  upstream, while Denote's rename and refresh functions already leave
  unknown keywords alone.
- `my/dashboards--journal-p` gained `#+wellbeing:` to its content
  fallback, so all three formats are recognised.
- `my-journal-schema-version` is 2. `my-journal-metrics-heading` is kept
  purely so the schema 1 files can still be found and converted.

### Files touched

- `modules/00-core.el` — schema version 2, all three formats documented
- `modules/05-notes.el` — no metrics headline in either journal
  template; `my/note-add-front-matter-extras`
- `modules/05b-journal-metrics.el` — rewritten around keywords; three
  phases; batch migration command
- `modules/07-git.el` — `my/auto-commit-config-enabled`
- `modules/20-transclusion.el`, `modules/31-org-images.el` — anchors
  moved from `w` to `d`
- `modules/21-dashboards.el` — `#+wellbeing:` in the content fallback
- `tests/test-journal-metrics.el` — rewritten; `quit` handled correctly;
  new cases for keyword mechanics, conversion, and the Insert menu chain
- `function_helper.org`

### Lesson

Two of the three defects this session were in things asserted rather than
checked: that removing a menu entry was local, and that a command was
atomic. The tests that would have caught both were cheap. The one that
existed for atomicity was written to pass rather than to fail, which is
worse than not having it.

---

## Session 2026-08-25 — A property drawer Org never read

### What was wrong

`my/denote-journal` wrote this into every new journal file:

```org
#+title:      2026-08-24 Journal
#+date:       [2026-08-24 pon 09:12]
#+filetags:   :journal:
#+identifier: 20260824T091200
:PROPERTIES:
:well-being:
:END:
```

That drawer is not a property drawer. The Org manual is explicit:
a property block before the first headline must be at the top of the
buffer with only comments above it. `#+title:` and the rest are
keywords, not comments, so `org-entry-get` returned nil for
`well-being`, `org-element` parsed the block as ordinary text, and
`org-columns` and `org-ql` could not see it at all. It rendered
correctly and meant nothing.

252 of 3502 journal files carry a value in that position. Ten years of
notes are meant to become a queryable series; a field the query layer
cannot reach is not a field.

### What replaced it

Metrics now live in a real property drawer under a dedicated `* Metryki`
headline. `modules/05b-journal-metrics.el` owns them:

- `my/journal-set-metrics` (`C-c n c w`) — prompts for the fields
  declared in `my/journal-metrics-fields` and writes the drawer.
- `my/journal-set-metrics-for-date` (`C-c n c W`) — same, for a date
  chosen with `org-read-date`, creating the journal file when the day
  has none.

Field set as of schema 1: `WELLBEING` (1–10), `ALCOHOL_U`, `ILLNESS`.
Kept short on purpose. Everything WHOOP already records — sleep
duration and efficiency, caffeine, recovery, the ~22 behaviour
checkboxes — is imported from its CSV export rather than typed a second
time, and the two axes considered for splitting well-being (anxiety,
energy) were dropped: forcing a decomposition finer than the one the
rater actually discriminates produces invented numbers, and one
consistent indicator beats three uncertain ones.

Missing and zero are kept distinct. `RET` accepts the field default,
`-` deletes the property, and a blank value is never written. An absent
property means "not measured" and is never to be read as zero.

### Migration without a migration

Nothing is rewritten in bulk. `my/journal-set-metrics` seeds `WELLBEING`
from the legacy `:well-being:` value, writes the new drawer, and only
then deletes the legacy drawer and stamps `#+schema:`. Aborting with
`C-g` at any prompt leaves the file exactly as it was. A note is
upgraded when it is deliberately opened and answered, and never
otherwise.

The 3250 files nobody ever touches stay untouched. Reading their legacy
value is a regexp in the indexer, which is an operation that cannot lose
data; rewriting 3502 files is one that can.

### Recording how the number was arrived at

Two properties are written without being asked for:

- `METRICS_ADDED` — when metrics were *first* recorded, never refreshed.
  The indexer derives a lag against the day in the file name.
- `RECALLED` — `t` when `WELLBEING` is written for a day other than
  today and the value differs from what was there before. Set once,
  never unset.

A day rated the same evening and a day reconstructed three weeks later
are not the same measurement. The flag exists so that an analysis can
exclude the second kind, not so that it can discount it: there is no
ground truth here against which a decay curve could be fitted, so any
"a 30-day recall is worth 0.7 of a same-day rating" weighting would be
arithmetic invented to look rigorous.

`METRICS_ADDED` overlaps with the `ADDED_AT` property that
`my/denote-journal-date` already puts on `* Uzupełnienie`, but does not
duplicate it: `ADDED_AT` exists only for backdated *prose*, and metrics
can be added to a same-day file weeks after it was written.

### A regression this would have caused

`my/dashboards--journal-p` identified journal notes by searching the
first 1200 bytes for `:well-being:`. Retiring that property would have
made every migrated and every newly created journal invisible to both
history dashboards — silently, since the predicate simply returns nil.

It now tests the `journal` Denote keyword in the file name, parsed with
a plain regexp so the predicate does not depend on which helper a given
Denote version exposes, and costs no file access at all. The content
check survives as a fallback for a note whose name lost its keywords,
matching either the `* Metryki` headline or the legacy drawer.

### Menu placement

`m` and `M` were the obvious keys in the Create submenu and both were
taken (`m` is Promote to note), so the two commands took `w` and `W`,
appended after `J` by `my/transient-append` from within
`with-eval-after-load '12-transient`. The module loads before
`12-transient.el`, so the append cannot run at load time.

The old Insert → `w` "Well-being" entry is gone along with
`my/denote-set-wellbeing`, which edited a `:well-being:` line by regexp
and would have reported "Could not find well-being property" on every
new file.

`my-journal-metrics-heading` and `my-journal-schema-version` moved to
`00-core.el`. The journal template needs both, and a mandatory module
must not depend on an optional one. `init.el` loads
`05b-journal-metrics.el` with NOERROR, so deleting the file degrades to
"no metrics commands, no menu entries" rather than aborting init partway
through and leaving the rest of the configuration unloaded.

### Files touched

- `modules/00-core.el` — `my-journal-metrics-heading`,
  `my-journal-schema-version`
- `modules/05-notes.el` — journal template rewritten; new
  `my/denote-journal--create-backdated` helper; `my/denote-set-wellbeing`
  removed
- `modules/05b-journal-metrics.el` — new module
- `modules/12-transient.el` — Insert → `w` removed, `w`/`W` reserved in
  Create
- `modules/21-dashboards.el` — journal detection no longer depends on
  `:well-being:`
- `init.el` — optional load for `05b-journal-metrics.el`
- `function_helper.org` — new entries under Create (`w`, `W`), Insert
  `w` removed, journal and dashboard entries corrected

### Lesson

A field that renders correctly is not a field that parses correctly.
Every metadata key added from here on gets checked once with
`org-entry-get` on a real file before anything is built on top of it.

---

## Session 2026-08-24 — Fetching a page title instead of typing one

### What was missing

Every Org link typed by hand needed a description someone had to write.
For an external URL, that description is almost always the page's own
title — information already sitting in the page's `<title>` tag,
re-typed by hand every time a source was cited.

### What was added

`modules/32-web-links.el`. `use-package org-web-tools` (MELPA) pulls in
the fetching logic rather than reimplementing an HTML-title parser.
`my/insert-web-link` wraps `org-web-tools-insert-link-for-url`, appended
as `u` in the Insert submenu (`C-c n i u`) through `my/transient-append`,
so `12-transient.el` itself is untouched.

### Files touched

- `modules/32-web-links.el` — new module
- `function_helper.org` — new entry under Insert (`u`)

---

## Session 2026-08-12 — The second most-used command had no binding

### What the measurement said

A new programmable keyboard was the occasion, but `keyfreq` (`C-c a k`)
answered a different question than the one being asked. Counts over the
whole logging period, `org-self-insert-command` aside:

| command | calls | reachable by |
|---------------------------------+-------+--------------|
| `my/notes-menu` | 2939 | `C-c n` |
| `my/spell-correct-previous` | 1305 | menu only |
| `transient-quit-one` | 1257 | `q` |
| `denote-open-or-create` | 293 | `C-c d f` |
| `my/spell-add-previous-to-dict` | 285 | menu only |

The second and fifth entries had no binding of their own. They existed
only as suffixes inside `my/notes-menu`, so every one of those 1590
invocations went `C-c n`, then `s` or `a`, and then — because both
entries carry `:transient t` — left the menu open to be dismissed. The
1257 `transient-quit-one` calls are largely that dismissal.

That is a defect in this configuration, not in the keyboard, and it was
worth fixing on its own terms: it applies just as much to the laptop's
built-in keyboard, where there are no macros to hide it.

### What was added

Five bindings in `08-keybindings.el`:

    C-c s    my/spell-correct-previous
    C-c S    my/spell-add-previous-to-dict
    C-c m c  my/notes-create-menu
    C-c m w  my/toggle-writeroom
    C-c m k  my/denote-keywords-edit

`C-c s` and `C-c S` are short because they are the ones that are used;
`C-c m` is a grab-bag prefix for the rest. All five were checked against
every `global-set-key`/`define-key`/`:bind` in the repo before being
taken — `C-c s`, `C-c S`, `C-c m` were free.

The menu entries stay. `:transient t` is right when correcting several
words in a row; the direct binding is right for one fix. Two paths to
one command, each suited to a different case, is not drift as long as
both are documented — which is why `12-transient.el` now carries a
comment pointing at `08-keybindings.el` and vice versa.

`C-c m k` is a deliberate duplicate of `C-c d t`. Both reach
`my/denote-keywords-edit`; `C-c d t` fits the Denote group, `C-c m k`
keeps the keyboard's macro targets in one namespace. Flagged in both
files rather than silently tolerated, since an undocumented duplicate is
exactly the kind of thing that later looks like a mistake.

### What lives outside this repository

Six macros on a momentary layer held by Caps Lock, typing the chords
above. They are stored in the keyboard's EEPROM. Nothing about that is
reproducible from a repository, it cannot be read back from Emacs, and
the VIA configurator's "Save Current Layout" button does not work in
this setup — so the table in `function_helper.org` and the copy in
`my/show-keybindings-help` are the only written record. Factory reset
(`Fn + [`) erases the lot.

This is the opposite of how everything else here is managed and it is
worth naming as a known weakness rather than pretending otherwise. The
mitigation is only that the macros type ordinary chords: every command
remains reachable, at more keystrokes, from any keyboard.

### A design assumption that did not survive contact

The first draft of the layer put a navigation cluster on the right hand
— arrows on IJKL, word jumps on UO, Home/End, PgUp/PgDn — reasoning from
the same `keyfreq` data, which showed mouse scrolling (59270 calls)
outnumbering every keyboard cursor movement combined by a factor of
three, and character-wise movement outnumbering word jumps ninety-nine
to one.

The diagnosis was right and the prescription was wrong. The Air75 V2 is
a 75 % board: it has a real arrow cluster and dedicated navigation keys
already, under the same hand. The layer was duplicating keys that were
physically present. It was dropped. The reasoning would hold on a 60 %
board, where those keys do not exist.

### Lessons

1. `keyfreq` is worth consulting before adding a binding and not only
   before buying hardware. The most-used command in a configuration can
   turn out to have no binding at all, and nothing in daily use makes
   that obvious.
2. `:transient t` is a cost as well as a convenience. It shows up in the
   data as `transient-quit-one`, which is easy to read as noise.
3. A layout borrowed from one form factor does not transfer to another.
   Check which keys the board already has before mapping them again.
4. Configuration held in device firmware is outside every guarantee this
   repository otherwise makes. Write it down somewhere that is in the
   repository, and say plainly that the record is manual.

---

## Session 2026-08-03b — Rescaling is not compression, and a failure that said nothing

### What was reported, twice

First: with ImageMagick installed, an inserted image still arrived at
4.2 MB. Then, after the compression ladder was added, the same file
again — this time with `stored unchanged: the converter refused it`.

Two separate faults, one visible symptom.

### Fault one: the pipeline was doing what it was told

Session 2026-08-03a rescaled to 1600 px and stopped. PNG is lossless, so
that removes pixels and stores every remaining one exactly. Measured on
a 2559x1639 terminal screenshot:

| step | size |
|---------------------------------+--------|
| source | 551 kB |
| rescaled to 1600 px, still PNG | 489 kB |
| rescaled, then `-colors 256` | 133 kB |
| rescaled, then JPEG q85 | 146 kB |

An 11 % saving against a factor of four. A source already under 1600 px
saves nothing at all. Size falls only when fidelity is traded, and
nothing in the module was trading any.

### A ladder with a budget

`my/org-image-max-bytes` (300 kB) is the target, and each rung runs only
if the previous one left the file above it:

1. rescale to `my/org-image-max-pixels`, never enlarging;
2. under budget — stop, and the stored file is still pixel-exact;
3. few colours in the source — quantise to 256 colours, staying PNG and
   keeping alpha;
4. otherwise, or when step 3 was not enough — JPEG at
   `my/org-image-jpeg-quality`, with `jpeg:extent` as a ceiling.

Quantising is tried before JPEG because it keeps text edges crisp while
JPEG rings around every letter, and screenshots are most of what gets
attached. The smallest candidate wins, so a rung that makes things worse
cannot be chosen — which is not hypothetical: on a night photograph the
palette branch produced 2.1 MB against 293 kB for JPEG.

Screenshot and photograph are told apart by distinct colours in a
400x400 sample of the source, against `my/org-image-palette-max-colors`
(4096). Measured: terminal screenshot 897, night photograph 18033,
synthetic photographic noise 120000.

`-sample`, not `-resize`. Interpolation invents colours: the same
screenshot reports 8.8 million of them after a rescale, so counting on a
resized copy would send every screenshot through JPEG. Counting a
sample rather than the whole file costs 0.11 s instead of 0.45 s on a
4 MP image, and only runs for files that are over budget anyway.

Measured end to end on a 4000x3000 phone photograph: 4.17 MB in,
1600x1200 and 293 kB out.

### Fault two: the failure had nowhere to be seen

`my/org-image--run` passed nil as the destination of `call-process`,
which discards standard output and standard error. When ImageMagick
exited non-zero the module knew only that, so it fell back to a plain
copy and reported "the converter refused it" — accurate, useless, and
indistinguishable from a dozen possible causes.

Discarding a failing process's output is the bug. Now:

- the command line, exit status and everything printed go to
  `my/org-image-log-buffer` (`*org-image-log*`), and the echo area
  names that buffer;
- both `magick` and `convert` are tried in turn rather than only the
  first one found, since "installed" and "working" are different
  claims;
- `my/org-image-diagnose` runs the same command on a chosen file and
  collects the executables, their versions, the command line and its
  output in one buffer;
- the source path is expanded before it reaches an external process. A
  name beginning with `~` passes `file-readable-p`, because Emacs
  expands it, and fails in ImageMagick, which does not — a cause worth
  removing rather than diagnosing.

The colour count now reads the number from the END of the converter's
output: called as `convert`, ImageMagick 7 prints a deprecation warning
that contains the digit 7, which a leading-match would have taken as the
colour count.

### Names now come from the title

`IDENTIFIER--TITLE-SLUG-N.EXT`, with N counting from 0 within the note,
which is the convention the migrated attachments already follow:

: 20241225T000000--25-12-2024-środa-0.png

The default at the prompt is the note's `#+title:` rather than the
source file's name, so an image from a camera folder no longer arrives
called `IMG_2451`. `my/org-image-prompt-for-name` set to nil skips the
prompt.

Numbering ignores the extension when looking for the next free number,
because the ladder may store one attachment of a note as PNG and the
next as JPEG, and those must not collide on `-0`.

One difference from the migrated files: the slug collapses runs of
non-alphanumeric characters to a single hyphen, so `25-12-2024 - środa`
gives `25-12-2024-środa` where the migration script produced
`25-12-2024---środa`. Neither is parsed by anything; the old files are
left alone.

### `my/org-image-recompress-attachments`

A one-off command for files stored before any of this existed. It
rescales and recompresses in place, only when the result is smaller, and
preserves names and extensions so that no link has to change. That
constraint is also its limit: a photograph stored as PNG gets quantised
rather than converted, and may band. Deleting such a file and inserting
it again gives the better result, since the insertion path can choose
the format.

### Files touched

- `modules/31-org-images.el` — compression ladder, title-based names,
  numbering from 0, converter logging and fallback, `my/org-image-diagnose`,
  recompress command, size reporting in the message
- `function_helper.org` — updated to match

---

## Session 2026-08-03b — Rescaling is not compression

### What was reported

With ImageMagick installed, an inserted image still arrived at 4.2 MB
where a few hundred kilobytes would do. At 1366 attachments and 204 MB,
the collection averages 153 kB per file; twenty images at four megabytes
would undo that on their own.

### The pipeline was doing what it was told, and that was not enough

Session 2026-08-03a rescaled to 1600 px and stopped. PNG is lossless, so
that removes pixels and stores every remaining one exactly. Measured
here on a 2559x1639 terminal screenshot:

| step | size |
|-------------------------------------+--------|
| source | 551 kB |
| rescaled to 1600 px, still PNG | 489 kB |
| rescaled, then `-colors 256` | 133 kB |
| rescaled, then JPEG q85 | 146 kB |

An 11 % saving against a factor of four. A source already under 1600 px
saves nothing at all, which is the other half of the report. Size falls
only when fidelity is traded, and nothing in the module was trading any.

### A ladder with a budget

`my/org-image-max-bytes` (300 kB) is now the target, and each rung runs
only if the previous one left the file above it:

1. rescale to `my/org-image-max-pixels`, never enlarging;
2. under budget — stop, and the stored file is still pixel-exact;
3. few colours in the source — quantise to 256 colours, staying PNG and
   keeping alpha;
4. otherwise, or when step 3 was not enough — JPEG at
   `my/org-image-jpeg-quality`, with `jpeg:extent` as a ceiling.

Quantising is tried before JPEG because it keeps text edges crisp, while
JPEG rings around every letter — and screenshots are most of what gets
attached. Whichever candidate is smallest wins, so a rung that makes
things worse cannot be chosen.

### Telling a screenshot from a photograph

By distinct colours in a 400x400 sample of the source, against
`my/org-image-palette-max-colors` (4096). Measured: the terminal
screenshot 897, a plasma-fractal stand-in for a photograph 120000.

`-sample` and not `-resize`, which matters more than it looks.
`-resize` interpolates, and interpolation invents colours: the same
screenshot reports 8.8 million of them after a rescale. Counting on a
resized copy would classify everything as photographic and route every
screenshot through JPEG.

Counting is done on a sample rather than the whole file for speed —
0.11 s against 0.45 s on a 4 MP image, and it only runs for files that
are over budget in the first place.

### Names now come from the title

`IDENTIFIER--TITLE-SLUG-N.EXT`, with N counting from 0 within the note,
which is the convention the migrated attachments already follow:

: 20241225T000000--25-12-2024-środa-0.png

The default offered at the prompt is the note's `#+title:` rather than
the source file's name, so an image dropped in from a camera or a
screenshot folder no longer arrives called `IMG_2451`.
`my/org-image-prompt-for-name` set to nil skips the prompt entirely and
takes the title.

Numbering ignores the extension when looking for the next free number,
because the ladder may store one attachment of a note as PNG and the
next as JPEG, and those must not collide on `-0`.

One difference from the migrated files: the slug collapses runs of
non-alphanumeric characters to a single hyphen, so a title of
`25-12-2024 - środa` gives `25-12-2024-środa` where the migration script
produced `25-12-2024---środa`. Both are stable and neither is parsed by
anything; the old files are left alone.

### `my/org-image-recompress-attachments`

A one-off command for files stored before any of this existed. It
rescales and recompresses in place, only when the result is smaller, and
preserves names and extensions so that no link has to change. That last
constraint is also its limit: a photograph stored as PNG gets quantised
rather than turned into a JPEG and may band. Deleting such a file and
inserting it again gives the better result, since the insertion path can
choose the format.

### The message now carries the evidence

Insertion reports source size, stored size and which rung ran — enough
to see at a glance whether ImageMagick was found and what it decided.

### Files touched

- `modules/31-org-images.el` — compression ladder, title-based names,
  numbering from 0, recompress command, size reporting in the message
- `function_helper.org` — updated to match

---

## Session 2026-08-03a — Images get a folder, a size, and a click

### What was missing

Notes could show an image only if one was already somewhere on disk and
a link to it was typed by hand. Nothing said where such files should
live, nothing kept them from being four megabytes of phone photograph,
and the inline preview was a dead rectangle: no way to see the picture
at full size short of finding the file again.

### 31-org-images.el

A new module, `C-c n i i`. It asks for a file, asks for a short name
(the source's own base name is offered as the default), copies the image
into `~/notes/attachments/` and links it at point.

The copy is named `IDENTIFIER--name.ext`, where the identifier is the
**note's**, taken from its file name via
`denote-retrieve-filename-identifier`. Every attachment of one note
therefore sorts next to its siblings, and a file whose identifier
matches no note is an orphan by inspection. Notes without a Denote
identifier fall back to `#+identifier:` and then to their file name, so
the command also works in `captures.org`.

`C-c n i I` opens the attachment folder in Dired.

### Why the attachment folder is hidden from Denote

Reusing the note's identifier means two files under `~/notes/` share
one. That is precisely what `27-denote-identifiers.el` reports as a
fault — but it reads `.org` files only, so images never reach it. The
exposure is Denote itself, which walks the whole tree for every prompt,
backlink buffer and keyword completion.

The module therefore adds the folder name to
`denote-excluded-directories-regexp`. It **extends** the value rather
than setting it: `25-inbox-review.el` owns the base value (`inbox`) and
that must survive. The extension is idempotent and disappears with the
module, which is correct — without the module there is no attachment
folder to hide.

### Rescaling happens once, on the way in

A phone photograph is three to four thousand pixels wide. Nothing in a
note needs that; Syncthing copies every byte of it to every device.
`my/org-image-max-pixels` (1600) caps the longer edge as the file is
copied, through ImageMagick's `magick`, or `convert` on version 6.

Two failure paths both end in a plain copy rather than an error: no
ImageMagick on `PATH`, and a format the installed ImageMagick has no
delegate for. The message says which happened. SVG and GIF are never
rescaled — pixel dimensions mean nothing for a vector, and an animated
GIF has to be coalesced frame by frame and usually grows.

On NixOS, `imagemagick` has to be in the system packages for any of
this to run; without it the module still works, it just stores
originals.

### Display width: 800 → 1100

`org-image-actual-width` in `11-org-appearance.el` was `'(800)` and read
as too small. The number is a pixel count, so what it looks like
depends on the display and its scaling; 1100 is a starting point, not a
measurement.

A float — `'(0.9)`, a fraction of the window — was considered and
rejected. The scaled bitmap would have to be rebuilt on every window
resize, which is every writeroom toggle and every split, and Org
measures the window rather than the text column, so under the centred
layout of `10-visual-fill.el` an image can come out wider than the
prose it sits in.

The two numbers are linked: asking to display more pixels than
`my/org-image-max-pixels` stores upscales a bitmap and only adds blur.
Raise both or neither.

### Clicking a preview

Org's inline preview is a scaled bitmap in an overlay carrying
`image-map`, which has no binding for a click. The module puts its own
keymap there, with `image-map` as parent so `i +`, `i -` and `i o` keep
working:

- `mouse-1` and `RET` open the file (`image-mode` buffer by default,
  `my/org-image-click-action` switches to the desktop viewer);
- `x` opens it in the desktop viewer regardless;
- a click that lands on something other than an image only moves point,
  so the binding never swallows an ordinary click.

Growing the overlay in place was the alternative. It rescales a bitmap
inside a text buffer, reflowing everything below it, and the size is
lost at the next image refresh. Opening the file gives full resolution
with panning and zooming that already exist.

### Two Org generations

Org 9.8 renamed `org-display-inline-images` to
`org-link-preview-region` and changed the argument list. Both names are
advised for the keymap, and the refresh after insertion tries each form
in turn, so a version that accepts neither degrades to "the preview
appears at the next manual refresh" rather than to an error.

### Files touched

- `modules/31-org-images.el` — new
- `modules/11-org-appearance.el` — `org-image-actual-width` 800 → 1100
- `init.el` — loads 31 after 30
- `function_helper.org` — `C-c n i i` and `C-c n i I` documented

`12-transient.el` is unchanged: both entries are appended through
`my/transient-append`, which reports and skips when the menu is absent.

---

## Session 2026-08-02s — Extraction was taking the front matter

### What was reported

`C-c n t i x` in an inbox note offered the whole `#+title:      ...`
line as the default title, then produced a note containing only front
matter, duplicated. A second attempt worked, but the new note carried
today's date rather than the source's, recorded
`:extracted_from: 20230331T114200--farewell-letter-to-bd-team.org`, and
the inbox note did not disappear.

### Three of those are not faults

`C-c n t i x` is `my/inbox-extract`, which splits a _fragment_ out into
a **new** note and leaves a link in its place. A new note gets a new
identifier and today's date; the source stays where it is; the
`:extracted_from:` property names the file it came from. All by design.

Promotion into a silo is `my/inbox-accept`, reached as `p` or `d` on a
row inside the review list (`C-c n t i r`), with `k` to reject. It needs
a selected row, which is why it is not on the menu — and why `x` sitting
there alone invited the confusion. Both entries are relabelled.

### One of them is a real fault, and it destroys source text

`my/inbox--extract-bounds` fell back to
`backward-paragraph`/`forward-paragraph`. Front matter lines are
contiguous, so with point anywhere among them **the surrounding
paragraph is the front matter block**. Extraction then:

1. offered `#+title:      Farewell letter…` as the default title —
   exactly what was seen;
2. wrote the source's header as the _body_ of the new note, which also
   receives a header of its own, hence the duplication;
3. **deleted that header from the source** and put a link there, because
   extracted text is replaced by a link.

The second attempt succeeded because point was by then in the body.

**Worth checking:** the note this was first tried on may have lost its
front matter. Its Denote identifier lives in the file name, so it is
recoverable, but `#+title:`, `#+filetags:` and `#+identifier:` may need
restoring.

### The fix

`my/inbox--content-start` returns where the body begins: past the
leading run of `#+key:` lines and any `:PROPERTIES:` drawer beneath
them. `my/inbox--extract-bounds` will not start above it.

- point in the body, paragraph reaching too far up → start clamped;
- point in the front matter → refused, with a message;
- empty result → refused.

The default title now takes the first line with something on it, and
strips a `#+key:` prefix as well as heading stars. That prefix cannot
reach it any more; stripping it makes a bad default impossible rather
than unlikely.

### Was this caused by recent work?

No. `my/inbox-extract` and `my/inbox--extract-bounds` have not been
edited in this configuration's recent history — the only change ever
made to `25-inbox-review.el` here is the cell coercion in session
2026-08-02r, in a different function. The changelog references the
module in eight earlier sessions and modifies it in none of them.

Nor is a global setting involved. Everything that moved out of
`26-performance.el` — `auto-revert-avoid-polling`,
`dired-auto-revert-buffer`, `jit-lock-defer-time`, image sizes, font
cache compaction — was already in effect before the move and is not
read by this module or by Denote's writing path.

### Why "it worked before" is true and unhelpful

Both faults in this module were positional or data-dependent:

- the `stringp, nil` crash needed an inbox note without `:source_path:`,
  which only notes _created_ in the inbox lack;
- this one needed point to be in the front matter rather than the body.

Neither is reached by ordinary use until the day it is. Code that has
worked for months can still contain a fault reached by one cursor
position, and "it worked before" narrows nothing.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02r — A nil in a tabulated-list cell

### The failure

`C-c n t r` (inbox review) reported

```
tabulated-list-print-entry: Wrong type argument: stringp, nil
```

`my/inbox--list-entries` built the Folder column as

```elisp
(file-name-directory (or (plist-get e :source) ""))
```

`file-name-directory` returns **nil**, not the empty string, when its
argument holds no directory part — and the empty string holds none. So
any inbox note without a `:source_path:` property put nil into the
vector, and `tabulated-list-print-entry` signalled on it.

The `(or ... "")` was already there, guarding the wrong side: it made
sure `file-name-directory` received a string and never asked what it
returned.

Notes migrated from Obsidian carry `:source_path:`. Notes created in the
inbox do not. This was waiting for the first one of those, and one such
note makes the entire list unreachable — every other note with it.

### Was this caused by recent work?

No. The line is in `25-inbox-review.el`, which none of the recent
sessions edited; the only change to that module's surroundings was
`init.el` loading 27-denote-identifiers.el before it, which stopped a
double load and touches nothing here. The fault is latent, data-driven,
and predates all of it.

That is worth recording plainly rather than assumed either way, because
the honest answer to "did the last change break this" is usually
findable and was findable here.

### The fix, at the boundary that demands the type

`my/inbox--folder` returns a string in every case, including the one
where there is no source path.

`my/inbox--cell` coerces every cell of the vector. `tabulated-list-mode`
requires strings and signals on anything else, taking the whole list
down — one malformed note and a thousand good ones become unreachable.
Guaranteeing the type where it is demanded turns that into an empty
cell on one row, with the note still listed, visible, and fixable.

The same hazard was checked for elsewhere: every other
`file-name-directory` call in the configuration is given an absolute
path, and `26-maintenance.el`'s own list builds its cells from values
that cannot be nil.

### What the mechanical checks do and do not cover

The two recorded in function*helper.org — duplicate top-level
definitions, and calls to functions never defined — both pass on this
repository and would have said nothing here. They catch a module being
internally inconsistent about \_symbols*.

This was a _value_ of the wrong type, produced only by data of a shape
that had not occurred yet. Byte-compilation does not catch it either.
Nothing short of running the command against a note without a source
path does.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02q — Writing to a file should not need a buffer's permission

### The failure

```
if: Buffer is read-only: #<buffer [D] Chrześcijaństwo - religia niewolników>
```

reported without the preview having been used at all. The note was
simply already open — from a tab, from an earlier preview, from
anywhere.

`my/maintenance--set-keywords` edited the front matter _through_ the
visiting buffer and saved it, on the reasoning that what is on screen
and what is on disk should stay the same thing. That reasoning holds;
the implementation did not. A buffer can be read-only for reasons that
have nothing to do with the file — `view-mode`, which the preview in
this very module turns on, is one of several — and the edit had no way
past it.

### The fix is a change of direction, not a workaround

Binding `inhibit-read-only` would have worked and would have been wrong:
fighting a buffer's read-only state in order to write to a file is the
wrong way round. Nothing about writing a file requires the cooperation
of a buffer that happens to be looking at it.

The file is now edited through a temporary buffer, and an open buffer is
brought back into line afterwards with `revert-buffer`. Screen and disk
still agree; the agreement is now reached from the disk's side.

`:preserve-modes` keeps `view-mode` and anything else the buffer had,
and its read-only state is saved and restored across
`set-visited-file-name`, which is free to clear it.

### Sequence

1. refuse if the visiting buffer has unsaved changes, or the
   destination name is taken;
2. rewrite `#+filetags:` on disk;
3. rename the file;
4. `set-visited-file-name` on any visiting buffer, preserving read-only;
5. `revert-buffer` it.

Steps 2 and 3 keep their order for the reason already recorded: an
interruption between them leaves new keywords under an old name, which
is visible and repaired by running the rename again.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02p — Built on the file-naming scheme, not on Denote's functions

### The failure, twice

```
Wrong number of arguments: denote-rename-file-keywords, 2
Wrong number of arguments: denote-rename-file, 5
```

Both signatures have changed across Denote releases. Correcting the
second call after the first failed was the wrong response: it kept the
same dependency and only moved the failure to whichever release changes
next.

### What is stable

The file-naming scheme, which is what Denote exists to promise:

```
IDENTIFIER[==SIGNATURE][--TITLE][__KEYWORD_KEYWORD].EXTENSION
```

and, for Org, `#+filetags:  :one:two:` holding the same keywords.
Changing a keyword means editing those two places. That is a smaller and
far more stable contract than any function signature, and it is the one
Denote's manual commits to.

`my/maintenance--set-keywords` now writes the front matter line and
renames the file itself. Two Denote functions remain in the module, both
one-argument accessors used for reading:
`denote-retrieve-filename-signature` and the variable
`denote-sort-keywords`.

### This is narrower than what it replaces, not wider

`denote-rename-file` rebuilds the _whole_ name from components, which is
why the previous version came with a warning that a note whose front
matter title disagreed with its file name would have the name
"corrected" as a side effect.

Nothing before the keyword field is now touched at all. Identifier,
signature and title are carried across as text. The change that was
asked for is the only change that arrives.

### Reader and writer are inverses on purpose

`my/maintenance--file-keywords` and `my/maintenance--new-file-name` both
find the keyword field at the first double underscore of the base name —
a title slug never contains one, so it is a reliable boundary. They
parse it here rather than one of them borrowing an accessor from Denote,
because if the two disagreed about where the field begins, a rename
would compute a name for a file it had misread.

### Order, and what an interruption leaves

Front matter first, file name second. Interrupted between the two, the
note has its new keywords and its old name — visible, and repaired by
running the same rename again. The other order would leave a name
claiming keywords the note does not have.

### Refuses rather than guesses

Two cases where guessing would lose work: a buffer with unsaved changes,
and a destination name already taken. Both stop with a message naming
the file.

When a buffer visits the note, the front matter is edited through it and
`set-visited-file-name` follows the rename, so what is on screen and
what is on disk stay the same thing. Keywords are lower-cased and
underscores and spaces become hyphens — not Denote's full
sluggification, and not trying to be, since keywords here are normally
chosen from the completion list of those already in use.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02o — Stop depending on another package's arity

### The failure

`y` in the keyword review reported

```
if: Wrong number of arguments: denote-rename-file-keywords, 2
```

`denote-rename-file-keywords` does not take `(FILE KEYWORDS)` in this
Denote version. Its arity has changed across releases — it is one of the
commands rewritten when Denote consolidated its renaming code — and this
module was calling it with a shape that happened to be true elsewhere.

### The fix is to remove the dependency, not to correct the call

Guessing the current arity would leave the same problem waiting for the
next Denote release. The rename now goes through `denote-rename-file`,
whose Lisp signature is documented and stable:

```
(denote-rename-file FILE &optional TITLE KEYWORDS SIGNATURE DATE)
```

Title and signature are read from the file and handed straight back, so
nothing but the keyword field is asked to move. DATE is nil, which
leaves the identifier alone.

Reading those values explicitly rather than passing the `keep-current`
symbol keeps this working on Denote versions predating that symbol. The
effect is identical — `keep-current` resolves to the same current
values — and it removes one more assumption about which version is
installed.

### One consequence worth stating

Denote rebuilds the entire file name from the components it is given. A
note whose front matter title disagrees with its file name — which the
Obsidian migration could produce — will therefore have its file name
corrected to match the front matter as well.

That is Denote's own rule for which of the two wins, and it is the
behaviour `keep-current` would have produced too. It is recorded here
and in the function's docstring because it is a second change arriving
alongside the one that was asked for.

### Note on the last three sessions

This is the third failure in a row in the same twenty lines: a helper
deleted with the section around it, a blocking prompt that could not
allow what it offered, and now an arity assumed rather than checked.
All three were invisible to paren balance and to reading, and all three
surfaced on the same keypress.

Two mechanical checks are now recorded in function_helper.org — the
duplicate-definition grep and the byte-compilation warning scan. Neither
would have caught this one. Only calling the function does.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02n — A function called and never defined

### The failure

`y` in the keyword review reported `Symbol's function definition is
void`. `my/maintenance--set-keywords` — the only function in the module
that writes — was called from `my/keyword-rename-apply` and did not
exist.

It was deleted in the previous session. Replacing the rename section
wholesale removed a helper that lived inside it and was still referenced
from the code that replaced it. The paren balance was correct, the file
loaded without complaint, and the only way to find out was to press the
one key that uses it.

Restored unchanged: `denote-rename-file-keywords`,
`denote-rename-confirmations` bound to nil, `denote-save-buffers` bound
to t, explicit save afterwards.

### The check that would have caught it

Byte-compilation. It reports a call to an undefined function as a
warning, which is exactly this class of error:

```sh
emacs -Q --batch \
  --eval '(dolist (f (file-expand-wildcards "modules/*.el")) (byte-compile-file f))' \
  2>&1 | grep "not known to be defined" | grep "my/"
rm -f modules/*.elc
```

Filtering on `my/` is what makes the output readable: under `-Q` the
compiler knows nothing about Denote, Vertico or Org either, and those
warnings are noise. A warning naming a `my/` symbol is not.

This belongs beside the duplicate-definition grep from session
2026-08-02i as a pre-commit check. Between them they cover the two ways a
module can be internally wrong while still loading: a symbol defined
twice, and a symbol called but never defined.

Neither is a substitute for running the command. This module's writing
path had been read carefully and reasoned about at length, and it had
been broken since the moment it was written.

_Not compiled or run: written without an Emacs available. The check
above is offered precisely because that is a real limitation here._

---

## Session 2026-08-02m — The keyword rename becomes a buffer

### What was wrong

`K` displayed a note on `v` and then refused to let it be read. The
preview could not be scrolled: touching it with the mouse replaced it
with the choice prompt again, and any movement or click inside the
affected windows caused redraws and previews in unexpected places.

`read-multiple-choice` reads **raw input events**. A mouse movement or a
click is not one of its answers, so each one re-prompts and redraws. And
while it is reading, nothing else receives input at all — so the note it
had just put on screen could not be scrolled, which was the entire
purpose of offering to put it there.

This was a design error rather than a detail. A blocking prompt cannot
be made to allow free navigation; it owns the input stream by
definition. Adding `v` to it produced something that looked like a
reading option and could not be used as one.

### The shape it should have had

A `tabulated-list-mode` review buffer — the shape that already works
twice in this configuration, in `25-inbox-review.el` and
`24-readwise.el`. Nothing holds the input stream, so the preview
scrolls, the mouse behaves, and stepping away and returning costs
nothing.

| Key   | Effect                                                         |
| ----- | -------------------------------------------------------------- |
| `RET` | preview the note in a side window, focus stays on the list     |
| `o`   | step into the preview, where it scrolls normally (`q` returns) |
| `y`   | rename this note                                               |
| `n`   | leave it alone                                                 |
| `g`   | redraw                                                         |
| `q`   | leave; unhandled notes keep their keyword                      |

Focus stays on the list on `RET` for the reason already written into
`my/inbox-preview`: the decision keys live in the list buffer, and
`view-mode` in the preview binds `n` to its own command, so a preview
that stole focus would swallow them.

Per-file confirmation is unchanged in substance — nothing is written
until `y` is pressed on that row. What changed is that the decision no
longer has to be made without the ability to look.

### Rows track what happened

Each row carries a state: pending, renamed, skipped. Denote returns the
new path after a rename and the row is updated with it, so a second `y`
cannot act on a name that no longer exists. The mode line counts what is
left. Leaving the buffer part-way through is safe: every note is written
and saved as it is handled.

The separate preview report is gone — the list is the preview, and it
stays on screen while the work is done.

### Consistency

`my/maintenance--note-window` is global and reused, for the reason given
against the identical variable in `25-inbox-review.el`: one preview
window per session rather than a new split per note.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02l — Keyword maintenance written here, not delegated

### What was reported

`K` (keyword rename, `denote-explore-rename-keyword`) produced a
**second file** carrying only front matter — 137 bytes, no body — and
left the original untouched. Two files, one identifier, one of them
empty.

`S` (`denote-explore-sync-metadata`) gave a save prompt that did not say
what it wanted to do, failed with `denote--rename-file: The destination
file already exists`, and made changes to a file that had been declined
at the prompt.

Neither could be reproduced from the outside, and both may depend on the
state of this particular tree. This is therefore not a verdict on
denote-explore. It is a decision about what can be vouched for when
three thousand real notes are on the other end of the command:
denote-explore is no longer called from the write path.

### A — Keywords, on Denote's own primitive

`my/maintenance-rename-keyword` is written against
`denote-rename-file-keywords` — the same primitive behind `C-c n d k`,
which touches the keyword field and nothing else. Title, identifier and
signature are not rebuilt, so nothing else can move.

Per-file confirmation is kept, as asked, and gains a fourth answer:

| Key | Effect                                            |
| --- | ------------------------------------------------- |
| `y` | rename this note                                  |
| `n` | leave it alone, move on                           |
| `v` | show the note in another window and **ask again** |
| `q` | stop, leaving the rest untouched                  |

`v` exists because a keyword that looks wrong in a list is sometimes
right in the note, and deciding that used to mean leaving the command,
finding the file, and starting over. It does not end the run: the same
question returns with the note on screen beside it. Built on
`read-multiple-choice`, which is the built-in for exactly this and
supplies its own help.

### B — Two things the old command got wrong, fixed explicitly

`denote-save-buffers` is bound to t for the duration, with a further
explicit `save-buffer` afterwards, so a renamed note reaches the disk
instead of sitting modified in a buffer. An interrupted run leaves
nothing unsaved.

`denote-rename-confirmations` is bound to nil. This command has already
asked about this file; a second prompt underneath, whose answer means
something different, is precisely how a declined change becomes a
carried-out one.

### C — A preview before the loop

The affected notes are listed in a buffer before the first prompt, with
the operation stated in a sentence — `Rename keyword X to Y` or
`Remove keyword X` — and the four answers explained. The complaint about
`S` was that it was impossible to see what it intended; that is a
property worth not repeating.

Renaming onto an existing keyword merges two spellings, so the
replacement prompt completes over the keywords already in use.

### D — `my/maintenance-keyword-inventory`

Every keyword with the number of notes using it, **sorted
alphabetically** rather than by frequency: near duplicates are what a
migrated collection accumulates, and `filozofia` directly above
`flozofia` is what makes them visible. Count is the second signal, and
keywords used once are marked. Each keyword is a button that starts a
rename of it.

This is the keyword review that was deferred to a later part. It arrived
early because the rename had to be rewritten anyway, and a rename
without a way to find what needs renaming is half a tool.

### E — Attachments

Correct as observed: attachments carry an identifier so links can reach
them, but no front matter and no keywords. Nothing here ever saw them —
`my/denote--all-files` returns .org files only — but the Commentary now
says so rather than leaving it to be inferred, and denote-explore, which
did scan them, is gone from this module.

### F — Menu

`O` (alphabetise all keywords) and `S` (sync front matter to file names)
are removed. Both were denote-explore writes and neither can be
recommended on this evidence. Keyword sorting is not lost: Denote sorts
keywords on every rename when `denote-sort-keywords` is non-nil, so the
inventory and rename above maintain it note by note.

Added: `k` keyword inventory, `z` notes with no keywords. Both read-only.

### G — Findings from the first run, for the record

`i` and `g` clean — no duplicate identifiers or signatures. `b` five
notes and `l` seven, six of them in the inbox: links into notes not yet
filed, which resolve as those notes move. The remainder are Obsidian
in-document section links that the migration did not distinguish from
links to other documents, and are a separate job.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02k — 26-maintenance.el, part one: checks and a menu

### Context

A maintenance layer was asked for: change a note's identifier including
its file name and every link to it, rename a keyword across the
collection, and find notes sharing an identifier or a signature.

Three of those four already existed and were reachable only through
`M-x`, which is why they read as missing:

| Wanted                               | Already provided by                |
| ------------------------------------ | ---------------------------------- |
| identifier change + link rewriting   | `my/denote-change-identifier` (27) |
| duplicate identifier report          | `my/denote-check-identifiers` (27) |
| walk and fix duplicates              | `my/denote-fix-duplicates` (27)    |
| keyword rename across the collection | `denote-explore-rename-keyword`    |
| front matter vs file name mismatch   | `denote-explore-sync-metadata`     |

denote-explore has been installed since 15-workspace.el was written;
only two of its commands were ever called.

Denote upstream does not cover the identifier case and says so: its
manual gives sample code for finding duplicates and states that, being
an edge case, it is not part of the code base. Nor does
`denote-rename-file-using-front-matter` change an identifier — Denote
treats the file name as the source of truth for that field. So 27 is
not duplicating upstream, and the new module calls it rather than
reimplementing it.

### A — What is new

`my/denote-check-signatures` and `my/denote-check-broken-links`.

denote-explore covers keywords and identifiers, not signatures. A
duplicate signature makes a sequence ambiguous in the same way a
duplicate identifier makes a link ambiguous, and `denote-sequence`
writes signatures into file names where a migration or a manual rename
can collide with them.

Broken links are the other half of the identifier problem: a `denote:`
link still looks like a link and still fontifies when its target is
gone. Reported grouped by missing identifier, so one deleted note does
not read as several problems.

Both scan `my-notes-dir` directly through `my/denote--all-files` from
27, which is why they see the staging inbox without any special
arrangement.

### B — The inbox had to be said out loud

Every denote-explore command works from `denote-directory-files`, which
honours `denote-excluded-directories-regexp` — `"inbox"`, set by
25-inbox-review.el. Left alone, renaming a keyword would silently skip
over a thousand staged notes, and the old keyword would return one note
at a time as they were filed. That failure would surface weeks later,
attached to nothing.

`my/maintenance-with-full-scope` binds both exclusion options to a
regexp matching only the empty string, so nothing is excluded for the
duration of a maintenance command and nothing outside one is affected.
An impossible regexp rather than nil, because Denote is free to treat
nil differently in future while a regexp that cannot match is safe under
either reading.

### C — Reads and writes are separated in the menu

`C-c n !`, appended to the main menu after `a` through
`my/transient-append`.

Checks sit in their own columns on lower-case keys; anything that
renames files across the collection is on a capital, so a mistyped key
cannot start one. `R` (change this note's identifier) and `I` (fix
duplicates) reach 27; `K`, `O` and `S` reach denote-explore through
wrappers that load it, widen the scope, and report its absence in a
sentence rather than a void-function error.

### D — Load order

`init.el` already loaded 27 before 25 for a dependency reason. 26 joins
that block after 25, so the sequence is 27, 25, 26 — dependency order,
not numeric. The comment there now says so rather than explaining one
pair.

Nothing in 26 runs at load time, so the number would not have mattered;
saying which order is intended does.

### E — Deliberately not in this part

A keyword review list — every keyword with its usage count, acting on
the one at point — and a wrapper giving
`denote-explore-rename-keyword` a single confirmation with a preview
instead of one prompt per file. That is the part that writes to the
whole collection at once, and it is being kept for its own pass rather
than added at the end of a long one.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02j — M-TAB never reached Emacs

### The failure

Stepping through keyword candidates with TAB worked; inserting one
without leaving the prompt did not, so taking several keywords from the
list meant retyping them.

`vertico-insert` was bound to `M-TAB`. GNOME owns `Alt-Tab` as the
window switcher, so the compositor consumes the event and Emacs never
receives it. The binding was correct and unreachable — the worst kind,
because nothing reports an error: the key simply does something else,
somewhere else.

A second defect in the same line: `M-TAB` was bound without `<M-tab>`,
while TAB and S-TAB were both given their function-key and
control-character spellings. Even on a desktop that left Alt-Tab alone,
a graphical frame might not have matched it.

### The fix

Insertion moves to two keys, for two different moments:

| Key     | Effect                                                       |
| ------- | ------------------------------------------------------------ |
| `,`     | insert the highlighted candidate and start the next keyword  |
| `C-TAB` | insert without exiting, when the separator is not wanted yet |

The comma is the better key on its own merits, not merely a key that
works. In a list of keywords it already means "this one is finished", so
completing to the highlighted candidate first is what it was going to be
used for anyway. Choosing several existing keywords becomes filter, TAB,
comma, repeat. On the input line, with nothing highlighted, it stays an
ordinary comma, so typing a new keyword by hand is untouched.

Detecting "is a candidate highlighted" needs `vertico--index`, which is
Vertico's own variable and no part of a public API. Guarded with
`bound-and-true-p`, so a future Vertico that renames it costs a
keystroke rather than breaking the prompt.

### One helper, two kinds of prompt

`my/notes--keyword-minibuffer-setup` is renamed
`my/notes--completion-keys` and takes an optional separator. Keyword
prompts pass `","`; the capture destination prompt in `06-capture.el`
passes nothing, because it reads a single heading and a heading may
legitimately contain a comma.

Naming the function for what it installs rather than for the first
prompt that wanted it also removes the awkwardness noted in session
2026-08-02h, where a capture prompt was calling something called
`keyword`.

### Worth remembering

Under GNOME on Wayland the compositor takes its keys before Emacs sees
them, and `C-h k` reports nothing at all for those — no event, no
message. Any binding reaching for `Alt` deserves that check first.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02i — Two modules, one symbol: moving notes between silos

### The failure

`my/denote-move-to-silo` stopped working with

```
let*: Wrong number of arguments: #[nil ...], 1
```

`my/denote--silo-files` was defined twice:

| Module                     | Signature | Returns                                              |
| -------------------------- | --------- | ---------------------------------------------------- |
| `05-notes.el`              | `(dir)`   | Denote files directly inside one silo, non-recursive |
| `27-denote-identifiers.el` | `()`      | every .org file across all silos, recursive          |

Two different functions, two different jobs, one symbol. `init.el` loads
27 after 05, so 27's zero-argument version was the one that existed by
the time anything ran, and 05's caller passed it a directory.

Elisp has one namespace for functions. The second `defun` replaces the
first without a word, and the module that loses is the one whose author
never sees the other file. Nothing warned: the two definitions were
eleven hundred lines apart in different files, and the failure only
surfaces when the losing module's code is actually invoked.

### The same trap, not yet sprung

`my/denote--file-identifier` was also defined in both, and is called
from `05-notes.el`, `25-inbox-review.el` and `27-denote-identifiers.el`.
Both versions took one argument and both returned the anchored
identifier, so 27's silently winning changed nothing — which is worse,
not better: the collision was invisible and would have become a bug the
first time either definition was edited.

### The fix

Two different functions get two different names, each saying what it
returns rather than what it operates on:

- `05-notes.el`: `my/denote--silo-files` → `my/denote--silo-note-files`
- `27-denote-identifiers.el`: `my/denote--silo-files` →
  `my/denote--identifier-scope-files`

One function gets one owner. `my/denote--file-identifier` stays in
27-denote-identifiers.el, which is the module responsible for identifier
integrity, and where 25-inbox-review.el already got it from. The copy in
05-notes.el is deleted along with the `my/denote--identifier-regexp`
constant that only it used.

Resolution is at call time, so load order does not matter.
`my/denote-move-to-silo` gains an `fboundp` guard so that a missing
module produces a sentence instead of a void-function backtrace.

### Preventing the next one

The whole class is visible in one command:

```sh
grep -h "^(defun \|^(defmacro \|^(defsubst " modules/*.el \
  | sed 's/^(def[a-z]* //; s/[ )].*//' | sort | uniq -d
```

It now returns nothing. The same check over `defvar`, `defconst` and
`defcustom` returns only `vertico-preselect`, which is the deliberate
bare declaration in `05-notes.el` and `06-capture.el` — those declare a
variable belonging to Vertico rather than defining one, and repeating a
declaration is harmless.

Worth running before any commit that adds a helper with a generic name.

### Note on the audit

This is the duplication finding from session 2026-08-02's audit —
"reading front matter: six independent implementations" — arriving as a
crash rather than as tidiness. The six front-matter readers are still
six; this closes only the pair that collided outright.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02h — One prompt, three answers; and a keybinding that never existed

### A — `C-c n m` is not a binding

`Unbound suffix: 'm'` was correct: promotion sits at `C-c n c m`
(Create → Promote to note) and always has. Three files claimed
`C-c n m` — `00-core.el` in the text written into a fresh captures.org,
`06-capture.el` in its commentary, and `function_helper.org`. All three
corrected.

Nothing in the code was wrong. This is the failure mode
`08-keybindings.el` already carries a note about: hand-written help text
drifting from the keymap it describes.

Adding `m` at the top level of `C-c n` would also resolve it and is one
line, but the top level is a menu of categories rather than commands and
that is the user's call, not a fix to apply while correcting a typo.

### B — The finalize prompt now names a new heading too

The template leaves the headline empty and puts point in the body, so
every new capture arrived unnamed and `my/capture-promote-to-note` had
no default title to offer. There was nowhere to type one.

The prompt introduced in the previous session was already asking the
right question; it just refused free text. It now takes three answers:

| Answer                            | Result                                                  |
| --------------------------------- | ------------------------------------------------------- |
| TAB onto an existing heading, RET | filed under it, source line, no second heading          |
| type something, RET               | the capture keeps its own heading, named with that text |
| RET on an empty prompt            | untitled, exactly as before                             |

The `+ Keep as a new heading` sentinel is gone — an empty answer says
the same thing without occupying a candidate slot.

Naming is done by editing the capture buffer while it is still open,
with `org-edit-headline`, rather than after filing. The headline is
right there and Org writes it out itself.

### C — RET must submit what was typed

With Vertico's own settings, RET submits the highlighted candidate. A
new heading beginning like an existing one could therefore not be
entered at all — the same trap as the keyword prompts, which is where it
was first met.

The prompt binds `my/notes-keyword-preselect` and installs
`my/notes--keyword-minibuffer-setup`, both from `05-notes.el`: RET is
literal, TAB steps onto the list. Reused rather than reimplemented, and
deliberately not given a second variable name — it governs one behaviour
and one name is what keeps it consistent. That the name says _keyword_
is a reminder of where the behaviour was first needed, not a claim about
its scope.

The prompt now appears even when no headings exist yet, since naming a
first capture is exactly the case that needs it.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02g — Filing a capture under an existing heading

### Context

A capture usually continues a thread that already has a heading in
captures.org. Retyping that heading from memory is how near-duplicates
are born: "Do poprawy w moim systemie notowania Emacs" against the same
words with one letter different is two headings to Org, and two separate
notes once each is promoted — which is exactly the failure the promotion
command exists to avoid.

### A — One source format, used in both files

Where a capture lives under its own heading, its origin sits in a
property drawer. Org only recognises a property drawer directly beneath
a heading, so a fragment filed under an existing heading cannot use one,
and body text is what a promoted note receives anyway. All three places
now use one line:

```
Source: [[denote:20260715T101500][Przewodnik po bibliografii]] — [2026-08-02 nie 18:10]
```

Written by `my/capture--source-value`, matched by
`my/capture-source-line-regexp`, compared by `my/capture--source-key`.
The capture side and the promotion side share a format, and sharing it
through three named functions is what keeps them from drifting apart —
the real cost of this change, and the reason it is contained in one
file.

`my/capture--source-key` compares the bracket link rather than the whole
line, so the same origin captured at two different times counts as one
source.

### B — The question at C-c C-c

`org-capture` decides where an entry goes before the buffer is opened
and offers no way to change that at the end. The entry is therefore
allowed to file normally and moved afterwards:

- `org-capture-prepare-finalize-hook` asks, while what was written is
  still on screen;
- `org-capture-after-finalize-hook` moves the stored entry.

The default candidate is "keep as a new heading", so a plain RET at the
prompt behaves exactly as before and the prompt costs one keystroke. It
is skipped entirely when there are no named headings to offer.

### C — Where this is fragile, and what makes it safe anyway

Reaching into finalize means depending on org-capture's own sequence.
Three guards, all of which fail towards changing nothing:

- Nothing is asked when `org-note-abort` is set, so `C-c C-k` is silent.
- Nothing is asked during `org-capture-refile`, which already picks a
  destination and moves the entry; two mechanisms moving one entry is
  worse than not offering the choice.
- The entry to move is identified twice: it is the last level-2 heading
  under `Ideas`, **and** its CAPTURED property must equal the one read
  from the capture buffer moments earlier. On disagreement nothing is
  touched and a message says so.

Deletion happens only after the destination marker has been found and
the replacement text built, so every failure path leaves the capture
where org-capture put it.

Heading text, if any was typed, is kept as the first paragraph of the
fragment. A filing decision should not quietly discard writing.

### D — Promotion reads several origins

`my/--capture-heading-data-at` now returns `:segments` instead of
`:source` and `:body` — an ordered list of (SOURCE . TEXT) produced by
`my/capture--split-into-segments`. The heading's own SOURCE and CAPTURED
describe the text before the first source line in the body, so an entry
captured the old way parses as exactly one segment and **nothing in
captures.org needs migrating**.

`my/--note-fragment` takes that list and emits a source line only when
the origin differs from the one before it, counting the line the target
note already ends with. Order is capture order; nothing is reordered or
merged.

### E — Known limitation

A line of ordinary prose beginning with `Source:` is read as metadata.
Recorded in the module commentary rather than defended against, because
the alternatives — a marker character, a drawer — cost more readability
in captures.org than the case is worth.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02f — Org faces, light-only theme, and 15-workspace split

### A — Why customised colours never survived a restart

`11-org-appearance.el` called, seven times over:

```elisp
(set-face-attribute 'org-code nil :inherit 'fixed-pitch
                    :height 'unspecified :foreground 'unspecified)
```

under a comment claiming this left colour and size "to inherit from the
face hierarchy (or custom.el)". It does the opposite. `unspecified`
**erases** the attribute. Every colour set through `M-x customize-face`
was written to custom.el, applied at startup, and then wiped the moment
Org loaded — so it had to be set again in every session. The same
mistake, with the same explanation attached, was in `03b-fonts.el` for
`org-quote`.

### B — Why the same face looked different in different windows

`set-face-attribute` changes the realised attributes of frames that
already exist. A new frame computes its faces from the theme and
`custom-set-faces` specs, in which the erasure does not appear. A note
read in a frame made by `my/detach-buffer-to-frame` therefore showed the
theme's colours while the same note in the main frame showed none — which
is what "every file looks different" was.

`=verbatim=` and `~code~` compounded it: they are two different faces,
and custom.el gave one `extra-bold` and the other `normal`, so the
difference read as a per-document quirk rather than a per-marker one.

### C — custom.el is now the only owner

Both face blocks are deleted. `01-ui.el` already stated that org faces
live exclusively in custom.el; that is now true. `:inherit fixed-pitch`
— the one thing those calls were really for, keeping code monospace
inside journal buffers that use a handwriting font — is expressed in
custom.el instead, so nothing is lost and Customize can edit all of it.

Faces added or changed there:

| Face                                                     | Now                                                   | Why                                                                                                                                     |
| -------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `org-quote`                                              | `:inherit variable-pitch`, italic, 1.1                | Quotations render in the journal handwriting font in every note, not just journals. Was Georgia.                                        |
| `org-block`                                              | `:inherit fixed-pitch`, background kept               | Source blocks are monospace. custom.el said Georgia and the module said monospace; they disagreed and the winner depended on frame age. |
| `org-verbatim`                                           | `:inherit fixed-pitch`, `:weight normal`              | Purple without the bold. No `:foreground` on purpose — the purple is the theme's, which is the one that was liked.                      |
| `org-code`                                               | `:inherit fixed-pitch`, `"dark green"`, normal weight | Distinguishable from verbatim at a glance. The theme has no dark green, so this one is pinned.                                          |
| `org-table`, `org-meta-line`, `org-checkbox`, `org-link` | `:inherit fixed-pitch`                                | Carried over from the deleted blocks.                                                                                                   |

`org-quote` inherits `variable-pitch` rather than naming the font, so
changing the handwriting font in `03b-fonts.el` still changes every face
that follows it.

### D — Light only

`my/load-theme-dark`, `my/toggle-modus-theme` and `my/load-theme` are
gone, along with the commented list of alternative themes. The dark
theme could not work while custom.el pins a dozen Org faces to literal
light colours, and keeping a switch beside a note explaining that the
switch is broken is worse than not having the switch.

Restoring dark mode later is real work rather than a toggle: the colours
would have to move to `modus-themes-common-palette-overrides`, which
names palette entries that each theme resolves for itself. Recorded here
so the size of that job is known before anyone starts it.

`modus-themes-headings` is kept with a note that custom.el's
`org-level-*` heights outrank it, so sizes are changed in one place.

### E — 15-workspace.el gives back what was not its

Three responsibilities left the module:

- **Unblocking Hunspell** → `03-spelling.el`. The blocking flag was
  already there; only the release lived elsewhere, which meant that
  removing the dashboard module silently disabled spell checking for the
  whole session while the header claimed "nothing else changes".
- **Deciding when startup has finished** → `01-ui.el`, which owns the
  session.
- **`denote-backlinks-display-buffer-action`** → `04-denote.el`. One
  Denote variable, advertised in the header as a "backlinks panel"
  feature of the dashboard.

### F — One startup hook instead of two paths

`01-ui.el` now publishes `my/desktop-after-startup-hook`, run once,
whether or not a session was restored. `desktop-after-read-hook` covers
the restore case, `emacs-startup-hook` covers a first launch with no
desktop file, and a flag makes sure only the first counts.

That deletes, from 15-workspace.el, two timers, a duplicated lambda and
a "does the Dashboard tab exist already?" test that existed only to stop
the two paths colliding. Consumers now say what they want and not when
they may have it. Both registrations are guarded, so a missing 01-ui.el
degrades to a visible message rather than to silence.

### G — A finding from the audit that was wrong

The audit claimed 15-workspace.el called `my/fixed-tab-goto` from
23-fixed-tabs.el, a module loaded later, and that it worked only by
timer accident. It does not: `my/fixed-tab-goto` is defined in
`01-ui.el`, which loads first. 23-fixed-tabs.el holds the routing advice
and the detach-to-frame commands, and nothing depends on it early. No
reordering was needed and none was done.

The dashboard's tab name is now a constant, `my/dashboard-tab-name`,
rather than a string repeated in three places.

### H — Stale header claims corrected

`C-c n o` for the dashboard (it is `C-c n f d`), and the "Denote
backlinks panel" feature entry.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02e — Dissolving 26-performance.el, plus structural fixes

### Context

`26-performance.el` was a module whose own header said it had to load
last so that its values would win over the modules that set the same
variables. That is the definition of a patch layer: it did not add
behaviour, it corrected other files from a distance. Every setting in it
had an obvious owner, and the reasoning attached to each — which was the
valuable part — sat where nobody would read it while editing the line it
described.

### A — Where each setting went

| Setting                                                 | New home                                                       |
| ------------------------------------------------------- | -------------------------------------------------------------- |
| `auto-revert-avoid-polling`, `dired-auto-revert-buffer` | `02-editing.el`, next to `global-auto-revert-mode`             |
| `jit-lock-defer-time`                                   | `02-editing.el`                                                |
| `org-image-actual-width`, `image-cache-eviction-delay`  | `11-org-appearance.el`                                         |
| `inhibit-compacting-font-caches`                        | `03b-fonts.el`                                                 |
| `gc-cons-threshold`                                     | `init.el` — see below                                          |
| The "what is deliberately not tuned" note               | `04-denote.el`, next to the Denote configuration it constrains |

The commentary moved with each setting rather than being summarised.

### B — `gc-cons-threshold` never worked

The module set 64 MB at load time. Modules load from the body of
`init.el`, so `after-init-hook` ran afterwards and set it back to 16 MB.
The value has been 16 MB throughout, apparently without trouble.

It is left at 16 MB, where it demonstrably works, with a comment
recording what was intended and why raising it is an experiment to run
and measure rather than a side effect of moving a setting between files.

### C — `27-denote-identifiers.el` loaded twice

`25-inbox-review.el` loads it by path when `featurep` reports it
missing, which it was, because `init.el` loaded 25 first. `init.el` then
loaded it again. Numeric order was the reason; dependency order is now
the rule for this pair, and the path fallback in 25 becomes what it was
meant to be — a fallback.

### D — Theme switching stacked themes

`load-theme` adds to `custom-enabled-themes` rather than replacing it.
`my/toggle-modus-theme` disabled the outgoing theme; `my/load-theme-light`
and `my/load-theme-dark` did not, so calling them directly left two
themes active with the result depending on application order. All three
now route through one function that disables what is enabled first.

The dark theme remains unusable for a different reason, which is now
recorded in the docstring rather than left to be rediscovered: `custom.el`
sets a dozen Org faces to literal light colours, and `custom-set-faces`
overrides theme faces. Deciding between palette overrides and a
light-only configuration is a separate change.

### E — Smaller corrections

- `C-c d t` ran `denote-rename-file-keywords` directly, bypassing the
  keyword prompt behaviour that `C-c n d k` gained in the previous
  session. It now runs `my/denote-keywords-edit` like the menu entry.
- `create-lockfiles` was set twice in `00-core.el`.
- `custom.el` carried `(package-selected-packages nil)`, which would
  make `package-autoremove` treat every installed package as an orphan.
  Removed; `package.el` repopulates it on the next install.

### F — TAB steps through candidates in keyword prompts

A candidate list appearing under a half-typed word reads as something to
step through, and TAB is the key hands reach for. In keyword prompts TAB
is now `vertico-next`, S-TAB is `vertico-previous`, and `vertico-insert`
— insert without exiting, which a comma-separated list needs between
entries — moves to M-TAB.

The rebinding is confined to these prompts, because TAB as insert is
what makes file-name completion work and that is worth more elsewhere
than stepping is. It is applied with `minibuffer-with-setup-hook`, the
built-in way to configure a single minibuffer session: the hook exists
for the duration of the call only, in the same way as the
`vertico-preselect` binding beside it, and nothing is added to
`minibuffer-setup-hook` globally. `:append` orders it after Vertico's
own setup so that the map it extends is Vertico's.

`my/notes-keyword-tab-navigates` set to nil restores Vertico's bindings
in these prompts.

### G — Not done

`denote-journal` was raised in the audit as the largest available
simplification. On the constraints it was measured against — identifiers
carrying migrated dates, collisions originating in the migration rather
than in note creation, a `:well-being:` property and a timestamped
append-to-today behaviour that the package does not have — it would
replace working code with configuration plus the same amount of custom
code on top. Recorded as considered and declined.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02d — One keyword prompt, in the commands that own it

### Context

Two problems, one cause.

A keyword that is a prefix of an existing keyword could not be created.
Typing `zuzi` at the Denote keyword prompt preselected `zuzia`, and RET
filed the note under `zuzia`. Vertico preselects the first matching
candidate and binds RET to `vertico-exit`, which submits the selected
candidate rather than the input; only the element at point is completed,
which is why placing the new keyword anywhere but last in the
comma-separated list was the way through.

Separately, `my/denote-base`, `my/denote-essay`, `my/denote-linked-note`,
`my/capture-promote-to-note` and Readwise quote promotion each read tags
with their own `read-string` and split on spaces. No completion at all,
so nothing stopped a typo becoming a keyword indistinguishable from a
real one — `filozofia` beside `flozofia` — and after three thousand
migrated notes that is not a hypothetical.

### A — `my/notes-read-keywords` in 05-notes.el

One function, called by every command in this configuration that asks
for tags. It delegates to Denote's own `denote-keywords-prompt`, which
completes against the vocabulary inferred from existing file names,
removes duplicates and returns a list. Writing a private prompt would
have meant these commands drifting away from
`denote-rename-file-keywords` at the first Denote release.

Keywords are consequently typed comma-separated now, as everywhere else
in Denote, rather than space-separated. A keyword may contain a space,
which the old prompt could not express.

Denote absent, the function falls back to the old space-separated
`read-string` rather than failing on a missing symbol.

### B — The prompt behaviour is bound, not hooked

`my/notes-keyword-preselect` (default `prompt`) is bound to
`vertico-preselect` around the call. The binding is dynamic, so it is
in force for the recursive minibuffer edit and for nothing else.

An earlier draft did this with a `minibuffer-setup-hook` in a separate
module, detecting keyword prompts by prompt text. That was rejected and
the reasoning is worth keeping: a module loading after the commands it
corrects, matching prompt strings to guess what is being asked, is a
repair layer rather than a fix. The prompt belongs to the command that
issues it.

Cost of the setting: reusing an existing keyword takes one more
keystroke, `<down>` then RET, or TAB (`vertico-insert`) to insert
without exiting, which is what a comma-separated list needs. Set to
`first` to restore Vertico's default; `M-RET` (`vertico-exit-input`)
submits the input as typed either way and needed no configuration in the
first place.

### C — `my/denote-keywords-edit`, and why a wrapper

`C-c n d k` ran `denote-rename-file-keywords` directly, and that
function is Denote's — there was no local function to correct. The
wrapper adds the binding and calls the command with
`call-interactively`, so which file is acted on, how front matter is
rewritten and what is confirmed all remain Denote's, and remain correct
when Denote changes them. `12-transient.el` points `k` at the wrapper.

### D — Essay project tag

`my/denote-essay` read its project tag with `read-string` and put it
into the keyword list verbatim. That is the keyword least tolerant of a
typo, since it is what later gathers the essay's material, so it now
goes through the same completing prompt and accepts more than one.

### E — Files touched

- `05-notes.el` — helper, wrapper, three call sites
- `06-capture.el`, `24-readwise.el` — call sites, dependency noted in
  their commentaries; both already load after 05-notes.el
- `12-transient.el` — `k` retargeted

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02c — Link tooltips: a directory scan per mouse movement

### Context

Hovering the mouse over a link in a note froze Emacs for a noticeable
interval. The freeze appeared only recently, and only over links.

Denote registers a `:help-echo` **function** for its Org link type.
Org copies whatever `:help-echo` holds into the `help-echo` text
property: a string is produced once during fontification, a function is
called by redisplay on every pointer movement onto or across the link.
The function, `denote-link-ol-help-echo`, resolves the identifier with
`denote-get-path-by-id`, which calls `denote-directory-files`, which
walks the tree with `directory-files-recursively`. Denote caches none
of this.

The cost is therefore one full recursive scan of `~/notes/` per pointer
movement. This is unnoticeable at a few hundred notes and unusable at
several thousand — which is what the Obsidian migration produced. No
recent commit introduced the freeze; the file count crossed the
threshold at which an always-present cost became visible.

### A — `modules/30-link-tooltips.el`

Replaces the parameter rather than the function, through the documented
`org-link-set-parameters` API, so nothing is advised or redefined in
Denote and a Denote upgrade cannot silently undo or conflict with it.

`my/link-tooltip-style` selects between:

- `identifier` — the link target, no file system access. Default.
- `path` — the resolved path, memoised for
  `my/link-tooltip-cache-seconds` (30). One scan per burst of hovering
  instead of one per pointer movement.
- `default` — parameter set to nil, Org supplies its own `LINK: ...`
  text, built at fontification time.

`identifier` is the default because the tooltip is informational and
the link's title is already on screen: the path answers a question that
is rarely being asked, at the price of the most expensive operation in
the note collection.

Only the tooltip changes. `:follow` is untouched, so opening a link
still resolves the identifier against the current state of the tree and
a note moved between devices by Syncthing is always found. The worst a
stale tooltip can do is name a path that has since changed, and nothing
reads that text but the user.

### B — Why the cache is local to tooltips

`26-performance.el` states that nothing caches `denote-directory-files`,
because a stale cache in a tree Syncthing writes into would advertise
notes that no longer exist. That still holds. The cache here is keyed
by identifier, is consulted only by the tooltip, expires wholesale after
`my/link-tooltip-cache-seconds`, and is unreachable from any prompt,
backlink buffer or search. Failed lookups are cached alongside
successful ones: an identifier with no file behind it is a broken link,
and retrying the scan on every pointer movement is the cost being
removed.

### C — Reading the link under the pointer

The identifier is taken from the `htmlize-link` text property, which
`org-activate-links` writes and which Denote's own tooltip function also
reads. A line-bounded regexp scan is kept as a fallback for buffers
fontified by something other than `org-activate-links`. Neither path
touches the file system, and neither cost grows with buffer size.

### D — Menu

`T` under `C-c n v` (View), appended after `e` via `my/transient-append`,
so an absent `12-transient.el` leaves the module working and silent.

Switching to or from `default` changes a decision Org makes while
fontifying, so `my/link-tooltip-set-style` calls `font-lock-flush` in
the current buffer; other open Org buffers pick the change up when they
are next refontified.

### E — Not addressed here

`denote-excluded-directories-regexp` is `"inbox"`, so any `.git`,
`.stversions` or attachment directory inside `~/notes/` is still walked
by every Denote scan. Whether that matters is a measurement, not a
guess:

```elisp
(benchmark-run 3 (denote-directory-files))
(length (denote-directory-files))
```

If the file count is far above the number of real notes, the exclusion
regexp — owned by `25-inbox-review.el` — is the next thing to widen,
and the gain applies to every prompt and backlink buffer rather than to
tooltips alone.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-02b — ODT/DOCX export

### A — `modules/29-writing-export.el`

Text that leaves Emacs had only one route out: PDF. A chapter going to a
supervisor needs an editable format.

Org exports to ODT and LibreOffice converts to DOCX, rather than pandoc
converting Org to DOCX in one step. Pandoc is the obvious choice and was
tested first; two findings ruled it out. Its Org reader is a
reimplementation that does not support `#+INCLUDE:` with a heading target
— it warns and omits the content — and ignores `:only-contents t`, which
is exactly how 20-transclusion.el writes INCLUDE pairs, so an assembled
manuscript would export short without failing. And it renders citations
with its own citeproc, so the same source could produce one apparatus in
the PDF and a different one in the DOCX, with the difference visible
only in the copy already sent.

Output lands in the project's export directory when the file declares
`#+project:`, otherwise mirrors the silo structure. The project
dependency is optional: without 28-writing-projects.el everything goes
to the notes tree.

ODT is kept as a first-class output rather than only an intermediate.
Word has opened ODT since 2007 and OnlyOffice reads it natively; DOCX
earns its conversion step only when the document is coming back edited.

### B — Denote link filter fixed for non-LaTeX backends

`my/--filter-denote-link` matched `\href{}{}` and returned an empty
string for anything else. That is correct for LaTeX and destructive
everywhere else: in ODT and HTML the transcoded link does not match, so
the filter deleted the link _and its description text_. Prose would have
gone missing from every ODT export, silently.

The filter now recognises the LaTeX, ODT and HTML shapes and falls back
to stripping tags while keeping the words.

### C — `my/office-check-setup`

Every failure here is quiet: a missing ox-odt exports nothing, a missing
LibreOffice yields an ODT where DOCX was requested, and a non-CSL
citation processor produces a document with no bibliography. Modelled on
`my/csl-check-setup` for the same reason.

_Not compiled or run: written without an Emacs available. The pandoc
limitations above were tested directly; the ox-odt path was not._

---

## Session 2026-08-02 — Writing Projects: note creation, mention filtering

### A — `my/writing-project-new-note`

Joining a project previously meant creating a note, then adding it in a
second step, which left the `#+project:` keyword to be remembered by
hand. One command now asks for project, section and title and writes
the rest: the keyword, the Denote tag, and the hub link.

Notes are created in `my/writing-project-note-directory` (`pks/`), not
in the project directory. A chapter draft is still knowledge — searched,
linked and transcluded with every other note, and useful after the
project is finished. Only the organisational layer lives under
`~/projects/`.

### B — Mentions now exclude members

New notes carry the project slug as a Denote keyword so that the
ordinary Denote commands can find them, which means a member also
satisfies the mention search and appeared in both lists. The mention
listing subtracts current members, leaving exactly the notes that could
still be promoted — the only reason to read that section.

The keyword can be turned off with `my/writing-keyword-new-notes`, at
the cost of chapters being reachable only through their hub.

### C — `my/writing-project-refresh-titles`

Hub links are `[[denote:IDENTIFIER][Title]]`, and identifiers never
change, so renaming a note breaks nothing. The caption is a copy of the
title taken when the link was written and does go stale. This resyncs
captions from current titles; purely cosmetic, nothing depends on them.

This does not extend to `#+INCLUDE:`, which takes a path and does break
on rename. Assembling a manuscript needs identifiers resolved to paths
at export time, which belongs to the export layer.

### D — Membership was already additive; now it says so

`my/writing-project-add-note` read the existing `#+project:` list and
appended, rather than overwriting, from the start. The behaviour was not
stated anywhere, so it was neither guaranteed nor obvious. The append is
now its own function with a docstring explaining why: a note is
routinely material for more than one text, and silently dropping an
older membership would be worse than any duplication.

### E — Smaller changes

- Project prompts default to the current buffer's project.
- Section prompts share one helper instead of being written out twice.
- `my/writing-project-refresh-mentions` had leftover point manipulation
  from an earlier draft and re-opened the hub buffer to save it.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-01b — Writing Projects, corrections

### A — `org-clock-persist-file` conflict removed from 04-denote.el

The previous session enabled clock persistence in
`28-writing-projects.el` but left `(setq org-clock-persist-file nil)`
in `04-denote.el`, which loads earlier. `org-clock-persistence-insinuate`
writes to that file on every clock change, so a nil file name would have
failed on the first clock-in. The block is now inert and says which
module owns the setting.

### B — Module 28 moved into numeric load order in init.el

It was loaded between 24 and 25. Nothing depended on the position, but
26-performance.el asks to load last among modules touching the same
variables; it sets none that 28 sets, so numeric order is both correct
and honest about the dependency.

### C — Interface strings translated to English

Transient labels, hub template headings, echo-area messages and prompts
were written in Polish. Everything in this repository is English,
including strings the interface shows.

Hub heading names are now `defcustom` (`my/writing-heading-*`) rather
than constants, since hub files are read and edited by hand and may as
well be in the language they are written in. English defaults. Changing
one after projects exist orphans that section in every existing hub,
which is documented at the definition and in function_helper.

### D — API and correctness fixes in module 28

- Day arithmetic no longer goes through `time-to-days`, which is not
  reliably loaded; it is computed from `org-time-string-to-time` and
  `float-time` directly. Overdue deadlines now report as such instead
  of being clamped to zero.
- Front matter is read from a live buffer when one exists, so a hub
  whose target was edited and not yet saved reports its own value
  rather than the copy on disk.
- Link insertion is one function (`my/writing--append-link`) instead of
  being open-coded twice with slightly different point handling.
- `my/writing-project-rebuild-materials` adds newly found identifiers
  to its own known-set as it goes; a note listed twice in the scan
  results was previously inserted twice.
- Progress reports links that resolve to no file as `unresolved`
  instead of silently counting fewer files, which would have hidden a
  deleted note or a changed identifier.
- Added `my/writing-clear-char-cache`, needed after toggling
  `my/writing-count-with-pandoc` since cache keys are modification
  times and toggling the counter does not change any file.

### E — function_helper.org

New section `#writing-projects`. The main menu overview now lists `p`
alongside `l` and `z` as dynamically appended, and names
`my/transient-append` as what makes a missing module harmless.

_Not compiled or run: written without an Emacs available._

---

## Session 2026-08-01 — Writing Projects, Phase 1

### Context

Managing a long-form text — tasks, deadline, time spent, which notes
belong to it — had no home. `my/denote-essay` created a flat note with
a static template and nothing else; `templates/project.org` described a
module (`13-project-management.el`) that does not exist, alongside
`my/denote-create-project` and `org-kanban`, neither of which exists
either. That directory is dead and is dealt with separately.

### A — `modules/28-writing-projects.el`

A project is a directory under `~/projects/` holding one hub file named
after it. The written text is not there: it stays in the Denote silos
and carries a `#+project:` line. The project directory holds only the
organisational layer, because notes are knowledge that outlives the
project while the hub is scaffolding that dies with the deadline.

Membership and mention are separate relations with separate mechanisms.
A journal entry keyworded `licencjat` records that something about the
thesis happened that day; it is not a chapter. Membership is a
`#+project:` keyword plus a link in the hub, mention is the Denote
keyword alone, and the two are listed in different sections.

The hub is the fast path and the keyword is repair data. Reading one
file is instant; scanning 3700 notes for a property is not, so the scan
exists only as a rebuild command.

`#+project:` is a front-matter keyword rather than an Org property
because Org properties live under a heading and Denote notes usually
have none, which would force `#+PROPERTY: PROJECT foo`. A keyword line
matches what Denote already writes and is greppable from a shell.

Progress is measured only over files linked under Materials → Tekst,
on pandoc-exported plain text, cached by modification time. Source
notes are excluded because they are not the deliverable, and the Org
source is not counted because front matter and markup can be a fifth of
a file while a publisher counts what the reader receives.

There is no drafting/editing phase flag. The two alternate between
sessions, so the flag would be wrong most of the time; instead the
progress line changes meaning once the target is passed, reporting an
excess to cut rather than a daily quota.

### B — `org-agenda-files` narrowed to hub files

05-notes.el pointed it at three silos plus the capture file. The silos
hold no tasks, and the TODOs in `docu/` are documentation examples that
should never appear as work — so every agenda build was reading some
3700 files to find nothing, or worse, to find examples. Now it is the
hub of every project. Personal tasks are not carved out as an
exception: a project named "Życie" is a project like any other.

The setting in 05-notes.el is deleted rather than left to lose on load
order.

### C — Clock configuration

Clocking is opt-in per heading, so enabling it cannot leak into
unrelated Emacs use. `org-clock-persist` becomes `'history` — a writing
session outlives an Emacs session, and a clock left running through a
crash can then be resolved against the file's modification time. Idle
handling covers walking away (`org-clock-idle-time`, prompt on return)
and falling asleep (`org-clock-auto-clockout-timer`).

Under Wayland none of this is fully reliable: Org can ask macOS and X11
how long the _user_ has been idle, but under Wayland it can only ask
Emacs, so reading in a browser with an Emacs frame focused counts as
work. A D-Bus query to GNOME Mutter answers the same question and is
included, disabled by default and marked unverified.
`org-time-stamp-rounding-minutes` is set to 5 so that correcting a
CLOCK line by hand with S-<up> moves by a useful step — manual
correction is the fallback whenever idle detection cannot be trusted.

## Session 2026-07-31 — Decoupling Menu Extension Between Modules

### Context

Asking whether the Zotero module could be used without the Readwise
one exposed a dependency chain nobody had written down:

    25-inbox-review  -> anchor "r"  -> contributed by 24-readwise
    24-readwise      -> anchor "z"  -> owned by 12-transient
    12-transient     -> my/zotero-menu       -> defined in 18-zotero
    18-zotero        -> my/insert-reference  -> defined in 17-bibliography

Two different kinds of coupling are tangled together here, and only
one of them is a problem.

---

### A — `modules/12-transient.el` — `my/transient-append`

#### The failure mode

Feature modules add their entries to the shared menus with
`transient-append-suffix`, which needs an anchor: an existing key to
append after. Several anchored on a key contributed by _another
optional module_.

`transient-append-suffix` signals when the anchor is absent. That
happens during module loading, so it aborts `init.el` partway and
leaves the rest of the configuration unloaded — turning "I removed a
module I do not use" into a broken Emacs. The error names the
appending module rather than the missing one, so the cause is not
apparent from the message.

The worst instance: `25-inbox-review` anchored on `"r"`, a key added by
`24-readwise`. Dropping Readwise broke inbox review.

#### The fix

`my/transient-append` degrades instead of signalling. A missing
prefix, a missing anchor, or a key already bound in that prefix leaves
the entry out and reports it — which is the right outcome, since an
entry whose neighbour does not exist has nowhere meaningful to sit.

All six call sites converted; no bare `transient-append-suffix`
remains outside `12-transient.el`. `25-inbox-review` now anchors on
`"z"`, which `12-transient` owns, so it no longer depends on Readwise
being installed.

The wrapper is idempotent, which removed a second piece of
boilerplate: the paired `transient-remove-suffix` calls and `unless
(transient-get-suffix ...)` guards that each module carried to make
re-evaluation safe during development.

#### Coupling that was left in place, deliberately

`18-zotero-transient.el` is the menu for `17-bibliography.el`: every
command in it comes from there or from citar, which that file
configures. The dependency runs one way — 17 knows nothing about 18 —
so the functionality works without the menu but not the reverse. That
is ordinary layering, not a defect, and is now stated in the module
header so it is not mistaken for one.

`12-transient.el` also names `my/zotero-menu` directly. Transient
resolves suffix commands at invocation rather than at definition, so a
missing module 18 does not break loading; the entry simply reports an
undefined command when pressed. Noted as a conscious exception rather
than fixed.

---

### B — `modules/18-zotero-transient.el` — Maintenance group

Adds `c` (check citation keys in notes), `C` (rename a citation key)
and `?` (check CSL export setup) to the Zotero menu, so the
bibliography maintenance commands added in the previous session are
reachable from the menu rather than only from `C-c b c` and `M-x`.

---

## Session 2026-07-30 — Obsidian Migration: Inbox Review

### Context

Roughly 3,300 journal notes and 442 non-journal notes were converted
from an Obsidian markdown vault to Org/Denote by external Python
scripts. The journal notes went straight into the `journal` silo, one
file per day, matching what `my/denote-journal` produces. The
non-journal notes did not: they are a mixed bag of fleeting notes,
course material, book cards and drafts, and each needs a human decision
about whether it belongs in `pks`, in `docu`, in the Zettelkasten, or
nowhere. They were therefore written to `~/notes/inbox/`, a staging
folder, and this session added the module that works through it.

---

### A — `modules/25-inbox-review.el` — Review queue for migrated notes

A `tabulated-list-mode` buffer listing every note still in the inbox,
with columns Date / Status / Tags / Source folder / Title, and
single-key actions on the note at point: preview, edit, accept into a
silo, promote into the Zettelkasten, edit tags, reject.

The structure follows `24-readwise.el` deliberately — same
`tabulated-list-mode` base, same global (not buffer-local) sort key,
filter string and preview window, for the reasons documented there:
`define-derived-mode` resets buffer-local values, and the list is
rebuilt after every action, so a buffer-local sort or filter would be
silently discarded each time. The active filter is shown in
`mode-line-process` so a narrowed list cannot be mistaken for a
complete one.

Two columns exist only because the migration produced them.
`:source_path:` records the note's original vault folder, which carries
real classification information (`00 Studia/Rok II/...` is `docu`
material, `00 ZK/...` is not), and `Status` surfaces the Obsidian
`status: draft` field that 117 of the notes carry.

#### A1 — Why the inbox is not a silo

`denote-directory` is the notes root, so every subdirectory under
`~/notes/` is visible to every Denote command and dashboard. Half-
reviewed material appearing in searches would defeat the point of
staging, so the module sets

    denote-excluded-directories-regexp = "inbox"

which also covers `inbox-odrzucone/` as a substring — intentionally,
since rejected notes should be even less visible than pending ones.

#### A2 — Rejection moves, it does not delete

`k` moves the note to `~/notes/inbox-odrzucone/` rather than deleting
it. Several hundred decisions taken over weeks will include mistakes,
and a folder that gets emptied once at the end costs nothing.

#### A3 — Accepting a note repairs journal links to it

The migration left 135 unresolved `[[wikilink]]` targets in the
converted notes, and the journal silo contains its own unresolved links
pointing at non-journal notes that did not exist in Org yet. Resolving
those at conversion time was impossible: the note might be rejected.

So it happens on accept instead. `my/inbox--fix-journal-links` scans the
journal for `[[Title]]` and `[[original-md-filename]]` — including
`#heading` and `|alias` variants — and rewrites them to
`[[denote:IDENTIFIER][...]]`. A cheap `search-forward` containment test
in a temp buffer runs before any file is visited, so the scan does not
open 3,300 buffers per accept.

This runs without confirmation. At several hundred accepts a prompt
each time would be noise, and the rewrite is unambiguous: it only ever
replaces a link naming this exact note.

#### A4 — Extraction: carving part of a note into a new one

`my/inbox-extract` (`C-c X` in inbox notes) is the counterpart to
promoting a whole note. Many fleeting notes contain one paragraph worth
keeping inside three that are not. The command takes the region, or the
subtree when point is on a heading, or the paragraph otherwise; writes
it to a new Denote note in a chosen silo with `:extracted_from:`
recording the origin; and leaves a `denote:` link in place of the
extracted text, so the source keeps its context instead of quietly
losing a passage.

Not bound to `C-c x`: that is `my/zotero-menu` globally, and a
minor-mode map would shadow it in exactly the buffers where a
bibliography lookup is most likely. `C-c X` was unbound repo-wide.

#### A5 — Menu placement

The submenu is appended to `my/notes-tools-menu` (`C-c n t i`), not to
the top level, per the rule stated in `function_helper.org`: new
integrations belong under Tools. The `unless (transient-get-suffix ...)`
guard makes reloading the file idempotent, as in `24-readwise.el`. The
anchor is Readwise's `r` when present and Zotero's `z` otherwise, so
the append survives reordering or removal of that module.

---

### B — Conversion scripts (external, kept in the repo for provenance)

Three pandoc behaviours corrupted output silently before they were
found, all worth recording because they will recur with any future
markdown import:

1. `yaml_metadata_block` treats a `---` fenced block _anywhere_ in the
   document as YAML metadata, not just at the top. Notes using `---` as
   a section divider therefore failed to parse, or had a section eaten.
2. A `---` line directly under text is a setext heading underline; one
   directly above text is a table separator. Both silently restructure
   the document. Fix: pad standalone `---` lines with blank lines
   before conversion.
3. `blank_before_header` and `blank_before_blockquote` require a blank
   line before `#` and `>`; without one, headings and callouts written
   flush against the preceding paragraph are folded into it as plain
   text. Obsidian renders them anyway, so the source looks fine.

The reading flags are now
`markdown-auto_identifiers-yaml_metadata_block-blank_before_header-blank_before_blockquote`.
465 of the 3,284 journal files were affected by 2 and 3 and were
re-converted and replaced after the fix.

---

## Session 2026-07-30 — Citation Export and Key Checking

### Context

Citations worked inside the editor but had never been exported. Making
that work exposed a chain of silent failures, and one structural
hazard worth guarding against permanently.

---

### A — `modules/17-bibliography.el` — CSL export

Citar configured three of the four org-cite processors: insert, follow
and activate. The fourth, which decides what a citation becomes on
export, was absent, so Org fell back to the `basic` processor — a
plain "(Author, Year)" in English, with no footnote and no
bibliography.

CSL rather than biblatex, because the deliverables include ODT and
EPUB as well as PDF and biblatex exists only inside LaTeX. CSL note
styles handle `ibid.` properly: the specification defines the `ibid`,
`ibid-with-locator`, `subsequent` and `near-note` positions, and
chicago-notes-bibliography implements them.

#### The silent failures found on the way

Every one of these produced a wrong or absent result rather than an
error, which is why `my/csl-check-setup` exists at all:

- **Wrong variable name.** `org-cite-export-processor` (singular) is
  buffer-local and set by a `#+cite_export:` keyword; assigning it
  globally does nothing. The global setting is
  `org-cite-export-processors` (plural), an alist keyed by backend.
- **A 404 saved as a style file.** `curl -O` without `--fail` wrote
  the server's error body, leaving a readable 14-byte
  "chicago-note-bibliography.csl". Citeproc parsed an empty style and
  the export died far from the cause with `Wrong type argument:
numberp, nil`. The CSL repository had renamed the file to
  `chicago-notes-bibliography.csl`.
- **Locales never configured.** `org-cite-csl-locales-dir` was unset,
  so citeproc used the en-US-only locales bundled with Org inside the
  Nix store and rendered a Polish document with English terms.
- **A setq without its defvar.** The locales assignment survived a
  round of edits while its `defvar` did not, so loading the module
  raised `Symbol's value as variable is void` and aborted `init.el`
  partway — leaving the checker itself undefined.

`my/csl-check-setup` therefore validates _content_, not just presence:
file size and an expected opening tag catch the 404 case, and the live
values of the locales directory and the processor alist are compared
against the intended ones, since the two can disagree.

#### Not a bug: `????` in place of a year

Traced to an empty `Date` field in Zotero, with the year misfiled
under `Original Publisher`. The same "no date" appeared in OnlyOffice
output from the same record — both tools were reporting the data
accurately.

---

### B — `modules/17-bibliography.el` — Citation key checker

`my/cite-check-keys` (`C-c b c`) scans the notes tree for citation
keys absent from the bibliography and lists each with clickable
locations. `my/cite-rename-key` replaces one across all scanned files.

#### Why

Better BibTeX derives keys from metadata, so correcting a year rewrote
`marksDziela11844` into `MarksDziela11960` — in an item already cited.
Disabling "Regenerate citation key when item changes" prevents
recurrence but does not repair existing drift, and pinning keys
individually only protects the items one remembers to pin.

The resulting `NO_ITEM_DATA` is visible, but only in a produced
document. A text can therefore be finished and correct-looking while
carrying dead references.

#### Implementation notes

- Keys are extracted only from within a matched `[cite:...]`, so an
  email address or an Org macro elsewhere in the prose cannot be
  mistaken for one. Verified against locators, prefixes, `/t` and
  `/na` variants, multiple keys in one citation, and two citations on
  one line.
- The key pattern excludes delimiters rather than enumerating allowed
  characters, because Better BibTeX keys may contain characters this
  configuration has no reason to predict.
- `my/cite-rename-key` rewrites only inside citations for the same
  reason: keys frequently look like ordinary words.

---

## Session 2026-07-29 — Org-transclusion Review

### Context

The org-transclusion setup had not been touched since the module was
written, while the documentation note describing it dated from October
2025 and described a keybinding scheme that no longer exists. Reading
the module for that update surfaced three defects worth fixing.

---

### A — `modules/20-transclusion.el` — Cursor jump, export safety, temp-buffer cost

#### A1 — Point was thrown to the end of the buffer on every insert

All three insert helpers ended with `(goto-char (point-max))`. That is
the end of the _buffer_, not the end of the text just inserted, so
adding a transclusion in the middle of a draft moved the cursor to the
bottom of the file every time.

The three helpers were also near-identical, differing only in the two
format strings. Both problems are fixed by one
`my/--transclusion-insert-pair`, which records the end of the inserted
region in a marker — a plain integer would be invalidated by
`org-transclusion-add` inserting the source text ahead of it — expands
the transclusion, and returns point to that marker.

Trailing whitespace in the generated `#+transclude:` lines and the
doubled space in `:only-contents  t` went with it.

#### A2 — Export could duplicate content or fail outright

The module inserts a `#+transclude:` / `#+INCLUDE:` pair: the first
works in the editor, the second at export time. That pairing is
sound, but nothing prevented exporting while transclusions were
_active_ — and then `org-transclusion-add` has already inserted the
source text into the buffer, so `#+INCLUDE:` pulls the same text a
second time.

Separately, transcluded regions carry a read-only text property, and
the Org exporter is documented as sensitive to it. Issue #86 in
nobiot/org-transclusion reports an export ending with a read-only
complaint and producing no file, and a comment in the package source
states that export may require the buffer to contain no read-only
elements.

`my/transclusion--collapse-before-export` on
`org-export-before-processing-functions` removes live transclusions
first. This is lossless: removal collapses each block back to its
`#+transclude:` keyword, and `A` re-expands afterwards.

The previous documentation note told the user to disable
transclusion-mode manually before exporting, which is the same fix
performed by hand and easy to forget.

#### A3 — `org-mode` enabled in a temp buffer for a regexp scan

`my/--org-file-headings` enabled `org-mode` in its temp buffer and
then searched with a plain regexp, so the mode bought nothing while
costing a full Org initialisation on every wizard invocation.
Removed.

Deliberately kept in `my/--extract-paragraphs`, where
`forward-paragraph` does depend on Org's paragraph definitions.

#### Reviewed and left alone

- `my/--ensure-custom-id` opens the source file with
  `find-file-noselect` and never kills the buffer, so every wizard run
  leaves one behind. This interacts with the desktop trim in
  `01-ui.el`, where those buffers count toward the limit. Left as is
  because an open source buffer is often wanted — the next step after
  transcluding a heading is frequently editing it — but worth
  revisiting if the buffer list starts filling with files never
  deliberately opened.
- `my/--extract-paragraphs` computes positions in a temp buffer and
  then uses them in the buffer returned by `find-file-noselect`. The
  two agree unless the file is already open and modified. Fragile
  rather than wrong; a correct version would locate the paragraph in
  the target buffer instead.
- The module hooks its submenu on with `with-eval-after-load
'12-transient` plus `transient-remove-suffix`, where the later
  modules (19, 22, 24) append directly behind a `transient-get-suffix`
  guard. Both work; the inconsistency is noted for a future tidy-up
  rather than churned now.

---

### B — Documentation note rewritten

The note describing transclusion usage dated from 2025-10 and had
drifted badly:

- Every keybinding it listed (`C-c t a/A/t/m/r/R`, from
  "06-keybindings.el") no longer exists. `C-c t` is now the tab-bar
  prefix, and transclusion lives under `C-c n i t`.
- The wizard, the `<<target>>` paragraph anchors and the
  `#+transclude:` / `#+INCLUDE:` pairing — the substance of the
  current implementation — were absent entirely.
- A comparison table claimed export "works", which A2 shows is only
  true with the workaround in place.

Rewritten around the current commands, with the anchor side effect
stated plainly (the wizard writes `CUSTOM_ID` and `<<target>>` into
source files it was never asked to open), the export caveat, and
workflow sections for philosophical and technical notes.

The workflow section draws the distinction the earlier note lacked:
signatures record where a thought came from, links record what it
connects to, and transclusion records what you want in front of you
while writing. Only the third is about drafting, which is why a draft
assembled from transclusions is disposable while its sources are not.

---

## Session 2026-07-28b — Readwise Import

### Context

Readwise holds highlights from books, with personal commentary
attached to each. The aim is a triage pipeline: import raw material,
review it, promote the worthwhile quotes into `pks` as proper notes,
and let the raw files become irrelevant.

An earlier hand-rolled import existed but was abandoned. Looking at
one of its output files showed why it was unsatisfying, and those
findings shaped this design.

---

### B — `modules/24-readwise.el` — Review and promotion

#### What changed

`my/readwise-review` (`C-c r r`) lists imported books that still have
unprocessed quotes; selecting one lists that book's quotes.

Book list is a `tabulated-list-mode` buffer with sortable columns —
unprocessed count, total, author, import date, title. Sorting and
alignment come free, so this ended up shorter than the hand-drawn list
it replaced. `mouse-1` opens a row; `S` or a header click re-sorts;
`/` filters; `g` rebuilds.

Quote list offers four actions, from the keyboard or from per-quote
buttons:

| Key | Effect                                                 |
| --- | ------------------------------------------------------ |
| RET | create a note, stay in the list                        |
| o   | create a note and show it beside the list              |
| z   | create a note, then run the Folgezettel commands on it |
| a   | add the quote to an EXISTING note as evidence          |

Quote lines show the Readwise URL as a clickable button.

#### Consumed versus cited

`a` needed a distinction that did not exist. A quote can be _consumed_
— a note IS that quote, nothing left to do — or merely _cited_, where
a note about the book quotes it as evidence. Citing must not hide the
quote, since it remains available to become a note of its own.

They are told apart by the marker written into the note:
`:RW_ID: rw-N` for consumed, `#+name: rw-N` for cited. The pks scan
classifies on that, and cited quotes stay listed, marked `[CYTOWANY]`.

Without the distinction, quoting a passage in a book note would
silently remove it from review — the failure mode this was designed
around.

#### Embedding rather than linking

The promoted note carries `RW_ID`, `RW_URL`, `SOURCE_AUTHOR`,
`SOURCE_TITLE` and `SOURCE_LOCATION` in a property drawer, and does
not link to the imported file. That file is disposable by design, so a
link would eventually dangle.

#### Processed-state detection

`my/readwise--promoted-ids` scans pks once and classifies every
`rw-<id>` it finds. Because promotion writes the id into the note, pks
is the single source of truth, and it survives losing the import
directory entirely — which an index kept beside those disposable files
would not.

One pass over pks rather than a grep per quote: a book can hold
hundreds of highlights, so per-quote scanning would be quadratic.

#### When the list is marked and when it is rebuilt

`RET` and `a` only mark the used quote — dimmed, labelled, disarmed —
because both are for working down the list, where a rebuild would lose
the position.

`o` and `z` rebuild instead, so the consumed quote disappears rather
than lingering struck through. That is affordable precisely because
attention moves to the new note anyway, leaving no position to
preserve.

The action buttons hold a marker pointing at the quote button rather
than their own copy of the record, so the done state lives in one
place and marking it disarms all five entry points at once.

#### Sort and filter persist

Both are held in globals rather than buffer-locals.
`tabulated-list-sort-key` is buffer-local and cleared by
`define-derived-mode`, so a chosen sort was lost on every return from
a book.

`/` narrows the list as you type, redrawing from `post-command-hook`
inside the minibuffer; `C-g` restores the previous filter, `C-/`
clears it. Author and title are matched as one string, so a search
need not know which field a word lives in — the case that prompted it
being the same author recorded as "Emil Cioran" in one book and
"Cioran Emil" in another.

A persistent filter that were invisible would make a partial list look
complete, so the active one appears in the mode line and is named in
the message after a rebuild.

#### Parsing

Regexp-based rather than `org-element`: these files are generated by
the importer in the same module, so their shape is known exactly and
the full parser would only buy tolerance for variation that cannot
occur. The regexps were checked against the first real import (92 and
239 highlights) and extracted every quote, location and URL, with note
counts matching an independent count.

#### Bugs found and fixed during this work

- The books keymap was `defvar`-ed after `define-derived-mode`, which
  creates `NAME-map` itself when the symbol is unbound. The later
  `defvar` is a no-op on an already-bound variable, so every binding
  in the book list would have been silently lost.
- The note window was remembered buffer-locally. Rebuilding the quote
  list re-runs its major mode, which cleared the value and made the
  next promotion split a third window instead of reusing the second.
  Introduced by the rebuild-on-open change and caught in the same pass.
- The filter variable was defined below `my/readwise-review`, which
  reads it — byte-compilation would report a free variable.

#### Fixed in the importer alongside

`#+identifier:` was derived from the import time, so all 89 files
produced by one run claimed the same identifier. The field has no
function outside `denote-directory`, and a duplicate is worse than
none — it would collide the moment a file was moved into the notes
tree — so it is no longer written.

#### Multiple authors: deliberately not parsed

Readwise's `author` is free display text with no separator convention;
one book arrived as "Neil BrowneStuart M. Keeley". Splitting it
heuristically would misfire on double-barrelled names, particles and
initials, so the importer passes the field through unchanged and
correction happens in Readwise. The structural answer, if it is ever
wanted, is to record a Citar key on the promoted note and let Zotero
be authoritative for bibliography rather than duplicating an unreliable
string.

### A — `modules/24-readwise.el` (new) — Importer

#### What changed

`my/readwise-sync` (`C-c r s`, `C-u` for a full re-import) pulls from
the Readwise export API into one Org file per book in
`~/Downloads/readwise/`. `my/readwise-open-directory` (`C-c r o`)
opens that folder. Both also under the notes menu at `C-c n t r`,
beside Zotero — the two are external-service integrations feeding the
same bibliographic workflow.

Token comes from `auth-source` (`machine readwise.io login apikey`).

#### Why the files sit outside the notes tree

`denote-directory` is the notes root, so anything beneath it is
visible to every Denote command, dashboard and search in this
configuration. Adding a `readwise` silo there would have meant
threading exclusions through roughly seven separate call sites. Raw
material awaiting triage is not part of the collection, so it lives
outside: invisible by default rather than visible-with-exclusions.

That also makes the files disposable, which is safe here because no
local knowledge is stored in them. Personal commentary lives in
Readwise's own `note` field on each highlight and returns on every
sync, so a book file can be regenerated exactly.

#### Why sync is two-phase

`updatedAfter` returns each book carrying only its _changed_
highlights. Writing that directly would replace a complete file with a
partial one. Phase one therefore discovers which books moved; phase
two re-fetches those books in full and rewrites their files. Each file
stays a pure function of Readwise's current state.

The sync timestamp is recorded _before_ fetching, so a highlight
changed mid-run does not fall into the gap between the fetch and the
timestamp and vanish from future syncs.

File names derive from `user_book_id` rather than import time, so
re-import overwrites instead of accumulating a copy per sync.

#### Format decisions, taken from the earlier attempt's failures

- **No heading per quote.** The Readwise id goes on a `#+name:`
  affiliated keyword. Headings exist to host property drawers, but
  these quotes have no natural title — one would have to be invented
  at import and discarded at promotion.
- **Personal notes go after the quote block, not inside it.** The
  earlier import nested a `*** Note` heading within `#+begin_quote`. A
  heading at column zero terminates the enclosing section, so the
  block is left unclosed as far as `org-element` is concerned, even
  though it still renders acceptably.
- **No template headings.** The earlier files carried empty `Główna
teza` / `Kluczowe koncepty` sections, which assumed the imported
  file was where the thinking happened. That conflicts with treating
  these files as a disposable inbox: it would invite putting work into
  a file that can be regenerated away.

#### Tracking what has been processed

Deliberately not tracked here. A promoted note in `pks` will carry the
highlight's `RW_ID`, so "have I already processed this quote?" is
answered by searching `pks`. One source of truth, and it survives
losing the import directory entirely — which an index file kept beside
the disposable files would not.

#### Not yet built, and why

The review interface and the promotion command are deferred until the
importer has run against the live API. Both depend on the exact shape
of the generated files, and only the highlight-level schema could be
verified from documentation; the book object's field names
(`user_book_id`, `readable_title`, `author`, `category`, `source`,
`unique_url`, `highlights`) are inferred and may need adjusting.

Writing the parser before seeing real output risks the two disagreeing
about a format that only one of them defines.

---

## Session 2026-07-28 — Persistent Branching Undo

### Context

The stated need was to recover text deleted before a save, which had
been framed as a version-control problem. It is not: a commit made at
save time records the state _after_ the deletion. The layers that
actually answer it are undo (within a session) and numbered backups
(between sessions), both of which existed but neither of which was
visible or persistent.

Emacs's built-in undo is already a branching tree — undoing an undo is
recorded as a change rather than discarding the branch, so every
previous buffer state stays reachable. What was missing was a way to
see that tree, and any memory of it across restarts.

---

### A — `modules/02-editing.el` — vundo and undo-fu-session

#### What changed

`vundo` bound to `C-x u`, replacing plain `undo` on that key, and
`undo-fu-session-global-mode` enabled. `undo-redo` bound to `C-S-z`;
`C-z` is left as plain `undo` so existing habits are unaffected.
`undo-outer-limit` added alongside the existing undo limits.

#### Why this pair rather than `undo-tree`

`undo-tree` is the closer analogue to Vim and has its own persistence,
but it _replaces_ Emacs's undo implementation. `vundo` visualises the
built-in one instead, which became practical once `undo-only` and
`undo-redo` were added to Emacs. Less surface area, nothing to
substitute.

The choice is also forced in one direction: undo-tree defines its own
undo data structures and is documented as incompatible with
undo-fu-session — the two cannot be combined. The leftover
`~/.emacs.d/undo-tree-history/` directory from an earlier
configuration is inert; nothing in the config has referenced
`undo-tree` for some time.

`undo-fu-session` is standalone despite its name: it has no dependency
on `undo-fu` and stores Emacs's built-in undo data unchanged.

#### Storage location

`undo-fu-session-directory` is set explicitly to
`~/.emacs.d/undo-fu-session/` rather than left at its default. It is
machine-local state, and the notes tree is synced by Syncthing —
placing it there would produce conflicts over files that are
meaningless on the other device.

Capped at `undo-fu-session-file-limit` (2000), since one file
accumulates per edited file indefinitely otherwise.

#### Known limitation

Restoration verifies buffer length and checksum first. A file changed
outside Emacs — a Syncthing update from another device — will not have
its history restored. This is correct behaviour rather than a defect:
the stored history would describe different text than what is on disk.

---

### B — New note: undo and backup history

Added `~/notes/docu/` note covering the four layers (undo, persistent
undo, numbered backups, git), the vundo keymap, and seven exercises
including a branch-recovery demonstration.

Two points recorded there because they had caused confusion:

- **A numbered backup is written on the first save of a buffer after
  visiting it, not on every save.** With `kept-new-versions` at 10 the
  kept files are roughly the last ten _editing sessions_. This is why
  consecutive `bookmarks.~N~` files are days apart.
- Backup file names contain `!`, which triggers history expansion in
  `bash`. The whole name must be single-quoted, not part of it.

---

### C — Correction: the vundo keymap as documented was wrong

The keymap written into section B's note and into `function_helper.org`
came from the package's ELPA summary rather than from `vundo-mode-map`,
and got three things wrong. Corrected against the source in both
places.

- **`q` and `C-g` were described as differing.** They are bound to the
  same command, `vundo-quit`. Both roll back by default: moving through
  the tree is provisional, and `RET` (`vundo-confirm`) is what commits
  it. The note claimed `q` kept the current state, which is the
  opposite of what happens. `vundo-roll-back-on-quit` set to nil gives
  the behaviour that was mistakenly described.
- **`n`/`p` were described as plain branch switching.** They only move
  at a branching point, between branches sharing a parent. On a linear
  stretch they do nothing, which reads as the keys being broken. The
  arrow keys are bound to the same commands and share the limitation.
  `a` (back to nearest fork) is the missing prerequisite step.

  Found while testing: the practical rule is stricter than "at a
  fork". The connecting lines are connectors, not paths — `n`/`p` jump
  vertically between nodes in the _same column_, since siblings are
  drawn one row apart at equal distance from their fork. You have to
  be standing directly above the target node; one step further right
  and the node below is no longer a sibling, so nothing happens. The
  drawing invites walking along the lines, which is not what the
  commands do. Documented with diagrams in both places.

- **`d` was described as diffing against a marked node**, omitting
  that with nothing marked it diffs against the _parent_ — so at the
  root, with no mark, there is nothing to compare and the command
  reports as much.

Also missing entirely: `w` (forward to next fork), `u` (unmark), and
the arrow-key bindings.

---

## Session 2026-07-27 — Fixed Tabs and Detachable Frames

### Context

Recurring activities (journal, dashboard, history) each had a natural
home tab, but only the dashboard actually went there on its own.
Reaching the journal meant clicking the Journal tab first, every time.
This session generalises the dashboard's behaviour into a routing
layer any command can opt into.

The same question from the other side — how to keep something visible
_while_ working on something else — turned out to want frames rather
than tabs, which section B covers.

---

### A — `modules/23-fixed-tabs.el` (new) — Route commands to named tabs

#### What changed

New module making registered commands switch to a named tab before
running. `my/fixed-tab-commands` maps commands to tab names;
`my/denote-journal` and `my/denote-journal-date` both route to
"Journal", so `C-c n c j` and `C-c n c J` now behave like
`C-c w d` already did: go to the tab, create it to the right of the
current one if missing, then do the work.

`my/fixed-tab-goto` was added to `01-ui.el` and three separate copies
of "find the tab or create and rename it" — in
`my/open-notes-dashboard`, `my/dashboards--goto-tab`, and now the
routing layer — were collapsed onto it.

#### Why advice rather than wrapper commands

Advice covers every route into a command at once: keybinding, `M-x`,
transient menu entry, and `emacsclient -n -e '(my/denote-journal)'`
from outside Emacs — which matters given the stated intent to trigger
these from the desktop environment eventually. Wrapper commands would
only cover whatever was rebound to them.

The advice is named `my/fixed-tab` so re-evaluating the module
replaces it rather than stacking copies, and
`my/fixed-tab-refresh-advice` removes routing before reinstalling, so
commands dropped from the alist stop being routed.

#### Why not `display-buffer-alist`

The declarative route (`display-buffer-in-tab` with a `tab-name`
entry) is the better tool for plain buffer display, and was
considered first. It does not fit these commands: `my/denote-journal`
finds a file, moves point to end of buffer and inserts a timestamped
heading. Routing only the display would leave the editing happening
wherever point already was.

It would also require `switch-to-buffer-obey-display-actions` to be
non-nil, since `find-file` reaches the buffer through
`switch-to-buffer`, which ignores `display-buffer-alist` by default.
That is a global change affecting every `find-file` in the
configuration — Protesilaos explicitly declines it for that reason,
while Mickey Petersen recommends it; the disagreement is itself a
signal that it is a matter of overall style rather than a local fix.
Switching tab first sidesteps the question entirely.

#### Tab placement

`my/fixed-tab-goto` binds `tab-bar-new-tab-to` to `'right` around
`tab-bar-new-tab` rather than relying on the global default, so
placement holds even if that option is customized later. It also skips
the switch when the target tab is already current, which would
otherwise push a redundant entry onto the tab switching history.

#### Not addressed

Two-frame separation (a "fixed" frame and a "working" frame) was
discussed and deferred. Fixed tabs are the smaller change and cover
the concrete complaint that prompted it; whether frames add anything
on top is best judged after living with tabs.

---

### B — `modules/23-fixed-tabs.el` — Detaching to a separate frame

#### What changed

Two commands added to the View submenu: `C-c n v f`
(`my/detach-buffer-to-frame`) puts the current buffer into a new frame,
`C-c n v F` (`my/detach-tab-to-frame`) moves the whole current tab,
splits intact, into one.

#### Why this belongs next to fixed tabs

They are the two halves of one distinction. A tab is a destination and
is exclusive: while it is shown, nothing else is. A frame is a separate
OS window, so it can sit on another monitor and be read _alongside_ the
work.

So the two mechanisms suit different things. Journal and Dashboard are
places you go to — tabs. A cheat sheet, or old entries being skimmed
through, is wanted beside the work — a frame. This also resolves the
"two Emacs windows" idea that prompted the previous session's
investigation: the need was real, but it was for occasional detachable
frames, not for a permanent second frame with its own buffer list.

#### Implementation notes

- `my/detach-tab-to-frame` wraps `tab-bar-detach-tab`, which exists
  from Emacs 28 (added 2021). It is checked with `fboundp` anyway, and
  refuses when only one tab exists, since detaching it would leave an
  empty frame.
- `my/detach-buffer-to-frame` moves rather than duplicates: it closes
  the originating window afterwards, unless that was the sole window in
  the tab — deleting that would take the tab with it.
- Monitor placement is not settable from Emacs; it belongs to the
  window manager. `my/detached-frame-parameters` sets a deliberately
  modest size, since these frames are for reading beside the main one.

---

## Session 2026-07-26 — Zettelkasten Layer, Silo Moving, and the Fixes That Followed

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

Sections C onwards came out of actually using the new Zettelkasten
layer against the tutorial exercises: several defects surfaced, and
following them led into the dashboard, history and session-persistence
work as well.

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
- same title _and_ identifier: keeping both is impossible because the
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

### Context

Continuation of the previous day's work, driven by using it: the
Zettelkasten layer built on 2026-07-26 was exercised against the
tutorial exercises and several defects surfaced, which in turn led to
the dashboard, session-persistence and tab-routing work below.

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
`\s-` is the whitespace _syntax_ class, and in a temp buffer
(fundamental mode, standard syntax table) a newline has whitespace
syntax — so `\s-*` consumed the end of the empty line and `\(.+\)`
captured the _following_ line. `[ \t]` would not have done this.

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

### F — `modules/21-dashboards.el` — History dashboards get their own tab and a reused preview window

#### What changed

The four history commands (`C-c n f h` `t`/`j`/`m`/`M`) previously
called `find-file` on the newest match, dropping the note into
whatever window was current, then showed `*Note History*` via a bare
`display-buffer` — so where either ended up depended on the layout at
the time.

Now they switch to a tab named `my/dashboards-tab-name` ("History"),
creating it beside the current tab when absent, reduce it to a single
window holding the list, and show the selected note in a window split
off to the right. Every subsequent selection reuses that window, so
clicking through the list replaces the note instead of accumulating
windows. Point stays in the list.

`*Note History*` gained a real major mode, `my/dashboards-nav-mode`
(derived from `special-mode`), with `n`/`p` to page through entries
previewing as they go, `RET`/`o` to preview the current line, and
`hl-line-mode` so the current entry is visible.

#### Why `switch-to-buffer` inside `with-selected-window`

`my/dashboards--visit` could have used `set-window-buffer`, which is
shorter. It uses `switch-to-buffer` wrapped in `with-selected-window`
because only that path records the outgoing buffer in the window's
history — which is what makes `C-x <left>` and `C-x <right>`
(`previous-buffer`, `next-buffer`) step back through previously
previewed notes, one of the stated goals.

#### Why the window is stored rather than declared

The alternative is a `display-buffer-alist` rule matching note files
and routing them to a side window. That is the idiomatic declarative
approach and is what a general solution would use. It was not chosen
here because the rule would apply to _every_ way a note gets
displayed, not just selections from this list, which is a much larger
behavioural change than the feature warrants. Since the button action
is our own code, addressing the window directly is both simpler and
narrower in effect.

The window is kept in the buffer-local `my/dashboards--preview-window`
and validated with `window-live-p` before every use, so `C-x 1`,
tab switching, or anything else that closes it is harmless — the next
selection splits a new one. It is reset to nil whenever the list is
rebuilt, since the layout is torn down at that point anyway.

#### Known limitations

- The preview window is not dedicated, so an unrelated
  `display-buffer` may reuse it. Dedicating it would also stop
  `find-file` from working inside it, which is the more common need:
  reading a note usually leads to following a link out of it.
- `previous-buffer` and `next-buffer` act on the selected window, so
  they require moving into the note window first, and they walk that
  window's whole history rather than only notes from the list.

---

### G — `modules/01-ui.el` — Session persistence: the three reported symptoms

Three complaints, investigated together because they share one cause
area: important buffers vanishing while throwaway ones survive, the
dashboard needing to be reopened manually after every restart, and no
sense of control over what is actually open.

None of them turned out to be a window-management problem, which was
the direction initially suspected.

#### G1 — Important buffers lost, transient ones kept

Inherent to a pure MRU policy. `my/desktop-trim-buffers` keeps the
`my/desktop-max-buffers` most recently _used_ file buffers, so a
reference document consulted daily but rarely selected keeps falling
out of the window, while a note opened once to check something
survives because it was touched most recently. Recency is a poor
proxy for importance.

The pin (`C-c d k`) already addressed this, but only per session and
only if remembered. Added `my/desktop-always-keep-regexps`: file name
regexps that protect permanently and without any action, defaulting to
`function_helper.org`. Matched against the full file name, so a whole
silo can be covered with `(regexp-quote my-notes-journal)`.

The simplest additional lever remains `my/desktop-max-buffers` itself,
still at 10. Note the interaction documented in this file's own
comments: it equals `desktop-restore-eager`, so raising it also
re-activates the lazy restore layer.

#### G2 — Dashboard gone after every restart

`desktop-save` only persists file-visiting buffers. The dashboard is
generated text with no file behind it, so it was never saved: the
Dashboard tab came back from the restored frame configuration, but its
window pointed at a buffer that no longer existed.

Rather than teaching `desktop` to serialise it — via
`desktop-save-buffer` plus a `desktop-buffer-mode-handlers` entry,
which would also require giving the buffer a real major mode — it is
rebuilt from `emacs-startup-hook` at depth 90. Regeneration is exact
rather than approximate here, because the content is derived from the
notes on disk anyway. `my/desktop-open-dashboard-at-startup` disables
it.

#### G3 — No sense of control over what is open

Added `my/desktop-show-protected` (`C-c d p`), which opens
`*Desktop Survival*` listing every open note buffer grouped by why it
survives — pinned, in a tab, always-kept, recent enough — and, last,
the ones that will be killed at the next save.

The trim was refactored so that both it and the report read one
`my/desktop--classify-buffers`. This matters more than it looks: a
report that drifted from the actual behaviour would be worse than
having none, since it would be trusted.

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
   _other_ tab, only the front `my/desktop-tab-protect-depth` (default 3) entries of that tab's own MRU buffer list (`wc-bl`, restored by
   `tab-bar` on tab switch — see `tab-bar--tab` in `tab-bar.el`).
2. **Manually pinned buffers**: new buffer-local
   `my/desktop-keep-buffer`, toggled with `C-c d k`, shown as a 📌 in
   `mode-line-misc-info`. Can also be set per-file via a
   `Local Variables` block.

#### Why — and a design correction

The first implementation protected a tab's _entire_ `wc-bl`/`wc-bbl`
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
it's _not_ important, so it should stay eligible for trimming.

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
- No documentation anywhere of the transient menu _contents_
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
all org-mode face _colors_ live exclusively in `custom.el` — it's the
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
never take X's _full_ history as the criterion. Emacs's own tracking
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
constraint: the appending module must load _after_ the module defining
the prefix, or the append targets a prefix that does not exist yet.

Two habits keep this safe: keep the appending modules numbered above
the prefix's module in `init.el`, and guard the append with
`transient-get-suffix` wrapped in `ignore-errors` (it signals when the
key is absent) so re-evaluating a module during development does not
stack duplicate entries. See Session 2026-07-26, A.

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
| Philosophy note types                               | `19-philosophy-notes.el` |
| Org-transclusion                                    | `20-transclusion.el`     |
| Dashboards                                          | `21-dashboards.el`       |
| Zettelkasten / Folgezettel sequences                | `22-zettelkasten.el`     |
| Fixed tabs (routing buffers to named tabs)          | `23-fixed-tabs.el`       |
| Readwise import and review                          | `24-readwise.el`         |
| **Migrated-notes inbox review, extraction**         | **`25-inbox-review.el`** |
| **Custom file load order, startup perf**            | **`init.el`**            |

**Before adding a new feature:** find the owning file in this table and
add the code there. If no file owns the concern yet, create a new
numbered file and add a row to this table.
