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
# writes that PTY's output to the full log. The PTY is the crucial part: pacman,
# pip and mkarchiso all detect a terminal and keep their LIVE, \r-redrawn
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
    # The PTY is the point: pacman/pip/mkarchiso see a terminal and keep their
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
# WORKDIR is where releng + airootfs + mkarchiso all operate.
BUILDDIR=$REPODIR/output
WORKDIR=$BUILDDIR

# Persistent download cache (repo root, survives cleanup). Downloads land here
# directly, so caching is incremental and resumable:
#   - present & complete -> pacman/pip skip it, no network hit.
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
TOTAL_STEPS=25
CURRENT_STEP=0
BAR_LABEL=""

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
    local rows cols pct barw filled i bar="" label
    rows=$(tput lines <&3); cols=$(tput cols <&3)
    pct=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))

    # Layout:  " 20/25  ████████████░░░░░░  80%  Building ISO "
    # Reserve room for the counter, percent, and a padded label; the rest is bar.
    local prefix pctstr
    printf -v prefix ' %2d/%d ' "$CURRENT_STEP" "$TOTAL_STEPS"
    printf -v pctstr ' %3d%% ' "$pct"
    barw=$(( cols - ${#prefix} - ${#pctstr} - 26 )); [ "$barw" -lt 8 ] && barw=8
    filled=$(( CURRENT_STEP * barw / TOTAL_STEPS ))
    for ((i=0; i<filled;      i++)); do bar+="█"; done
    for ((i=filled; i<barw;   i++)); do bar+="░"; done

    # Truncate the label so the bar never wraps to a second line.
    label=$BAR_LABEL
    (( ${#label} > 22 )) && label="${label:0:21}…"

    # All escape output goes to fd 3 (/dev/tty) so it paints the real terminal
    # and never lands in the tee'd full log.
    {
        tput sc                              # save cursor
        tput cup $((rows - 1)) 0             # go to bottom row
        tput el                              # clear the line
        # dim counter · cyan bar · bold percent · plain label
        printf '\033[2m%s\033[0m\033[36m%s\033[0m\033[1m%s\033[0m %s' \
            "$prefix" "$bar" "$pctstr" "$label"
        tput rc                              # restore cursor
    } >&3
}

# (Re-)reserve the bottom row: scroll region = rows 1..(N-1). Subprocesses like
# pacman and mkarchiso reset the terminal's scroll region for their own progress
# bars, which unpins ours; calling this again before each redraw re-arms it so
# the bar never gets scrolled away or frozen mid-build.
arm_region() {
    [ "$PROGRESS_TTY" -eq 1 ] || return 0
    local rows; rows=$(tput lines <&3)
    tput csr 0 $((rows - 2)) >&3             # reserve last row for the bar
}

# First-time setup: clear the screen so the reserved region starts clean, then
# arm the region and paint the initial (empty) bar.
progress_init() {
    [ "$PROGRESS_TTY" -eq 1 ] || return 0
    arm_region
    tput cup 0 0 >&3
    draw_bar
}

# Restore the full scroll region and cursor. Runs on any exit (success, error,
# Ctrl-C) so the terminal is never left in a broken state.
progress_cleanup() {
    [ "$PROGRESS_TTY" -eq 1 ] || return 0
    local rows; rows=$(tput lines <&3)
    {
        tput csr 0 $((rows - 1))             # restore full scroll region
        tput cup $((rows - 1)) 0
        tput el
        tput cnorm                           # ensure cursor visible
    } >&3
}
trap progress_cleanup EXIT INT TERM

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    BAR_LABEL="$1"
    arm_region                               # re-pin in case pacman/mkarchiso reset it
    # Goes to stdout -> terminal + full log (via tee).
    printf '\n[ %2d/%d ] %s\n' "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
    # Milestone-only summary, appended straight to the steps log (no escapes).
    printf '[ %2d/%d ] %s\n' "$CURRENT_STEP" "$TOTAL_STEPS" "$1" >> "$STEPS_LOG"
    draw_bar
}

progress_init

step "Cleaning up previous build directory..."
AIROOTFS=$BUILDDIR/work/x86_64/airootfs
for mount in proc sys dev run; do
    if mountpoint -q $AIROOTFS/$mount; then
        echo "    [+] Unmounting $AIROOTFS/$mount..."
        sudo umount -lf $AIROOTFS/$mount
    fi
done
sudo umount -R $AIROOTFS 2>/dev/null || true
# Wipe the entire build dir and start fresh (cache/ lives outside it, untouched).
sudo rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
# Everything below operates inside the build dir; bare-relative paths (airootfs/...)
# resolve here instead of polluting the project root.
cd "$BUILDDIR"

step "Checking for build-host dependencies..."
HOST_PKGS="archiso git base-devel go python python-pip"
# These are the tools the build itself runs on (mkarchiso, makepkg, pip, ...),
# not ISO content. If they're already installed we stay fully offline; only a
# missing tool triggers a sync. (Docker also layer-caches these via the Dockerfile.)
if pacman -Qq $HOST_PKGS >/dev/null 2>&1; then
    echo "    [+] Build-host dependencies already present, skipping sync (offline)."
else
    echo "    [+] Installing missing build-host dependencies..."
    sudo pacman -Sy --noconfirm --needed $HOST_PKGS
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
if ! bash $CONFDIR/install/setup-pkgs-cache.sh "$BUILDDIR" "$CACHEDIR"; then
    echo "[✗] Package caching/staging failed..."
    exit 1
fi
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

step "Setting up Python libraries for the finalizer script..."
mkdir -p airootfs/root/Easy-Arch/finalize
mkdir -p airootfs/root/Easy-Arch/finalize/pip-cache
cp -r $CONFDIR/finalize/. airootfs/root/Easy-Arch/finalize/
cp $CONFDIR/pip-libraries airootfs/root/Easy-Arch/finalize/pip-cache/pip-libraries
# Download wheels straight into the PERSISTENT cache/pip. pip reuses wheels
# already present there and fetches only the missing ones, so this is real-time
# and resumable: a prior Ctrl-C leaves finished wheels cached, and a re-run only
# grabs what's left. Staging into the airootfs then happens from the cache.
mkdir -p "$CACHEDIR/pip"
echo "    [+] Downloading missing Python wheels into the persistent cache (resumable)..."
if pip download -d "$CACHEDIR/pip" -r $CONFDIR/pip-libraries; then
    :
elif [ -n "$(ls -A "$CACHEDIR/pip" 2>/dev/null)" ]; then
    echo "    [+] Wheel download failed but cache/pip is populated — using it offline."
else
    echo "[✗] Downloading Python wheels failed and cache/pip is empty."
    exit 1
fi
arm_region; draw_bar                         # pip may reset the region; re-pin
# Stage cached wheels into the ISO working tree (always runs; local, offline).
cp "$CACHEDIR/pip"/* airootfs/root/Easy-Arch/finalize/pip-cache/ || true
if [ -z "$(ls -A "$CACHEDIR/pip" 2>/dev/null)" ]; then
    echo "[✗] Python wheel cache (cache/pip) is empty after download."
    exit 1
fi

step "Cleaning up temp directory..."
rm -rfv $WORKDIR/.temp

step "Building ISO..."
### This line fixes an odd bug that appeared out of nowhere
### """FATAL ERROR: xz uncompress failed with error code 9""" 
export MKSQUASHFS_OPTIONS="-processors 4"
###
sudo mkarchiso -v $WORKDIR
arm_region; draw_bar                         # mkarchiso reset the region; re-pin at 25/25
if [ -d "$WORKDIR/out" ] && [ -n "$(find "$WORKDIR/out" -maxdepth 1 -type f -name '*.iso')" ]; then
    printf '\n[ %d/%d ] [✓] ISO built successfully in output/out/\n' "$TOTAL_STEPS" "$TOTAL_STEPS" | tee -a "$STEPS_LOG"
else
    printf '\n[ %d/%d ] [✗] ISO build failed: output/out/ or ISO file not found\n' "$TOTAL_STEPS" "$TOTAL_STEPS" | tee -a "$STEPS_LOG"
    exit 1
fi
