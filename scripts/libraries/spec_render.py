"""
spec_render -- assemble documentation/SPECIFICATIONS.md from resolved graph data
and the editorial content in spec_content.

The renderer is where computed reality meets curated prose:
  * Tables (base tier, top tier, keystones, manifest tier, appendix) are built
    purely from the resolved package data.
  * Subsystem sections take their prose/grouping from spec_content but pull the
    real version for every listed package from the closure, so versions never go
    stale. Any listed package missing from the closure is reported as a warning.
"""

import sys

import spec_content as C

REPOS = ("core", "extra", "multilib")


def _warn(msg):
    print(f"[render] WARN: {msg}", file=sys.stderr)


def human_size(num):
    b = float(num)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if b < 1024:
            return f"{b:.0f} {unit}" if unit == "B" else f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PiB"


class Doc:
    def __init__(self):
        self.parts = []

    def w(self, s=""):
        self.parts.append(s)

    def text(self):
        return "\n".join(self.parts) + "\n"


def _pkg_version(packages, name):
    rec = packages.get(name)
    return rec["version"] if rec else "?"


def _first_present(packages, token):
    """A subsystem row label may be 'a / b'; return the first real package name."""
    for candidate in [p.strip() for p in token.split("/")]:
        if candidate in packages:
            return candidate
    return None


def _versions_for_label(packages, label, closure):
    """Render the version cell for a possibly-'a / b' label, warning on misses."""
    names = [p.strip() for p in label.split("/")]
    versions = []
    for name in names:
        if name in packages and name in closure:
            versions.append(_pkg_version(packages, name))
        else:
            _warn(f"subsystem lists '{name}' which is not in the resolved closure")
            versions.append("?")
    # collapse identical versions (common for KDE app groups)
    if len(set(versions)) == 1:
        return versions[0]
    return " / ".join(versions)


