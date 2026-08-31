# Emacs — a personal knowledge and writing system

A single-purpose Emacs configuration built around [Denote](https://protesilaos.com/emacs/denote):
daily journalling, a zettelkasten, long-form academic writing, and the
maintenance tooling that keeps a few thousand notes honest. Everything
is local — no cloud services, no external database, no sync layer other
than the file system.

## Written by LLMs — read this first

**Every line of Elisp in this repository was written by a large
language model.** Not assisted, not autocompleted: written. The person
whose configuration this is does not program in Elisp and would need
years to reach the level the modules here operate at, quite apart from
learning Emacs internals well enough to know what is possible.

What the human contributed is the part that decides whether any of it
is worth having: the requirements, the working habits the system is
shaped around, and — more than anything — the rejections. A large share
of the design notes in `CHANGELOG.md` record ideas that were built,
examined and thrown away, because a coarser division of an axis already
covered was not worth a new note type, or because a module turned out
to be a leaf of another module rather than a functionality of its own.
That judgement is human. The Elisp implementing it is not.

**How it is checked.** Quality, security and data privacy matter here,
so nothing goes in on one model's word. Code is cross-reviewed by
models from different companies, on the reasoning that independently
trained systems are less likely to share a blind spot than one system
asked twice. Design decisions are argued rather than accepted, and the
CHANGELOG exists partly so that the reasoning behind each one survives
the conversation that produced it. `tests/` and `hooks/` exist for the
same reason: mechanical checks do not get tired, and they do not agree
with you out of politeness.

**What that verification is not.** Several models agreeing is not the
same as review by an experienced Elisp programmer, and it is not a
security audit. Models share training data and can share mistakes. A
subtle bug that every reviewer's priors accept — a race in a hook, a
misused Org internal, an assumption that holds until a package updates
— survives cross-checking exactly as easily as it survives a single
review. Nothing here has been read by a person who could catch that
class of error.

So: **read this before running it.** That is ordinary advice for any
configuration off the internet, and it applies here with more force
than usual. The code touches your notes directory, commits to git on a
timer, and shells out to ImageMagick and LibreOffice. Those are
reasonable things for a notes system to do and bad things to run
unread.

**On privacy.** The notes themselves have never been sent anywhere —
the whole system is local by design, and that is much of its point. The
*configuration* is a different matter: writing it meant sharing this
repository with hosted models, so the code has been through them and
the notes have not. If that distinction matters to you, it is the one
worth knowing about.

This disclaimer is here because "written by an LLM" is information a
reader is entitled to before deciding whether to trust a codebase, not
because it is an apology. The code works, it is documented past the
point most personal configurations are, and its reasoning is written
down. Judge it on that.

## Where this came from

It started as two needs, and everything else grew around them.

**Writing a journal entry or a plain note has to be instant.** Not
"open an app, click New, choose a folder, type a title" — a key, a
prompt, and a cursor already in the right place. `C-c n c j` either
creates today's entry with its front matter written or appends a
timestamped heading to the one that exists, and the decision between
those two is not the writer's problem. Everything about note creation
here is measured against that: how many keystrokes, how many decisions,
how much of it can be inferred.

**Notes have to connect and accumulate without ceremony.** Linking is a
completing prompt over every note in every silo. A new note can be
created already linked in both directions. Existing notes are gathered
into hubs, into folgezettel sequences, into writing projects — each of
those a different shape of connection, none of them requiring the note
itself to be edited to join.

**The keyboard does everything.** There are no graphical menus in this
configuration and none are wanted. Every operation is a key sequence or
a transient menu, and a transient menu is a keyboard interface that
happens to be visible — you can click it, but that is not what it is
for. `which-key` exists to make the keyboard discoverable so that the
mouse never becomes the shortcut for "I forgot the key". The layered
`C-c n` tree is what makes forty modules' worth of commands reachable
without memorising forty prefixes.

**The notes are meant to be thought with later, by a machine as well as
a person.** This is why journal entries carry `#+schema:`, why metrics
are front-matter keywords with an explicit "absent means not measured"
rule rather than zeroes, why `#+project:`, `#+week:` and `#+language:`
exist as structured fields instead of prose. The intended reader of
that structure is a local LLM: the plan is to build a wiki and other
derived views over the collection, and to be able to ask questions of
it that span years. Structured, honest, machine-readable metadata is
what makes that possible later, so it is written now, while the note is
being made and the facts are known. The model configuration itself is
not here — it lives in a separate NixOS repository covering all
machines and servers.

Nothing in the system depends on the LLM existing. The metadata is
useful on its own — it is what the gaps report, the statistics and the
dashboards read — and if the analysis never happens, nothing was lost
except a few keywords.

## Read this before cloning

**This is not a starter kit, and it is not trying to be one.** It is
one person's working environment, shaped around one person's habits,
one language, one machine, and one way of thinking about notes. Several
decisions here are actively hostile to anyone who did not make them:

- **Default Emacs keys are rebound.** `C-f` starts an incremental
  search, `C-s` saves, `C-z` undoes, `C-x u` opens the visual undo
  tree. If twenty years of muscle memory matter to you, delete
  `modules/02-editing.el` before the first launch.
- **The interface language is mixed.** Code, comments and commit
  messages are English; docstrings are English; prompts, note templates
  and the philosophy note types are Polish. Journal front matter is
  written with `#+language: pl`.
- **Paths are assumed, not configured.** `~/notes/` with three silos, a
  planner directory, an inbox and an attachments folder. They are
  variables in `00-core.el`, but nothing checks whether the layout
  makes sense for you.
- **It assumes Linux.** Developed on NixOS with GNOME under Wayland.
  It should run elsewhere; the external tools it shells out to are
  named below and their absence degrades rather than breaks.

What is worth stealing is rarely the whole thing. Individual modules
are close to self-contained and several are useful on their own — the
transclusion wizard, the hub notes, the image compression ladder, the
identifier integrity checks, the transient menu extension mechanism.
Take those.

---

## Requirements

**Emacs 29 or later.** Uses `when-let*`/`if-let*` with the modern
semantics, `string-trim-right`, the list form of `encode-time`, and
`transient` as a package rather than as part of Magit.

**Packages** are installed from GNU ELPA and MELPA by `use-package`
with `use-package-always-ensure`, so the first launch downloads them.
Nothing is vendored and there is no lockfile.

| Area | Packages |
|------|----------|
| Notes | `denote`, `consult-denote`, `denote-explore`, `denote-sequence` |
| Completion | `vertico`, `orderless`, `marginalia`, `consult` |
| Org | `org-modern`, `org-transclusion`, `org-web-tools` |
| Bibliography | `citar`, `citar-denote`, `citeproc`, `pdf-tools` |
| Version control | `magit` |
| Appearance | `modus-themes`, `ef-themes`, `standard-themes`, `doric-themes`, `doom-themes`, `spacious-padding`, `lin`, `pulsar`, `visual-fill-column`, `default-text-scale` |
| Editing | `which-key`, `vundo`, `undo-fu-session`, `flyspell-correct` |
| Other | `keyfreq`, `nov` |

**External programs.** Each is looked up with `executable-find`, and a
missing one disables a feature rather than breaking the configuration:

| Program | Used for | Module |
|---------|----------|--------|
| `git` | auto-commit, `git mv`/`git rm` for notes | `07-git.el`, `05-notes.el` |
| `hunspell` | spell checking (Polish and English dictionaries) | `03-spelling.el` |
| `magick` or `convert` (ImageMagick) | image attachment compression | `31-org-images.el` |
| `libreoffice` / `soffice` | ODT → DOCX conversion | `29-writing-export.el` |
| `pandoc` | Obsidian migration script only | `convert_journal.py` |
| LaTeX | PDF export | `16-org-export.el` |

Optional and non-obvious: `keylog` (typing analytics) is not on any
package archive and must be installed by hand; `14-typing-analytics.el`
handles its absence.

---

## Expected file layout

```
~/notes/                    Denote directory — the root, so search spans all silos
├── journal/                daily entries          keyword: journal
├── pks/                    personal knowledge     zettelkasten lives here
├── docu/                   technical notes        keyword: docu
├── inbox/                  staging for migrated notes (excluded from Denote)
├── attachments/            compressed images      (excluded from Denote)
├── planner/                tasks.org, habits.org  (outside the silos)
├── csl-locales/            CSL locale files for citation export
├── pdf/                    PDF export destination
└── refs.bib                exported from Zotero via Better BibTeX

~/projects/<slug>/          writing-project scaffolding (not notes)
~/.emacs.d/                 this repository
```

`denote-directory` is `~/notes/` rather than any single silo, which is
what makes every Denote command search across all of them at once.
Silos are ordinary subdirectories; note-creating commands choose the
target explicitly.

---

## First run

```sh
git clone <this repo> ~/.emacs.d
emacs
```

The first launch installs packages and will be slow. Afterwards startup
time is printed to `*Messages*`.

Three things happen automatically on that first launch and are worth
knowing about in advance: directories under `~/notes/` are created if
absent, a capture file `~/notes/journal/captures.org` is written if
absent, and the Notes Dashboard opens once startup finishes.

If you want to try it without committing to the key rebindings, comment
out `02-editing.el` in `init.el`.

---

## How the configuration is put together

### Explicit load order

`init.el` loads every module by full path, in a hand-written sequence.
Not `load-path` plus `require`, and not a directory glob. The order is
part of the design and the file says why at each point where it is not
simply numeric.

The consequence to know when writing a module: `require` on a sibling
module does not work, because siblings are not on `load-path`. Modules
that need something from another one either guard with `fboundp` or
load by explicit path.

### Optional modules

Modules whose absence should degrade rather than break are loaded with
`load`'s NOERROR argument:

```elisp
(load (concat modules-dir "34-appearance.el") t)
```

Deleting such a file removes its commands and its menu entries and
leaves everything else working. Roughly a third of the modules are
optional. Note the limit: NOERROR suppresses "file not found", not an
error *inside* the file.

### Menu extension without coupling

`12-transient.el` defines the menu skeleton — `C-c n` and its
submenus. Feature modules add their own entries at load time through
`my/transient-append`, which does nothing (and says so) when the prefix
is missing, when the anchor key is absent, or when the key is already
bound:

```elisp
(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-insert-menu "L"
                       '("H" "Add to HUB" my/denote-add-to-hub)))
```

The rule that makes this safe: **anchor only on keys defined in
`12-transient.el` itself**, never on a key contributed by another
optional module. Anchoring on another module's key is how the Insert
menu silently lost four entries in August 2026.

Raw `transient-append-suffix` signals when its anchor is missing, and
signalling during module load aborts `init.el` partway through — which
turns "I deleted a module I do not use" into a broken Emacs, with an
error naming the wrong file.

### Naming

`my/` prefixes commands and functions, `my-` prefixes plain
configuration variables, and a double dash marks a symbol as internal
to its module. That last convention is currently violated by
twenty-one symbols; see *Known issues*.

### Documentation is part of every change

Two files are kept current with every commit:

- **`CHANGELOG.md`** — sessions newest-first, headed
  `## Session YYYY-MM-DDx — Title`, where `x` is a letter counting
  sessions within a day and is always present. It records reasoning and
  rejected alternatives, not just what changed. It is the longer half
  of this documentation and the part worth reading if you want to know
  *why* anything is the way it is.
- **`function_helper.org`** — user-facing reference for every command
  and menu, with `CUSTOM_ID` anchors. Modules point at it from their
  headers (`Docs: ~/.emacs.d/function_helper.org::#anchor`) and `C-c n h`
  opens it.

---

## Module map

Mandatory modules are loaded without NOERROR; deleting one breaks
startup. Optional ones can be removed.

### Foundation

| Module | | Purpose |
|--------|---|---------|
| `00-core.el` | required | Package system, silo paths, backup/autosave policy, persisted UI state, front-matter keyword helpers. 24 other modules depend on it. |
| `01-ui.el` | required | Interface, mode line, `desktop` session persistence, tab-bar, `my/fixed-tab-goto`. |
| `02-editing.el` | required | which-key, vundo, undo-fu-session, **and the rebound default keys**. |
| `02b-bold-marker.el` | required | Obsidian-style `word*` inline emphasis. |
| `03-spelling.el` | required | Hunspell, Polish and English. |
| `03b-fonts.el` | required | Per-silo fonts: journal Playpen Sans, pks Source Sans 3, docu JetBrains Mono. |
| `04-denote.el` | required | Denote itself, multi-silo setup, backlink window placement. |
| `08-keybindings.el` | required | Not where keys are defined — a reference buffer (`C-c h k`) plus a few helpers. |
| `12-transient.el` | required | The `C-c n` menu skeleton and `my/transient-append`. |

### Notes and writing

| Module | | Purpose |
|--------|---|---------|
| `05-notes.el` | required | Journal (today and backdated), plain notes, essays, linked notes, silo moves, the shared keyword prompt, week-day link lists. |
| `05b-journal-metrics.el` | optional | Structured daily metrics as front-matter keywords. |
| `06-capture.el` | required | Idea capture that records where it came from, and promotion to a full note. |
| `19-philosophy-notes.el` | required | Five note types: literatura, pojęcie, myśliciel, problem, mapa. |
| `20-transclusion.el` | required | `org-transclusion` wizard and live-sync editing. |
| `22-zettelkasten.el` | required | Folgezettel sequences via `denote-sequence`, scoped to `pks/`. |
| `33-denote-hubs.el` | required | Hub notes: curated link lists with descriptions, kept in chronological order. |
| `28-writing-projects.el` | optional | Project registry, membership by `#+project:`, progress tracking, clocking. |
| `29-writing-export.el` | optional | Org → ODT → DOCX via LibreOffice. |
| `31-org-images.el` | required | Image attachments with a compression ladder to a 300 kB budget. |
| `32-web-links.el` | required | Insert an Org link with the page title fetched. |

### Reading in, cleaning up

| Module | | Purpose |
|--------|---|---------|
| `17-bibliography.el` | required | Citar, `refs.bib`, CSL, org-noter, pdf-tools. |
| `18-zotero-transient.el` | required | The bibliography menu (`C-c x`). |
| `24-readwise.el` | required | Incremental import of Readwise highlights. |
| `25-inbox-review.el` | required | Review queue for notes migrated from Obsidian. |
| `26-maintenance.el` | required | Integrity checks, keyword inventory, keyword renames. |
| `27-denote-identifiers.el` | required | Duplicate identifiers, broken links, self-links. |

### Reports

| Module | | Purpose |
|--------|---|---------|
| `15-workspace.el` | required | The Notes Dashboard: clickable sections in columns, in its own tab. |
| `21-dashboards.el` | required | "This day in history" and "this day, every month". |
| `35-journal-gaps.el` | optional | Days with no entry, or an entry with no metrics. |
| `36-notes-stats.el` | optional | Collection statistics, two tiers: cheap from file names, expensive on demand. |

### Tasks

| Module | | Purpose |
|--------|---|---------|
| `37-tasks.el` | optional | Task capture without leaving the buffer, routed by `#+project:`; owns `org-agenda-files`. |
| `38-habits.el` | optional | org-habit setup, fast logging, history derived from journal file names. |
| `39-project-git.el` | optional | Remotes and staleness checks for project repositories. |

### Appearance and comfort

| Module | | Purpose |
|--------|---|---------|
| `09-theme.el` | required | Five theme collections, `<F4>`/`<F5>` cycling, choice persisted. |
| `10-visual-fill.el` | required | Single source of truth for wrapping. No other module may set `visual-fill-column-*`. |
| `11-org-appearance.el` | required | Org visual behaviour. Faces belong to `custom.el`. |
| `13-centered-writing.el` | required | Recentring that only fires while typing. |
| `23-fixed-tabs.el` | required | Routes chosen commands into named tabs, by advice. |
| `30-link-tooltips.el` | required | Cheap `denote:` tooltips — Denote's own freeze on large collections. |
| `34-appearance.el` | optional | Padding, shared faces, `lin`, `pulsar`, text scaling. |

### Infrastructure

| Module | | Purpose |
|--------|---|---------|
| `07-git.el` | required | Auto-commit *and push* on idle and on exit, for notes and for this repo. |
| `14-typing-analytics.el` | required | keyfreq and keylog. Data is gitignored. |
| `16-org-export.el` | required | PDF export and LaTeX preamble. |

---

## Keybindings

`which-key` is on: press a prefix and wait, and the rest is listed live.
`C-c h k` opens a hand-maintained summary. The menus themselves are the
primary interface — the global bindings below are shortcuts to the
things used most often.

### The menu

`C-c n` opens the notes menu:

```
c  Create      new note / journal today / journal for a date / essay /
               linked note / metrics / captures
f  Find        find file / grep / backlinks / dashboard / tag stats /
               random / history / journal gaps / statistics
i  Insert      link / linked note / time / date / week's days /
               transclusion / image / attachments / web link / hub
d  Document    rename / keywords / change silo / delete
x  Export      PDF / batch by any keyword / batch by all keywords / ODT / DOCX
v  View        centre text / writing mode / indent / emphasis markers /
               tooltips / theme / padding / detach to frame
t  Tools       Zotero / spelling / Readwise / inbox
l  Philosophy  five note types                     (19-philosophy-notes.el)
z  Zettelkasten                                    (22-zettelkasten.el)
p  Projects                                        (28-writing-projects.el)
!  Maintenance                                     (26-maintenance.el)
h  Function help — opens function_helper.org
```

Entries after `t` are appended at load time by their own modules, which
is why they disappear cleanly when a module is removed.

### Global

| Prefix | |
|--------|---|
| `C-c n` | notes menu |
| `C-c d` | Denote quick access: `f` find, `l` link, `b` backlinks, `r` rename, `t` keywords; also `s`/`k`/`p` for desktop session |
| `C-c v` | version control: `s`/`c` notes status and commit, `S`/`C` config, `d` diff, `h` history, `a` commit everything, `l` log |
| `C-c g` | Magit: `s` status, `l` log, `b` blame (plus `C-x g`) |
| `C-c t` | tabs: `n` new, `c` close, `o` switch, `r` rename |
| `C-c w` | workspace: `d` dashboard, `x` tag stats, `r` random note, `s` statistics |
| `C-c u` | appearance: `w` text width, `f` font size, `p` padding, `+`/`-`/`0` scale, `s` save scale to note |
| `C-c r` | Readwise: `s` sync, `r` review, `o` open folder |
| `C-c y` | typing analytics: `k` command frequency, `s` keylog status, `t`/`T` disable and re-enable |
| `C-c m` | `c` create submenu, `w` writing mode, `k` keywords |
| `C-c e` | `b` eval buffer, `r` eval region |
| `C-c o i` | open `init.el` |
| `C-c h k` | keybinding summary |

Single keys: `C-c a` agenda, `C-c c` capture, `C-c p` export to PDF,
`C-c x` Zotero menu, `C-c s` correct previous misspelling, `C-c S` add
to dictionary, `C-;` correct word at point, `<F4>`/`<F5>` cycle themes.

### Rebound defaults

```
C-f      isearch-forward        (not forward-char)
C-s      save-buffer            (not isearch)
C-z      undo                   (not suspend-frame)
C-S-z    undo-redo
C-x C-b  ibuffer
C-x u    vundo
M-Q      unfill region
```

`C-a` is stock `move-beginning-of-line`. It was `mark-whole-buffer`
until August 2026 — convenient once a week, in the way of a movement
command used hundreds of times an hour. Select-all is `C-x h`, which is
what the rest of Emacs already calls it.

---

## Note types and what they write

### Journal — today (`C-c n c j`)

Creates `~/notes/journal/IDENTIFIER--YYYY-MM-DD__journal.org` if today
has none, otherwise appends a `* HH:MM` heading to the existing file:

```org
#+title:      2026-08-31
#+date:       [2026-08-31 Mon 09:14]
#+filetags:   :journal:
#+identifier: 20260831T091412
#+language:   pl
#+schema:     2

* 09:14
```

No metrics placeholder. Metrics are front-matter keywords added later
by `C-c n c w`, so a file created without `05b-journal-metrics.el` is
simply a journal with no metrics rather than a template with a hole in
it.

### Journal — a specific date (`C-c n c J`)

Same shape, with the identifier clock zeroed (`T000000`) as this
configuration's marker for "the time of day was not recorded", and a
supplement heading carrying the real write time:

```org
* Uzupełnienie
:PROPERTIES:
:ADDED_AT:   [2026-08-31 Mon 21:40]
:EVENT_DATE: [2026-08-24]
:END:
```

If the day already has a journal, the heading is appended to it instead.

### Plain note (`C-c n c n`)

Title, keywords, silo. Denote writes its own four front-matter lines;
`#+language:` and `#+schema:` are appended afterwards rather than by
overriding `denote-org-front-matter`, so this configuration is not on
the hook for keeping Denote's format string in step with upstream.

### Essay (`C-c n c e`)

Title prefixed `ESEJ:`, keywords `esej` + `project` + the project
keywords, always in `pks/`, with a scaffold: Metadata, Essay Plan,
Bibliography, Working Notes.

### Philosophy types (`C-c n l`)

Five templates, Polish, in `pks/`: literatura, pojęcie, myśliciel,
problem, mapa.

### Hub (`C-c n i H`)

A note with the `hub` keyword whose body is a list of links with
descriptions. Membership is **derived**, never stored: a note is in a
hub because the hub links to it, and that link is the only record.
Entries are kept in identifier order and a hub out of order is sorted
before a new entry is placed.

### Transclusion (`C-c n i t`)

The answer to "I want this passage in two places without keeping two
copies of it". A wizard picks a note, then whole note / heading /
paragraph, generates a stable anchor for the target — `CUSTOM_ID` for a
heading, `<<target>>` for a paragraph — and inserts two lines:

```org
#+transclude: [[denote:20260715T101500::#some-heading]]
#+INCLUDE: "path" :only-contents t
```

`#+transclude:` is live: `org-transclusion` pulls the text into the
buffer for reading, and it can be made editable in place so that
changes go back to the source note. `#+INCLUDE:` is the static twin
used at export time, because the exporter does not understand
transclusion.

This is what makes composing a long piece out of existing notes
practical. A chapter draft can be assembled from paragraphs that stay
where they were written; the source note remains the single copy, and
editing it updates everywhere it appears. For anyone browsing this
repository for one idea to take away, this and the hub notes are the
two most portable.

Auto-transclusion on file open is deliberately off
(`org-transclusion-add-all-on-activate` is nil): on a collection this
size, opening a file with many transclusions would be slow enough to
notice. `g` in the submenu refreshes on demand.

Known limitation: `#+INCLUDE:` paths break when the target note is
renamed. Denote identifier links do not, which is why the live half of
the pair uses them.

### Capture (`C-c n c i`)

Appends to `~/notes/journal/captures.org` under `* Ideas`, recording
the note it was captured from and when. `C-c n c m` promotes an entry
to a full Denote note, carrying the source line across.

---

## What happens without being asked

- **Auto-commit and push.** Five minutes idle and on exit, for `~/notes`
  and for this repository. Notes get `Auto-commit: <date>`; the
  configuration does not — a config change is a decision worth
  describing.
- **The dashboard opens** once startup finishes.
- **Buffers are renamed** to note titles (`denote-rename-buffer-mode`).
- **Dired shows Denote name components** in distinct faces.
- **Wrapping and fonts are chosen per silo** when a note is visited.
- **The session is restored**, with a trim policy; pinned buffers
  (`C-c d k`) survive it.
- **Backups and autosaves are separated** by location — note backups go
  to `~/notes/.backups/`, everything else to `~/.emacs.d/backups/` — and
  ten versions are kept.

---

## Design principles

These recur, and most of them were learned by getting them wrong first.
`CHANGELOG.md` has the incidents.

**Derived, never stored.** A fact computable from another fact is
computed. Hub membership is not recorded in the member note; the
weekday is not written into a journal title; backlinks are not a front
matter field. Two copies of one fact drift, and the drift is silent.

**Structure identifies, prose does not.** A journal note is recognised
by its `journal` keyword and its date, never by its title or slug.
Titles are prose and must stay free to change. This was originally
wrong — eight places across four modules tested a `-journal` slug — and
the fix is why a journal can now be retitled to "Obrona licencjatu"
without disappearing from four reports.

**One owner per variable.** `org-agenda-files` belongs to `37-tasks.el`
and `28-writing-projects.el` delegates to it; `visual-fill-column-*`
belongs to `10-visual-fill.el` and nothing else may touch it. Two
modules setting one variable means the load order decides the
behaviour.

**Degrade, do not signal.** A missing optional module costs its own
features and nothing else. Menu entries skip, file lists filter,
missing helpers produce a sentence instead of a backtrace.

**Reuse upstream.** Denote's own prompts, link formats and rename
machinery are called rather than reimplemented, so this configuration
does not have to track their internals. Where a package already solves
a problem — `org-web-tools`, `org-transclusion`, `denote-sequence` — it
is used.

**Measure before optimising.** `denote-infer-keywords` stays on and
`denote-directory-files` is not cached globally, both deliberately: a
stale cache in a directory Syncthing writes into is a worse failure
than a slow prompt.

**Batch operations preview first.** Anything touching hundreds of files
offers a dry run.

---

## Known issues

From an audit on 2026-08-31, recorded rather than silently carried:

1. **Twenty-one privately-named symbols are called across module
   boundaries.** The double-dash convention has stopped being reliable.
   Worst case: `27-denote-identifiers.el` is a library by every measure
   and half its exported API is named as internal.
2. **`28-writing-projects.el` and `37-tasks.el` reference each other.**
   Both directions are guarded, but the arrow from `28` to its own
   extension is backwards; `28` already has the hook mechanism to avoid
   it.
3. **`18-zotero-transient.el` is a menu with no other content**, unlike
   every other module, which declares its menu at the bottom of its own
   file.
4. **`#+INCLUDE:` paths break on rename**; Denote identifier links do
   not. Known limitation of the writing-project and transclusion export
   path.
5. **The help text in `08-keybindings.el` is a hand-maintained snapshot
   of facts that live in three other places** — the bindings
   themselves, `which-key`, and `function_helper.org`. It has drifted
   twice. `hooks/lint.py` now catches keys it advertises that nothing
   binds, but a checker treats the symptom; generating the buffer from
   the live keymaps would remove the possibility.

## Repository contents

```
init.el                  module load order, with the reasoning
custom.el                Customize-managed settings; the faces block is
                         deliberately empty — see the note at the top
modules/                 the configuration
function_helper.org      user-facing command reference (C-c n h)
CHANGELOG.md             session log: what changed and why
tests/                   ERT tests, run with emacs -Q --batch
hooks/                   pre-commit consistency checks
convert_journal.py       one-off Obsidian → Denote migration script
ui-state.el              persisted UI choices (theme, sizes)
theme-state.el           persisted theme choice
.gitignore               privacy-oriented: session state, typing data,
                         undo history and desktop files are never committed
```

## Before committing a change

Automated. Install the hooks once per clone:

```sh
git config core.hooksPath hooks
```

Six checks then run on every commit — that modules still read as Lisp,
that no symbol is defined twice, that every `Docs:` anchor exists, that
every documented function still does, that every key the help text
advertises is still bound, and that modules were not staged without a
CHANGELOG entry. A seventh reports privately-named symbols crossing
module boundaries, advisory until the known backlog is cleared.

Run them by hand at any time with `python3 hooks/lint.py`; see
`hooks/README.md` for what each one can and cannot see.

## Licence

No licence has been chosen. Everything here is written for one person's
use; treat it as reference material rather than as something to depend
on.
