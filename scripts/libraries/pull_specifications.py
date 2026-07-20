"""
pull_specifications -- orchestrator for the Az'arch distribution specification.

Generates documentation/SPECIFICATIONS.md: a technical spec of the OS that ships
on the ISO, centred on the real package dependency graph (base kernel/libs at the
bottom, leaf applications at the top).

Pipeline:
  spec_db      fetch + parse the official Arch core/extra/multilib databases
  spec_resolve expand the manifest, walk the full transitive closure, tier it
  spec_render  emit the Markdown from the resolved data + editorial content

Invoked by scripts/pull_specifications.sh (which sets up paths), or directly:
  python3 scripts/libraries/pull_specifications.py [options]
"""

import argparse
import os
import re
import sys

_SELF_DIR = os.path.dirname(os.path.abspath(__file__))
if _SELF_DIR not in sys.path:
    sys.path.insert(0, _SELF_DIR)

import spec_db
import spec_resolve
import spec_classify
import spec_render
import spec_svg

# scripts/libraries/ -> repo root is two levels up.
REPO_ROOT = os.path.abspath(os.path.join(_SELF_DIR, "..", ".."))
DEFAULT_MANIFEST = os.path.join(REPO_ROOT, "libraries", "data", "packages.x86_64")
DEFAULT_OUTPUT = os.path.join(REPO_ROOT, "documentation", "SPECIFICATIONS_GENERAL.md")
DEFAULT_SVG = os.path.join(REPO_ROOT, "documentation", "SPECIFICATIONS_COMPONENTS.svg")
DEFAULT_CACHE = os.path.join(REPO_ROOT, "cache", "spec-db")
PROFILE_PY = os.path.join(REPO_ROOT, "libraries", "azarch", "config", "profile.py")


def read_cow_spacesize():
    """Read the live-session writable-RAM size (cow_spacesize) from the real build
    config, so the spec reports the actual configured value, not a hardcoded one."""
    try:
        with open(PROFILE_PY) as f:
            text = f.read()
    except OSError:
        return "unknown"
    m = re.search(r'cow_spacesize\s*=\s*["\']([^"\']+)["\']', text)
    return m.group(1) if m else "unknown"


def parse_args(argv):
    p = argparse.ArgumentParser(
        prog="pull_specifications",
        description="Generate the Az'arch distribution specification.",
    )
    p.add_argument("-o", "--output", default=DEFAULT_OUTPUT,
                   help=f"output Markdown file (default: {DEFAULT_OUTPUT})")
    p.add_argument("--svg", default=DEFAULT_SVG,
                   help=f"output SVG diagram (default: {DEFAULT_SVG}); "
                        "the Markdown links to it")
    p.add_argument("-m", "--manifest", default=DEFAULT_MANIFEST,
                   help=f"package manifest (default: {DEFAULT_MANIFEST})")
    p.add_argument("--db-cache", default=DEFAULT_CACHE,
                   help=f"where to store the fetched Arch .db files "
                        f"(default: {DEFAULT_CACHE})")
    p.add_argument("--mirror", default=spec_db.DEFAULT_MIRROR,
                   help=f"Arch mirror base URL (default: {spec_db.DEFAULT_MIRROR})")
    p.add_argument("--offline", action="store_true",
                   help="do not download; reuse the .db files already in --db-cache")
    p.add_argument("--stdout", action="store_true",
                   help="print the report to stdout instead of writing the file")
    return p.parse_args(argv)


def _build_glance(packages, resolved, tiers, tags):
    """Assemble the at-a-glance facts shared by the Markdown and the SVG."""
    closure = resolved["closure"]
    roots = resolved["roots"]
    by_repo = {r: sum(1 for p in closure if packages[p]["repo"] == r)
               for r in spec_db.REPOS}
    total_isize = sum(packages[p]["isize"] for p in closure)
    from collections import Counter
    ed_counts = Counter(t["edition"] for t in tags.values())
    return {
        "base": "Arch Linux (rolling), x86_64",
        "desktop": "KDE Plasma (X11) with KDE Gear applications",
        "kernel": spec_render._pkg_version(packages, "linux"),
        "init": spec_render._pkg_version(packages, "systemd"),
        "dm": "SDDM autologin into the X11 Plasma session",
        "iso_version": "date-based, YYYY.MM.DD (no semver)",
        "ram": f"{read_cow_spacesize()} writable overlay held in RAM",
        "purpose": "live / rescue / installer medium with a full KDE desktop",
        "tokens": len(resolved["manifest_map"]),
        "raw_lines": resolved["raw_lines"],
        "by_repo": by_repo,
        "closure": len(closure),
        "selected": ed_counts.get("arch-selected", 0),
        "dep": ed_counts.get("arch-dep", 0),
        "azarch": ed_counts.get("az'arch", 0),
        "max_height": tiers["max_height"],
        "size": f"{total_isize / 1024 ** 3:.2f} GiB",
    }


def build(manifest_path, db_cache, mirror, offline, svg_rel="SPECIFICATIONS.svg"):
    """Run the full pipeline. Return (markdown_text, svg_text)."""
    db_paths = spec_db.fetch_databases(db_cache, mirror=mirror, offline=offline)
    packages, provides, groups = spec_db.load_databases(db_paths)
    print(f"[spec] indexed {len(packages)} packages from core/extra/multilib",
          file=sys.stderr)

    tokens, raw_lines = spec_resolve.load_manifest(manifest_path)
    resolved = spec_resolve.resolve_closure(tokens, packages, provides, groups)
    resolved["raw_lines"] = raw_lines
    tiers = spec_resolve.compute_tiers(resolved)
    tags = spec_classify.classify(packages, resolved["closure"], resolved["roots"])

    unresolved_tokens = [t for t, v in resolved["manifest_map"].items()
                         if v["kind"] == "unresolved"]
    if unresolved_tokens:
        print(f"[spec] WARN: manifest tokens that did not resolve: "
              f"{unresolved_tokens}", file=sys.stderr)
    if resolved["unresolved"]:
        uniq = sorted({tok for _, tok in resolved["unresolved"]})
        print(f"[spec] WARN: {len(resolved['unresolved'])} unresolved dependency "
              f"edges ({len(uniq)} unique tokens)", file=sys.stderr)

    from collections import Counter
    ed_counts = Counter(t["edition"] for t in tags.values())
    print(f"[spec] closure: {len(resolved['closure'])} packages | "
          f"{len(tiers['bases'])} base / {len(tiers['leaves'])} top | "
          f"editions {dict(ed_counts)}", file=sys.stderr)

    glance = _build_glance(packages, resolved, tiers, tags)
    md = spec_render.render(packages, resolved, tiers, tags, glance, svg_rel)
    svg = spec_svg.render_svg(packages, resolved, tiers, tags, glance)
    return md, svg


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    svg_rel = os.path.relpath(args.svg, os.path.dirname(args.output))
    md, svg = build(args.manifest, args.db_cache, args.mirror, args.offline,
                    svg_rel=svg_rel)

    if args.stdout:
        sys.stdout.write(md)
        return 0

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w") as f:
        f.write(md)
    print(f"[spec] wrote {args.output} "
          f"({md.count(chr(10)) + 1} lines, {len(md)} bytes)", file=sys.stderr)

    os.makedirs(os.path.dirname(args.svg), exist_ok=True)
    with open(args.svg, "w") as f:
        f.write(svg)
    print(f"[spec] wrote {args.svg} ({len(svg)} bytes)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
