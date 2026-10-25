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

import glob
import os
import re
import sys
import subprocess
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULES = os.path.join(ROOT, "modules")
HELPER = os.path.join(ROOT, "function_helper.org")
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
CHANGELOG_DIR = os.path.join(ROOT, "changelog")
KEYS_FILE = os.path.join(MODULES, "08-keybindings.el")

# Top-level definitions: at column 0.  One nested in another form
# (inside `with-eval-after-load', say) is not seen -- a known limit.
DEF_RE = re.compile(
    r"^\((defun|defmacro|defsubst|define-inline|defvar|defvar-local|defcustom"
    r"|defconst|defgroup|defface|defalias|define-derived-mode|define-minor-mode"
    r"|define-globalized-minor-mode|transient-define-prefix|transient-define-suffix"
    r"|transient-define-infix|transient-define-argument"
    r"|cl-defun|cl-defmacro|cl-defgeneric)\s+'?([^\s()]+)",
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
    # "Function: =my/a=, =my/b= and =my/c= | Module: ..." -- every name
    # between = signs before the first "|", over continuation lines too;
    # "Functions:" as well.  Until 2026-10-20 the pattern stopped at the
    # first closing "=", so only the first name was checked, and the
    # plural was not read at all (audit of 2026-10-20).
    for m in re.finditer(r"^Functions?:(.*(?:\n(?![ \t]*$)(?!\*)(?!\S+:)[^|\n]*)*)",
                         helper, re.M):
        names = m.group(1).split("|", 1)[0]
        for sym in re.findall(r"=([^=\s]+)=", names):
            # =my/zettel-*= names a family: one member must exist.
            if sym.endswith("*") and any(k.startswith(sym[:-1]) for k in known):
                continue
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


# A key as the bindings write it: C-, M-, s-, S-, H-, A- or <...>.
KEY_STRING = r'(?:[CMsSHA]-|<)[^"\n]*'
BOUND_KEY_RES = [
    # (global-set-key (kbd "C-c x") ...), (define-key MAP (kbd "C-c x") ...),
    # (keymap-set MAP "C-c x" ...), (keymap-global-set "C-c x" ...),
    # (bind-key "C-c x" ...)
    re.compile(r'\((?:global-set-key|define-key|keymap-set|keymap-global-set|bind-key'
               r'|local-set-key)\s+(?:[^\s()"]+\s+)?(?:\(kbd\s+)?"(' + KEY_STRING + r')"'),
    # A (KEY . COMMAND) pair: use-package :bind, `my/module-keys' lists.
    re.compile(r'\("(' + KEY_STRING + r')"\s*\.\s*[#\']*[^\s()"]+\)'),
]


def bound_keys():
    """Every key a binding form in modules/ binds, comment lines left out.

    Until 2026-10-20 the check asked only whether the quoted key appeared
    anywhere in a module -- a comment or a docstring was enough (audit of
    2026-10-20).  Now it must be the key of a binding form.
    """
    found = set()
    for _, text in modules():
        code = code_of(text)
        for rx in BOUND_KEY_RES:
            found.update(m.group(1) for m in rx.finditer(code))
    return found


def check_keybinding_help():
    """A key the help text advertises that no binding form in modules/ binds."""
    if not os.path.exists(KEYS_FILE):
        return []
    bound = bound_keys()
    problems = []
    for key, line in help_text_keys():
        if key in EXTERNAL_KEYS:
            continue
        if key not in bound:
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
# Menu keys.  Modules add entries to the menus of 12-transient.el (and
# to each other's) at load time; `my/transient-append' and
# `my/transient-insert' leave an entry out when its key is already
# taken, so two modules choosing the same key lose one entry, and load
# order decides which.  This check finds that before Emacs starts.
# ------------------------------------------------------------------

MENU_ENTRY_RE = re.compile(r'\(\s*"([^"\s]{1,4})"\s+"(?:[^"\\]|\\.)*"\s+#?\'?([^\s()\[\]]+)')
MENU_DEF_RE = re.compile(r"\(transient-define-prefix\s+([^\s()]+)")
MENU_ADD_RE = re.compile(r"\(my/transient-(append|insert|replace)\s+'([^\s()]+)\s+(\"[^\"]*\")?")
# An entry specification for `my/transient-entries' inside quoted data:
# (insert my/notes-tools-menu "q" ("o" "Label" my/cmd)).  The menu must
# end in -menu, so that (insert my/some-variable ...) in code is not
# read as one.
MENU_SPEC_RE = re.compile(r"\((insert|append)\s+(my/[^\s()]*-menu)\s")


def form_end(text, start):
    """Return the index just past the balanced form opening at START.

    Strings, comments and character literals are skipped, so a paren
    inside a docstring or a character literal does not count.
    """
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c == ";":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c == "?":
            i += 2 if i + 1 < n and text[i + 1] == "\\" else 1
        elif c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def menu_entries():
    """Return [(menu, key, command, file)] for every menu entry in modules/.

    From the menus' own definitions (`transient-define-prefix') and from
    the additions (`my/transient-append', `my/transient-insert', and the
    entry specifications a module's switch hands to
    `my/transient-entries').  An
    entry replaced with `my/transient-replace' is replaced, not added:
    the pair (menu, key) is returned with the new command only.
    """
    entries, replaced = [], set()
    for name, text in modules():
        code = code_of(text)
        for m in MENU_DEF_RE.finditer(code):
            body = code[m.start(): form_end(code, m.start())]
            for e in MENU_ENTRY_RE.finditer(body):
                entries.append((m.group(1), e.group(1), e.group(2), name))
        for m in MENU_SPEC_RE.finditer(code):
            body = code[m.end(): form_end(code, m.start())]
            for e in MENU_ENTRY_RE.finditer(body):
                entries.append((m.group(2), e.group(1), e.group(2), name))
        for m in MENU_ADD_RE.finditer(code):
            kind, menu = m.group(1), m.group(2)
            body = code[m.end(): form_end(code, m.start())]
            for e in MENU_ENTRY_RE.finditer(body):
                if kind == "replace":
                    replaced.add((menu, e.group(1)))
                    entries.append((menu, e.group(1), e.group(2), name + " (replaces)"))
                else:
                    entries.append((menu, e.group(1), e.group(2), name))
    return entries, replaced


def check_menu_keys():
    """One key, two different entries in one menu.

    `my/transient-append' and `my/transient-insert' skip an entry whose
    key is taken: the module loaded first keeps the key, the other's
    entry is silently missing.  The same command on the same key twice
    is not a conflict (a module re-adding its own entry).  A key taken
    over on purpose goes through `my/transient-replace', which this
    check leaves alone.
    """
    entries, replaced = menu_entries()
    seen = defaultdict(list)
    for menu, key, command, name in entries:
        seen[(menu, key)].append((command, name))
    problems = []
    for (menu, key), uses in sorted(seen.items()):
        if (menu, key) in replaced:
            continue
        if len({command for command, _ in uses}) > 1:
            problems.append(f"{menu} \"{key}\": " + ", ".join(
                f"{command} ({name})" for command, name in uses))
    return problems


# ------------------------------------------------------------------
# The loader.  init.el names every module once, in load order, for
# `my/modules-load' (00-core.el); a module left out of that list is never
# loaded, and nothing else would say so.  A module's switch is named in
# its header (MyPKS-Switch), which the modules menu (C-c n , m) uses to
# turn it at once; a name that the module does not define would make
# that menu silently fail to switch it.
# ------------------------------------------------------------------

INIT = os.path.join(ROOT, "init.el")


def load_list():
    """Return the module names init.el hands to `my/modules-load'."""
    text = open(INIT, encoding="utf-8").read()
    start = text.find("(my/modules-load")
    if start < 0:
        return None
    body = text[start: form_end(text, start)]
    return re.findall(r'^\s*"([0-9][^"]*)"', body, re.M)


def slot_problems(texts):
    """Problems with the slots of TEXTS, a list of (file name, text).

    A slot (`;; MyPKS-Provides: spelling') is a place one module fills
    and another could fill instead; the loader never loads two modules
    of one slot together (00-core.el).  Checked here: a slot is one or
    more lower-case words; a module providing one is optional (a core
    module cannot give way to another); at most one module per slot
    starts on a new machine -- the others say `MyPKS-Default: off'."""
    problems = []
    starting = {}
    for name, text in texts:
        head = text.split(";;; Code:", 1)[0]
        m = re.search(r"^;+[ \t]*MyPKS-Provides:[ \t]*(.*)$", head, re.M | re.I)
        if not m:
            continue
        slots = m.group(1).split()
        if not slots:
            problems.append(f"{name}: MyPKS-Provides names no slot")
        for slot in slots:
            if not re.fullmatch(r"[a-z][a-z0-9-]*", slot):
                problems.append(f"{name}: slot '{slot}' -- lower-case words joined by hyphens")
        optional = re.search(r"^;+[ \t]*MyPKS-Optional:[ \t]*yes[ \t]*$", head, re.M | re.I)
        if not optional:
            problems.append(f"{name}: provides a slot but is not optional -- "
                            "a core module cannot give way to another")
        default_off = re.search(r"^;+[ \t]*MyPKS-Default:[ \t]*off[ \t]*$", head, re.M | re.I)
        if not default_off:
            for slot in slots:
                starting.setdefault(slot, []).append(name[:-3] if name.endswith(".el") else name)
    for slot, names in sorted(starting.items()):
        if len(names) > 1:
            problems.append(f"slot '{slot}': {', '.join(names)} would all start on a new machine "
                            "-- all but one need MyPKS-Default: off")
    return problems


def check_loader():
    """Every module in init.el's list once; every MyPKS-Switch defined;
    slots well formed, at most one module per slot starting by default."""
    names = load_list()
    if names is None:
        return ["init.el has no (my/modules-load ...) list"]
    problems = []
    files = [name[:-3] for name, _ in modules()]
    listed = ["00-core"] + names
    for name in files:
        count = listed.count(name)
        if count == 0:
            problems.append(f"modules/{name}.el is not in init.el's list: it is never loaded")
        elif count > 1:
            problems.append(f"{name} is listed {count} times in init.el")
    for name in sorted(set(listed) - set(files)):
        problems.append(f"init.el lists {name}, which has no file in modules/")
    for name, text in modules():
        m = re.search(r"^;+ MyPKS-Switch:[ \t]*(\S+)", text.split(";;; Code:", 1)[0], re.M)
        # The name, then a space or a newline: \b let my/x-mode-extra
        # stand for my/x-mode (audit of 2026-10-20).
        if m and not re.search(r"^\(define-minor-mode\s+" + re.escape(m.group(1)) + r"\s",
                               text, re.M):
            problems.append(f"{name}: MyPKS-Switch names {m.group(1)}, which it does not define")
    problems.extend(slot_problems(list(modules())))
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


def git_output(args, what):
    """Output of git ARGS in ROOT; Skip, naming WHAT, when git fails.

    A check whose input could not be listed has checked nothing, and must
    say so rather than report `ok' (audit of 2026-10-20: three checks
    returned an empty list here, which read as clean).
    """
    try:
        return subprocess.run(
            ["git", "-c", "core.quotePath=false"] + args,
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as err:
        raise Skip(f"could not list {what} (git: {err})") from None


def repository_files():
    """Text files git would commit: tracked, plus untracked not ignored."""
    out = git_output(["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                     "the files git would commit")
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


# Files of this installation that 00-core.el reads in ~/.emacs.d without
# git tracking them: which settings folder to use, and the places the
# settings had before the settings folder (read once, to copy them).
CODE_FOLDER_INSTALLATION = {"mypks-local.eld", "host", "hosts/", "custom.el", "ui-state.el"}

CODE_FOLDER_NAME = re.compile(
    r'\(locate-user-emacs-file\s+"([^"]+)"'
    r'|\(expand-file-name\s+"([^"]+)"\s+user-emacs-directory\)')


def check_code_folder():
    """A file named in ~/.emacs.d is a file of the repository.

    State and data go to the settings folder (`my/var-file',
    `my/etc-file', 00-core.el); a name in the configuration folder that
    git does not track is a file written next to the code."""
    tracked = [t for t in git_output(["ls-files", "-z"], "the tracked files").split("\0")
               if t]
    problems = []
    for name, text in modules():
        for match in CODE_FOLDER_NAME.finditer(text):
            path = match.group(1) or match.group(2)
            if path in CODE_FOLDER_INSTALLATION:
                continue
            folder = path.rstrip("/") + "/"
            if any(t == path or t.startswith(folder) for t in tracked):
                continue
            line = text.count("\n", 0, match.start()) + 1
            problems.append(f"modules/{name}:{line}: {path!r} in ~/.emacs.d is no file of the "
                            "repository; state goes to my/var-file, shared data to my/etc-file")
    return problems


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


TESTS_DIR = os.path.join(ROOT, "tests")


def test_coverage():
    """Map module name (without .el) -> test files whose `;; Tests:' names it.

    The header is the test file's own statement of which modules it tests
    -- not merely loads: TESTING.org, *Which module a test tests*.
    Also returns the names a header gives that are no module.
    """
    modules_known = {name[:-3] for name in module_names()}
    covered, unknown = defaultdict(list), []
    for path in sorted(glob.glob(os.path.join(TESTS_DIR, "test-*.el"))):
        text = open(path, encoding="utf-8").read()
        m = re.search(r"^;; Tests:[ \t]*(.*)$", text, re.M)
        base = os.path.basename(path)
        if not m:
            unknown.append(f"{base}: no ';; Tests:' header naming the modules it tests")
            continue
        for module in m.group(1).split():
            if module in modules_known:
                covered[module].append(base)
            else:
                unknown.append(f"{base}: ';; Tests:' names {module}, which is no module")
    return covered, unknown


def check_tests():
    """Modules without a test, and modules staged without one of their tests.

    Advisory (TESTING.org): the list is the backlog of module tests, and
    the staged part is the reminder that a change comes with its test.
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import module_contract
    covered, problems = test_coverage()
    # A module marked `MyPKS-Tests: weekly' needs no tests of its own:
    # the weekly checks are its tests (TESTING.org, "Every module tested").
    weekly = {name[:-3] for name, text in modules() if module_contract.weekly_only(text)}
    untested = [name[:-3] for name in module_names()
                if name[:-3] not in covered and name[:-3] not in weekly]
    if untested:
        problems.append(f"{len(untested)} of {len(module_names()) - len(weekly)} modules "
                        f"that need tests have none ({len(weekly)} marked weekly): "
                        + " ".join(untested))
    try:
        staged = staged_files()
    except Skip:
        staged = []
    staged_tests = {os.path.basename(f) for f in staged if f.startswith("tests/")}
    for path in staged:
        if not (path.startswith("modules/") and path.endswith(".el")):
            continue
        module = os.path.basename(path)[:-3]
        tests = covered.get(module)
        if module in weekly:
            continue
        if not tests:
            problems.append(f"{path} changed; it has no test (TESTING.org)")
        elif not staged_tests.intersection(tests):
            problems.append(f"{path} changed; none of its tests is staged with it "
                            f"({', '.join(tests)})")
    return problems


def staged_files():
    """Files staged for the commit: added, copied, modified, renamed, deleted.

    Deleted too: removing a module is a change the CHANGELOG has to
    record (until 2026-10-20 the filter left deletions out).
    """
    out = git_output(["diff", "--cached", "--name-only", "--diff-filter=ACMRD"],
                     "the staged files")
    return [l for l in out.split("\n") if l]


# A month's file of the change log: changelog/YYYY-MM.md (since
# 2026-10-20k; before, every session was in CHANGELOG.md).
MONTH_FILE_RE = re.compile(r"^changelog/(\d{4}-\d{2})\.md$")
SESSION_LINE_RE = re.compile(r"^## Session\b.*$", re.M)
SESSION_RE = re.compile(r"^## Session (\d{4}-\d{2})-\d{2}[a-z] — \S")


def check_changelog():
    """Modules changed without a change log entry in the same commit.

    The entry is in a month's file, changelog/YYYY-MM.md; CHANGELOG.md
    alone (its lessons, its table) does not count as one.
    """
    staged = staged_files()
    if not staged:
        return []
    touched = [f for f in staged if f.startswith("modules/") and f.endswith(".el")]
    if touched and not any(MONTH_FILE_RE.match(f) for f in staged):
        return [
            "modules changed with no change log entry (changelog/YYYY-MM.md): "
            + ", ".join(touched),
            "  (write the entry, or commit with --no-verify if this is a rollback)",
        ]
    return []


def session_label(line):
    """The label of a session heading LINE: 2026-10-20k."""
    return line.split()[2]


def label_key(label):
    """Sort key of a LABEL: the date, then the letter."""
    return (label[:10], label[10:])


def check_changelog_files(directory=None, index=None):
    """The change log's month files keep the heading convention.

    Every session heading in changelog/YYYY-MM.md has the form
    `## Session YYYY-MM-DDx — Title` with the file's month, the
    sessions are newest first, no label is used twice, CHANGELOG.md
    links every month's file and holds no session.
    """
    directory = directory or CHANGELOG_DIR
    index = index or CHANGELOG
    problems = []
    if not os.path.isdir(directory):
        raise Skip(f"no folder {os.path.relpath(directory, ROOT)}")
    with open(index, encoding="utf-8") as f:
        index_text = f.read()
    for line in SESSION_LINE_RE.findall(index_text):
        problems.append(f"CHANGELOG.md: a session belongs in changelog/YYYY-MM.md: {line}")
    seen = {}
    for name in sorted(os.listdir(directory)):
        rel = "changelog/" + name
        m = MONTH_FILE_RE.match(rel)
        if not m:
            problems.append(f"{rel}: not a month's file (changelog/YYYY-MM.md)")
            continue
        month = m.group(1)
        if f"]({rel})" not in index_text:
            problems.append(f"{rel}: not linked from CHANGELOG.md's table of months")
        with open(os.path.join(directory, name), encoding="utf-8") as f:
            lines = SESSION_LINE_RE.findall(f.read())
        if not lines:
            problems.append(f"{rel}: holds no session")
        previous = None
        for line in lines:
            s = SESSION_RE.match(line)
            if not s:
                problems.append(f"{rel}: heading not of the form "
                                f"'## Session YYYY-MM-DDx — Title': {line}")
                continue
            label = session_label(line)
            if s.group(1) != month:
                problems.append(f"{rel}: session {label} belongs in changelog/{s.group(1)}.md")
            if label in seen:
                problems.append(f"{rel}: label {label} used twice (also in {seen[label]})")
            seen[label] = rel
            if previous and label_key(label) >= label_key(previous):
                problems.append(f"{rel}: {label} is above {previous}: newest first")
            previous = label
    return problems


CHECKS = {
    "duplicates": (check_duplicate_defs, "one symbol defined in two modules"),
    "private": (check_private_symbols, "`--' symbols used across module boundaries"),
    "anchors": (check_anchors, "Docs: links pointing at missing CUSTOM_IDs"),
    "functions": (check_documented_functions, "documented functions that no longer exist"),
    "keys": (check_keybinding_help, "keys the help text claims but nothing binds"),
    "changelog": (check_changelog, "modules staged without a change log entry"),
    "changelogs": (check_changelog_files, "change log month files: headings, order, the table of months"),
    "coverage": (check_menu_coverage, "menu commands function_helper.org never mentions"),
    "menus": (check_menu_reachability, "documented commands no menu or key reaches"),
    "modules": (check_module_contract, "module contract: headers, provide, declared dependencies"),
    "menukeys": (check_menu_keys, "one key given to two different entries of one menu"),
    "codefolder": (check_code_folder, "files named in ~/.emacs.d that the repository does not hold"),
    "loader": (check_loader, "every module in init.el's list once; every MyPKS-Switch defined; slots"),
    "tests": (check_tests, "modules without a test; modules changed without one of their tests"),
    "personal": (check_personal_strings, "personal strings (private-strings.txt) in files git would commit"),
}

# Checks that report but never block.  `private' was here while its
# twenty-one violations were a known backlog; the decoupling cleared
# them, and since 2026-10-18e it blocks, so that a new call to another
# module's `--' function stops the commit instead of starting a new
# backlog.
ADVISORY = {"coverage", "tests"}


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
