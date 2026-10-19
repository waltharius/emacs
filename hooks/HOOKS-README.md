# Pre-commit checks

## What git can and cannot do here

Git validates nothing by itself. A hook is a script git runs at a fixed
point in its lifecycle; if the script exits non-zero, the commit is
refused. All of the judgement is in the script, and the only judgements
worth automating are the mechanical ones.

So the honest division is:

**A script can check** whether a name a document mentions still exists,
whether a key a help text advertises is still bound somewhere, whether
an anchor a module points at is present in `function_helper.org`,
whether a symbol whose name says "internal" is called from another
file. These are decidable questions about two texts that must agree.

**A script cannot check** whether a docstring describes what the
function does, whether a CHANGELOG entry is honest, or whether a design
note is still true. Nothing here attempts it, and no check should be
written that pretends to.

The checks below exist because every one of them corresponds to
something that has already drifted at least once in this repository.

## Install

```sh
git config core.hooksPath hooks
```

Repository-local, written to `.git/config`, which home-manager does not
manage — unlike `~/.config/git/config`, which it symlinks read-only, so
`git config --global core.hooksPath` fails on NixOS. To set it for every
repository declaratively, use `programs.git.extraConfig.core.hooksPath`
in `git.nix`.

Bypass with `git commit --no-verify`, which is the right answer for a
rollback or a deliberately partial commit.

## The checks

| Check | Question | Blocks |
|-------|----------|--------|
| `parens` | Does every module still read as Lisp? | yes |
| `duplicates` | Is any symbol defined at top level in two modules? | yes |
| `anchors` | Does every `Docs: ...::#anchor` exist in `function_helper.org`? | yes |
| `functions` | Does every `Function: =my/x=` in the docs name a symbol that exists? | yes |
| `keys` | Does every key the `08-keybindings.el` help text lists get bound somewhere? | yes |
| `changelog` | Were modules staged without a `CHANGELOG.md` entry? | yes |
| `menus` | Is every command `function_helper.org` mentions reachable from a menu or a key — or listed, with its reason, under *Commands without a menu entry*? | yes |
| `modules` | Does every module keep the module contract -- headers, `provide`, every hard dependency declared, nothing core needing something optional, no circles? | yes |
| `codefolder` | Is every file a module names in `~/.emacs.d` (`locate-user-emacs-file`, `expand-file-name` with `user-emacs-directory`) a file of the repository, or one of the installation files 00-core.el reads? State belongs in `my/var-file`. | yes (since 2026-10-19) |
| `loader` | Is every file in `modules/` in init.el's list for `my/modules-load`, once, and does every `MyPKS-Switch` header name a mode its module defines? | yes (since 2026-10-19) |
| `menukeys` | Is any key of a menu given to two different commands -- in the menu's definition or by the modules adding to it? | yes (since 2026-10-19) |
| `private` | Is a `--` symbol called from outside its module? | yes (since 2026-10-18) |
| `personal` | Does a file git would commit contain a string from the private list `private-strings.txt` in the settings folder? | yes; *skipped*, with the path, when the list does not exist |
| `coverage` | Is every command a menu runs mentioned in `function_helper.org`? | no — advisory |

Run them by hand at any time:

```sh
python3 hooks/lint.py              # everything
python3 hooks/lint.py keys anchors # a subset
python3 hooks/lint.py --list
emacs -Q --batch -l hooks/parens.el
```

### What `menus` counts as reachable

A suffix of a transient menu (`("k" "Label" my/command)`), a key bound
with `global-set-key`, `define-key`, `keymap-set`, `bind-key` or a
use-package `:bind` pair (`("C-c u t" . my/theme-toggle)`), or a key
taken from an option through `my/settings-bind-key`.  A command
deliberately left to `M-x` goes into the first column of the table in
the section with `CUSTOM_ID: commands-without-menu`; that table is the
switch, and an entry there that is no longer an interactive command
fails the check too, so the list cannot rot.  Only commands the manual
mentions are checked: an undocumented command is the `coverage`
check's business.

### `modules`: the module contract

The rules are in `hooks/module_contract.py` and described in
`function_helper.org`, section *Module contract*.  Most of the check is
form: the first line, the `MyPKS-Requires` and `MyPKS-Optional`
headers, a `Docs:` line, `provide`.  The rest reads the code without
running it: which module defines each function and variable, and which
uses of them in other modules are not guarded by `fboundp`, `boundp`,
`featurep` or `with-eval-after-load`.  Those must be declared:

```text
24-readwise.el: uses my/zettel-adopt (and 1 more) from 22-zettelkasten.el
without a guard; add 22-zettelkasten to MyPKS-Requires, or test
(fboundp 'my/zettel-adopt) first
```

A pair the reader gets wrong goes into `MODULE_DEPENDENCY_OK` in
`lint.py`, with its reason.

