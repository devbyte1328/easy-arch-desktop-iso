#!/bin/bash

set -o pipefail

REPODIR=$(pwd)
CONFDIR=$REPODIR/conf
CACHEDIR=$REPODIR/cache

# --- Logging --------------------------------------------------------------
# Every run produces two logs under logs/:
#   - full:  the complete build output (every line, incl. pacman/pip/mkarchiso
#            chatter and the "    [+] ..." sub-actions). This is the firehose.
#   - steps: only the step() milestones, one line each. This is the summary you
#            skim to see how far the build got and where it stopped.
# The steps log is escape-free text; the full log is a faithful capture of the
# terminal (it may contain the children's own \r-based progress redraws).
#
# We re-exec the whole script under `script`, which runs it on a real PTY and
# writes that PTY's output to the full log. The PTY is the crucial part: pacman
# and mkarchiso both detect a terminal and keep their LIVE, \r-redrawn
# progress bars. (Piping through plain `tee` makes them see a non-TTY, so they
# switch to buffered output and appear frozen for minutes during big downloads.)
LOGDIR=$REPODIR/logs
mkdir -p "$LOGDIR"
FULL_LOG=$LOGDIR/full.log
STEPS_LOG=$LOGDIR/steps.log

if [ -z "$_COMPILE_LOGGING" ]; then
    export _COMPILE_LOGGING=1
    # Prime sudo ONCE here, on the real controlling terminal, BEFORE the `script`
    # re-exec below. This is the only point in the run where a password prompt is
    # guaranteed to reach the user: after the re-exec everything runs on a PTY, and
    # the exit/signal traps have no interactive channel at all. The primed credential
    # is what lets the long-lived root helper (launched after SUDO is set) start with
    # `sudo -n`; that helper then holds root for the whole build so the ownership
    # handback works even after sudo's short timestamp expires mid-build -- the exact
    # failure that left cache/build/ root-owned and locked.
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        # Order of preference:
        #   1. `sudo -n -v` : refresh an existing valid timestamp with no prompt.
        #   2. `sudo -n true`: usable WITHOUT a timestamp (NOPASSWD config) -> no prompt.
        #   3. `sudo -v`    : prompt interactively (fine here: real terminal, pre-re-exec).
        # Only bail if none work, so we never launch a build that can't reclaim its tree.
        sudo -n -v 2>/dev/null || sudo -n true 2>/dev/null || sudo -v || {
            echo "[!] sudo is required for the privileged build steps." >&2; exit 1; }
    fi
    # Truncate both logs at the start of a fresh run.
    : > "$FULL_LOG"
    : > "$STEPS_LOG"
    # Re-exec on a PTY via util-linux `script`, which writes the full log itself:
    #   -q  quiet     (trims banners on newer util-linux; older ones still print a
    #                  one-line "Script started/done" header/footer — harmless, it
    #                  even records the exit code)
    #   -e  return-exit (propagate the child's exit status so a failed download or
    #                  mkarchiso still fails the whole run)
    #   -f  flush     (write the log after every chunk -> real-time, tail-able)
    #   -c  command   (run our own re-exec of this script on the PTY)
    # The PTY is the point: pacman/mkarchiso see a terminal and keep their
    # live \r-redrawn progress bars instead of buffering silently.
    # If `script` is unavailable, fall back to tee (children buffer, but the run
    # still works and both logs are produced).
    if command -v script >/dev/null 2>&1; then
        exec script -qefc "_COMPILE_LOGGING=1 _COMPILE_ONPTY=1 bash '$0' $*" "$FULL_LOG"
    else
        exec > >(tee "$FULL_LOG") 2>&1
    fi
fi
# Under `script` our stdout IS the PTY, so [ -t 1 ] is true again and the pinned
# progress bar draws normally on it. Without script (tee fallback) it is a pipe.
if [ "${_COMPILE_ONPTY:-0}" -eq 1 ] || [ -t 1 ]; then
    export _COMPILE_ISATTY=1
else
    export _COMPILE_ISATTY=0
fi
# All build scratch lives here so the project root stays clean.
# BUILDDIR is the final artifact dir: the finished ISO lands directly in it
# (and it is the host bind-mount target under Docker).
# WORKDIR is the disposable mkarchiso PROFILE tree (releng + airootfs + packages).
# It lives under cache/ (not output/) so the heavy, regenerable scratch tree sits
# next to the download cache and never litters output/ next to the finished ISO.
BUILDDIR=$REPODIR/output
WORKDIR=$CACHEDIR/build

