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


def modules():
    for name in sorted(os.listdir(MODULES)):
        if name.endswith(".el"):
            yield name, open(os.path.join(MODULES, name), encoding="utf-8").read()


def code_of(text):
    """Return TEXT with the file header and comment-only lines removed."""
    body = text.split(";;; Code:", 1)[-1]
    return "\n".join(l for l in body.split("\n") if not l.lstrip().startswith(";"))


def definitions():
    """Map symbol -> [(file, line), ...] for every top-level definition."""
    found = defaultdict(list)
    for name, text in modules():
        for m in DEF_RE.finditer(text):
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
}

# Checks that report but never block.  `private' is here because the
# twenty-one existing violations are a known backlog: blocking on them
# would make every commit fail until the backlog is cleared, and a hook
# that always fails is a hook that gets bypassed by reflex.  Move it to
# blocking once the count reaches zero.
ADVISORY = {"private", "coverage"}


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
        problems = fn()
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
