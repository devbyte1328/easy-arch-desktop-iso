#!/bin/bash

set -e

# Function to handle errors
fail() {
    echo "[✗] Download failed for package: $1"
    exit 1
}

# Scratch location for pacman to write to. Kept inside the build dir so the
# script is self-contained and needs no root-owned paths like /mnt.
SCRATCH=${1:-$PWD}/.pkgs-cache-tmp
TMPDB=$SCRATCH/db
MNTREPO=$SCRATCH/repo

# Set final destination (relative to current dir)
FINALDB=airootfs/root/Easy-Arch/pacstrap-easyarch-db
FINALCACHE=airootfs/root/Easy-Arch/pacstrap-easyarch-repo

# Self-contained Arch download config lives next to this script. Using it (instead
# of the host /etc/pacman.conf) makes the download work regardless of what distro
# the build host runs (e.g. Manjaro), and pins Arch's official mirrors.
SELFDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DLCONF=$SELFDIR/setup-pkgs-cache-pacman.conf

# Create safe temp dirs
rm -rf $SCRATCH
mkdir -p $TMPDB/sync
mkdir -p $MNTREPO

# Fresh, empty GPG dir so no host keyring is ever consulted for the download step
# (a non-Arch host's keyring would not trust Arch package signatures). Lives under
# $SCRATCH, so the existing cleanup removes it.
GPGDIR=$SCRATCH/gnupg
mkdir -p $GPGDIR

echo "[*] Downloading and caching base packages using pacman..."

# Important: Initialize pacman database for custom dbpath
echo "[*] Initializing pacman database in temporary path..."
sudo pacman -Sy --config $DLCONF --gpgdir $GPGDIR --dbpath $TMPDB --cachedir $MNTREPO --noconfirm

echo "[*] Preparing package list..."
pkgs=$(tr '\n' ' ' < packages.x86_64)

echo "[*] Downloading and caching each package individually (auto-resolving dependencies)..."

for pkg in $pkgs; do
    echo "    [+] Downloading: $pkg"
    sudo pacman -Sw --config $DLCONF --gpgdir $GPGDIR --noconfirm --cachedir $MNTREPO --dbpath $TMPDB $pkg || fail "$pkg"
done

echo "[*] Creating local repository..."
# pacman ran as root, so the scratch files are root-owned; repo-add must too.
sudo repo-add $MNTREPO/pacstrap-easyarch-repo.db.tar.gz $MNTREPO/*.tar.zst || fail "repo-add"

# Create final destination dirs
mkdir -p $FINALDB
mkdir -p $FINALCACHE

# Move downloaded data back to working directory
sudo cp -r $TMPDB/* $FINALDB/ || fail "copying DB"
sudo cp -r $MNTREPO/* $FINALCACHE/ || fail "copying cache"

# Hand the copied files back to the invoking user so mkarchiso and the cache
# copy-back (both run unprivileged) can read/write them.
sudo chown -R "$(id -u):$(id -g)" $FINALDB $FINALCACHE

# Cleanup (scratch is root-owned after sudo pacman)
echo "[*] Cleaning up temporary files..."
sudo rm -rf $SCRATCH

echo "[✓] All packages downloaded successfully and moved to working directory."

