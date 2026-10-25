#!/usr/bin/env python3
"""Advisory report on the module dependency graph (MODULES.org).

The graph is the one the blocking lint check `modules' already builds
(hooks/module_contract.py): every file of modules/ read as Lisp forms,
every use of another module's symbol classified as *hard* (it fails
without that module) or *guarded* (fboundp and kin, with-eval-after-load,
a quoted hook or menu entry -- it degrades without it).  This script
adds what that check does not ask, after Robert C. Martin's component
principles (MODULES.org, Principles 2), on the hard edges only: a
guarded use may point anywhere (rule 2), so it neither closes a cycle
nor makes a module less stable.

  * hard uses pointing up the group table of MODULES.org (rule 2);
  * cycles of hard uses (the acyclic dependencies principle, ADP),
    reported as groups of modules that depend on each other;
  * instability I = Ce / (Ca + Ce) per module, Ca the modules that use
    it hard, Ce the modules it uses hard, and the hard uses of a module
    less stable than the user (the stable dependencies principle, SDP);
  * MyPKS-Requires entries no use in the code explains -- some exist
    only for load order, so each is a question, not an error.

What the `modules' check already blocks (an undeclared hard use, a
circle in MyPKS-Requires) is not repeated here.  The exit status is 0
whatever is found: nothing here blocks a commit.

    python3 tools/check_module_graph.py [repo-root]

Written 2026-10-25z, replacing a first version (commit 56e0912) that
read the code with regular expressions: a character literal ?\\" hid
whole functions from it, and definitions made by transient-define-prefix
were not seen.
"""

import os
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                       os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hooks"))
import module_contract  # noqa: E402
from lint import org_section_table  # noqa: E402


def read_modules(root):
    """{'NN-name.el': text} of the files in ROOT/modules."""
    folder = os.path.join(root, "modules")
    found = {}
    # modules/NAME.el, or modules/GROUP/NAME.el since 2026-10-26c.
    for here, _dirs, names in os.walk(folder):
        if os.path.relpath(here, folder).count(os.sep) > 0:
            continue
        for name in names:
            if name.endswith(".el"):
                found[name] = open(os.path.join(here, name), encoding="utf-8").read()
    return dict(sorted(found.items()))


def read_groups(root):
    """{'NN-name': group number} from the map of MODULES.org, or {}."""
    path = os.path.join(root, "MODULES.org")
    if not os.path.exists(path):
        return {}
    rows = org_section_table(open(path, encoding="utf-8").read(), "Map") or []
    return {r[0]: int(r[1]) for r in rows if len(r) > 1 and r[1].isdigit()}


def strongly_connected(nodes, edges):
    """Groups of more than one node reachable from each other (Tarjan)."""
    index, low, stack, on_stack, out = {}, {}, [], set(), []
    counter = [0]

    def visit(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on_stack.add(v)
        for w in sorted(edges.get(v, ())):
            if w not in index:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in on_stack:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            group = []
            while True:
                w = stack.pop()
                on_stack.discard(w)
                group.append(w)
                if w == v:
                    break
            if len(group) > 1:
                out.append(sorted(group))

    for v in sorted(nodes):
        if v not in index:
            visit(v)
    return sorted(out)


def report(files, groups):
    """The findings for FILES ({'NN-name.el': text}) and GROUPS.

    A dict: up (list of (user, used, symbols)), cycles (lists of module
    names), stability ({module: (ca, ce, i)}), sdp (list of (user, i,
    used, i)), unused (list of (module, required name)), guarded_up (a
    count, for information)."""
    hard, guarded = module_contract.dependencies(files)
    strip = lambda f: f[:-3]
    edges = {strip(a): {strip(b) for b in hard[a]} for a in hard}
    names = [strip(f) for f in files]

    up = []
    for a in sorted(hard):
        for b in sorted(hard[a]):
            ga, gb = groups.get(strip(a)), groups.get(strip(b))
            if ga is not None and gb is not None and gb > ga:
                up.append((strip(a), strip(b), sorted(hard[a][b])))
    guarded_up = sum(1 for a in guarded for b in guarded[a]
                     if groups.get(strip(b), -1) > groups.get(strip(a), 10**6))

    stability = {}
    for n in names:
        ca = sum(1 for a in edges if n in edges[a])
        ce = len(edges.get(n, ()))
        stability[n] = (ca, ce, ce / (ca + ce) if ca + ce else None)
    sdp = []
    for a in sorted(edges):
        for b in sorted(edges[a]):
            ia, ib = stability[a][2], stability[b][2]
            if ia is not None and ib is not None and ib > ia:
                sdp.append((a, ia, b, ib))

    unused = []
    for f, text in files.items():
        used = set(hard.get(f, {})) | set(guarded.get(f, {}))
        for r in sorted(module_contract.requires(text)):
            if r + ".el" not in used and r + ".el" in files:
                unused.append((strip(f), r))

    return {"up": up, "cycles": strongly_connected(names, edges),
            "stability": stability, "sdp": sdp, "unused": sorted(unused),
            "guarded_up": guarded_up}


def main():
    files = read_modules(ROOT)
    groups = read_groups(ROOT)
    r = report(files, groups)

    def section(title, lines, empty="None."):
        print("== " + title)
        for line in lines or [empty]:
            print("   " + line)
        print()

    section("Hard uses pointing up the group table (rule 2)",
            [f"{a} ({groups[a]}) -> {b} ({groups[b]})  via {', '.join(s[:4])}"
             for a, b, s in r["up"]],
            "None." if groups else "MODULES.org has no map.")
    print(f"   ({r['guarded_up']} guarded uses point up: allowed by rule 2)\n")
    section("Modules depending on each other through hard uses (ADP)",
            [" <-> ".join(c) for c in r["cycles"]])
    section("Stability of hard uses: I = Ce/(Ca+Ce), 0 = most used, least using",
            [f"{n:28} Ca={ca:<3} Ce={ce:<3} I={'n/a' if i is None else f'{i:.2f}'}"
             for n, (ca, ce, i) in sorted(r["stability"].items())])
    section("Hard uses of a less stable module (SDP)",
            [f"{a} (I={ia:.2f}) -> {b} (I={ib:.2f})" for a, ia, b, ib in r["sdp"]])
    section("MyPKS-Requires entries no use explains (load order only?)",
            [f"{m}: {req}" for m, req in r["unused"]])
    print("Advisory only: exit 0.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
