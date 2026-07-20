"""
spec_resolve -- turn the package manifest + the Arch DB universe into the real
dependency graph of the Az'arch distribution.

Steps:
  1. Load the explicit manifest (libraries/data/packages.x86_64).
  2. Resolve every entry to a concrete package, expanding groups (xorg, plasma)
     to their members and following `provides` for virtual deps.
  3. Walk the full transitive dependency closure from those roots.
  4. Compute graph tiers: base/sinks (out-degree 0), top/leaves (in-degree 0),
     transitive dependent/dependency counts, and layer heights.

Everything here is derived from the real `%DEPENDS%`/`%PROVIDES%` data -- no
guessing from package names.
"""

import sys
from collections import defaultdict, deque

from spec_db import dep_name

sys.setrecursionlimit(100000)


def load_manifest(manifest_path):
    """Return (unique_tokens_in_order, raw_line_count). Dupes de-duped, order kept."""
    raw = []
    with open(manifest_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            raw.append(line)
    seen = set()
    unique = []
    for tok in raw:
        if tok not in seen:
            seen.add(tok)
            unique.append(tok)
    return unique, len(raw)


def resolve_token(token, packages, provides):
    """Resolve one dep/manifest token to a concrete package name, or None."""
    name = dep_name(token)
    if name in packages:
        return name
    if name in provides:
        return sorted(provides[name])[0]
    return None


def resolve_closure(manifest_tokens, packages, provides, groups):
    """Expand groups, then BFS the full transitive closure.

    Returns a dict with: manifest_map, roots (set), closure (set),
    edges (pkg -> set of dep pkgs within the closure), unresolved (list).
    """
    manifest_map = {}
    roots = set()

    for token in manifest_tokens:
        if token in groups:
            members = sorted(set(groups[token]))
            manifest_map[token] = {"kind": "group", "members": members}
            roots.update(members)
            continue
        pkg = resolve_token(token, packages, provides)
        if pkg:
            manifest_map[token] = {"kind": "package", "resolved": pkg}
            roots.add(pkg)
        else:
            manifest_map[token] = {"kind": "unresolved"}

    closure = set()
    edges = defaultdict(set)
    unresolved = []
    queue = deque(sorted(roots))
    while queue:
        pkg = queue.popleft()
        if pkg in closure:
            continue
        closure.add(pkg)
        rec = packages.get(pkg)
        if not rec:
            continue
        for dtok in rec["depends"]:
            dep_pkg = resolve_token(dtok, packages, provides)
            if dep_pkg is None:
                unresolved.append((pkg, dtok))
                continue
            edges[pkg].add(dep_pkg)
            if dep_pkg not in closure:
                queue.append(dep_pkg)

    return {
        "manifest_map": manifest_map,
        "roots": roots,
        "closure": closure,
        "edges": {k: (v & closure) for k, v in edges.items()},
        "unresolved": unresolved,
    }


def stock_reachable(stock_tokens, azarch_closure, packages, provides, groups):
    """Return the set of packages in the Az'arch closure that the STOCK archiso
    `releng` medium already pulls in.

    We resolve the stock releng manifest through the exact same machinery as the
    Az'arch manifest (groups expanded, `provides` followed) and walk its full
    transitive closure, then intersect with the Az'arch closure. A package is
    "Stock Arch" iff it lands in that intersection; everything else in the
    Az'arch closure is there only because of an Az'arch addition.

    Resolving the stock list on its own graph (rather than reusing the Az'arch
    edges) is deliberate: it answers "what would plain archiso install?" honestly,
    independent of what Az'arch happens to also request.
    """
    stock = resolve_closure(stock_tokens, packages, provides, groups)
    return stock["closure"] & azarch_closure


def _strongly_connected_components(closure, edges):
    """Tarjan's SCC algorithm (iterative, so deep dependency graphs don't blow
    the Python stack). Returns (comp_id_of_node, list_of_components).

    Real package graphs contain dependency cycles; grouping cyclic packages into
    one component is what lets the height below be computed deterministically.
    """
    index_of = {}
    low = {}
    on_stack = set()
    stack = []
    comp_of = {}
    comps = []
    counter = 0

    for root in sorted(closure):
        if root in index_of:
            continue
        # work stack of (node, iterator-position) frames
        work = [(root, 0)]
        while work:
            node, pi = work[-1]
            if pi == 0:
                index_of[node] = low[node] = counter
                counter += 1
                stack.append(node)
                on_stack.add(node)
            children = sorted(edges.get(node, ()))
            if pi < len(children):
                work[-1] = (node, pi + 1)
                child = children[pi]
                if child not in index_of:
                    work.append((child, 0))
                elif child in on_stack:
                    low[node] = min(low[node], index_of[child])
            else:
                if low[node] == index_of[node]:
                    comp = []
                    while True:
                        w = stack.pop()
                        on_stack.discard(w)
                        comp_of[w] = len(comps)
                        comp.append(w)
                        if w == node:
                            break
                    comps.append(comp)
                work.pop()
                if work:
                    parent = work[-1][0]
                    low[parent] = min(low[parent], low[node])
    return comp_of, comps


def _longest_height(closure, edges):
    """Longest chain of dependencies below each package (0 = sink).

    Computed on the SCC condensation so it is deterministic and cycle-safe: a
    dependency cycle is one tier (its members share a height), and the height is
    1 + the deepest height among the *other* components it depends on. This
    avoids the order-dependent result a naive recursive cycle-cut produces.
    """
    comp_of, comps = _strongly_connected_components(closure, edges)

    # Edges between distinct components, in the condensation DAG.
    comp_edges = defaultdict(set)
    for a, deps in edges.items():
        ca = comp_of[a]
        for d in deps:
            cd = comp_of[d]
            if cd != ca:
                comp_edges[ca].add(cd)

    # Longest path in the condensation DAG via memoized recursion. No cycles
    # remain, so the memo is unconditional and the result is order-independent.
    comp_h = {}

    def cheight(c):
        if c in comp_h:
            return comp_h[c]
        best = 0
        for nxt in comp_edges.get(c, ()):
            h = cheight(nxt) + 1
            if h > best:
                best = h
        comp_h[c] = best
        return best

    for c in range(len(comps)):
        cheight(c)

    return {p: comp_h[comp_of[p]] for p in closure}


def compute_tiers(resolved):
    """Enrich the resolved closure with per-package graph metrics + tier lists."""
    closure = resolved["closure"]
    edges = resolved["edges"]

    rev = defaultdict(set)
    for a, deps in edges.items():
        for d in deps:
            rev[d].add(a)

    outdeg = {p: len(edges.get(p, ())) for p in closure}
    indeg = {p: len(rev.get(p, ())) for p in closure}

    def _reachable(start_map, p):
        seen = set()
        stack = list(start_map.get(p, ()))
        while stack:
            x = stack.pop()
            if x in seen:
                continue
            seen.add(x)
            stack.extend(start_map.get(x, ()))
        return len(seen)

    trans_dependents = {p: _reachable(rev, p) for p in closure}
    trans_deps = {p: _reachable(edges, p) for p in closure}
    heights = _longest_height(closure, edges)

    leaves = sorted(p for p in closure if indeg[p] == 0)
    bases = sorted(p for p in closure if outdeg[p] == 0)

    return {
        "rev": {k: sorted(v) for k, v in rev.items()},
        "outdeg": outdeg,
        "indeg": indeg,
        "trans_dependents": trans_dependents,
        "trans_deps": trans_deps,
        "heights": heights,
        "leaves": leaves,
        "bases": bases,
        "max_height": max(heights.values()) if heights else 0,
    }
