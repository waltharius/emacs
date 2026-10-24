"""The module contract: what every file in modules/ promises.

Used by the `modules' check of hooks/lint.py; documented in
function_helper.org, section 'Module contract' (#module-contract).

Two parts:

- *Form*: the file's name, its first line, the headers
  `MyPKS-Requires' and `MyPKS-Optional', a `Docs:' line, the
  `;;; Commentary:' and `;;; Code:' markers, `provide' and the closing
  line, and the parent of every `defgroup'.

- *Dependencies*: every use of another module's function or variable
  that would fail without that module must be declared in
  `MyPKS-Requires'.  Found by reading the code, not by running it: a
  small reader splits each file into forms and symbols (strings and
  comments skipped), records which module defines which symbol, and
  classifies every use of a symbol defined elsewhere as *guarded* or
  *hard*.

A use is guarded -- the module still loads and explains itself without
the other one -- when it runs only where a test has shown it present:

- in the branch where the test is true: the body of `(when (fboundp
  'f) ...)', the THEN of `(if (boundp 'v) THEN ELSE)', the later
  arguments of `(and (featurep '05-notes) ...)', the body of a `cond'
  clause, the bindings after it and the body of `when-let*' and kin;
  and in the branch where a negated test is false: the ELSE of `(if
  (not (fboundp 'f)) ...)', the later arguments of `(or (not ...) ...)';
- after `(unless (fboundp 'f) (user-error ...))' in the same body --
  only when that body ends by leaving (`user-error', `error', `signal',
  `throw'): an `unless' that only warns and goes on guards nothing;
- inside `(with-eval-after-load '05-notes ...)';
- the quoted name of a variable (`add-hook 'my/x-hook',
  `customize-save-variable 'my/v'): naming a variable does not read it
  -- unless the name is handed to what reads it (`symbol-value',
  `default-value', `eval');
- a face or a customization group: a missing face is drawn with the
  default face, a missing group leaves an option ungrouped;
- an argument of `my/transient-append', `my/transient-insert' or
  `my/transient-replace', which skip a menu they cannot find, or of
  `remq', `memq' and the like, which compare a name without calling it;
- the menu named in a quoted entry specification for
  `my/transient-entries', '((insert MENU ANCHOR SUFFIX) ...) or
  (append ...): data handed to the same degrading functions.

What a test shows: `fboundp', `boundp' and the like show that one symbol
is present -- they guard that symbol, not its neighbours; `featurep'
shows that a module loaded, and guards everything it defines.  A test
under `and' counts in the true branch, under `or' in the false one,
under `not' or `null' the other way round; `(or (fboundp 'f) t)' shows
nothing.

Everything else is hard.  The reader errs towards hard: a dependency
declared that is not strictly needed costs a toggle; one missed costs
an error at run time.  The cases the reader once got wrong are kept as
tests in tests/hooks/test_module_contract.py (audit of 2026-10-20).

00-core.el is loaded first and is never listed: every module may use it.
"""

import os
import re
from collections import defaultdict

# ------------------------------------------------------------------
# Reading Emacs Lisp
# ------------------------------------------------------------------

DEF_HEADS = {
    "defun", "defmacro", "defsubst", "define-inline", "defalias",
    "defvar", "defvar-local", "defcustom", "defconst",
    "defface", "defgroup",
    "define-minor-mode", "define-globalized-minor-mode", "define-derived-mode",
    "transient-define-prefix", "transient-define-suffix",
    "transient-define-infix", "transient-define-argument",
    "cl-defun", "cl-defmacro", "cl-defgeneric", "cl-defstruct",
}
VAR_HEADS = {"defvar", "defvar-local", "defcustom", "defconst"}
SOFT_HEADS = {"defface", "defgroup"}
GUARD_HEADS = {"fboundp", "boundp", "default-boundp", "facep", "featurep",
               "commandp", "functionp", "custom-variable-p"}
# Forms that leave the body they are in, ending what follows them.
EXIT_HEADS = {"user-error", "error", "signal", "throw"}
# Forms that read the value of a variable named by a quoted symbol.
VALUE_HEADS = {"symbol-value", "default-value", "default-toplevel-value",
               "buffer-local-value", "eval"}
# Conditional binding forms: each binding must be non-nil to go on.
LET_GUARD_HEADS = {"when-let*", "if-let*", "and-let*", "when-let", "if-let",
                   "while-let"}
