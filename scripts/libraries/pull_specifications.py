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
import sys

_SELF_DIR = os.path.dirname(os.path.abspath(__file__))
if _SELF_DIR not in sys.path:
    sys.path.insert(0, _SELF_DIR)

import spec_db
import spec_resolve
import spec_render

# scripts/libraries/ -> repo root is two levels up.
REPO_ROOT = os.path.abspath(os.path.join(_SELF_DIR, "..", ".."))
DEFAULT_MANIFEST = os.path.join(REPO_ROOT, "libraries", "data", "packages.x86_64")
DEFAULT_OUTPUT = os.path.join(REPO_ROOT, "documentation", "SPECIFICATIONS.md")
DEFAULT_CACHE = os.path.join(REPO_ROOT, "cache", "spec-db")


def parse_args(argv):
    p = argparse.ArgumentParser(
        prog="pull_specifications",
        description="Generate the Az'arch distribution specification.",
    )
    p.add_argument("-o", "--output", default=DEFAULT_OUTPUT,
                   help=f"output Markdown file (default: {DEFAULT_OUTPUT})")
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


def build(manifest_path, db_cache, mirror, offline):
    """Run the full pipeline and return the rendered Markdown text."""
    db_paths = spec_db.fetch_databases(db_cache, mirror=mirror, offline=offline)
    packages, provides, groups = spec_db.load_databases(db_paths)
    print(f"[spec] indexed {len(packages)} packages from core/extra/multilib",
          file=sys.stderr)

    tokens, raw_lines = spec_resolve.load_manifest(manifest_path)
    resolved = spec_resolve.resolve_closure(tokens, packages, provides, groups)
    resolved["raw_lines"] = raw_lines
    tiers = spec_resolve.compute_tiers(resolved)

    unresolved_tokens = [t for t, v in resolved["manifest_map"].items()
                         if v["kind"] == "unresolved"]
    if unresolved_tokens:
        print(f"[spec] WARN: manifest tokens that did not resolve: "
              f"{unresolved_tokens}", file=sys.stderr)
    if resolved["unresolved"]:
        uniq = sorted({tok for _, tok in resolved["unresolved"]})
        print(f"[spec] WARN: {len(resolved['unresolved'])} unresolved dependency "
              f"edges ({len(uniq)} unique tokens)", file=sys.stderr)

    print(f"[spec] closure: {len(resolved['closure'])} packages | "
          f"{len(tiers['bases'])} base / {len(tiers['leaves'])} top",
          file=sys.stderr)

    return spec_render.render(packages, resolved, tiers)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    text = build(args.manifest, args.db_cache, args.mirror, args.offline)

    if args.stdout:
        sys.stdout.write(text)
    else:
        os.makedirs(os.path.dirname(args.output), exist_ok=True)
        with open(args.output, "w") as f:
            f.write(text)
        print(f"[spec] wrote {args.output} "
              f"({text.count(chr(10)) + 1} lines, {len(text)} bytes)",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