# Root-aware sudo wrapper. Inside the build container everything already runs as
# root, so a `sudo` prefix is pure overhead AND an extra process between this
# shell and pacman/mkarchiso. Dropping it when EUID=0 keeps the heavy commands as
# DIRECT children of this shell's process group, so a group-kill (see the INT/TERM
# trap below) reaches them. On a non-root Arch host $SUDO stays "sudo" so the
# privileged steps still work.
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# --- Never leave cache/build/ locked ----------------------------------------
# mkarchiso/pacstrap run as root (via sudo on a native build) and create
# cache/build/** owned by root. If that ownership is not handed back, the invoking
# user cannot rm/edit cache/build/ -- it is "locked". We guarantee it is NEVER left
# locked with THREE independent, overlapping safeguards, so no single failure
# (expired sudo timestamp, uncatchable SIGKILL, power loss) can leave it root-owned:
#
#   1. STARTUP reclaim (below): before doing anything, unconditionally chown the
#      whole cache/ output/ logs/ back to the user. This is the ONLY thing that can
#      recover a tree left behind by a previous run that was SIGKILL'd / power-cut
#      (no trap can ever run in those cases). So even in the worst case, the lock
#      lasts only until the next invocation and is cleared automatically.
#   2. IMMEDIATE reclaim: right after `mkarchiso` returns (success OR failure), we
#      chown inline in the normal control flow -- while the sudo timestamp is
#      guaranteed fresh (mkarchiso itself just used it). No trap, no background
#      process, no FIFO -- nothing to wedge or be killed mid-teardown.
#   3. TRAP reclaim: on Ctrl-C/TERM/HUP/QUIT and on any EXIT, handback_ownership
#      runs the same chown, covering an interrupt that happens mid-mkarchiso.
#
# A background `sudo -v` keepalive keeps the timestamp warm across the long build so
# the trap/immediate `sudo -n chown` still works even past sudo's short timeout. If
# a given sudo config can't refresh non-interactively, safeguard 1 still covers it.
SUDO_KEEPALIVE_PID=0
start_sudo_keepalive() {
    [ -n "$SUDO" ] || return 0
    ( while true; do sudo -n -v 2>/dev/null || sudo -n true 2>/dev/null || exit 0; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
}
stop_sudo_keepalive() {
    (( SUDO_KEEPALIVE_PID > 0 )) || return 0
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null
    SUDO_KEEPALIVE_PID=0
}

# --- Continuous ownership reclaim (never leave the host locked mid-build) -----
# The three overlapping safeguards above (startup / post-mkarchiso / trap) only
# unlock the trees at BUILD BOUNDARIES. In between -- for the whole multi-hour
# mkarchiso run -- every file root freshly writes under cache/ output/ logs/ is
# root-owned and thus LOCKED for the host user. This loop closes that window: it
# re-chowns (and restores owner-write) the safe trees back to the host user every
# few seconds for the entire build, so nothing stays locked for more than one
# sweep interval. It mirrors the sudo keepalive exactly: `sudo -n` only (never
# prompts, so it can't hang the PTY), self-terminating, fully trap-managed.
#
# CRITICAL -- it must NEVER recurse the work tree $WORKDIR (=cache/build). During
# mkarchiso that tree holds the airootfs with LIVE bind mounts
# (proc/sys/dev/run); a naive `chown -R cache/` would descend through those into
# the host's real /dev,/sys,/run under --privileged (corrupting the host), race
# pacstrap's writes, and bake wrong ownership/modes into the squashfs (e.g. a
# writable 0440 sudoers breaks sudo in the shipped ISO). So reclaim_periodic (see
# below) deliberately skips cache/build; that tree is reclaimed ONLY by the inline
# reclaim_now AFTER unmount_worktree -- the one point where it is safe to touch.
CHOWNER_PID=0
start_continuous_chowner() {
    local owner=""
    if [ "$(id -u)" -eq 0 ]; then
        [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ] && owner="$HOST_UID:$HOST_GID"
    elif [ -n "$SUDO" ]; then
        owner="$(id -u):$(id -g)"
    fi
    [ -n "$owner" ] || return 0                       # unresolved owner -> nothing to do
    (
        while true; do
            # Single-flight: reclaim_periodic skips the work tree, so a sweep is only
            # a chown/chmod over the flat package caches + output + logs -- ~10ms even
            # at thousands of files (measured). So we can poll TIGHT (1s) to keep the
            # residual lock window ~1s even during pacman's fast download bursts, at
            # negligible load. flock -n still guards against the pathological case
            # where a sweep somehow runs longer than the interval: the next tick just
            # skips instead of stacking a second concurrent chown.
            ( flock -n 9 || exit 0; reclaim_periodic "$owner" ) 9>"$LOGDIR/.chowner.lock"
            sleep 1                                    # sleep AFTER the sweep -> strictly serialized
        done
    ) &
    CHOWNER_PID=$!
}
# Collect a PID and every descendant, deepest first, by walking pgrep -P. Used to
# reap the chowner's whole subtree (loop -> flock subshell -> in-flight chown -R)
# in one shot: we must snapshot the tree BEFORE killing the root, because once the
# root dies the parent links break and orphaned grandchildren can't be found again.
_descendant_pids() {
    local p=$1 kid
    for kid in $(pgrep -P "$p" 2>/dev/null); do
        _descendant_pids "$kid"
        printf '%s\n' "$kid"
    done
}
stop_continuous_chowner() {
    (( CHOWNER_PID > 0 )) || return 0
    local victims v
    victims=$(_descendant_pids "$CHOWNER_PID")     # snapshot subtree first
    kill "$CHOWNER_PID" 2>/dev/null
    for v in $victims; do
        kill "$v" 2>/dev/null
        # An in-flight chown -R may be a root child on a native run; reap it via sudo.
        [ -n "$SUDO" ] && $SUDO -n kill "$v" 2>/dev/null
    done
    wait "$CHOWNER_PID" 2>/dev/null
    CHOWNER_PID=0
}

# --- Host ownership handback ------------------------------------------------
# Everything under cache/ output/ logs/ is created by ROOT inside the container,
# so on the host bind mounts it lands root:root and the invoking user cannot
# rm/edit it without sudo. We chown all three trees back to the host user on
# every exit path. The host uid/gid CANNOT be discovered inside the container:
#   * the bind-mount source dirs are auto-created by the Docker daemon as root
#     (host output/ is 0:0), so stat'ing them yields root;
#   * /build and the COPY'd files are ALSO root:root inside the container even
#     when the host build context is owned by the user, because `COPY` without
#     --chown sets uid 0.
# Therefore the ONLY reliable source is the HOST_UID/HOST_GID env vars passed by
#   docker run -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" ...
# If they are absent (or resolve to 0) we DO NOT guess -- we disable the handback
# and print a one-line hint, because a silent chown-to-root would leave the files
# locked (the exact bug we are fixing) with no signal to the user.
resolve_host_owner() {
    HOST_UID=${HOST_UID:-}
    HOST_GID=${HOST_GID:-}
    # Reject anything non-numeric / empty / partial.
    case "$HOST_UID:$HOST_GID" in
        *[!0-9:]*|:*|*:|'') HOST_UID=''; HOST_GID='' ;;
    esac
    # Reject uid 0: it means "unresolved" for our purposes -- chowning to root is a
    # no-op that leaves everything locked. (Also covers running docker as literal
    # root with -e HOST_UID=0.)
    if [ "${HOST_UID:-0}" = "0" ] || [ "${HOST_GID:-0}" = "0" ]; then
        HOST_UID=''; HOST_GID=''
    fi
    export HOST_UID HOST_GID
    # If we're root in a container with no valid host ids, warn ONCE now (not at
    # exit) so the user can re-run with the -e flags. Only warn when we're clearly
    # in a container as root (the problem is real) to stay quiet on native runs.
    if [ -z "$HOST_UID" ] && [ "$(id -u)" -eq 0 ] && [ -f /.dockerenv ]; then
        echo "[!] HOST_UID/HOST_GID not set: output/ cache/ logs/ will stay root-owned" >&2
        echo "[!] on the host. Re-run with:  -e HOST_UID=\$(id -u) -e HOST_GID=\$(id -g)" >&2
    fi
}
resolve_host_owner

# Persistent download cache (repo root, survives cleanup). Downloads land here
# directly, so caching is incremental and resumable:
#   - present & complete -> pacman skips it, no network hit.
#   - partial (e.g. prior Ctrl-C) -> only the missing files are fetched.
#   - deleted -> everything is re-fetched. To force that: rm -rf cache/
mkdir -p "$CACHEDIR"

# --- Persistent progress bar ----------------------------------------------
# A status bar is pinned to the BOTTOM row of the terminal and repainted on
# every step, while all build output scrolls in the region above it. It shows
# "current/total", a filled bar, and the name of the running step, so there is
# always a single line that follows you through the whole build.
#
# TOTAL_STEPS is the number of step() calls below; bump it if you add/remove one.
# Sub-actions inside a step use plain "    [+] ..." lines and DON'T advance the
# counter, so only real milestones move the bar.
#
# Implementation: a DECSTBM scroll region reserves the last row. If stdout is
# not a TTY (piped to a file / Docker logs) we fall back to plain lines so no
# escape codes leak into the log.
TOTAL_STEPS=24
CURRENT_STEP=0
BAR_LABEL=""

# --- Weighted progress model ------------------------------------------------
# The old bar used pct = CURRENT_STEP*100/TOTAL_STEPS, giving every step 1/24 of
# the bar. But two steps (20 = pacman -Sw + repo-add, 24 = mkarchiso) are ~99% of
# wall-clock, so the bar rocketed to 22/24 in seconds then froze for the whole
# build. We now weight each step and, inside the two giant steps, drive a live
# sub-fraction from the build's own log output. Weights are integers (arbitrary
# units; only ratios matter). Trivial file-copy steps = 1 unit each. The two
# giants are sized from the measured log line-spans of a real run.
STEP_WEIGHTS=(
  0     # index 0 unused (steps are 1-indexed to match CURRENT_STEP)
  1 1 1 1 1 1 1 1 1 1     #  1..10  file copies / mkdir / chown -- all near-instant
  1 1 1 1 1 1 1 1 1       # 11..19  file copies -- all near-instant
  250   # 20 Setting up packages : pacman -Sw (~110u) + repo-add (~140u)  GIANT
  1     # 21 First-boot config    : 3x cp
  1     # 22 force-x11 pacman.conf : 1x cp
  1     # 23 Cleaning temp dir     : rm -rf
  270   # 24 Building ISO         : mkarchiso pacstrap(~230u)+squashfs(~20u)+iso(~20u) GIANT
)
# Prefix sums: ACCUM_WEIGHT[N] = total weight completed at the END of step N.
ACCUM_WEIGHT=(0); _acc=0
for ((i=1; i<=TOTAL_STEPS; i++)); do
    _acc=$(( _acc + ${STEP_WEIGHTS[i]} )); ACCUM_WEIGHT[i]=$_acc
done
TOTAL_WEIGHT=$_acc      # = 19*1 + 250 + 1 + 1 + 1 + 270 = 542

DONE_WEIGHT=0     # sum of weights of fully-completed steps  (= ACCUM_WEIGHT[CURRENT_STEP-1])
CUR_WEIGHT=0      # weight of the step currently running     (= STEP_WEIGHTS[CURRENT_STEP])
SUBFRAC=0         # 0..1000 permille progress WITHIN the current step
SUB_PID=0         # pid of the running background sub-progress reader (0 = none)

# Where the pinned bar's escape codes go (fd 3). It MUST be the same terminal the
# scrolling build output goes to, or the reserved scroll region won't line up.
#   - On the PTY (script): that's stdout, which is a real TTY -> draw to stdout.
#     Bonus: the bar is then captured in the full log too, same as on-screen.
#   - tee fallback: stdout is a pipe, so draw to /dev/tty and keep escapes out of
#     the log (the scrolling text also reaches /dev/tty, so they still align).
if [ "${_COMPILE_ONPTY:-0}" -eq 1 ]; then
    exec 3>&1                                # bar -> stdout (the PTY)
    PROGRESS_TTY=1
