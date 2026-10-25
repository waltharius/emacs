#!/usr/bin/env python3
"""Advisory check of the module dependency graph (MODULES.org rule 2).

Builds the graph from what the code does, not from what MyPKS-Requires
claims, and reports:

  * undeclared hard uses -- an unguarded use of another module's
    symbol that the header does not name in MyPKS-Requires.  This is
    the one finding that matters for rule 2: turn the target module
    off (my/modules-off) or remove it, and the user gets a void-function
    error at run time, not at start-up;
  * uses pointing up the MODULES.org group table (a module may require
    its own or a lower group, never a higher one);
  * cycles over all edges (ADP), with guarded edges marked as allowed;
  * the instability metric I = Ce/(Ca+Ce) per module and SDP violations
    (an edge pointing at a clearly less stable module);
  * MyPKS-Requires entries the code does not use.

Guarded uses (fboundp/boundp and kin, hook variables, menu data,
with-eval-after-load) are the branches converging on the trunk: by
rule 2 they may point anywhere and degrade quietly, so they are listed
for information only, never as violations.

The check never fails: exit code is 0 even with findings, so it cannot
break a commit or a weekly check.  Run it before a commit and read:

    python3 tools/check_module_graph.py

Usage: tools/check_module_graph.py [repo-root]
"""

import re
import sys
from collections import Counter
from pathlib import Path

MY_PREFIXES = ("my/", "mypks", "my-")
GUARDS = ("fboundp", "boundp", "featurep", "macrop", "functionp")
SYMBOL_CHARS = "A-Za-z0-9\\-/+=*<>=!?:._"
# The loader itself: always loaded first, cannot be turned off, so an
# undeclared use of it is fine by design.
ALWAYS_LOADED = {"00-core.el"}

def repo_root():
    if len(sys.argv) > 1:
        return Path(sys.argv[1]).resolve()
    return Path(__file__).resolve().parent.parent

def strip_noise(text):
    """Remove comments and string contents (docstrings go too)."""
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r";[^\n]*", "", text)
    return text

def definitions(code_text):
    out = set()
    for m in re.finditer(
            r"\((?:cl-)?def(?:un|var|custom|macro|const|subst|var-local"
            r"|face|group|alias)\*?\s+'?\(?([^\s()]+)", code_text):
        out.add(m.group(1))
    for m in re.finditer(r"\(define-\w+\s+'?\(?([^\s()]+)", code_text):
        out.add(m.group(1))
    return out

def hard_uses(code_text, sym):
    """Line numbers of unguarded, unquoted uses of sym.

    A quoted occurrence ('sym) is a guard, a hook name, a face or menu
    data -- soft.  An occurrence right after (declare-function is a
    promise, not a use.  What is left is a call or a value read; it is
    hard unless the same symbol is guarded just before it or the whole
    form is ordered after the other module's load.
    """
    out = []
    start = 0
    while True:
        i = code_text.find(sym, start)
        if i < 0:
            break
        start = i + len(sym)
        # token boundary: my/dashboard-section must not match inside
        # my/dashboard-sections
        if start < len(code_text) and re.match(r"[%s]" % SYMBOL_CHARS, code_text[start]):
            continue
        if "'" in code_text[max(0, i - 2):i]:
            continue  # quoted: guard, hook, face or data
        if code_text[max(0, i - 40):i].find("(declare-function") >= 0:
            continue
        window = code_text[max(0, i - 500):i]
        if re.search(r"\(\s*(?:%s)\s+'?\s*%s[\s)]"
                     % ("|".join(GUARDS), re.escape(sym)), window):
            continue
        if "with-eval-after-load" in code_text[max(0, i - 700):i]:
            continue
        out.append(code_text.count("\n", 0, i) + 1)
    return out

def read_requires(raw_text):
    m = re.search(r"^[ \t]*;;[ \t]*MyPKS-Requires:[ \t]*(.*)$",
                  raw_text, re.M)
    return set(m.group(1).split()) if m and m.group(1).strip() else set()

