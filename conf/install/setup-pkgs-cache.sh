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

# Create safe temp dirs
rm -rf $SCRATCH
mkdir -p $TMPDB/sync
mkdir -p $MNTREPO

echo "[*] Downloading and caching base packages using pacman..."

# Important: Initialize pacman database for custom dbpath
echo "[*] Initializing pacman database in temporary path..."
sudo pacman -Sy --dbpath $TMPDB --cachedir $MNTREPO --noconfirm

echo "[*] Preparing package list..."
pkgs=$(tr '\n' ' ' < packages.x86_64)

echo "[*] Downloading and caching each package individually (auto-resolving dependencies)..."

for pkg in $pkgs; do
    echo "    [+] Downloading: $pkg"
    sudo pacman -Sw --noconfirm --cachedir $MNTREPO --dbpath $TMPDB $pkg || fail "$pkg"
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