### `personal`: the list is private, the check is public

This repository is meant to be public; what must not appear in it —
names, host names, addresses of the home network, private project names
— is itself private.  So the list lives in the settings folder
(`~/.config/mypks/private-strings.txt` by default; wherever 00-core.el
finds the settings: `MYPKS_DIR`, else `mypks-local.eld`, else
`~/.config/mypks/`), never in the repository:

```text
# One entry per line, matched ignoring case.
yourname
your-laptop
example.lan
# re: starts a regular expression; a comment is a line of its own
re:\bsecond-host\b
```

Every text file git would commit is read, line by line — tracked files
and untracked ones not ignored — except `csl/`, third-party files kept
unchanged.  Without the list there is nothing to look for: the check
reports `skipped` with the path it looked for, and does not block.  On
anyone else's machine that is the correct outcome; on the owner's — a
new machine, a settings folder that moved — it is the reminder that
nothing was checked, which an `ok` would hide.

A check that cannot run raises `Skip` in `lint.py`; the runner prints
`skipped`, never `ok`.

### Why `private` blocks only since 2026-10-18

Twenty-one violations were catalogued in the 2026-08-31 audit. A
blocking check would have failed every commit until they were cleared,
and a hook that always fails is a hook that gets bypassed by reflex —
so it stayed advisory, reporting new violations against a known count.
The decoupling of 2026-10-16 brought the count to zero; since then a
new call to another module's `--` function stops the commit instead of
starting a new backlog.

### `menukeys`: a key two modules want

Modules add their menu entries while they load, with
`my/transient-append` and `my/transient-insert` (12-transient.el).  A
key already taken there keeps its first owner and the second entry is
left out -- in Emacs, a warning after start-up (since 2026-10-19), but
only once the configuration runs.  This check sees it at commit time:
it reads every `transient-define-prefix` and every addition in
`modules/` and fails on one key of one menu given to two different
commands.  A key taken over on purpose goes through
`my/transient-replace` and is skipped.

What it cannot see: an entry whose description is computed (a key
followed by a command and `:description`, without a label string), and
keys bound by packages inside their own menus.

### What `keys` cannot see

It reads the flat reference section of the help text only, stopping at
the transient menu tree. Menu keys are not global bindings and would
all look unbound.

It also only asks whether *something* binds the key, not whether it
binds it to what the text claims. A key moved from one command to
another passes. Catching that would mean parsing which command each
`global-set-key` names and comparing it to a prose description, which is
the point where a checker starts guessing.

`EXTERNAL_KEYS` in `lint.py` lists keys bound by a package rather than
by this configuration — Magit's `C-x g` and `C-x M-g` — since grepping
`modules/` for them correctly finds nothing.

### Exceptions

`DUPLICATE_DEF_OK` holds `vertico-preselect`: a valueless `defvar`
marks a symbol special for the file it appears in, so every file
binding an external variable dynamically needs its own declaration.

Both exception lists carry a reason next to each entry. An exception
list without reasons stops being a record of decisions and becomes a
way to silence checks.

## Which files are read

The module files git would commit: `git ls-files --cached --others
--exclude-standard -- modules/`, i.e. tracked files plus untracked ones
that are not ignored. A new module is therefore checked before its first
`git add`, while an ignored file is not checked at all.

The reason is Syncthing. Conflict copies named
`*.sync-conflict-<date>-<device>.el` appeared in `modules/`. `.gitignore`
already excludes them and `init.el` never loads them, yet a plain
directory listing picked them up, so `duplicates` reported every symbol
in them as defined twice and blocked every commit. A file git ignores is
not part of the configuration and has no business failing its checks.

Without git — an unpacked archive, or `ROOT` outside any repository —
both `lint.py` (`module_names`) and `parens.el`
(`parens--module-files`) fall back to every `.el` file on disk.

## Working tree, not staged content

The content checks read the working tree rather than what is staged.
The two differ when only some changes are staged, and then the hook
validates something that is not being committed.

This is a deliberate trade. Getting it exactly right means stashing
unstaged work for the duration of the hook, and a hook that moves work
around has failure modes worse than the one it fixes — losing an edit
to a checker is worse than checking slightly the wrong tree in a
repository where commits are whole-tree in practice.

The `changelog` check is the exception: it reads the staged file list,
because "was the CHANGELOG staged alongside the modules" is a question
about the commit itself.

## Adding a check

A new check is a function in `lint.py` returning a list of problem
strings, plus an entry in `CHECKS`. Two rules:

1. It must be decidable. If it needs to guess, it will produce false
   positives, and false positives are how a checker gets disabled.
2. It should correspond to something that has actually gone wrong. A
   check for a failure that has never happened costs attention on every
   commit and buys nothing.