elif [ "${_COMPILE_ISATTY:-0}" -eq 1 ] && { exec 3<>/dev/tty; } 2>/dev/null; then
    PROGRESS_TTY=1                           # bar -> real terminal (fd 3 opened above)
else
    PROGRESS_TTY=0
    exec 3>/dev/null
fi

# --- Shared bar layout ------------------------------------------------------
# Compute the four visible pieces of the bar so the WHOLE line is guaranteed to
# fit in `cols` display columns at ANY width -- the old code reserved a fixed 26
# columns for " <label>" and could overflow on a narrow terminal (or leave the
# label running off the right edge). Here the label gets exactly the columns that
# are actually left over, and is dropped entirely when there is no room.
#
# Called by BOTH the foreground draw_bar and the background reader's redraw, so the
# geometry lives in one place and the two can never drift. All the block glyphs and
# the ellipsis are 1 display column each; we count columns explicitly rather than
# via ${#str} because the reader runs under LC_ALL=C where ${#str} counts BYTES
# (each █/░/… is 3 bytes) and would mis-measure the label.
#
# In:  $1=cols $2=eff $3=total $4=pct $5=step $6=steps $7=label
# Out: globals _LP_prefix _LP_bar _LP_pctstr _LP_label  (ready to print in order,
#      separated by nothing except a single space before a non-empty label).
_bar_layout() {
    local cols=$1 eff=$2 total=$3 pct=$4 step=$5 steps=$6 label=$7
    local prefix="" pctstr barw filled i bar=""
    # The "N/24" step counter was dropped from the bar (it read as meaningless): the
    # bar is now just "[████░░░░]  50%  Label". prefix is kept as an empty string so
    # all the width/centering math below (which sums ${#prefix}) still holds with no
    # other change. step/steps stay in the signature for callers but are unused here.
    printf -v pctstr ' %3d%% ' "$pct"                  # ASCII: width == ${#pctstr}
    # Columns left for the bar + a 1-col separator + the label, after the fixed
    # ASCII counter and percent. Never let the bar itself drop below 8 columns; if
    # even that doesn't fit, the caller-side clamps below drop the label/bar.
    local fixed=$(( ${#prefix} + ${#pctstr} ))
    # Give the bar up to ~55% of the remaining width, floor 8, so there is always
    # room for a label on a reasonably wide terminal but the bar shrinks first when
    # space is tight.
    local avail=$(( cols - fixed ))
    barw=$(( avail * 55 / 100 )); (( barw < 8 )) && barw=8
    (( barw > avail )) && barw=$avail                  # ultra-narrow: bar takes all
    (( barw < 0 )) && barw=0
    filled=$(( total > 0 ? eff * barw / (1000 * total) : 0 )); (( filled > barw )) && filled=barw
    (( filled < 0 )) && filled=0
    for ((i=0; i<filled;   i++)); do bar+="█"; done
    for ((i=filled; i<barw; i++)); do bar+="░"; done
    # Whatever columns remain after prefix+bar+pctstr become the label budget, minus
    # 1 for the space that separates them. If <=0, there's no room -> no label.
    local budget=$(( cols - fixed - barw - 1 ))
    if (( budget <= 0 )); then
        label=""
    elif (( ${#label} > budget )); then
        # Labels are ASCII, so ${#label} is the display width and a byte-slice is a
        # char-slice. Reserve 1 column for the ellipsis (its own display width is 1).
        if (( budget >= 2 )); then
            label="${label:0:budget-1}…"
        else
            label="${label:0:budget}"
        fi
    fi
    # Total display width of the assembled line (prefix+bar+pctstr, plus the 1-col
    # separator and label when present). Callers use it to center the line: the bar
    # pieces are ASCII/box-drawing whose display width equals their char count, so
    # summing char counts is correct. Left pad = (cols - width) / 2, floored at 0.
    local width=$(( ${#prefix} + barw + ${#pctstr} ))
    [ -n "$label" ] && width=$(( width + 1 + ${#label} ))
    local pad=$(( (cols - width) / 2 )); (( pad < 0 )) && pad=0
    _LP_prefix=$prefix; _LP_bar=$bar; _LP_pctstr=$pctstr; _LP_label=$label; _LP_col=$(( pad + 1 ))
}

# Redraw the pinned bottom bar. Saves cursor, jumps to the last row, paints the
# bar, then restores the cursor back into the scroll region.
draw_bar() {
    [ "$PROGRESS_TTY" -eq 1 ] || return 0
    local rows cols pct eff sf
    rows=$(tput lines <&3); cols=$(tput cols <&3)
    [ -n "$cols" ] || cols=80; [ -n "$rows" ] || rows=24
    # Effective completed weight (permille units) = fully-done steps + the partial
    # of the current step. Clamp SUBFRAC to [0,1000] so a bad parse can never push
    # this step past its own slice.
    sf=$SUBFRAC; (( sf < 0 )) && sf=0; (( sf > 1000 )) && sf=1000
    eff=$(( DONE_WEIGHT * 1000 + CUR_WEIGHT * sf ))
    pct=$(( eff / 10 / TOTAL_WEIGHT )); (( pct > 100 )) && pct=100

    # Layout: " 20/24 ████████░░░░  80%  Building ISO". _bar_layout sizes every
    # piece so the whole line fits in `cols` and truncates/drops the label as needed.
    _bar_layout "$cols" "$eff" "$TOTAL_WEIGHT" "$pct" "$CURRENT_STEP" "$TOTAL_STEPS" "$BAR_LABEL"
    local sep=""; [ -n "$_LP_label" ] && sep=" "

    # All escape output goes to fd 3 so it paints the real terminal and never
    # lands in the tee'd full log. The bar is PINNED to the bottom row: save the
    # cursor, jump to the last row, paint, then restore the cursor back inside the
    # scroll region (rows 1..N-1) where the build output keeps scrolling.
    {
        # \033[s save cursor · jump to row N col 1 · \033[K clear the whole row ·
        # jump to the centered start column · dim counter · cyan bar · bold percent ·
        # plain label · \033[u restore cursor. _LP_col centers the line in `cols`.
        printf '\033[s\033[%d;1H\033[K\033[%d;%dH\033[2m%s\033[0m\033[36m%s\033[0m\033[1m%s\033[0m%s%s\033[u' \
            "$rows" "$rows" "$_LP_col" "$_LP_prefix" "$_LP_bar" "$_LP_pctstr" "$sep" "$_LP_label"
    } >&3
}

# Print the bar ONE last time as a permanent, normal (scrolled) line -- used at the
# end of a successful build so a completed 100% bar stays on screen (the pinned bar
# is wiped by progress_cleanup on exit). Unpins the scroll region first so the line
# lands in normal flow, computes the layout from the current SUBFRAC (caller sets it
# to 1000 for 100%), and writes to stdout so it is also captured in the full log.
# On a non-TTY run it prints a plain, escape-free "[####....]  100%  <label>" line.
finalize_bar() {
    local cols rows pct eff sf=$SUBFRAC
    (( sf < 0 )) && sf=0; (( sf > 1000 )) && sf=1000
    eff=$(( DONE_WEIGHT * 1000 + CUR_WEIGHT * sf ))
    pct=$(( eff / 10 / TOTAL_WEIGHT )); (( pct > 100 )) && pct=100
    if [ "${PROGRESS_TTY:-0}" -eq 1 ]; then
        printf '\033[r' >&3                      # unpin: restore full scroll region
        cols=$(tput cols <&3 2>/dev/null) || cols=80
        _bar_layout "$cols" "$eff" "$TOTAL_WEIGHT" "$pct" "$CURRENT_STEP" "$TOTAL_STEPS" "$BAR_LABEL"
        local sep=""; [ -n "$_LP_label" ] && sep=" "
        # Print as a normal line (scrolls, persists). Leading \r\033[K clears whatever
        # the pinned bar left on the current row; then the centered, colored bar.
        printf '\r\033[K%*s\033[2m%s\033[0m\033[36m%s\033[0m\033[1m%s\033[0m%s%s\n' \
            "$(( _LP_col - 1 ))" "" "$_LP_prefix" "$_LP_bar" "$_LP_pctstr" "$sep" "$_LP_label" >&3
    else
        # No TTY: plain ASCII bar so nothing weird lands in a piped log.
        local barw=40 filled i bar=""
        filled=$(( eff * barw / (1000 * TOTAL_WEIGHT) )); (( filled > barw )) && filled=barw
        for ((i=0; i<filled; i++)); do bar+="#"; done
        for ((i=filled; i<barw; i++)); do bar+="."; done
        printf '[%s] %3d%%  %s\n' "$bar" "$pct" "$BAR_LABEL"
    fi
}

# (Re-)reserve the bottom row: scroll region = rows 1..(N-1). Subprocesses like
# pacman and mkarchiso reset the terminal's scroll region for their own progress
# bars, which unpins ours; calling this again before each redraw re-arms it so
# the bar never gets scrolled away or frozen mid-build. progress_cleanup runs on
# EVERY catchable exit and resets the region (\033[r), so the terminal is left
# sane; the only unrecoverable case is SIGKILL, which no trap can catch anyway.
arm_region() {
    [ "$PROGRESS_TTY" -eq 1 ] || return 0
    local rows; rows=$(tput lines <&3 2>/dev/null) || return 0
    # DECSTBM: scroll region = rows 1..(rows-1), leaving row `rows` for the bar.
    printf '\033[1;%dr' "$((rows - 1))" >&3
}

# First-time setup: reserve the bottom row, then paint the initial (empty) bar
# pinned to it. arm_region sets the scroll region so subsequent build output
# scrolls in rows 1..N-1 and never overwrites the bar.
progress_init() {
    [ "$PROGRESS_TTY" -eq 1 ] || return 0
    arm_region
    draw_bar
}

# Restore the full scroll region and cursor. Runs on any exit (success, error,
# Ctrl-C) so the terminal is never left in a broken state.
# Always restore the terminal to a sane state on ANY exit, without depending on a
# `tput lines` query that can fail during a signal. ESC[r resets the scroll region
# to the full screen, ESC[K clears the bar line, ESC[0m drops leftover attributes.
# We deliberately do NOT emit ESC c (RIS): that would wipe the build output.
progress_cleanup() {
    # Guaranteed reader sweep: the EXIT trap runs progress_cleanup but NOT
    # terminate_build, so an `exit 1` after a sub_start (that somehow skipped
    # sub_stop) would otherwise leave the reader alive. Idempotent.
    if (( ${SUB_PID:-0} > 0 )); then
        kill "$SUB_PID" 2>/dev/null; pkill -P "$SUB_PID" 2>/dev/null
        wait "$SUB_PID" 2>/dev/null; SUB_PID=0
    fi
    if [ "${PROGRESS_TTY:-0}" -eq 1 ]; then
        { printf '\r\033[K\033[r\033[0m'; tput cnorm 2>/dev/null; } >&3 2>/dev/null
    fi
    # Belt-and-braces: reset the line discipline so a killed child can't leave the
    # tty in raw/no-echo mode. The whole group is redirected so that when there is
    # no controlling terminal (docker run without -t, piped/CI) bash's own
    # "/dev/tty: No such device or address" open-error is swallowed too.
    { stty sane </dev/tty >/dev/tty; } >/dev/null 2>&1 || true
}

# Guard so the kill runs at most once.
_KILLED=0
terminate_build() {
    [ "$_KILLED" -eq 1 ] && return 0
    _KILLED=1
    # Kill the sub-progress reader first (and its tail|grep leaf) and WAIT it, so
    # it can't fire one last bar redraw into fd 3 while progress_cleanup is
    # restoring the terminal on the same line.
    if (( ${SUB_PID:-0} > 0 )); then
        kill "$SUB_PID" 2>/dev/null
        pkill -P "$SUB_PID" 2>/dev/null
        wait "$SUB_PID" 2>/dev/null
        SUB_PID=0
    fi
    # Signal the whole process group so pacman/mkarchiso and their pacstrap chroot
    # children die together. On a native run this shell is unprivileged while those
    # children are root, so an unprivileged kill(2) is rejected with EPERM and does
    # nothing -- which is why the build used to drag on and every extra Ctrl-C just
    # reprinted. We escalate through $SUDO to reach the root PIDs. Ignore INT/TERM
    # in this shell first so the group signal doesn't take us down before the trap
    # finishes its unmount + ownership handback.
    trap '' INT TERM
    local pgid
    pgid=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')
    kill_group "${pgid:-$$}"
}

# Kill the build's children (mkarchiso/pacstrap and their descendants) WITHOUT
# killing this shell -- the previous version sent `kill -KILL -$pgid` to the whole
# process group, and since this shell is IN that group and KILL cannot be trapped or
# ignored, it took the parent down MID-TRAP, before handback_ownership ran. That is
# exactly why cache/build/ was left root-owned and locked after a Ctrl-C.
#
# So we enumerate the group's PIDs and signal every one EXCEPT our own ($$) and the
# sudo keepalive. Root children (pacstrap under mkarchiso) are killed via `sudo -n`
# (the keepalive keeps the timestamp warm). $SUDO empty -> we are root already.
kill_group() {
    local pgid=$1 s p pids
    for s in TERM KILL; do
        # PIDs in this process group, minus this shell and the keepalive loop.
        pids=$(ps -o pid= -o pgid= -a 2>/dev/null | awk -v g="$pgid" -v me="$$" -v h="${SUDO_KEEPALIVE_PID:-0}" -v c="${CHOWNER_PID:-0}" \
                 '$2==g && $1!=me && $1!=h && $1!=c {print $1}')
        for p in $pids; do
            kill -"$s" "$p" 2>/dev/null || true
            [ -n "$SUDO" ] && $SUDO -n kill -"$s" "$p" 2>/dev/null || true
        done
    done
}

# --- Live sub-progress readers ----------------------------------------------
# During the two giant steps (20, 25) a background reader tails the live full.log
# and maps the build's own progress lines to SUBFRAC (0..1000), redrawing the bar
# on fd 3. The reader is a DIRECT child of this shell's process group, so the
# existing group-kill in terminate_build reaps it too; we also kill it explicitly.
#
# CRITICAL: while a reader is alive it is the SOLE writer of the bar. The reader
# runs in a backgrounded subshell, so it cannot mutate the parent's SUBFRAC; it
# owns its own copies of the weight context (passed as locals) and draws the bar
# itself. The foreground does not touch the bar between sub_start and sub_stop.

# Start a background bar-driver for the current step.
#   $1 = mode: "step20" | "mkarchiso"
#   $2 = (step20 only) repo-add package count for the repo-add band divisor.
sub_start() {
    [ "$PROGRESS_TTY" -eq 1 ] || return 0        # no TTY -> spawn nothing, no log noise
    local mode=$1 repo_total=${2:-0}
    # Snapshot the weight/label context so the child needs no shared parent state.
    local done=$DONE_WEIGHT cur=$CUR_WEIGHT total=$TOTAL_WEIGHT
    local step=$CURRENT_STEP steps=$TOTAL_STEPS label=$BAR_LABEL
    {
        # Force C locale so EPOCHREALTIME uses a '.' decimal separator (the throttle
        # math below strips it) and so the tail|grep regex is byte-wise/fast.
        LC_ALL=C
        local sf=0 last=-1 cols=80 rows=24 lastdraw=0 now rc=0 rc2=0 m=0 inpac=0
        # Cache terminal width/height; only re-query occasionally (avoid a tput fork
        # per package line during pacstrap's ~1381 Total() updates). SIGWINCH re-reads.
        cols=$(tput cols <&3 2>/dev/null) || cols=80
        rows=$(tput lines <&3 2>/dev/null) || rows=24
        trap 'cols=$(tput cols <&3 2>/dev/null) || cols=80; rows=$(tput lines <&3 2>/dev/null) || rows=24' WINCH
        # Redraw via the shared _bar_layout (inherited into this subshell) so the
        # width math matches the foreground exactly and always fits `cols`. Throttled
        # to ~4/s. Note: _bar_layout counts columns explicitly, so it is correct even
        # though this subshell runs under LC_ALL=C where ${#str} would count bytes.
        redraw() {
            now=$(( ${EPOCHREALTIME/./} ))       # microseconds; bash 5 builtin
            # Throttle: at most one redraw per ~250ms UNLESS this is the final snap.
            if (( sf < 1000 )) && (( now - lastdraw < 250000 )); then return 0; fi
            lastdraw=$now
            local pct eff sep=""
            (( sf < 0 )) && sf=0; (( sf > 1000 )) && sf=1000
            eff=$(( done*1000 + cur*sf )); pct=$(( eff/10/total )); (( pct>100 )) && pct=100
            _bar_layout "$cols" "$eff" "$total" "$pct" "$step" "$steps" "$label"
            [ -n "$_LP_label" ] && sep=" "
            # Pinned to the bottom row: save cursor, jump to row N, clear the line
            # with \r\033[K (the same token the tail|grep guard drops, so the reader
            # never re-ingests its own output), jump to the centered start column,
            # paint, restore cursor. Keep the \r\033[K clear BEFORE the reposition so
            # the self-feedback guard still matches the emitted line's prefix.
            printf '\033[s\033[%d;1H\r\033[K\033[%d;%dH\033[2m%s\033[0m\033[36m%s\033[0m\033[1m%s\033[0m%s%s\033[u' \
                "$rows" "$rows" "$_LP_col" "$_LP_prefix" "$_LP_bar" "$_LP_pctstr" "$sep" "$_LP_label" >&3
        }
        # Follow only NEW lines (-n0), then translate CR->LF. This is the crux of the
        # progress fix: pacman/pacstrap redraw their live progress with CARRIAGE
        # RETURNS, not newlines, so a whole phase like "checking keys in keyring" is a
        # SINGLE ~98KB physical line carrying ~1200 embedded '\r' frames. Without the
        # `tr`, `read -r` (which splits on '\n' only) receives that entire phase as one
        # line delivered AFTER it finishes -- so the reader saw none of the intermediate
        # (N/M) counts and the bar froze for the whole multi-minute phase. `tr '\r' '\n'`
        # turns every frame into its own line so the loop can react to each (N/M) live.
        # The grep then DROPS the reader's own bar redraws: after the `tr` split, our
        # redraw's leading "\r\033[K" becomes an empty line + a line starting with
        # ESC[K, so we drop any line containing ESC[K (self-feedback guard).
        # --line-buffered keeps it real-time.
        tail -n0 -F "$FULL_LOG" 2>/dev/null \
          | tr '\r' '\n' \
          | grep --line-buffered -av $'\033\[K' \
          | while IFS= read -r line; do
            case $mode in
              step20)
                # step 20 = cache-pkgs.sh: sync DB -> download missing pkgs -> index
                # (repo-add) -> stage into airootfs. We drive SUBFRAC from cache-pkgs.sh's
                # own milestone echoes and from pacman's live per-file download counter,
                # so the bar moves smoothly whether the cache is cold (real downloads)
                # or warm (near-instant). Bands: DB/download 0..440, index 440..880,
                # stage 880..1000.
                #
                # Phase A: pacman -Sw download. pacman prints one "downloading <file>"
                # line per package as it fetches; count them against the package total
                # (repo_total is the current repo size, a good upper bound). On a fully
                # cached run there are no downloads and this never fires.
                if [[ $line == *"downloading "*".pkg.tar."* ]]; then
                    (( rc++ ))
                    if (( repo_total > 0 )); then
                        local d=$(( rc * 440 / repo_total )); (( d > 440 )) && d=440
                        (( d > sf )) && sf=$d
                    fi
                # Milestone: DB synced / download step reached -> ensure we're at least
                # at the start of the download band so the bar leaves 0 promptly.
                elif [[ $line == *"Downloading missing packages"* ]]; then
                    (( sf < 20 )) && sf=20
                # Phase B: repo-add indexing -> band 440..880. The fresh-seed path
                # (cache-pkgs.sh, first run only) prints "[+] Indexing N/TOTAL
                # packages..." per chunk -- parse that N/TOTAL directly so the bar
                # tracks the one-time seed exactly instead of sitting idle.
                elif [[ $line =~ \[\+\]\ Indexing\ ([0-9]+)/([0-9]+)\ packages ]]; then
                    local n=${BASH_REMATCH[1]} m=${BASH_REMATCH[2]}
                    (( m > 0 )) && sf=$(( 440 + n * 440 / m ))
                # Fallback: on paths where repo-add itself is verbose, count its
                # 'Adding package' lines against the passed-in file total.
                elif [[ $line == *"Adding package '"* ]]; then
                    (( rc2++ ))
                    if (( repo_total > 0 )); then
                        sf=$(( 440 + rc2 * 440 / repo_total ))
                    else
                        (( sf < 440 )) && sf=440
                    fi
                # Milestone: reconcile reached (index up to date on a warm cache, so the
                # Indexing/Adding lines never appear) -> advance past the index band.
                elif [[ $line == *"Reconciling local repository index"* ]]; then
                    (( sf < 440 )) && sf=440
                # Phase C: staging the cache into the airootfs -> band 880..1000.
                elif [[ $line == *"Staging cached packages"* ]]; then
                    (( sf < 880 )) && sf=880
                elif [[ $line == *"Package cache is complete and staged"* ]]; then
                    sf=1000
                fi ;;
              mkarchiso)
                # Step 24 = mkarchiso. pacstrap dominates (~84% of the step). pacstrap
                # runs pacman, whose live progress is a series of "(N/M) <phase>" frames
                # redrawn with '\r' -- now split into individual lines by the `tr` above.
                # We map each pacman phase to its own sub-band within 20..820 and scale
                # by that phase's own N/M, so the bar RAMPS smoothly through the whole
                # multi-minute install instead of freezing at 20 (the exact bug this
                # fixes: the old code looked for "Total (N/M)", a string pacman NEVER
                # prints). squashfs/checksum/iso keep their milestone snaps after 820.
                #
                # pacman phase order during a pacstrap: keyring -> integrity -> load
                # files -> file conflicts -> disk space -> installing/upgrading (the
                # long one) -> post-transaction hooks. Bands are sized to roughly match
                # each phase's share of wall-clock (install dominates).
                case $line in
                  *"Installing packages to"*)   inpac=1; (( sf<20 )) && sf=20 ;;
                  *"Done! Packages installed"*) inpac=0; (( sf<820 )) && sf=820 ;;
                  *"Creating SquashFS image"*)  inpac=0; (( sf<840 )) && sf=840 ;;
                  *"Creating checksum file"*)   (( sf<930 )) && sf=930 ;;
                  *"Creating ISO image"*)       (( sf<960 )) && sf=960 ;;
                  *)
                    # Map pacman's "(N/M) <phase>" frames while pacstrap is running.
                    # Each phase gets [base..base+span]; within it we scale by N/M.
                    if (( inpac == 1 )) && [[ $line =~ \(\ *([0-9]+)/([0-9]+)\)\ (checking\ keys\ in\ keyring|checking\ package\ integrity|loading\ package\ files|checking\ for\ file\ conflicts|checking\ available\ disk\ space|installing|upgrading|reinstalling|downgrading) ]]; then
                        local n=${BASH_REMATCH[1]} mm=${BASH_REMATCH[2]} ph=${BASH_REMATCH[3]}
                        local base=20 span=0
                        case $ph in
                          "checking keys in keyring")      base=20;  span=90  ;;  #  20..110
                          "checking package integrity")    base=110; span=70  ;;  # 110..180
                          "loading package files")         base=180; span=20  ;;  # 180..200
                          "checking for file conflicts")   base=200; span=20  ;;  # 200..220
                          "checking available disk space") base=220; span=20  ;;  # 220..240
                          installing|upgrading|reinstalling|downgrading)
                                                           base=240; span=580 ;;  # 240..820 (long)
                        esac
                        if (( mm > 0 )); then
                            local d=$(( base + n * span / mm ))
                            (( d > sf )) && sf=$d       # monotonic within the band
                        fi
                    fi ;;
                esac ;;
            esac
            (( sf < last )) && sf=$last          # never go backwards (seam guard)
            if (( sf != last )); then last=$sf; redraw; fi
        done
    } &
    SUB_PID=$!
}

