#!/bin/bash

set -o pipefail

REPODIR=$(pwd)
BUILDDIR=$REPODIR/output

echo "[*] Cleaning up build directory..."
# Unmount any virtual filesystems left mounted inside the build airootfs.
AIROOTFS=$BUILDDIR/work/x86_64/airootfs
for mount in proc sys dev run; do
    if mountpoint -q $AIROOTFS/$mount; then
        echo "[*] Unmounting $AIROOTFS/$mount..."
        sudo umount -lf $AIROOTFS/$mount
    fi
done
# Ensure recursive unmount in case of nested mounts
sudo umount -R $AIROOTFS 2>/dev/null || true

# Remove the whole build dir. cache/ lives outside it and is left untouched;
# delete cache/ separately if you want to force a fresh download.
sudo rm -rf "$BUILDDIR"

echo "[✓] Build directory removed. (cache/ kept — 'rm -rf cache/' to force re-download.)"
