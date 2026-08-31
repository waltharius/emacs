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
| `private` | Is a `--` symbol called from outside its module? | no — advisory |

Run them by hand at any time:

```sh
python3 hooks/lint.py              # everything
python3 hooks/lint.py keys anchors # a subset
python3 hooks/lint.py --list
emacs -Q --batch -l hooks/parens.el
```

### Why `private` is advisory

Twenty-one existing violations, catalogued in the 2026-08-31 audit. A
blocking check would fail every commit until the backlog is cleared,
and a hook that always fails is a hook that gets bypassed by reflex —
at which point it stops catching the things it was written for. It
reports, so new violations are visible against a known count. Move it
to blocking when the count reaches zero.

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
