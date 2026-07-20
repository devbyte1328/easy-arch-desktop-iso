#!/usr/bin/env bash
#
# view_specifications.sh -- open the interactive Az'arch component map.
#
# Opens documentation/SPECIFICATIONS_COMPONENTS.html in your browser: the same
# layered map as the SVG (kernel at the bottom up to leaf apps at the top, every
# component a box coloured by category and marked by edition) but fully
# interactive. Click any component to inspect its plain-language purpose, version,
# edition, category, layer, size and upstream link; the map then highlights what
# it requires (below) and what requires it (above). Search by name and filter by
# category / edition to find exactly what you want to add or pull out.
#
# The page is produced by scripts/pull_specifications.sh and is fully
# self-contained (no server, no network). If it does not exist yet, this script
# offers to generate it (offline, from the cached Arch databases) first.
#
# Usage:
#   scripts/view_specifications.sh [HTML_FILE]
#
# Options:
#   -n, --no-open   generate if needed but only print the path; do not open
#   -h, --help      show this help and exit
#
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
HTML="$REPO_ROOT/documentation/SPECIFICATIONS_COMPONENTS.html"
GENERATOR="$SELF_DIR/pull_specifications.sh"

NO_OPEN=0
case "${1:-}" in
    -h|--help)
        sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    -n|--no-open)
        NO_OPEN=1
        shift
        ;;
esac

# An explicit path argument overrides the default and is used as-is.
if [ "$#" -ge 1 ]; then
    HTML="$1"
fi

# Generate the map if it is missing (offline, from the cached databases).
if [ ! -f "$HTML" ]; then
    echo "view_specifications: $HTML does not exist yet." >&2
    if [ -x "$GENERATOR" ]; then
        printf 'Generate it now (offline, from cached Arch databases)? [Y/n] ' >&2
        read -r reply || reply="n"
        case "$reply" in
            ''|[Yy]*) "$GENERATOR" --offline ;;
            *) echo "Run: scripts/pull_specifications.sh" >&2; exit 1 ;;
        esac
    else
        echo "Generate it with: scripts/pull_specifications.sh" >&2
        exit 1
    fi
fi

if [ "$NO_OPEN" -eq 1 ]; then
    echo "$HTML"
    exit 0
fi

# Open in the user's default browser. Try the usual openers in turn; if none is
# present, just print the path so the user can open it manually.
for opener in xdg-open gio open sensible-browser; do
    if command -v "$opener" >/dev/null 2>&1; then
        exec "$opener" "$HTML"
    fi
done

echo "view_specifications: no opener found (xdg-open/gio/open)." >&2
echo "Open this file in your browser:" >&2
echo "  $HTML"
