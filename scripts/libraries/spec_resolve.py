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


def _longest_height(closure, edges):
    """Longest chain of dependencies below each package (0 = sink)."""
    memo = {}

    def height(p, stack):
        if p in memo:
            return memo[p]
        best = 0
        for d in edges.get(p, ()):
            if d in stack or d == p:
                continue
            h = height(d, stack | {p}) + 1
            if h > best:
                best = h
        memo[p] = best
        return best

    return {p: height(p, frozenset()) for p in closure}


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