def render(packages, resolved, tiers):
    manifest_map = resolved["manifest_map"]
    closure = resolved["closure"]
    roots = resolved["roots"]
    edges = resolved["edges"]

    outdeg = tiers["outdeg"]
    indeg = tiers["indeg"]
    trans_dep = tiers["trans_dependents"]
    trans_deps = tiers["trans_deps"]

    by_repo = {r: sum(1 for p in closure if packages[p]["repo"] == r) for r in REPOS}
    total_isize = sum(packages[p]["isize"] for p in closure)
    manifest_tokens = [t for t in manifest_map]
    n_tokens = len(manifest_tokens)
    xorg_members = len(manifest_map.get("xorg", {}).get("members", []))
    plasma_members = len(manifest_map.get("plasma", {}).get("members", []))
    kernel_version = _pkg_version(packages, "linux")
    glibc_direct = indeg.get("glibc", 0)

    d = Doc()
    d.w("# Az'arch -- Distribution Specification")
    d.w()
    d.w(C.INTRO)
    d.w()
    d.w("---")
    d.w()

    # 1. At a glance ---------------------------------------------------------
    d.w("## 1. At a glance")
    d.w()
    d.w("- **Base distribution:** Arch Linux (rolling), x86_64")
    d.w("- **Desktop:** KDE Plasma (Wayland + X11) with KDE Gear applications")
    d.w(f"- **Kernel:** `linux` {kernel_version}")
    d.w(f"- **Init:** `systemd` {_pkg_version(packages, 'systemd')}")
    d.w("- **Purpose:** live / rescue / installer medium with a full KDE desktop")
    d.w()
    d.w("| Metric | Value |")
    d.w("|---|---:|")
    d.w(f"| Explicit manifest entries | {n_tokens} ({resolved['raw_lines']} lines; "
        "`unzip` listed twice) |")
    d.w(f"| Explicit entries incl. group members (`xorg`+`plasma`) | {len(roots)} |")
    d.w(f"| **Full package set (transitive closure)** | **{len(closure)}** |")
    d.w(f"| &nbsp;&nbsp;from `core` / `extra` / `multilib` | "
        f"{by_repo['core']} / {by_repo['extra']} / {by_repo['multilib']} |")
    d.w(f"| Pulled-in-only dependencies (not explicitly listed) | "
        f"{len(closure) - len(roots)} |")
    d.w(f"| Top / leaf packages (nothing depends on them) | {len(tiers['leaves'])} |")
    d.w(f"| Base / sink packages (depend on nothing else in the set) | "
        f"{len(tiers['bases'])} |")
    d.w(f"| Deepest dependency chain (leaf -> base) | {tiers['max_height']} hops |")
    d.w(f"| Total installed size of the package set | "
        f"{total_isize / 1024 ** 3:.2f} GiB |")
    d.w()
    d.w(C.GLANCE_NOTE)
    d.w()
    d.w("---")
    d.w()

    # 2. Graph --------------------------------------------------------------
    d.w("## 2. The dependency graph -- base to top")
    d.w()
    d.w(C.ASCII_GRAPH.format(
        leaves=len(tiers["leaves"]), bases=len(tiers["bases"]),
        kernel_version=kernel_version))
    d.w()
    d.w("### 2.1 How the layers were computed")
    d.w()
    d.w(C.LAYERS_NOTE.format(
        xorg_members=xorg_members, plasma_members=plasma_members,
        closure=len(closure), unresolved=len(resolved["unresolved"])))
    d.w()
    d.w("---")
    d.w()

    # 3. Base tier ----------------------------------------------------------
    bases = sorted(tiers["bases"], key=lambda p: (-trans_dep[p], p))
    d.w("## 3. The base tier (the bottom of the graph)")
    d.w()
    d.w(f"These **{len(bases)}** packages are the sinks of the dependency graph: "
        "they pull in nothing else from the set. They are the foundation everything "
        "else is stacked on. Sorted by how many packages ultimately depend on them.")
    d.w()
    d.w("| Package | Version | Repo | Depended on by (transitive) | Installed | "
        "What it is |")
    d.w("|---|---|---|---:|---:|---|")
    for p in bases:
        r = packages[p]
        d.w(f"| `{p}` | {r['version']} | {r['repo']} | {trans_dep[p]} | "
            f"{human_size(r['isize'])} | {r['desc']} |")
    d.w()
    d.w("### 3.1 The load-bearing keystones")
    d.w()
    d.w(C.KEYSTONE_NOTE.format(glibc_direct=glibc_direct))
    d.w()
    d.w("| Package | Version | Direct dependents | Transitive dependents | "
        "What it is |")
    d.w("|---|---|---:|---:|---|")
    keystones = sorted(closure, key=lambda p: (-trans_dep[p], p))[:30]
    for p in keystones:
        r = packages[p]
        d.w(f"| `{p}` | {r['version']} | {indeg[p]} | {trans_dep[p]} | {r['desc']} |")
    d.w()
    d.w("---")
    d.w()

    # 4. Top tier -----------------------------------------------------------
    leaves = sorted(tiers["leaves"], key=lambda p: (-trans_deps[p], p))
    d.w("## 4. The top tier (the leaves)")
    d.w()
    d.w(f"These **{len(leaves)}** packages are the leaves: nothing in the package "
        "set depends on them. Remove any one and nothing else in the system breaks "
        "-- only that package (and dependencies that become orphaned) goes away. "
        "\"Pulls in\" is the number of transitive dependencies each leaf drags in "
        "behind it.")
    d.w()
    d.w("| Package | Version | Repo | Pulls in (transitive deps) | Installed | "
        "What it is |")
    d.w("|---|---|---|---:|---:|---|")
    for p in leaves:
        r = packages[p]
        d.w(f"| `{p}` | {r['version']} | {r['repo']} | {trans_deps[p]} | "
            f"{human_size(r['isize'])} | {r['desc']} |")
    d.w()
    d.w("---")
    d.w()

    # 5. Subsystems ---------------------------------------------------------
    d.w("## 5. Subsystems -- what the software actually is")
    d.w()
    d.w("The package set grouped by real function, with concrete technical "
        "capabilities and real versions. (Grouping is by role in the OS, not by "
        "string-matching names.)")
    d.w()
    for _key, title, prose, rows in C.SUBSYSTEMS:
        d.w(f"### {title}")
        d.w()
        d.w(prose)
        d.w()
        d.w("| Package | Version | Capability |")
        d.w("|---|---|---|")
        for label, capability in rows:
            version = _versions_for_label(packages, label, closure)
            tick = " / ".join(f"`{x.strip()}`" for x in label.split("/"))
            d.w(f"| {tick} | {version} | {capability} |")
        d.w()
    d.w("---")
    d.w()

    # 6. Manifest tier ------------------------------------------------------
    d.w("## 6. Explicit manifest tier")
    d.w()
    d.w("The **source of truth** is `libraries/data/packages.x86_64`. These are the "
        "packages the ISO explicitly requests; everything else in the graph is "
        "pulled in as a dependency. Below, each manifest entry is mapped to the real "
        "package it resolves to, with its tier in the resolved graph.")
    d.w()
    d.w("| # | Manifest entry | Resolves to | Tier | Version |")
    d.w("|---:|---|---|---|---|")
    for i, tok in enumerate(manifest_tokens, 1):
        v = manifest_map[tok]
        if v["kind"] == "group":
            d.w(f"| {i} | `{tok}` | *group -> {len(v['members'])} pkgs* | "
                "root (group) | -- |")
        elif v["kind"] == "package":
            res = v["resolved"]
            tier = []
            if indeg.get(res) == 0:
                tier.append("top/leaf")
            if outdeg.get(res) == 0:
                tier.append("base/sink")
            if not tier:
                tier.append("interior")
            d.w(f"| {i} | `{tok}` | `{res}` | {', '.join(tier)} | "
                f"{_pkg_version(packages, res)} |")
        else:
            d.w(f"| {i} | `{tok}` | UNRESOLVED | -- | -- |")
    d.w()
    d.w("---")
    d.w()

    # 7. Appendix -----------------------------------------------------------
    d.w("## 7. Appendix -- full resolved package set")
    d.w()
    d.w(f"All **{len(closure)}** packages in the transitive closure, with real "
        "versions and source repo. A leading `*` marks an explicitly-requested "
        "package (a root / group member); unmarked packages are pulled in purely as "
        "dependencies.")
    d.w()
    d.w("```text")
    for p in sorted(closure):
        r = packages[p]
        mark = "*" if p in roots else " "
        d.w(f"{mark} {p} {r['version']} [{r['repo']}]")
    d.w("```")

    return d.text()