# Stop the reader, snap the current step to 100% of its slice, redraw once from
# the foreground. Idempotent (SUB_PID resets to 0). Called on EVERY exit path of
# a giant step (success and failure branches).
sub_stop() {
    if (( SUB_PID > 0 )); then
        kill "$SUB_PID" 2>/dev/null
        pkill -P "$SUB_PID" 2>/dev/null          # kill the tail|grep leaf pipeline
        wait "$SUB_PID" 2>/dev/null              # reap; ensures no late fd-3 write
        SUB_PID=0
    fi
    SUBFRAC=1000; draw_bar; SUBFRAC=0            # foreground: snap step to complete
}

# Best-effort teardown of any mkarchiso bind mounts left under the work tree, so a
# Ctrl-C'd/failed build doesn't leave proc/sys/dev mounted and so the ownership
# handback doesn't try to chown into a live procfs. Safe to call anytime.
unmount_worktree() {
    local m AIROOTFS_W="$WORKDIR/work/x86_64/airootfs"
    [ -d "$AIROOTFS_W" ] || return 0
    # Non-interactive sudo; the keepalive keeps the timestamp warm across the build.
    for m in proc sys dev run; do
        if mountpoint -q "$AIROOTFS_W/$m" 2>/dev/null; then
            $SUDO -n umount -lf "$AIROOTFS_W/$m" 2>/dev/null || true
        fi
    done
    $SUDO -n umount -R "$AIROOTFS_W" 2>/dev/null || true
    return 0
}

