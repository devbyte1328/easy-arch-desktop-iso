#!/bin/bash
#
# azarch -- ISO build entrypoint (thin shim).
#
# The build itself is Python: everything (steps, staging, the package cache, the
# progress bar, the ownership handback) lives in libraries/azarch/. This shim
# only does the two things that genuinely must be bash BEFORE Python starts:
#
#   1. Prime sudo ONCE on the real controlling terminal. After the PTY re-exec
#      below there is no interactive channel, so this is the only point a password
#      prompt can reach the user. The primed credential lets the Python sudo
#      keepalive + ownership handback run `sudo -n` for the rest of the build.
#
#   2. Re-exec on a PTY via util-linux `script`, which writes the full log itself.
#      The PTY is the point: pacman/mkarchiso detect a terminal and keep their
#      live, \r-redrawn progress bars (piping through plain tee makes them buffer
#      and appear frozen for minutes during big downloads). `script` also captures
#      a faithful copy of everything to logs/full.log.
#
# Then it hands off to `python3 -m azarch.build`, which does the rest.

set -o pipefail

REPODIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGDIR="$REPODIR/logs"
FULL_LOG="$LOGDIR/full.log"
STEPS_LOG="$LOGDIR/steps.log"
mkdir -p "$LOGDIR"

if [ -z "$_COMPILE_LOGGING" ]; then
    export _COMPILE_LOGGING=1
    # Prime sudo once, interactively, on the real terminal (see note 1 above).
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        sudo -n -v 2>/dev/null || sudo -n true 2>/dev/null || sudo -v || {
            echo "[!] sudo is required for the privileged build steps." >&2; exit 1; }
    fi
    : > "$FULL_LOG"
    : > "$STEPS_LOG"
    # Re-exec on a PTY. `script` flags: -q quiet, -e propagate child exit status,
    # -f flush after each write (real-time, tail-able), -c run our command.
    if command -v script >/dev/null 2>&1; then
        exec script -qefc "_COMPILE_LOGGING=1 _COMPILE_ONPTY=1 bash '${BASH_SOURCE[0]}' $*" "$FULL_LOG"
    else
        # No `script` available: fall back to tee (children buffer, but it works).
        exec > >(tee "$FULL_LOG") 2>&1
    fi
fi

# --- Under the PTY now: hand off to the Python build driver. ----------------
# PYTHONPATH points at libraries/ so `import azarch` resolves. -u = unbuffered,
# so the bar and build output interleave correctly on the PTY and in full.log.
export PYTHONPATH="$REPODIR/libraries${PYTHONPATH:+:$PYTHONPATH}"
export _COMPILE_ONPTY
exec python3 -u -m azarch.build "$@"