# Calls whose quoted argument names a symbol without calling it, or which
# tolerate a symbol that does not exist.
DATA_HEADS = {"remq", "remove", "delq", "delete", "memq", "member", "eq",
              "equal", "assq", "my/transient-append", "my/transient-insert",
              "my/transient-replace"}
# Heads of the quoted entry specifications `my/transient-entries' reads:
# '((insert my/notes-tools-menu "q" ("o" "Label" my/cmd)) ...).
MENU_SPEC_HEADS = {"insert", "append"}
DELIMITERS = set("()[]\"; \t\n\r'`,")


class Form:
    """One parenthesised form: its span, its items, its parent."""

    __slots__ = ("start", "end", "items", "parent", "quoted")

    def __init__(self, start, parent, quoted=False):
        self.start, self.end, self.items, self.parent = start, None, [], parent
        # Inside '( ... ) everything is data, not code.
        self.quoted = quoted or bool(parent and parent.quoted)

    def head(self):
        """The first symbol, or None when the form starts with a form."""
        if self.items and self.items[0][0] == "sym":
            return self.items[0][1]
        return None


def parse(text):
    """Return (top-level form, [(symbol, position, form, quoted), ...])."""
    top = Form(0, None)
    current = top
    symbols = []
    quote = None
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == ";":
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif c == '"':
            # A string is an item too: (defvar my/path "somewhere") has
            # three, and a reader that dropped it took it for a bare
            # declaration (audit of 2026-10-20).
            current.items.append(("lit", None))
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
            i += 1
        elif c == "?":
            # Character literal: ?a ?\( ?\"
            current.items.append(("lit", None))
            i += 3 if i + 1 < n and text[i + 1] == "\\" else 2
        elif c in "([":
            form = Form(i, current, quote == "'")
            current.items.append(("form", form))
            current = form
            i += 1
        elif c in ")]":
            current.end = i
            current = current.parent or top
            i += 1
        elif c in "'`":
            quote = c
            i += 1
            continue
        elif c in " \t\n\r,#@":
            if c in ",@":
                quote = None
            i += 1
            continue
        else:
            j = i
            while j < n and text[j] not in DELIMITERS:
                j += 2 if text[j] == "\\" else 1
            name = text[i:j]
            quoted = bool(quote) or current.quoted
            current.items.append(("sym", name, i, quoted))
            symbols.append((name, i, current, quoted))
            i = j
        quote = None
    top.end = n
    return top, symbols


def walk(form):
    """Every form inside FORM, depth first."""
    for entry in form.items:
        if entry[0] == "form":
            yield entry[1]
            yield from walk(entry[1])


def defined(form):
    """Return (symbol, kind) when FORM defines something, else None.

    Kind is 'function', 'variable' or 'soft' (a face or a group).
    `(defvar NAME)' only declares, and `defalias' of a name without the
    configuration's prefix redefines an Emacs function rather than
    providing one (02-editing.el: yes-or-no-p).
    """
    head = form.head()
    if head not in DEF_HEADS or len(form.items) < 2 or form.items[1][0] != "sym":
        return None
    name = form.items[1][1]
    if head == "defvar" and len(form.items) == 2:
        return None
    if head == "defalias" and not name.startswith("my"):
        return None
    if head in VAR_HEADS:
        return name, "variable"
    if head in SOFT_HEADS:
        return name, "soft"
    return name, "function"


def facts(item, truth, owner, by_feature):
    """What ITEM, a condition, shows to be present when it is TRUTH.

    A set of ('sym', SYMBOL) for `fboundp' and the like, ('mod', FILE)
    for `featurep'.  Through `not' and `null' the truth flips; `and'
    shows all its tests when true, `or' all its tests when false; a
    condition of any other shape shows nothing.
    """
    if item[0] != "form":
        return frozenset()
    form = item[1]
    head, args = form.head(), form.items[1:]
    if head in GUARD_HEADS and args and args[0][0] == "sym":
        if not truth:
            return frozenset()
        arg = args[0][1]
        if head == "featurep":
            module = by_feature.get(arg)
            return frozenset({("mod", module)}) if module else frozenset()
        return frozenset({("sym", arg)}) if arg in owner else frozenset()
    if head in ("not", "null") and len(args) == 1:
        return facts(args[0], not truth, owner, by_feature)
    if (head == "and" and truth) or (head == "or" and not truth):
        return frozenset().union(*(facts(a, truth, owner, by_feature) for a in args))
    if head in ("and", "or") and len(args) == 1:
        return facts(args[0], truth, owner, by_feature)
    return frozenset()


