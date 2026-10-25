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

## Everything at once: check-all

`git am` runs no pre-commit hook, and the hook runs neither the tests
nor anything else that takes time.  After applying patches, or before
pushing:

```sh
bash hooks/check-all            # parens, lint, hook tests, every tests/test-*.el
bash hooks/check-all loader     # only the test files whose name has "loader"
```

Each test file runs in its own `emacs -Q --batch` with the packages
installed for this user (`~/.emacs.d/elpa/`); nothing is installed.
Tests that load modules go through `tests/helper.el`, which loads
`00-core.el` and the modules named in a sandbox -- a temporary HOME,
settings folder and `~/.emacs.d` -- so a run neither reads nor writes
the real notes and settings.  A file that fails prints why: ERT's
condition, or, when it did not load, its error lines (a missing package
reads "Cannot load <package>").

What "passed" means, since 2026-10-20 (audit of that date: a selection
that matched nothing, or a file without tests, passed):

- a name that selects no test file fails -- a typo is not a pass;
- a test file that runs no test fails;
- skipped tests are counted, and the last line says `result: passed,
  nothing skipped`, `result: passed, N test(s) skipped -- not
  everything was checked`, or `result: FAILED`;
- with `MYPKS_STRICT_TESTS=1` a skipped test fails the run.  The
  workflow sets it: every package the tests need is installed there,
  so a skip can only hide something.  Locally a skip stays a skip --
  a missing package or program is reported, not counted against the
  code;
