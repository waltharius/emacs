#!/usr/bin/env python3
"""Consistency checks for the Emacs configuration.

Every check here answers a question that has a mechanical answer.  None
of them judge whether prose is *correct* -- only whether a name a
document mentions still exists, whether a key it lists is still bound,
whether a symbol crosses a boundary its own name says it should not.

Run by hooks/pre-commit, or by hand:

    python3 hooks/lint.py            # all checks
    python3 hooks/lint.py anchors    # one check
    python3 hooks/lint.py --list

Exit status is 1 when any check fails, so it can gate a commit.
"""

import os
import re
import sys
import subprocess
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULES = os.path.join(ROOT, "modules")
HELPER = os.path.join(ROOT, "function_helper.org")
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
KEYS_FILE = os.path.join(MODULES, "08-keybindings.el")

DEF_RE = re.compile(
    r"^\((defun|defmacro|defvar|defvar-local|defcustom|defconst|defgroup"
    r"|defalias|define-derived-mode|define-minor-mode|transient-define-prefix"
    r"|transient-define-suffix|cl-defun)\s+'?([^\s()]+)",
    re.M,
)
SYM_RE = re.compile(r"\bmy[/-][A-Za-z0-9/_?<>=+*!-]+")

# ------------------------------------------------------------------
# Known, deliberate exceptions.  Each one needs a reason, not just an
# entry: an exception list without reasons becomes a way to silence
# checks instead of a record of decisions.
# ------------------------------------------------------------------

DUPLICATE_DEF_OK = {
    # A valueless `defvar' marks a symbol special for the file it
    # appears in.  Every file that binds an external variable
    # dynamically needs its own declaration, so this is correct Elisp
    # rather than a duplicate definition.
    "vertico-preselect",
}

# Keys listed in the 08-keybindings.el help text that are bound by a
# package rather than by this configuration, so grepping modules/ for
# them finds nothing and that is fine.
EXTERNAL_KEYS = {
    "C-x g",     # magit-status, Magit's own default
    "C-x M-g",   # magit-dispatch, Magit's own default
}