def leaves(item):
    """True when ITEM, the last form of a body, leaves that body."""
    return item[0] == "form" and item[1].head() in EXIT_HEADS


def dependencies(files):
    """FILES maps 'NN-name.el' to its text.

    Return (hard, guarded): each maps a file name to
    {other file name: {symbols}}.
    """
    parsed = {name: parse(text) for name, text in files.items()}
    owner, kind = {}, {}
    for name, (top, _) in parsed.items():
        for form in walk(top):
            d = defined(form)
            if d and d[0] not in owner:
                owner[d[0]], kind[d[0]] = name, d[1]
    by_feature = {name[:-3]: name for name in files}

    hard = defaultdict(lambda: defaultdict(set))
    guarded = defaultdict(lambda: defaultdict(set))

    def use(name, item, form, known):
        sym, quoted = item[1], item[3]
        module = owner.get(sym)
        if not module or module == name:
            return
        safe = (kind[sym] == "soft"
                or (kind[sym] == "variable" and quoted
                    and form.head() not in VALUE_HEADS)
                # The name a test is given is not a use: (fboundp 'f).
                or (quoted and form.head() in GUARD_HEADS)
                or (quoted and form.head() in DATA_HEADS)
                or (quoted and form.head() in MENU_SPEC_HEADS)
                or ("sym", sym) in known or ("mod", module) in known)
        (guarded if safe else hard)[name][module].add(sym)

    def visit(name, form, known):
        """Classify every use in FORM, KNOWN being what tests have shown."""
        head, items = form.head(), form.items
        if head == "declare-function" or (head == "defvar" and len(items) == 2):
            return
        extra = [frozenset()] * len(items)
        if head in ("when", "unless") and len(items) >= 2:
            shown = facts(items[1], head == "when", owner, by_feature)
            extra[2:] = [shown] * (len(items) - 2)
        elif head == "if" and len(items) >= 3:
            extra[2] = facts(items[1], True, owner, by_feature)
            false = facts(items[1], False, owner, by_feature)
            extra[3:] = [false] * (len(items) - 3)
        elif head in ("and", "or"):
            so_far = frozenset()
            for k in range(1, len(items)):
                extra[k] = so_far
                so_far |= facts(items[k], head == "and", owner, by_feature)
        elif head in ("with-eval-after-load", "eval-after-load") and len(items) >= 2:
            module = by_feature.get(items[1][1]) if items[1][0] == "sym" else None
            if module:
                extra[2:] = [frozenset({("mod", module)})] * (len(items) - 2)
        elif head == "cond":
            for k in range(1, len(items)):
                if items[k][0] == "form":
                    clause = items[k][1]
                    if clause.items:
                        visit_item(name, clause, clause.items[0], known)
                        shown = known | facts(clause.items[0], True, owner, by_feature)
                        visit_body(name, clause, 1, shown)
            return
        elif head in LET_GUARD_HEADS and len(items) >= 2 and items[1][0] == "form":
            shown = frozenset()
            for binding in items[1][1].items:
                if binding[0] != "form":
                    continue
                parts = binding[1].items
                # (VAR EXPR) or (EXPR), EXPR a form.
                expr = parts[-1] if parts else None
                for part in parts:
                    visit_item(name, binding[1], part, known | shown)
                if expr is not None:
                    shown |= facts(expr, True, owner, by_feature)
            body_start = 2
            if head.startswith("if-let"):
                if len(items) > 2:
                    visit_item(name, form, items[2], known | shown)
                visit_body(name, form, 3, known)
            else:
                visit_body(name, form, body_start, known | shown)
            return
        visit_body(name, form, 0, known, extra)

    def visit_item(name, form, item, known):
        if item[0] == "sym":
            use(name, item, form, known)
        elif item[0] == "form":
            visit(name, item[1], known)

    def visit_body(name, form, start, known, extra=None):
        """Visit FORM's items from START on, in order.

        `(unless TEST ... LEAVE)' and `(when TEST ... LEAVE)' guard what
        follows them in the same body: past them, TEST is true, or false.
        """
        after = frozenset()
        for k in range(start, len(form.items)):
            item = form.items[k]
            visit_item(name, form, item,
                       known | after | (extra[k] if extra else frozenset()))
            if item[0] == "form" and item[1].head() in ("when", "unless"):
                sub = item[1].items
                if len(sub) >= 3 and leaves(sub[-1]):
                    after |= facts(sub[1], item[1].head() == "unless", owner, by_feature)

    for name, (top, _) in parsed.items():
        visit_body(name, top, 0, frozenset())
    return hard, guarded


