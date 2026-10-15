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
the other one -- when it is:

- inside a form that tests for it first: `(when (fboundp 'f) ...)',
  `(if (boundp 'v) ...)', `(and (featurep '05-notes) ...)', and the
  same through `cond' clauses and `when-let*' bindings;
- after `(unless (fboundp 'f) (user-error ...))' in the same body;
- inside `(with-eval-after-load '05-notes ...)';
- the quoted name of a variable (`add-hook 'my/x-hook',
  `customize-save-variable 'my/v'): naming a variable does not read it;
- a face or a customization group: a missing face is drawn with the
  default face, a missing group leaves an option ungrouped;
- an argument of `my/transient-append', `my/transient-insert' or
  `my/transient-replace', which skip a menu they cannot find, or of
  `remq', `memq' and the like, which compare a name without calling it.

Everything else is hard.  The reader errs towards hard: a dependency
declared that is not strictly needed costs a toggle; one missed costs
an error at run time.

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
# Guards inside these are climbed out of: (when (and (fboundp 'a) x) ...)
CLIMB_HEADS = {"and", "or", "not", "null"}
# Calls whose quoted argument names a symbol without calling it, or which
# tolerate a symbol that does not exist.
DATA_HEADS = {"remq", "remove", "delq", "delete", "memq", "member", "eq",
              "equal", "assq", "my/transient-append", "my/transient-insert",
              "my/transient-replace"}
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
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
            i += 1
        elif c == "?":
            # Character literal: ?a ?\( ?\"
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
            current.items.append(("sym", name))
            symbols.append((name, i, current, bool(quote) or current.quoted))
            i = j
        quote = None
    top.end = n
    return top, symbols


def walk(form):
    """Every form inside FORM, depth first."""
    for kind, item in form.items:
        if kind == "form":
            yield item
            yield from walk(item)


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
    for name, (top, symbols) in parsed.items():
        spans, declarations = [], []
        for form in walk(top):
            head = form.head()
            if head == "declare-function" or (head == "defvar" and len(form.items) == 2):
                declarations.append((form.start, form.end))
            if head in GUARD_HEADS and len(form.items) >= 2 and form.items[1][0] == "sym":
                arg = form.items[1][1]
                module = by_feature.get(arg) if head == "featurep" else owner.get(arg)
                guard = form.parent
                # Never climb to the file itself: a guard covers a form,
                # not the module.
                while (guard and guard.parent and guard.parent.parent
                       and (guard.head() in CLIMB_HEADS or guard.head() is None)):
                    guard = guard.parent
                if (guard and guard.parent and guard.parent.parent
                        and guard.head() == "unless"):
                    guard = guard.parent
                if module and guard:
                    spans.append((guard.start, guard.end, module))
            if (head in ("with-eval-after-load", "eval-after-load")
                    and len(form.items) >= 2 and form.items[1][0] == "sym"):
                module = by_feature.get(form.items[1][1])
                if module:
                    spans.append((form.start, form.end, module))
        for sym, pos, form, quoted in symbols:
            module = owner.get(sym)
            if not module or module == name:
                continue
            if any(a <= pos <= b for a, b in declarations):
                continue
            safe = (kind[sym] == "soft"
                    or (kind[sym] == "variable" and quoted)
                    or (quoted and form.head() in DATA_HEADS)
                    or any(a <= pos <= b and m == module for a, b, m in spans))
            (guarded if safe else hard)[name][module].add(sym)
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