def module_names():
    """Return the module file names the checks should read, sorted.

    The files git would commit: tracked ones plus untracked ones that are
    not ignored, so a new module is checked before its first `git add'.
    Ignored files are left out -- a Syncthing conflict copy
    (`*.sync-conflict-*', ignored in .gitignore) lying in modules/ once
    made every symbol look defined twice and blocked every commit,
    although Emacs never loads it and git never sees it.

    Falls back to every .el file on disk when git is unavailable or ROOT
    is not a repository, e.g. an unpacked archive.
    """
    try:
        out = subprocess.run(
            ["git", "-c", "core.quotePath=false", "ls-files", "-z",
             "--cached", "--others", "--exclude-standard", "--", "modules/"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout
        names = {os.path.basename(p) for p in out.split("\0")
                 if p.endswith(".el") and os.path.dirname(p) == "modules"}
        # --cached still lists a tracked file deleted from the working
        # tree; there is nothing on disk to read for it.
        return sorted(n for n in names if os.path.isfile(os.path.join(MODULES, n)))
    except (OSError, subprocess.CalledProcessError):
        return sorted(n for n in os.listdir(MODULES) if n.endswith(".el"))


def modules():
    for name in module_names():
        yield name, open(os.path.join(MODULES, name), encoding="utf-8").read()


def code_of(text):
    """Return TEXT with the file header and comment-only lines removed."""
    body = text.split(";;; Code:", 1)[-1]
    return "\n".join(l for l in body.split("\n") if not l.lstrip().startswith(";"))


def definitions():
    """Map symbol -> [(file, line), ...] for every top-level definition.

    A valueless `(defvar NAME)' is a declaration, not a definition: it
    marks NAME special in its own file, and every file binding or setting
    another module's or package's variable needs one.  Skipped, rather
    than listed one by one in DUPLICATE_DEF_OK.
    """
    found = defaultdict(list)
    for name, text in modules():
        for m in DEF_RE.finditer(text):
            if m.group(1) == "defvar" and text[m.end():].lstrip().startswith(")"):
                continue
            found[m.group(2).strip("'")].append((name, text[: m.start()].count("\n") + 1))
    return found


# ------------------------------------------------------------------
# Checks.  Each returns a list of problem strings; empty means passed.
# ------------------------------------------------------------------

def check_duplicate_defs():
    """One symbol defined at top level in two modules."""
    problems = []
    for sym, locs in sorted(definitions().items()):
        if len(locs) > 1 and sym not in DUPLICATE_DEF_OK:
            where = ", ".join(f"{f}:{n}" for f, n in locs)
            problems.append(f"{sym} defined in {where}")
    return problems


def check_private_symbols():
    """A `--' symbol called from outside the module that defines it."""
    owner = {s: locs[0][0] for s, locs in definitions().items()}
    problems = []
    for name, text in modules():
        code = code_of(text)
        for sym in sorted(set(SYM_RE.findall(code))):
            if "--" in sym and owner.get(sym) not in (None, name):
                problems.append(f"{name} calls {sym}, private to {owner[sym]}")
    return problems


def check_anchors():
    """A `Docs: ...::#anchor' pointing at a CUSTOM_ID that does not exist."""
    if not os.path.exists(HELPER):
        return ["function_helper.org is missing"]
    helper = open(HELPER, encoding="utf-8").read()
    known = set(re.findall(r"^:CUSTOM_ID:\s+(\S+)", helper, re.M))
    problems = []
    for name, text in modules():
        for anchor in re.findall(r"function_helper\.org::#(\S+)", text):
            anchor = anchor.rstrip(".,;)'\"`")
            if anchor not in known:
                problems.append(f"{name} points at #{anchor}, absent from function_helper.org")
    return problems


def check_documented_functions():
    """A `Function: =my/foo=' in function_helper.org naming a symbol that is gone."""
    if not os.path.exists(HELPER):
        return ["function_helper.org is missing"]
    helper = open(HELPER, encoding="utf-8").read()
    known = set(definitions())
    problems = []
    for m in re.finditer(r"^Function:\s+=([^=]+)=", helper, re.M):
        # Several docs name two functions: "=my/a= and =my/b=", or a
        # comma-separated pair.  Never split on "/" -- that is part of
        # the `my/' prefix itself.
        for sym in re.split(r"\s*(?:,|=?\s+and\s+=?)\s*", m.group(1).strip()):
            sym = sym.strip()
            if sym.startswith("my") and sym not in known:
                line = helper[: m.start()].count("\n") + 1
                problems.append(f"function_helper.org:{line} documents {sym}, which no module defines")
    return problems


def help_text_keys():
    """Key sequences listed in the help text of 08-keybindings.el.

    Only the flat reference section is read.  The transient menu tree
    below it describes menu keys, which are not global bindings and
    would all look unbound to this check.
    """
    text = open(KEYS_FILE, encoding="utf-8").read()
    head = text.split("NOTES TRANSIENT MENU TREE", 1)[0]
    keys = []
    for line in head.split("\n"):
        m = re.match(r"^\s{2,}((?:C-|M-|s-|<)\S*(?: \S+)*?)\s+-\s+\S", line)
        if m:
            keys.append((m.group(1).strip(), line.strip()))
    return keys


def check_keybinding_help():
    """A key the help text advertises that nothing in modules/ binds."""
    if not os.path.exists(KEYS_FILE):
        return []
    bound = "".join(text for _, text in modules())
    problems = []
    for key, line in help_text_keys():
        if key in EXTERNAL_KEYS:
            continue
        if f'"{key}"' not in bound:
            problems.append(f"help text claims {key!r} but no module binds it  ({line})")
    return problems


MENU_SUFFIX_RE = re.compile(r'\("([^"]{1,3})"\s+"([^"]+)"\s+(my/[A-Za-z0-9/_?-]+)')


def check_menu_coverage():
    """A command reachable from a transient menu that the docs never mention.

    Menu PREFIXES are exempt: a command whose name ends in `-menu' opens a
    submenu, and function_helper.org documents those as whole sections
    rather than as entries, so requiring the symbol by name would flag
    every section that is in fact written.
    """
    if not os.path.exists(HELPER):
        return ["function_helper.org is missing"]
    helper = open(HELPER, encoding="utf-8").read()
    problems = []
    for name, text in modules():
        for m in MENU_SUFFIX_RE.finditer(text):
            key, label, command = m.groups()
            if command.endswith("-menu"):
                continue
            if command not in helper:
                problems.append(f"{name}: {key!r} {label!r} runs {command}, undocumented")
    return sorted(set(problems))


EXEMPT_ID = "commands-without-menu"

KEY_BINDING_RES = [
    # (global-set-key (kbd "C-c x") #'my/x), define-key, keymap-set ...
    re.compile(r"\((?:global-set-key|global-unset-key|define-key|keymap-set|keymap-global-set|bind-key)\b"
               r"[^\n]*?#?'(my/[A-Za-z0-9/_?-]+)"),
    # use-package :bind / :bind-keymap pairs: ("C-c u t" . my/theme-toggle)
    re.compile(r'\("[^"\n]+"\s*\.\s*#?\'?(my/[A-Za-z0-9/_?-]+)\)'),
    # 00-core.el's helper for keys taken from options
    re.compile(r"my/settings-bind-key\s+#?'(my/[A-Za-z0-9/_?-]+)"),
]


def interactive_commands():
    """Return every `my/' function whose body contains `(interactive'."""
    found = set()
    for _, text in modules():
        for m in re.finditer(r"^\((?:defun|cl-defun)\s+(my/[^\s()]+)", text, re.M):
            rest = text[m.end():]
            nxt = re.search(r"^\(", rest, re.M)
            if "(interactive" in rest[: nxt.start() if nxt else len(rest)]:
                found.add(m.group(1))
    return found


def reachable_commands():
    """Return every `my/' command a transient menu or a key reaches."""
    found = set()
    for _, text in modules():
        code = code_of(text)
        found.update(m.group(3) for m in MENU_SUFFIX_RE.finditer(code))
        for rx in KEY_BINDING_RES:
            found.update(m.group(1) for m in rx.finditer(code))
    return found


def helper_section(helper, custom_id):
    """Return the text of the Org section carrying CUSTOM_ID, or ''."""
    m = re.search(r"^(\*+) .*\n:PROPERTIES:\n(?::[^\n]*\n)*?:CUSTOM_ID: " + re.escape(custom_id) + r"\n",
                  helper, re.M)
    if not m:
        return ""
    depth = len(m.group(1))
    end = re.compile(r"^\*{1,%d} " % depth, re.M).search(helper, m.end())
    return helper[m.start(): end.start() if end else len(helper)]


def check_menu_reachability():
    """A command function_helper.org documents that no menu or key reaches.

    Every interactive `my/' command the manual mentions should be
    reachable without remembering its name: from a transient menu, or a
    key.  A command deliberately left to M-x -- a one-off migration, a
    diagnostic, something dangerous -- is listed, with its reason, in the
    section `Commands without a menu entry' (CUSTOM_ID
    commands-without-menu), in the first column of its table, which is
    the switch this check reads.
    """
    if not os.path.exists(HELPER):
        return ["function_helper.org is missing"]
    helper = open(HELPER, encoding="utf-8").read()
    # The first column of the table in that section; names in the
    # reasons are prose.
    exempt = set(re.findall(r"^\|\s*=(my/[A-Za-z0-9/_?-]+)=",
                            helper_section(helper, EXEMPT_ID), re.M))
    if not helper_section(helper, EXEMPT_ID):
        return [f"function_helper.org has no section with CUSTOM_ID {EXEMPT_ID}"]
    documented = set(re.findall(r"=(my/[A-Za-z0-9/_?-]+)=", helper))
    missing = (documented & interactive_commands()) - reachable_commands() - exempt
    problems = [f"{c} is documented but no menu or key reaches it "
                f"(add it to a menu, or to #{EXEMPT_ID} with the reason)"
                for c in sorted(missing)]
    stale = exempt - interactive_commands()
    problems += [f"#{EXEMPT_ID} lists {c}, which is not an interactive command"
                 for c in sorted(stale)]
    return problems


# ------------------------------------------------------------------
# Personal strings.  The repository is meant to be public; the list of
# what must not appear in it is not, so it lives in the settings folder
# (00-core.el, `my/settings-directory'), outside the repository.
# ------------------------------------------------------------------

PERSONAL_LIST = "private-strings.txt"


class Skip(Exception):
    """Raised by a check that could not run; the message says why.

    Reported as `skipped', never as `ok': a check with nothing to look
    at has not passed.  It does not block either -- on a machine
    without the check's input, skipping is the correct outcome.
    """

# Third-party files, copied unchanged and not ours to edit.
PERSONAL_SKIP = ("csl/",)


def settings_directory():
    """Return the settings folder as 00-core.el finds it.

    MYPKS_DIR, else :directory in mypks-local.eld beside init.el, else
    ~/.config/mypks/.
    """
    env = os.environ.get("MYPKS_DIR")
    if env:
        return os.path.expanduser(env)
    local = os.path.join(ROOT, "mypks-local.eld")
    if os.path.exists(local):
        m = re.search(r':directory\s+"([^"]+)"', open(local, encoding="utf-8").read())
        if m:
            return os.path.expanduser(m.group(1))
    return os.path.expanduser("~/.config/mypks/")


def personal_patterns():
    """Return (pattern, label) pairs from the private list, or None if absent.

    One entry per line; blank lines and lines starting with # ignored.
    A plain line matches as a substring, ignoring case.  A line starting
    with `re:' is a Python regular expression, also ignoring case.
    """
    path = os.path.join(settings_directory(), PERSONAL_LIST)
    if not os.path.exists(path):
        return None
    patterns = []
    for line in open(path, encoding="utf-8").read().split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("re:"):
            patterns.append((re.compile(line[3:], re.I), line))
        else:
            patterns.append((re.compile(re.escape(line), re.I), line))
    return patterns


def repository_files():
    """Text files git would commit: tracked, plus untracked not ignored."""
    try:
        out = subprocess.run(
            ["git", "-c", "core.quotePath=false", "ls-files", "-z",
             "--cached", "--others", "--exclude-standard"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
    files = []
    for path in out.split("\0"):
        if not path or path.startswith(PERSONAL_SKIP):
            continue
        full = os.path.join(ROOT, path)
        if not os.path.isfile(full):
            continue
        try:
            files.append((path, open(full, encoding="utf-8").read()))
        except (UnicodeDecodeError, OSError):
            continue    # binary: not text anyone reads
    return files


def check_personal_strings():
    """A personal string -- a name, a host, an address -- in a file git would commit.

    The strings come from private-strings.txt in the settings folder,
    which is outside the repository, so the list itself is never
    committed.  Without that file the check has nothing to look for and
    is skipped, with the path it looked for: on someone else's machine
    that is the correct outcome, on the owner's (a new machine, a moved
    settings folder) a reminder that nothing was checked.
    """
    patterns = personal_patterns()
    if patterns is None:
        raise Skip(f"no {PERSONAL_LIST} in {settings_directory()}")
    problems = []
    for path, text in repository_files():
        for number, line in enumerate(text.split("\n"), 1):
            for rx, label in patterns:
                if rx.search(line):
                    problems.append(f"{path}:{number}: {label!r} in: {line.strip()[:90]}")
    return problems


# Uses of another module's code that hooks/module_contract.py reads as
# hard but that are not, as (module, other module) pairs.  Each needs a
# reason, as above.
MODULE_DEPENDENCY_OK = {
}


def check_module_contract():
    """Every module keeps the contract of hooks/module_contract.py."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import module_contract
    return module_contract.check(dict(modules()), MODULE_DEPENDENCY_OK)


def staged_files():
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        cwd=ROOT, capture_output=True, text=True,
    )
    return [l for l in out.stdout.split("\n") if l]


def check_changelog():
    """Modules changed without a CHANGELOG entry in the same commit."""
    staged = staged_files()
    if not staged:
        return []
    touched = [f for f in staged if f.startswith("modules/") and f.endswith(".el")]
    if touched and "CHANGELOG.md" not in staged:
        return [
            "modules changed with no CHANGELOG.md entry: " + ", ".join(touched),
            "  (write the entry, or commit with --no-verify if this is a rollback)",
        ]
    return []


CHECKS = {
    "duplicates": (check_duplicate_defs, "one symbol defined in two modules"),
    "private": (check_private_symbols, "`--' symbols called across module boundaries"),
    "anchors": (check_anchors, "Docs: links pointing at missing CUSTOM_IDs"),
    "functions": (check_documented_functions, "documented functions that no longer exist"),
    "keys": (check_keybinding_help, "keys the help text claims but nothing binds"),
    "changelog": (check_changelog, "modules staged without a CHANGELOG entry"),
    "coverage": (check_menu_coverage, "menu commands function_helper.org never mentions"),
    "menus": (check_menu_reachability, "documented commands no menu or key reaches"),
    "modules": (check_module_contract, "module contract: headers, provide, declared dependencies"),
    "personal": (check_personal_strings, "personal strings (private-strings.txt) in files git would commit"),
}

# Checks that report but never block.  `private' was here while its
# twenty-one violations were a known backlog; the decoupling cleared
# them, and since 2026-10-18e it blocks, so that a new call to another
# module's `--' function stops the commit instead of starting a new
# backlog.
ADVISORY = {"coverage"}


def main(argv):
    names = [a for a in argv if not a.startswith("-")]
    if "--list" in argv:
        for k, (_, desc) in CHECKS.items():
            print(f"  {k:12s} {desc}")
        return 0
    selected = names or list(CHECKS)
    failed = False
    for key in selected:
        if key not in CHECKS:
            print(f"lint: no such check: {key}", file=sys.stderr)
            return 2
        fn, desc = CHECKS[key]
        try:
            problems = fn()
        except Skip as reason:
            print(f"  skipped  {key}: {reason}")
            continue
        if not problems:
            print(f"  ok       {key}")
            continue
        label = "advisory" if key in ADVISORY else "FAILED"
        print(f"  {label:8s} {key}: {desc}")
        for p in problems:
            print(f"           {p}")
        if key not in ADVISORY:
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
