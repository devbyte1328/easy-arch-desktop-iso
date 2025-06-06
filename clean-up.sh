#!/bin/bash

set -o pipefail

WORKDIR="$(pwd)"

echo "[*] Cleaning up build directories..."
# Define airootfs path
AIROOTFS="$WORKDIR/work/x86_64/airootfs"
# Unmount any virtual filesystems if mounted
for mount in proc sys dev run; do
    if mountpoint -q "$AIROOTFS/$mount"; then
        echo "[*] Unmounting $AIROOTFS/$mount..."
        sudo umount -lf "$AIROOTFS/$mount"
    fi
done
# Ensure recursive unmount in case of nested mounts
sudo umount -R "$AIROOTFS" 2>/dev/null || true
# Now safely remove build directories
rm -rfv "$WORKDIR/out" "$WORKDIR/work" "$WORKDIR/.temp" "$WORKDIR/airootfs" "$WORKDIR/efiboot" "$WORKDIR/grub" "$WORKDIR/syslinux" "$WORKDIR/bootstrap_packages.x86_64" "$WORKDIR/packages.x86_64" "$WORKDIR/pacman.conf" "$WORKDIR/profiledef.sh"