# ------------------------------------------------------------------
# Headers
# ------------------------------------------------------------------

NAME_RE = re.compile(r"^\d\d[a-z]?-[a-z0-9-]+\.el$")
CORE = "00-core.el"


def header(text, field):
    """The value of ';; FIELD: value' before ';;; Code:', as lisp-mnt reads it."""
    head = text.split("\n;;; Code:", 1)[0]
    m = re.search(r"^;+[ \t]*" + re.escape(field) + r"[ \t]*:[ \t]*(.*)$", head, re.M | re.I)
    return m.group(1).strip() if m else None


def requires(text):
    value = header(text, "MyPKS-Requires")
    return [] if not value else value.split()


def optional(text):
    return (header(text, "MyPKS-Optional") or "").lower() == "yes"


# ------------------------------------------------------------------
# The check
# ------------------------------------------------------------------

# Calls that change files, or reach the network or run a program, which
# may do either.  A module calling one may not be marked `MyPKS-Tests:
# weekly' (TESTING.org, "Every module tested"): its functions need tests
# of their own.  Recognised as symbols in the code -- the head of a form,
# or a function passed as #'NAME -- not in comments, strings or quoted
# data; a call made another way (`funcall' of a variable, an alias) is
# not seen.
CHANGES_FILES = {
    "write-region", "with-temp-file", "write-file", "save-buffer", "basic-save-buffer",
    "save-some-buffers", "rename-file", "delete-file", "delete-directory", "copy-file",
    "copy-directory", "move-file-to-trash", "make-symbolic-link", "add-name-to-file",
    "set-file-modes", "make-directory",
    "url-retrieve", "url-retrieve-synchronously", "url-copy-file", "make-network-process",
    "open-network-stream", "plz", "request",
    "call-process", "call-process-region", "process-file", "make-process", "start-process",
    "start-file-process", "shell-command", "async-shell-command",
}
CHANGES_FILES_PREFIXES = ("org-web-tools-",)


def changes_files(text):
    """Return the names in CHANGES_FILES that TEXT's code calls, sorted."""
    code = text.split("\n;;; Code:", 1)[-1]
    _top, symbols = parse(code)
    found = set()
    for name, pos, _form, quoted in symbols:
        if quoted and code[max(0, pos - 2):pos] != "#'":
            continue
        if name in CHANGES_FILES or name.startswith(CHANGES_FILES_PREFIXES):
            found.add(name)
    return sorted(found)


def weekly_only(text):
    """Non-nil when TEXT's module is marked `MyPKS-Tests: weekly'."""
    return (header(text, "MyPKS-Tests") or "").lower() == "weekly"