def read_groups(root):
    """Module name -> group number, from the MODULES.org table."""
    table = root / "MODULES.org"
    groups = {}
    if not table.exists():
        return groups
    for line in table.read_text().splitlines():
        m = re.match(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|", line)
        if m and not m.group(1).startswith("-") and m.group(1) != "Module":
            groups[m.group(1)] = int(m.group(2))
    return groups

def main():
    root = repo_root()
    mod_files = sorted((root / "modules").glob("*.el"))
    if not mod_files:
        print("No modules found under", root / "modules")
        return 0
    raw = {p.name: p.read_text() for p in mod_files}
    code = {f: strip_noise(t) for f, t in raw.items()}
    requires = {f: read_requires(t) for f, t in raw.items()}
    groups = read_groups(root)

    owner = {}
    for f in code:
        for sym in definitions(code[f]):
            owner.setdefault(sym, f)

    def is_mine(tok):
        return tok.startswith(MY_PREFIXES)

    edges = {}  # (from, to) -> {symbol: hard or soft}
    for f in code:
        for tok in set(re.findall(r"[A-Za-z0-9\-/+*<>=!?:._]+", code[f])):
            if not is_mine(tok):
                continue
            tgt = owner.get(tok)
            if not tgt or tgt == f:
                continue
            kind = "hard" if hard_uses(code[f], tok) else "soft"
            edges.setdefault((f, tgt), {})[tok] = kind

    hard = {(a, b) for (a, b), syms in edges.items()
            if any(k == "hard" for k in syms.values())}
    declared = {f: {d + ".el" for d in requires[f]} for f in raw}

    print("== Module graph: %d modules, %d edges (%d with a hard use)"
          % (len(raw), len(edges), len(hard)))
    print()
    print("== Undeclared hard uses (the finding that matters)")
    print("   An unguarded use MyPKS-Requires does not name: turning the")
    print("   target off or removing it breaks the user at run time.")
    found = False
    for (a, b) in sorted(edges):
        if b in ALWAYS_LOADED:
            continue
        syms = edges[(a, b)]
        bad = sorted(s for s, k in syms.items()
                     if k == "hard" and b not in declared[a])
        if bad:
            found = True
            print("   %s -> %s  via %s" % (a, b, ", ".join(bad)))
    if not found:
        print("   None. Every hard use is declared in MyPKS-Requires.")
    print()
    print("== Uses pointing up the group table (rule 2: never a higher group)")
    if groups:
        up = []
        for (a, b) in sorted(edges):
            ga, gb = groups.get(a[:-3]), groups.get(b[:-3])
            if ga is not None and gb is not None and gb > ga:
                up.append((a, b, ga, gb, edges[(a, b)]))
        if up:
            for a, b, ga, gb, syms in up:
                kinds = "hard" if any(k == "hard" for k in syms.values()) else "guarded"
                print("   %s (%d) -> %s (%d)  [%s]" % (a, ga, b, gb, kinds))
        else:
            print("   None.")
    else:
        print("   MODULES.org not found or has no group table.")
    print()
    print("== Cycles over all edges (ADP)")
    adj = {}
    for (a, b) in edges:
        adj.setdefault(a, set()).add(b)
    found_cycles = []
    def dfs(node, stack, seen):
        for nxt in sorted(adj.get(node, ())):
            if nxt in stack:
                found_cycles.append(stack[stack.index(nxt):] + [nxt])
            elif nxt not in seen:
                dfs(nxt, stack + [nxt], seen | {nxt})
    seen = set()
    for n in sorted(adj):
        if n not in seen:
            dfs(n, [n], seen)
            seen.add(n)
    if found_cycles:
        for cyc in found_cycles:
            pairs = [(cyc[i], cyc[i + 1]) for i in range(len(cyc) - 1)]
            marks = []
            for a, b in pairs:
                if b in ALWAYS_LOADED:
                    marks.append("foundation")
                elif (a, b) in hard:
                    marks.append("HARD" if b not in declared[a] else "hard-declared")
                else:
                    marks.append("guarded")
            print("   " + " -> ".join(cyc))
            print("     edges: " + ", ".join(
                "%s->%s (%s)" % (a[:-3], b[:-3], m)
                for (a, b), m in zip(pairs, marks)))
    else:
        print("   None. The graph is acyclic (ADP holds).")
    print()
    print("== Stability (SDP): I = Ce/(Ca+Ce), 0 = most stable")
    rows = []
    for f in sorted(raw):
        ca = sum(1 for (a, b) in edges if b == f)
        ce = sum(1 for (a, b) in edges if a == f)
        i = ce / (ca + ce) if ca + ce else None
        rows.append((f, ca, ce, i))
    idx = {f: i for f, _, _, i in rows if i is not None}
    for n, ca, ce, i in rows:
        print("   %-24s Ca=%-3d Ce=%-3d I=%s"
              % (n, ca, ce, "n/a" if i is None else "%.2f" % i))
    print()
    print("== SDP violations (I(dep) - I(user) > 0.2)")
    viol = []
    for (a, b) in sorted(edges):
        ia, ib = idx.get(a), idx.get(b)
        if ia is not None and ib is not None and ib - ia > 0.2:
            viol.append((a, b, ia, ib))
    if viol:
        for a, b, ia, ib in viol:
            print("   %s (I=%.2f) -> %s (I=%.2f)" % (a, ia, b, ib))
    else:
        print("   None.")
    print()
    print("== MyPKS-Requires entries the code does not use")
    any_unused = False
    for f in sorted(raw):
        unused = sorted(d for d in requires[f] if d + ".el" not in
                        {b for (a, b) in edges if a == f})
        if unused:
            any_unused = True
            print("   %s: %s" % (f, ", ".join(unused)))
    if not any_unused:
        print("   None.")
    print()
    print("Advisory only: exit 0. Nothing above blocks a commit.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
