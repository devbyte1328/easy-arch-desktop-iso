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
# WORKDIR is the disposable mkarchiso PROFILE tree (releng + airootfs + packages),
# a subdir of BUILDDIR so it never litters output/ next to the ISO.
BUILDDIR=$REPODIR/output
WORKDIR=$BUILDDIR/build

# Root-aware sudo wrapper. Inside the build container everything already runs as
# root, so a `sudo` prefix is pure overhead AND an extra process between this
# shell and pacman/mkarchiso. Dropping it when EUID=0 keeps the heavy commands as
# DIRECT children of this shell's process group, so a group-kill (see the INT/TERM
# trap below) reaches them. On a non-root Arch host $SUDO stays "sudo" so the
# privileged steps still work.
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

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

# Redraw the pinned bottom bar. Saves cursor, jumps to the last row, paints the
# bar, then restores the cursor back into the scroll region.
draw_bar() {
    [ "$PROGRESS_TTY" -eq 1 ] || return 0
    local rows cols pct barw filled i bar="" label eff sf
    rows=$(tput lines <&3); cols=$(tput cols <&3)
    # Effective completed weight (permille units) = fully-done steps + the partial
    # of the current step. Clamp SUBFRAC to [0,1000] so a bad parse can never push
    # this step past its own slice.
    sf=$SUBFRAC; (( sf < 0 )) && sf=0; (( sf > 1000 )) && sf=1000
    eff=$(( DONE_WEIGHT * 1000 + CUR_WEIGHT * sf ))
    pct=$(( eff / 10 / TOTAL_WEIGHT )); (( pct > 100 )) && pct=100

    # Layout:  " 20/25  ████████████░░░░░░  80%  Building ISO "
    # Reserve room for the counter, percent, and a padded label; the rest is bar.
    local prefix pctstr
    printf -v prefix ' %2d/%d ' "$CURRENT_STEP" "$TOTAL_STEPS"
    printf -v pctstr ' %3d%% ' "$pct"
    barw=$(( cols - ${#prefix} - ${#pctstr} - 26 )); [ "$barw" -lt 8 ] && barw=8
    filled=$(( eff * barw / (1000 * TOTAL_WEIGHT) )); (( filled > barw )) && filled=barw
    for ((i=0; i<filled;      i++)); do bar+="█"; done
    for ((i=filled; i<barw;   i++)); do bar+="░"; done

    # Truncate the label so the bar never wraps to a second line.
    label=$BAR_LABEL
    (( ${#label} > 22 )) && label="${label:0:21}…"

    # All escape output goes to fd 3 so it paints the real terminal and never
    # lands in the tee'd full log. The bar is PINNED to the bottom row: save the
    # cursor, jump to the last row, paint, then restore the cursor back inside the
    # scroll region (rows 1..N-1) where the build output keeps scrolling.
    {
        # \033[s save cursor · jump to row N · dim counter · cyan bar · bold
        # percent · plain label · \033[u restore cursor
        printf '\033[s\033[%d;1H\033[K\033[2m%s\033[0m\033[36m%s\033[0m\033[1m%s\033[0m %s\033[u' \
            "$rows" "$prefix" "$bar" "$pctstr" "$label"
    } >&3
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
    # kill_children, so an `exit 1` after a sub_start (that somehow skipped
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
kill_children() {
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
    # Signal the whole process group so pacman/mkarchiso (and their pacstrap
    # mounts) die. sudo keeps its child in THIS group (no use_pty in sudoers), so
    # a group kill reaches even root children. Look up the real PGID defensively
    # and fall back to $$ if the lookup fails; ignore "no such process".
    local pgid
    pgid=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')
    kill -TERM -"${pgid:-$$}" 2>/dev/null || true
}

# --- Live sub-progress readers ----------------------------------------------
# During the two giant steps (20, 25) a background reader tails the live full.log
# and maps the build's own progress lines to SUBFRAC (0..1000), redrawing the bar
# on fd 3. The reader is a DIRECT child of this shell's process group, so the
# existing group-kill in kill_children reaps it too; we also kill it explicitly.
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
        local sf=0 last=-1 cols=80 rows=24 lastdraw=0 now rc=0 m=0 inpac=0
        # Cache terminal width/height; only re-query occasionally (avoid a tput fork
        # per package line during pacstrap's ~1381 Total() updates). SIGWINCH re-reads.
        cols=$(tput cols <&3 2>/dev/null) || cols=80
        rows=$(tput lines <&3 2>/dev/null) || rows=24
        trap 'cols=$(tput cols <&3 2>/dev/null) || cols=80; rows=$(tput lines <&3 2>/dev/null) || rows=24' WINCH
        # Self-contained redraw (identical math to draw_bar, throttled to ~4/s).
        redraw() {
            now=$(( ${EPOCHREALTIME/./} ))       # microseconds; bash 5 builtin
            # Throttle: at most one redraw per ~250ms UNLESS this is the final snap.
            if (( sf < 1000 )) && (( now - lastdraw < 250000 )); then return 0; fi
            lastdraw=$now
            local barw filled i bar="" pct eff lbl=$label
            (( sf < 0 )) && sf=0; (( sf > 1000 )) && sf=1000
            eff=$(( done*1000 + cur*sf )); pct=$(( eff/10/total )); (( pct>100 )) && pct=100
            local prefix pctstr
            printf -v prefix ' %2d/%d ' "$step" "$steps"
            printf -v pctstr ' %3d%% ' "$pct"
            barw=$(( cols-${#prefix}-${#pctstr}-26 )); (( barw<8 )) && barw=8
            filled=$(( eff*barw/(1000*total) )); (( filled>barw )) && filled=barw
            for ((i=0;i<filled;i++)); do bar+="█"; done
            for ((i=filled;i<barw;i++)); do bar+="░"; done
            (( ${#lbl}>22 )) && lbl="${lbl:0:21}…"
            # Pinned to the bottom row: save cursor, jump to row N, clear the line
            # with \r\033[K (the same token the tail|grep guard drops, so the reader
            # never re-ingests its own output), paint, restore cursor.
            printf '\033[s\033[%d;1H\r\033[K\033[2m%s\033[0m\033[36m%s\033[0m\033[1m%s\033[0m %s\033[u' \
                "$rows" "$prefix" "$bar" "$pctstr" "$lbl" >&3
        }
        # Follow only NEW lines (-n0). The grep DROPS the reader's own bar redraws
        # (they begin with CR + ESC[K) so the reader can never match its own output
        # even if a label ever contained an anchor word (self-feedback guard).
        # --line-buffered keeps it real-time.
        tail -n0 -F "$FULL_LOG" 2>/dev/null \
          | grep --line-buffered -av $'\r\033\[K' \
          | while IFS= read -r line; do
            case $mode in
              step20)
                # Phase A: pacman -Sw download -> band 0..440 (44% of step 20).
                # Read N and M off the SAME line; M is live (1206 here) so nothing
                # is hardcoded. On a fully-cached run this line never appears and
                # sf simply stays 0 until phase B.
                if [[ $line =~ Total\ \(\ *([0-9]+)/([0-9]+)\) ]]; then
                    local n=${BASH_REMATCH[1]}; m=${BASH_REMATCH[2]}
                    (( m > 0 )) && sf=$(( n * 440 / m ))
                # Phase B: repo-add indexing -> band 440..1000 (56% of step 20).
                # Count 'Adding package' lines; DIVISOR is the file count passed in
                # ($repo_total), NOT the download's M -> works on a cached re-run
                # where there was no download at all.
                elif [[ $line == *"Adding package '"* ]]; then
                    (( rc++ ))
                    if (( repo_total > 0 )); then
                        sf=$(( 440 + rc * 560 / repo_total ))
                    else
                        sf=440   # unknown total: hold at band start, sub_stop snaps to 1000
                    fi
                fi ;;
              mkarchiso)
                # Ordered phase table for step 25. pacstrap dominates (~84% of the
                # step), so we parse ITS live 'Total (N/1133)' into the 20..860 band
                # while pacstrap is running -- otherwise the bar would freeze at 20
                # for ~5270 log lines (the exact freeze this whole task fixes).
                case $line in
                  *"Installing packages to"*)   inpac=1; (( sf<20 )) && sf=20 ;;
                  *"Done! Packages installed"*) inpac=0; sf=860 ;;
                  *"Creating SquashFS image"*)  inpac=0; sf=880 ;;
                  *"Creating checksum file"*)   sf=930 ;;
                  *"Creating ISO image"*)       sf=960 ;;
                  *)
                    # Only while pacstrap is downloading/installing: map N/1133.
                    if (( inpac == 1 )) && [[ $line =~ Total\ \(\ *([0-9]+)/([0-9]+)\) ]]; then
                        local n=${BASH_REMATCH[1]} mm=${BASH_REMATCH[2]}
                        (( mm > 0 )) && sf=$(( 20 + n * 840 / mm ))   # 20..860
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
    for m in proc sys dev run; do
        mountpoint -q "$AIROOTFS_W/$m" 2>/dev/null && \
            $SUDO umount -lf "$AIROOTFS_W/$m" 2>/dev/null || true
    done
    $SUDO umount -R "$AIROOTFS_W" 2>/dev/null || true
    return 0
}

# Hand the three host bind-mount trees back to the invoking host user so nothing
# is left root-owned/locked on the host. Best-effort, idempotent, never hangs,
# never aborts the exit. No-op when HOST_UID is unresolved (see resolve_host_owner).
_HANDED_BACK=0
handback_ownership() {
    [ "$_HANDED_BACK" -eq 1 ] && return 0
    _HANDED_BACK=1
    [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ] || return 0   # unresolved -> skip
    [ "$(id -u)" -eq 0 ] || return 0                        # only root created the root-owned files
    local d
    for d in "$CACHEDIR" "$BUILDDIR" "$LOGDIR"; do
        [ -d "$d" ] || continue
        # -R walks the tree; --preserve-root guards a pathological empty $d. A live
        # procfs under work/ can't be chowned but errors per-file WITHOUT hanging;
        # we swallow it. unmount_worktree (run first in the trap) removes those
        # mounts in the common case anyway. output/build/ is disposable regardless.
        chown -R --preserve-root "$HOST_UID:$HOST_GID" "$d" 2>/dev/null || true
    done
    return 0
}

# On Ctrl-C / SIGTERM: kill the build + reader, unmount mkarchiso's bind mounts,
# restore the terminal, hand the host dirs back, exit 130. The EXIT trap re-runs
# cleanup + handback (both idempotent) for the normal/error-exit paths.
trap 'kill_children; unmount_worktree; progress_cleanup; handback_ownership; exit 130' INT TERM HUP QUIT
trap 'progress_cleanup; handback_ownership' EXIT

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
# $WORKDIR (output/build/), never $BUILDDIR (output/) itself: that keeps any
# previously-built ISO sitting in output/ intact until the new build overwrites
# it, and — under Docker, where output/ is the host bind mount — it means the
# rm never recurses into a live mountpoint (output/build is an ordinary same-fs
# subdir). cache/ lives outside output/ entirely and is untouched.
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
# Divisor for the repo-add sub-band: count the .pkg.tar.zst already in the
# persistent repo. On a fully-cached re-run there is NO download, but repo-add
# still re-indexes every package, so we must size the band from the file count,
# not from the (absent) download total. Fallback 0 -> reader holds at band start.
REPO_TOTAL=$(ls -1 "$CACHEDIR"/pkgs/repo/*.pkg.tar.zst 2>/dev/null | wc -l)
sub_start step20 "$REPO_TOTAL"               # live download + repo-add sub-progress
if ! bash $CONFDIR/install/setup-pkgs-cache.sh "$WORKDIR" "$CACHEDIR"; then
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

step "Cleaning up temp directory..."
rm -rfv $WORKDIR/.temp

step "Building ISO..."
### This line fixes an odd bug that appeared out of nowhere
### """FATAL ERROR: xz uncompress failed with error code 9""" 
export MKSQUASHFS_OPTIONS="-processors 4"
###
# profile_dir = $WORKDIR (output/build); scratch = $WORKDIR/work; ISO -> $BUILDDIR
# (output/) directly via -o, so the finished .iso sits in output/ next to nothing.
sub_start mkarchiso                           # live pacstrap + squashfs + iso sub-progress
$SUDO mkarchiso -v -w "$WORKDIR/work" -o "$BUILDDIR" "$WORKDIR"
sub_stop
arm_region; draw_bar                         # mkarchiso reset the region; re-pin at 24/24
if [ -n "$(find "$BUILDDIR" -maxdepth 1 -type f -name '*.iso')" ]; then
    printf '\n[ %d/%d ] [✓] ISO built successfully in output/\n' "$TOTAL_STEPS" "$TOTAL_STEPS" | tee -a "$STEPS_LOG"
else
    printf '\n[ %d/%d ] [✗] ISO build failed: no .iso found in output/\n' "$TOTAL_STEPS" "$TOTAL_STEPS" | tee -a "$STEPS_LOG"
    exit 1
fi