def check(files, exempt=None):
    """Return a list of problems with FILES ({name: text})."""
    exempt = exempt or {}
    problems = []
    features = {name[:-3] for name in files}

    for name, text in sorted(files.items()):
        feature = name[:-3]
        first = text.split("\n", 1)[0]
        if not NAME_RE.match(name):
            problems.append(f"{name}: name is not NN-name.el (two digits, a letter "
                            "at most, lower-case words with hyphens)")
        if not re.match(rf"^;;; {re.escape(name)} --- \S.* -\*- lexical-binding: t; -\*-$",
                        first):
            problems.append(f"{name}: first line is not "
                            f"';;; {name} --- Summary -*- lexical-binding: t; -*-'")
        for marker in (";;; Commentary:", ";;; Code:"):
            if not re.search(rf"^{re.escape(marker)}$", text, re.M):
                problems.append(f"{name}: no '{marker}' line")
        head = text.split("\n;;; Code:", 1)[0]
        if not re.search(r"Docs: ~/\.emacs\.d/function_helper\.org::#\S+", head):
            problems.append(f"{name}: no 'Docs: ~/.emacs.d/function_helper.org::#id' "
                            "line before ';;; Code:'")
        if not re.search(rf"^\(provide '{re.escape(feature)}\)", text, re.M):
            problems.append(f"{name}: no (provide '{feature})")
        if not re.search(rf"^;;; {re.escape(name)} ends here", text, re.M):
            problems.append(f"{name}: no closing ';;; {name} ends here' line")

        req_value = header(text, "MyPKS-Requires")
        opt_value = header(text, "MyPKS-Optional")
        if req_value is None:
            problems.append(f"{name}: no ';; MyPKS-Requires:' header (empty when "
                            "the module needs nothing but 00-core)")
        if opt_value is None or opt_value.lower() not in ("yes", "no"):
            problems.append(f"{name}: no ';; MyPKS-Optional: yes' or 'no' header")
        # MyPKS-Default: off -- a new machine starts with the module off
        # (00-core.el, `my/host--new-machine-modules-off').  Only "off"
        # means anything, and only an optional module can be off.
        default = header(text, "MyPKS-Default")
        if default is not None:
            if default.lower() != "off":
                problems.append(f"{name}: 'MyPKS-Default: {default}' -- the only value is 'off' "
                                "(leave the header out for a module that starts on)")
            elif (opt_value or "").lower() != "yes":
                problems.append(f"{name}: 'MyPKS-Default: off' on a module that is not optional")
        # MyPKS-Tests: weekly -- the weekly load, switch and compile tests
        # are enough for this module (appearance, screen behaviour); the
        # lint check `tests' does not ask for tests of its functions.
        # Refused on a module that changes files or reaches the network.
        tests_value = header(text, "MyPKS-Tests")
        if tests_value is not None:
            if tests_value.lower() != "weekly":
                problems.append(f"{name}: 'MyPKS-Tests: {tests_value}' -- the only value is "
                                "'weekly' (leave the header out for a module whose "
                                "functions need tests)")
            else:
                calls = changes_files(text)
                if calls:
                    problems.append(f"{name}: 'MyPKS-Tests: weekly' on a module that calls "
                                    f"{', '.join(calls)} -- a module that changes files, "
                                    "runs programs or reaches the network needs tests of "
                                    "its functions (TESTING.org)")
        for other in requires(text):
            if other == feature:
                problems.append(f"{name}: requires itself")
            elif other == CORE[:-3]:
                problems.append(f"{name}: lists 00-core, which every module may use "
                                "without listing")
            elif other not in features:
                problems.append(f"{name}: requires {other}, which is not a module")

        for m in re.finditer(r"\(defgroup\s+(\S+)(.*?)(?=\n\(|\Z)", text, re.S):
            parent = re.search(r":group\s+'([^\s()]+)", m.group(2))
            if name != CORE and not (parent and parent.group(1).startswith("mypks")):
                problems.append(f"{name}: group {m.group(1)} is not under one of "
                                "the mypks- areas (:group 'mypks-...)")

    hard, _ = dependencies(files)
    for name, text in sorted(files.items()):
        declared = set(requires(text))
        for other, symbols in sorted(hard[name].items()):
            if other == CORE or other[:-3] in declared:
                continue
            if (name, other) in exempt:
                continue
            sample = sorted(symbols)[0]
            more = f" (and {len(symbols) - 1} more)" if len(symbols) > 1 else ""
            problems.append(f"{name}: uses {sample}{more} from {other} without a "
                            f"guard; add {other[:-3]} to MyPKS-Requires, or test "
                            f"(fboundp '{sample}) first")

    # A module that must stay on may not need one that can be turned off.
    for name, text in sorted(files.items()):
        if optional(text):
            continue
        for other in requires(text):
            other_text = files.get(other + ".el")
            if other_text is not None and optional(other_text):
                problems.append(f"{name} is not optional but requires {other}, "
                                "which is: make one of the two match the other")

    # No circles: the loader will order modules by these lists.
    graph = {name[:-3]: [r for r in requires(text) if r in features]
             for name, text in files.items()}
    state, seen = {}, set()

    def visit(node, path):
        state[node] = "open"
        for nxt in graph.get(node, []):
            if state.get(nxt) == "open":
                cycle = path[path.index(nxt):] + [nxt]
                if frozenset(cycle) not in seen:
                    seen.add(frozenset(cycle))
                    problems.append("circular MyPKS-Requires: " + " -> ".join(cycle))
            elif nxt not in state:
                visit(nxt, path + [nxt])
        state[node] = "done"

    for node in sorted(graph):
        if node not in state:
            visit(node, [node])
    return problems
