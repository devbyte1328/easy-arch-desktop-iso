#!/bin/bash

set -e

# Function to handle errors
fail() {
    echo "[✗] Download failed for package: $1"
    exit 1
}

# Set temp location for pacman to safely write
DB=/tmp/pacman-easyarch-db
REPO=/mnt/pacman-easyarch-repo

# Set final destination (relative to current dir)
FINALDB=easy-arch-packages-cache/pacman-easyarch-db
FINALCACHE=easy-arch-packages-cache/pacman-easyarch-repo

# Create safe temp dirs
mkdir -p $DB/sync
mkdir -p $REPO

echo "[*] Downloading and caching base packages using pacman..."

# Important: Initialize pacman database for custom dbpath
echo "[*] Initializing pacman database in temporary path..."
sudo pacman -Sy --dbpath $DB --cachedir $REPO --noconfirm

echo "[*] Preparing package list..."
pkgs=$(jq -r '.packages[]' easy-arch-configuration.json | tr '\n' ' ')

echo "[*] Downloading and caching each package individually (auto-resolving dependencies)..."

for pkg in $pkgs; do
    echo "    [+] Downloading: $pkg"
    sudo pacman -Sw --noconfirm --cachedir $REPO --dbpath $DB $pkg || fail "$pkg"
done

echo "[*] Creating local repository..."
repo-add $REPO/pacman-easyarch-repo.db.tar.gz $REPO/*.tar.zst || fail "repo-add"

# Create final destination dirs
mkdir -p $FINALDB
mkdir -p $FINALCACHE

# Move downloaded data back to working directory
cp -r $DB/* $FINALDB/ || fail "copying DB"
cp -r $REPO/* $FINALCACHE/ || fail "copying cache"

# Cleanup
echo "[*] Cleaning up temporary files..."
rm -rf $DB
rm -rf $REPO

echo "[✓] All packages downloaded successfully and cached at 'easy-arch-packages-cache/'."

