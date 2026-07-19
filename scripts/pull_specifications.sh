#!/usr/bin/env bash
#
# pull_specifications.sh -- generate the Az'arch DISTRIBUTION specification.
#
# This produces documentation/SPECIFICATIONS.md: a technical spec of the operating
# system that ships on the ISO -- its real package set and the dependency graph
# from the base (kernel + core libraries) up to the top (leaf applications), with
# real versions and capabilities.
#
# The dependency data is resolved from the official Arch Linux core/extra/multilib
# package databases (the repos the ISO is actually built against), NOT from the
# host's pacman databases -- on a non-Arch host those carry different packages and
# versions and would produce a wrong spec. The databases are fetched once and
# cached under cache/spec-db/; pass --offline to reuse them without network.
#
# This is a thin shim: it locates the repo, checks for python3, and hands off to
# scripts/libraries/pull_specifications.py, which orchestrates the work across
# scripts/libraries/spec_{db,resolve,content,render}.py. All flags are passed
# straight through.
#
# Usage:
#   scripts/pull_specifications.sh [options]
#
# Options (forwarded to the Python orchestrator):
#   -o, --output FILE   write the report here (default: documentation/SPECIFICATIONS.md)
#   -m, --manifest FILE package manifest (default: libraries/data/packages.x86_64)
#       --db-cache DIR  where to cache the Arch .db files (default: cache/spec-db)
#       --mirror URL    Arch mirror base URL to fetch databases from
#       --offline       reuse cached .db files; do not download
#       --stdout        print to stdout instead of writing the file
#   -h, --help          show this help and exit
#
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_ENTRY="$SELF_DIR/libraries/pull_specifications.py"

case "${1:-}" in
    -h|--help)
        sed -n '3,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
    echo "pull_specifications: python3 is required but was not found" >&2
    exit 1
fi

if [ ! -f "$PY_ENTRY" ]; then
    echo "pull_specifications: missing $PY_ENTRY" >&2
    exit 1
fi

exec python3 "$PY_ENTRY" "$@"