# Hand the three build trees back to the invoking user so nothing is left
# root-owned/locked. Best-effort, idempotent, never hangs, never aborts the exit.
# Two distinct paths create root-owned files, and BOTH must be handed back or
# cache/build/ ends up locked:
#   * Docker: the WHOLE script runs as root inside the container; the host bind
#     mounts land root:root. We chown to HOST_UID/HOST_GID (passed via -e), and
#     can chown directly because we ARE root.
#   * Native: the script runs as the user with $SUDO=sudo, so only mkarchiso &
#     pacstrap run as root -- but THEY create cache/build/** as root. We chown
#     back to the current (non-root) user, escalating via $SUDO since the files
#     are root-owned. This is the case the old code skipped (it returned early
#     whenever id!=0), which is exactly why native Ctrl-C left the tree locked.
_HANDED_BACK=0
handback_ownership() {
    [ "$_HANDED_BACK" -eq 1 ] && return 0
    _HANDED_BACK=1
    local owner d
    if [ "$(id -u)" -eq 0 ]; then
        # Root (Docker path): hand back to the host user, but only if resolved.
        [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ] || return 0   # unresolved -> skip
        owner="$HOST_UID:$HOST_GID"
    else
        [ -n "$SUDO" ] || return 0
        owner="$(id -u):$(id -g)"
    fi
    reclaim_trees "$owner"
    return 0
}

