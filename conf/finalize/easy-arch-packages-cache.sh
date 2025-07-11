#!/bin/bash

set -e

# Function to handle errors
fail() {
    echo "[✗] Download failed for package: $1"
    exit 1
}

# Set temp location for pacman to safely write
TMPDB=/tmp/pacstrap-easyarch-db
MNTREPO=/mnt/pacstrap-easyarch-repo

# Set final destination (relative to current dir)
FINALDB=airootfs/root/pacstrap-easyarch-db
FINALCACHE=airootfs/root/pacstrap-easyarch-repo

# Create safe temp dirs
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
repo-add $MNTREPO/pacstrap-easyarch-repo.db.tar.gz $MNTREPO/*.tar.zst || fail "repo-add"

# Create final destination dirs
mkdir -p $FINALDB
mkdir -p $FINALCACHE

# Move downloaded data back to working directory
cp -r $TMPDB/* $FINALDB/ || fail "copying DB"
cp -r $MNTREPO/* $FINALCACHE/ || fail "copying cache"

# Cleanup
echo "[*] Cleaning up temporary files..."
rm -rf $TMPDB
rm -rf $MNTREPO

echo "[✓] All packages downloaded successfully and moved to working directory."