- a test file that runs longer than `MYPKS_TEST_TIMEOUT` seconds (600
  by default; coreutils' `timeout`) fails as "timed out": a test caught
  in a loop, or waiting for an answer (standard input is `/dev/null`),
  fails the run instead of hanging it.

The checkers' own tests (`tests/hooks/test_*.py`, Python unittest) run
after lint, as "hook tests".  Continuous integration runs the same
script.

One difference between the two entry points: `pre-commit` skips the
parens check when no `emacs` is on PATH; `check-all` fails then -- a run
meant to check everything has not.

## On GitHub: the workflow

`.github/workflows/checks.yml` runs on every push and pull request, on
GitHub's machines; the result is the mark next to each commit and the
*Actions* tab of the repository.  Three jobs:

| Job | What it runs |
|---|---|
| `check-all (Emacs 29.1 / 30.2 / 31.1)` | `tests/ci-packages.el` installs the packages the tests load (Denote, no-littering, and transient from the archives rather than the built-in one, as the owner runs it), cached for a week; then `bash hooks/check-all` |
| `secrets` | Gitleaks over the whole history, all branches (pinned release, checked against its published SHA-256); a false positive goes into `.gitleaksignore` by its fingerprint, with a line saying why |
| `shell` | ShellCheck on `hooks/pre-commit`, `hooks/check-all` and `hooks/check-weekly` |

The actions it uses are pinned to the commit of a release, so a moved
tag cannot change what runs.  The workflow file itself is checked with
actionlint before delivery.  On a private repository GitHub counts the
minutes against the account's free monthly allowance; a run takes a few
minutes per job.

## Once a week: check-weekly

The checks above install only the packages their tests need.  Some
checks need every package of the configuration, and take longer; they
run once a week, Mondays 04:17 UTC, in `.github/workflows/weekly.yml`,
and by hand from *Actions → weekly → Run workflow*:

| Step | What it shows |
|---|---|
| First start on a clean machine (`tests/weekly/install.el`) | every module loads and every package installs from the archives, as at a new user's first start; nothing is cached, so a package withdrawn or renamed in the archives shows here |
| Byte compilation (`tests/weekly/compile.el`) | every module compiled after the whole configuration loaded; a warning not listed in `tests/weekly/compile-warnings.txt` fails -- a misspelt function, a wrong number of arguments, a variable never defined, something obsolete |
| Declarations (`tests/weekly/declarations.el`) | every `declare-function` form in `modules/` names a file that defines the function with the same argument list (Emacs's `check-declare`); a declaration left behind after a function moved or gained an argument fails. Exceptions, with their reason, in `tests/weekly/declare-exceptions.txt` |
| Module tests (`tests/weekly/test-modules.el`) | for every module: it loads alone with what it declares; the others load without it; its switch goes off and on leaving nothing behind and doubling nothing (TESTING.org, *Every module tested*, part 2) |

On a machine where the configuration runs, every package is installed
already, so the last two run by hand too (the first installs, so it is
left to the workflow):

```sh
bash hooks/check-weekly             # byte compilation and module tests, about 3 minutes
bash hooks/check-weekly compile     # only the byte compilation
bash hooks/check-weekly declarations # only the declare-function check
bash hooks/check-weekly 24-readwise # the module tests of one module
```

The same sandbox as check-all: the real notes, settings and
`~/.emacs.d` are neither read nor written.

The warning list started with the 28 warnings of 2026-10-22 (Emacs 29.3).
Emacs quotes names in its messages with curved quotes where it can
show them and with a grave accent and an apostrophe elsewhere; both the
list and the warnings are compared in the second form, so the same
warning matches on every machine (on the owner's machine every listed
warning first came out as NEW for this alone).
The compile step writes its report (`NEW`, `gone`, `FAILED`, the
`compiled` line) to a file of its own, named by `MYPKS_COMPILE_REPORT`,
which check-weekly prints: read from the mixed output of Emacs, a `NEW`
line glued to text a package wrote to standard error without a newline
was not shown, leaving "1 new" without the warning (2026-10-24).
A warning shown as `NEW` is fixed in the module, not listed: an
obsolete name replaced, a missing `require` added, a fault fixed.  The
list is not a way to quiet a warning; a line goes into it only when the
fix has to wait, with the reason in BACKLOG.org (*Compiler warnings*).
Decided 2026-10-22, at the first NEW warnings of Emacs 31.1: one of the
three was a real fault in every version (a `cl-return-from` with no
block to return from), which only that compiler sees.  A
listed warning no longer seen is reported as `gone` and does not fail
the run -- the versions differ; its line is removed when the warning
was fixed.  `MYPKS_COMPILE_BASELINE=write bash hooks/check-weekly
compile` adds every warning of this Emacs to the list.

## The checks

| Check | Question | Blocks |
|-------|----------|--------|
| `parens` | Does every module still read as Lisp? | yes |
| `duplicates` | Is any symbol defined at top level in two modules? | yes |
| `anchors` | Does every `Docs: ...::#anchor` exist in `function_helper.org`? | yes |
| `functions` | Does every name in a `Function:` or `Functions:` line of the docs (each `=my/x=` before the first `|`, continuation lines too) exist? | yes |
| `keys` | Is every key the `08-keybindings.el` help text lists the key of a binding form in a module -- `global-set-key`, `define-key`, `keymap-set`, `keymap-global-set`, `bind-key`, `local-set-key`, or a `("KEY" . command)` pair? | yes |
| `changelog` | Were modules staged without an entry in a month's file of the change log, `changelog/YYYY-MM.md`? (`CHANGELOG.md` alone, the table of months and the lessons, is not an entry.) | yes |
| `changelogs` | Does every session heading in `changelog/` have the form `## Session YYYY-MM-DDx — Title`, sit in the file of its month, newest first, with a label used once; is every month's file in `CHANGELOG.md`'s table, and no session left in `CHANGELOG.md`? | yes (since 2026-10-20k) |
| `menus` | Is every command `function_helper.org` mentions reachable from a menu or a key — or listed, with its reason, under *Commands without a menu entry*? | yes |
| `modules` | Does every module keep the module contract -- headers, `provide`, every hard dependency declared, nothing core needing something optional, no circles? Is `MyPKS-Tests: weekly` only on modules whose code calls nothing that changes files, runs a program or reaches the network (a list of names in `hooks/module_contract.py`, `CHANGES_FILES`, recognised as the head of a form or as `#'NAME`, not in comments, strings or quoted data)? | yes |
| `codefolder` | Is every file a module names in `~/.emacs.d` (`locate-user-emacs-file`, `expand-file-name` with `user-emacs-directory`) a file of the repository, or one of the installation files 00-core.el reads? State belongs in `my/var-file`. | yes (since 2026-10-19) |
| `loader` | Is every file in `modules/` in init.el's list for `my/modules-load`, once, and does every `MyPKS-Switch` header name a mode its module defines?  Is every slot (`MyPKS-Provides`) lower-case words, on an optional module, with at most one module per slot starting on a new machine (since 2026-10-25q)? | yes (since 2026-10-19) |
| `menukeys` | Is any key of a menu given to two different commands -- in the menu's definition or by the modules adding to it? | yes (since 2026-10-19) |
| `private` | Is a `--` symbol called from outside its module? | yes (since 2026-10-18) |
| `personal` | Does a file git would commit contain a string from the private list `private-strings.txt` in the settings folder? | yes; *skipped*, with the path, when the list does not exist |
| `coverage` | Is every command a menu runs mentioned in `function_helper.org`? | no — advisory |
| `groups` | Reads the tables under `* Groups` and `* Map` of `MODULES.org`: is every module in the map once, in one of the groups, and does every `MyPKS-Requires` point to a module of the same or a lower group?  Reads hard dependencies only; a guarded use is not seen. | no — advisory until the move (2026-10-25r) |
| `tests` | Which modules does no test file name in its `;; Tests:` header, and is a module staged without any of its test files? Modules marked `MyPKS-Tests: weekly` are left out of both. (TESTING.org) | no — advisory |

A check that cannot read its input -- git cannot list the files, outside
a repository -- raises `Skip` and prints `skipped` with the reason; it
never prints `ok` for files it did not see (until 2026-10-20 three of
them returned an empty list there).

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
`featurep` or `with-eval-after-load`.  A guard counts only for the
branch where its test has shown the name present -- the `when` body,
the `if` THEN (ELSE when negated), the later `and` arguments; an
`unless` only when its body leaves (`user-error`, `error`); `fboundp`
guards the name it tests, `featurep` the whole module.  Those must be
declared:

```text
24-readwise.el: uses my/zettel-adopt (and 1 more) from 22-zettelkasten.el
without a guard; add 22-zettelkasten to MyPKS-Requires, or test
(fboundp 'my/zettel-adopt) first
```

A pair the reader gets wrong goes into `MODULE_DEPENDENCY_OK` in
`lint.py`, with its reason.

The reader itself is tested: `tests/hooks/test_module_contract.py`
holds a provider and a consumer module for each case, guarded and hard,
among them the seven an audit of 2026-10-20 found read as guarded
though they were not (an `if` that calls in its ELSE, `(when (not
(fboundp ...)))`, `(or ... t)`, a guard on one name and a call of
another, an `unless` that only warns, `symbol-value` of a quoted name,
a `defvar` with a string value, which the reader took for a bare
declaration).

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

It asks whether a binding form binds the key -- not, as until
2026-10-20, whether the quoted key appears anywhere, where a comment or
a docstring was enough (audit of that date). It does not ask whether
the form binds it to what the text claims: a key moved from one command
to another passes, and a binding in code that never runs counts. Catching that would mean parsing which command each
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