# Hand cache/ output/ logs/ back to $1 (uid:gid) so the user is never locked out.
# This is the ONE operation that must never be skipped. It restores BOTH:
#   * ownership (chown) -- mkarchiso/pacstrap create files as root; and
#   * owner WRITE permission (chmod -R u+w) -- pacstrap builds a real rootfs, so some
#     dirs (airootfs, /usr subdirs, etc.) are mode r-x with NO write bit. chown alone
#     leaves those un-deletable even once you own them (you couldn't rm cache/build/):
#     the missing write bit is a second, independent lock. u+w on dirs restores the
#     ability to modify/delete the tree; it never removes any existing access.
# Runs directly (no helper/FIFO/signal indirection). Idempotent.
reclaim_trees() {
    local owner=$1 d chown_cmd chmod_cmd
    if [ "$(id -u)" -eq 0 ]; then
        chown_cmd=(chown); chmod_cmd=(chmod)                 # already root
    else
        chown_cmd=($SUDO -n chown); chmod_cmd=($SUDO -n chmod)  # keepalive keeps ts warm
    fi
    for d in "$CACHEDIR" "$BUILDDIR" "$LOGDIR"; do
        [ -d "$d" ] || continue
        "${chown_cmd[@]}" -R --preserve-root "$owner" "$d" 2>/dev/null || true
        "${chmod_cmd[@]}" -R u+w "$d" 2>/dev/null || true
    done
}

# Low-cost periodic reclaim used ONLY by the continuous chowner. Unlike
# reclaim_trees it deliberately does NOT recurse the work tree $WORKDIR
# (=cache/build): during mkarchiso that subtree holds the airootfs with LIVE
# bind mounts (proc/sys/dev/run) and becomes the squashfs, so recursing it here
# would chown into the host's real /dev,/sys,/run (under --privileged), race
# pacstrap, and bake wrong owner/modes into the ISO. cache/build is reclaimed
# only by the inline reclaim_now that runs AFTER unmount_worktree.
# What it DOES reclaim, live, every few seconds:
#   * the three top-level roots cache/ output/ logs/ (non-recursive) -- so the
#     inodes the Docker daemon and root create directly under them are unlocked;
#   * every direct child of cache/ EXCEPT build/ (recursive) -- the persistent
#     stores (cache/pkgs, cache/pip, cache/pacman-pkg, ...) that grow during the
#     build, without ever entering the live work tree;
#   * output/ and logs/ in full (recursive) -- small, no live mounts, safe.
reclaim_periodic() {
    local owner=$1 d chown_cmd chmod_cmd
    if [ "$(id -u)" -eq 0 ]; then
        chown_cmd=(chown); chmod_cmd=(chmod)                 # already root
    else
        chown_cmd=($SUDO -n chown); chmod_cmd=($SUDO -n chmod)  # keepalive keeps ts warm
    fi
    # Non-recursive unlock of the top inodes (cheap; catches daemon-created dirs).
    for d in "$CACHEDIR" "$BUILDDIR" "$LOGDIR"; do
        [ -d "$d" ] || continue
        "${chown_cmd[@]}" "$owner" "$d" 2>/dev/null || true
        "${chmod_cmd[@]}" u+w "$d" 2>/dev/null || true
    done
    # Recurse output/ and logs/ fully (no live mounts, small trees).
    for d in "$BUILDDIR" "$LOGDIR"; do
        [ -d "$d" ] || continue
        "${chown_cmd[@]}" -R --preserve-root "$owner" "$d" 2>/dev/null || true
        "${chmod_cmd[@]}" -R u+w "$d" 2>/dev/null || true
    done
    # Recurse every child of cache/ EXCEPT the work tree (cache/build). This
    # auto-covers the persistent caches without ever descending into the airootfs
    # bind mounts -- the naive `chown -R cache/` hazard is avoided by construction.
    for d in "$CACHEDIR"/*; do
        [ -e "$d" ] || continue          # empty glob guard
        [ "$d" = "$WORKDIR" ] && continue # NEVER the live work tree
        "${chown_cmd[@]}" -R --preserve-root "$owner" "$d" 2>/dev/null || true
        "${chmod_cmd[@]}" -R u+w "$d" 2>/dev/null || true
    done
}

# Reclaim ownership NOW to whoever should own the trees, working in BOTH modes:
#   * Docker (root in container): chown to the host uid/gid passed via -e HOST_UID/GID.
#   * Native (non-root + sudo)  : chown to the invoking user.
# This is what the startup and post-mkarchiso safeguards call. It must NOT be gated on
# `id -u != 0` (an earlier version was, which disabled those safeguards inside Docker --
# the exact case that left cache/build/ root-owned on the host). Idempotent, cheap.
reclaim_now() {
    local owner=""
    if [ "$(id -u)" -eq 0 ]; then
        [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ] && owner="$HOST_UID:$HOST_GID"
    elif [ -n "$SUDO" ]; then
        owner="$(id -u):$(id -g)"
    fi
    [ -n "$owner" ] && reclaim_trees "$owner"
    return 0
}

# On Ctrl-C / SIGTERM: kill the build + reader, unmount mkarchiso's bind mounts,
# restore the terminal, hand the host dirs back, exit 130. The EXIT trap re-runs
# cleanup + handback (both idempotent) for the normal/error-exit paths.
trap 'terminate_build; stop_continuous_chowner; unmount_worktree; progress_cleanup; handback_ownership; stop_sudo_keepalive; exit 130' INT TERM HUP QUIT
trap 'stop_continuous_chowner; progress_cleanup; handback_ownership; stop_sudo_keepalive' EXIT

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    BAR_LABEL="$1"
    DONE_WEIGHT=${ACCUM_WEIGHT[$((CURRENT_STEP-1))]}   # everything before this step
    CUR_WEIGHT=${STEP_WEIGHTS[$CURRENT_STEP]}
    SUBFRAC=0                                        # reset intra-step progress
    arm_region                               # re-pin in case pacman/mkarchiso reset it
    # Goes to stdout -> terminal + full log (via tee).
    printf '\n[ %2d/%d ] %s\n' "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
    # Milestone-only summary, appended straight to the steps log (no escapes).
    printf '[ %2d/%d ] %s\n' "$CURRENT_STEP" "$TOTAL_STEPS" "$1" >> "$STEPS_LOG"
    draw_bar
}

# SAFEGUARD 1 (startup reclaim): unconditionally hand any pre-existing root-owned
# tree back to the user BEFORE doing anything else. A previous run that was
# SIGKILL'd / power-cut cannot have run any trap, so this is the only thing that can
# unlock a tree left behind that way -- guaranteeing the lock never outlives a single
# invocation. Cheap: chown -R over an already-user-owned tree is a near-no-op.
reclaim_now
# Keep the sudo timestamp warm for the whole build so the immediate/trap chowns work.
start_sudo_keepalive
# SAFEGUARD 0 (continuous reclaim): keep the safe trees owned by the host user for
# the WHOLE build, not just at boundaries, so nothing stays locked mid-build for
# more than one sweep interval. Starts after the keepalive so its first `sudo -n`
# finds a warm timestamp. No-op if the owner is unresolved (Docker without -e).
start_continuous_chowner

progress_init

step "Cleaning up previous build directory..."
AIROOTFS=$WORKDIR/work/x86_64/airootfs
for mount in proc sys dev run; do
    if mountpoint -q $AIROOTFS/$mount; then
        echo "    [+] Unmounting $AIROOTFS/$mount..."
        $SUDO umount -lf $AIROOTFS/$mount
    fi
done
$SUDO umount -R $AIROOTFS 2>/dev/null || true
# Wipe the disposable profile/scratch tree and start fresh. We wipe only
# $WORKDIR (cache/build/), never $CACHEDIR (cache/) itself: that keeps the
# persistent download cache (cache/pkgs, cache/pip) intact, and — under Docker,
# where cache/ is the host bind mount — it means the rm never recurses into a
# live mountpoint (cache/build is an ordinary same-fs subdir). output/ (the
# finished ISO) lives outside cache/ entirely and is untouched, so a prior ISO
# survives until the new build overwrites it.
mkdir -p "$BUILDDIR"
$SUDO rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
# Everything below operates inside the profile tree; bare-relative paths
# (airootfs/..., packages.x86_64) resolve here instead of polluting output/.
cd "$WORKDIR"

step "Checking for build-host dependencies..."
HOST_PKGS="archiso git base-devel go"
# These are the tools the build itself runs on (mkarchiso, makepkg, ...),
# not ISO content. If they're already installed we stay fully offline; only a
# missing tool triggers a sync. (Docker also layer-caches these via the Dockerfile.)
if pacman -Qq $HOST_PKGS >/dev/null 2>&1; then
    echo "    [+] Build-host dependencies already present, skipping sync (offline)."
else
    echo "    [+] Installing missing build-host dependencies..."
    $SUDO pacman -Sy --noconfirm --needed $HOST_PKGS
fi

step "Copying releng base into working directory..."
cp -r /usr/share/archiso/configs/releng/* $WORKDIR

step "Adding custom bootloader entries and config files..."
cp $CONFDIR/system/01-archiso-x86_64-linux.conf $WORKDIR/efiboot/loader/entries/
cp $CONFDIR/system/02-archiso-x86_64-speech-linux.conf $WORKDIR/efiboot/loader/entries/
cp $CONFDIR/system/archiso_sys-linux.cfg $WORKDIR/syslinux/

step "Copying custom package list..."
cp $CONFDIR/packages.x86_64 $WORKDIR/packages.x86_64

step "Setting up users..."
mkdir -p airootfs/etc
cp $CONFDIR/system/passwd airootfs/etc/passwd
cp $CONFDIR/system/shadow airootfs/etc/shadow
cp $CONFDIR/system/gshadow airootfs/etc/gshadow
cp $CONFDIR/system/group airootfs/etc/group

step "Creating home directory and configuring permissions to allow SDDM autologin..."
mkdir -p airootfs/home/main
chown -R 1000:998 airootfs/home/main

step "Adding setup-locale script..."
mkdir -p airootfs/root/Easy-Arch
cp $CONFDIR/system/setup-locale.sh airootfs/root/Easy-Arch/setup-locale.sh
chmod +x airootfs/root/Easy-Arch/setup-locale.sh

step "Adding locale systemd service..."
mkdir -p airootfs/etc/systemd/system
cp $CONFDIR/system/locale-setup.service airootfs/etc/systemd/system/locale-setup.service

step "Apply KDE minimal theme..."
mkdir -p airootfs/home/main/.config/menus
mkdir -p airootfs/root/Easy-Arch/Next
mkdir -p airootfs/root/Easy-Arch/kde
cp $CONFDIR/kde/Footer.qml airootfs/root/Easy-Arch/Footer.qml
cp $CONFDIR/kde/main.qml airootfs/root/Easy-Arch/main.qml
cp $CONFDIR/kde/plasmashellrc airootfs/home/main/.config/plasmashellrc
cp $CONFDIR/kde/kwinrc airootfs/home/main/.config/kwinrc
cp $CONFDIR/kde/plasma-org.kde.plasma.desktop-appletsrc airootfs/home/main/.config/plasma-org.kde.plasma.desktop-appletsrc
cp $CONFDIR/kde/applications-kmenuedit.menu airootfs/home/main/.config/menus/applications-kmenuedit.menu
cp $CONFDIR/kde/kdeglobals airootfs/home/main/.config/kdeglobals
cp -r $CONFDIR/kde/Next/. airootfs/root/Easy-Arch/Next/
cp -r $CONFDIR/kde/. airootfs/root/Easy-Arch/kde/

step "Configure pacman..."
cp $CONFDIR/system/pacman.conf airootfs/etc/pacman.conf

step "Adding setup-pkgs script..."
cp $CONFDIR/setup-pkgs.sh airootfs/root/Easy-Arch/setup-pkgs.sh
chmod +x airootfs/root/Easy-Arch/setup-pkgs.sh

step "Adding pkgs systemd service..."
cp $CONFDIR/system/pkgs-setup.service airootfs/etc/systemd/system/pkgs-setup.service

step "Adding SDDM config..."
mkdir -p airootfs/etc
cp $CONFDIR/system/sddm.conf airootfs/etc/sddm.conf

step "Configuring X11..."
mkdir -p airootfs/usr/share/xsessions
cp $CONFDIR/system/plasma.desktop airootfs/usr/share/xsessions/plasma.desktop

step "Linking systemd services..."
mkdir -p airootfs/etc/systemd/system/{multi-user.target.wants,graphical.target.wants}
ln -sf /usr/lib/systemd/system/sddm.service airootfs/etc/systemd/system/graphical.target.wants/sddm.service
ln -sf /usr/lib/systemd/system/NetworkManager.service airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service
ln -sf /usr/lib/systemd/system/bluetooth.service airootfs/etc/systemd/system/multi-user.target.wants/bluetooth.service
ln -sf /usr/lib/systemd/system/org.cups.cupsd.service airootfs/etc/systemd/system/multi-user.target.wants/org.cups.cupsd.service
ln -sf /etc/systemd/system/locale-setup.service airootfs/etc/systemd/system/multi-user.target.wants/locale-setup.service
ln -sf /etc/systemd/system/pkgs-setup.service airootfs/etc/systemd/system/multi-user.target.wants/pkgs-setup.service

step "Setting up sudoers..."
mkdir -p airootfs/etc/sudoers.d
cp $CONFDIR/system/00-rootpw airootfs/etc/sudoers.d/00-rootpw
cp $CONFDIR/system/00-main airootfs/etc/sudoers.d/00-main
chmod 440 airootfs/etc/sudoers.d/00-rootpw
chmod 440 airootfs/etc/sudoers.d/00-main

step "Copying profile definition..."
cp $CONFDIR/system/profiledef.sh $WORKDIR/profiledef.sh

step "Setting up Easy Arch ISO Installer script that runs on startup..."
mkdir -p airootfs/home/main/.config/autostart
mkdir -p airootfs/home/main/Desktop
cp $CONFDIR/install/easy-arch-iso-installer.sh airootfs/home/main/Desktop/easy-arch-iso-installer.sh
cp "$CONFDIR/install/easy-arch-iso-install.desktop" airootfs/home/main/.config/autostart/easy-arch-iso-install.desktop

step "Setting up packages for harddrive installation..."
# The cache script downloads straight into cache/pkgs (persistent), so it is
# incremental and resumable: only missing packages are fetched, and a prior
# Ctrl-C leaves finished ones cached. It then stages the cache into the airootfs.
# Divisor for the repo-add sub-band: count the .pkg.tar.zst in the persistent repo
# as an upper bound. cache-pkgs.sh now reconciles the repo index INCREMENTALLY
# (it only repo-adds new/changed packages, quietly), so on a fully-cached re-run the
# indexing is near-instant and emits few/no "Adding package" lines -- the reader's
# repo-add band simply doesn't fill and sub_stop snaps step 20 to 100%. On a run
# that actually downloads new packages the band advances per "Adding package" line
# up to this count. Fallback 0 -> reader holds at band start.
REPO_TOTAL=$(ls -1 "$CACHEDIR"/pkgs/repo/*.pkg.tar.zst 2>/dev/null | wc -l)
sub_start step20 "$REPO_TOTAL"               # live download + repo-add sub-progress
if ! bash $CONFDIR/install/cache-pkgs.sh "$WORKDIR" "$CACHEDIR"; then
    sub_stop
    echo "[✗] Package caching/staging failed..."
    exit 1
fi
sub_stop
arm_region; draw_bar                         # pacman reset the region; re-pin the bar
mkdir -p airootfs/root/Easy-Arch/pacman-base-conf
mkdir -p airootfs/root/Easy-Arch/pacstrap-easyarch-conf
cp $CONFDIR/packages.x86_64 airootfs/root/Easy-Arch/packages.x86_64
cp $CONFDIR/system/pacman.conf airootfs/root/Easy-Arch/pacman-base-conf/pacman.conf
cp $CONFDIR/install/pacstrap-easyarch-conf/pacman.conf airootfs/root/Easy-Arch/pacstrap-easyarch-conf/pacman.conf
cp $CONFDIR/install/chroot-setup.sh airootfs/root/Easy-Arch/chroot-setup.sh

step "Copying and setting up first boot configuration script..."
cp $CONFDIR/install/first-boot/first-boot-setup.sh airootfs/root/Easy-Arch/first-boot-setup.sh
cp $CONFDIR/install/first-boot/first-boot-setup.service airootfs/root/Easy-Arch/first-boot-setup.service
cp $CONFDIR/install/first-boot/first-boot-setup.conf airootfs/root/Easy-Arch/first-boot-setup.conf

step "Prepare script that forces x11 session..."
cp $CONFDIR/system/force-x11-session/pacman.conf $WORKDIR/pacman.conf
# Point mkarchiso's internal pacstrap at the PERSISTENT package cache so the
# live-ISO packages (~1200, several GB) are reused across builds instead of
# re-downloaded from mirrors every time. Without this, mkarchiso resolves the
# profile CacheDir to the default /var/cache/pacman/pkg -- ephemeral inside the
# container (emptied by the image's `pacman -Scc`, destroyed by `docker run
# --rm`) -- so every build refetched the whole set even with a warm cache/.
# mkarchiso only honors a profile CacheDir when it differs from the default, so
# we inject a non-default absolute path here (correct for Docker's /build/cache
# and a native run's $REPODIR/cache alike). The dir must exist before mkarchiso
# runs; pacman writes new packages here too, so the cache stays warm going forward.
PACSTRAP_CACHE="$CACHEDIR/pacman-pkg"
mkdir -p "$PACSTRAP_CACHE"
# Drop any existing (commented or active) CacheDir line, then add the real one
# right after [options]. Two steps so the result is exactly one active CacheDir
# regardless of what the template had.
sed -i '/^#*CacheDir/d' "$WORKDIR/pacman.conf"
sed -i "/^\[options\]/a CacheDir    = $PACSTRAP_CACHE/" "$WORKDIR/pacman.conf"

step "Cleaning up temp directory..."
rm -rfv $WORKDIR/.temp

step "Building ISO..."
### This line fixes an odd bug that appeared out of nowhere
### """FATAL ERROR: xz uncompress failed with error code 9""" 
export MKSQUASHFS_OPTIONS="-processors 4"
###
# profile_dir = $WORKDIR (cache/build); scratch = $WORKDIR/work; ISO -> $BUILDDIR
# (output/) directly via -o, so the finished .iso sits in output/ next to nothing.
sub_start mkarchiso                           # live pacstrap + squashfs + iso sub-progress
$SUDO mkarchiso -v -w "$WORKDIR/work" -o "$BUILDDIR" "$WORKDIR"
sub_stop
# SAFEGUARD 2 (immediate reclaim): mkarchiso just created cache/build/** as root.
# Reclaim ownership RIGHT NOW, inline, while the sudo timestamp is guaranteed fresh
# (mkarchiso used it moments ago) -- not deferred to a trap that could be skipped or
# hit an expired timestamp. First drop any bind mounts so the chown doesn't touch a
# live procfs. After this line cache/build/ is already user-owned on the normal path;
# the exit trap's handback is then just a redundant safety net.
unmount_worktree
reclaim_now
if [ -n "$(find "$BUILDDIR" -maxdepth 1 -type f -name '*.iso')" ]; then
    # Finalize the bar at 100%. The pinned bar is cleared by progress_cleanup on exit,
    # so we also print a permanent full bar as a normal (scrolled) line here -- that is
    # the "done" state the user actually sees. Force SUBFRAC=1000 because sub_stop reset
    # it to 0 (and step 24 starts at 50%), which is why the bar looked stuck at 50%.
    SUBFRAC=1000; finalize_bar
    # Report the ISO's ACTUAL location. mkarchiso prints the path it wrote to, which
    # inside Docker is the container path (/build/output/...) -- not where the file
    # really is for the user. So we echo the true location ourselves:
    #   * Native run: BUILDDIR is the real absolute host path -> print it verbatim.
    #   * Docker run: /build/output is a bind mount of the host's repo output/ dir, so
    #     the container can't know the host's absolute path; print the repo-relative
    #     output/<iso> (correct and unambiguous on the host).
    ISO_FILE=$(find "$BUILDDIR" -maxdepth 1 -type f -name '*.iso' -printf '%f\n' 2>/dev/null | head -1)
    # Compute the size ourselves with `du -h` so the number matches (and lets the
    # user ignore) mkarchiso's own trailing du line, which shows the CONTAINER path.
    ISO_SIZE=$(du -h "$BUILDDIR/$ISO_FILE" 2>/dev/null | cut -f1)
    if [ -f /.dockerenv ]; then
        ISO_PATH="output/$ISO_FILE"
    else
        ISO_PATH="$BUILDDIR/$ISO_FILE"
    fi
    if [ -n "$ISO_SIZE" ]; then
        printf '\n[ %d/%d ] [✓] ISO built successfully: %s (%s)\n' "$TOTAL_STEPS" "$TOTAL_STEPS" "$ISO_PATH" "$ISO_SIZE" | tee -a "$STEPS_LOG"
    else
        printf '\n[ %d/%d ] [✓] ISO built successfully: %s\n' "$TOTAL_STEPS" "$TOTAL_STEPS" "$ISO_PATH" | tee -a "$STEPS_LOG"
    fi
    # Docker only: mkarchiso's trailing "du" line above shows the CONTAINER path
    # /build/output/... which does NOT exist on the host. Spell out the real spot so
    # the user never mistakes it for build/output/. (Native runs already print the
    # real host path, so this note would be false there -- hence the /.dockerenv gate.)
    if [ -f /.dockerenv ]; then
        printf '           The ISO is at %s on your host (NOT build/output/ -- that\n' "$ISO_PATH" | tee -a "$STEPS_LOG"
        printf '           /build/output/ du line above is the path INSIDE the container).\n' | tee -a "$STEPS_LOG"
    fi
else
    printf '\n[ %d/%d ] [✗] ISO build failed: no .iso found in output/\n' "$TOTAL_STEPS" "$TOTAL_STEPS" | tee -a "$STEPS_LOG"
    exit 1
fi
