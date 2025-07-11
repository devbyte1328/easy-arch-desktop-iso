#!/bin/bash

set -e

# Function to handle errors
fail() {
    echo "[✗] Error: $1"
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

echo "[*] Downloading and caching base packages..."

# Initialize pacman database
echo "[*] Initializing pacman database in temporary path..."
sudo pacman -Sy --dbpath $DB --cachedir $REPO --noconfirm || fail "pacman database initialization"

echo "[*] Preparing package list..."
pkgs=$(jq -r '.packages[]' easy-arch-configuration.json | tr '\n' ' ')

echo "[*] Downloading and caching each package individually (auto-resolving dependencies)..."

for pkg in $pkgs; do
    echo "    [+] Checking: $pkg"
    # Check if package exists in pacman
    if pacman -Si "$pkg" >/dev/null 2>&1; then
        echo "    [+] Downloading with pacman: $pkg"
        sudo pacman -Sw --noconfirm --cachedir $REPO --dbpath $DB "$pkg" || fail "pacman download for $pkg"
    else
        # Fallback to yay if pacman fails
        echo "    [+] Package not found in pacman, trying yay: $pkg"
        if yay -Si "$pkg" >/dev/null 2>&1; then
            yay -Sw --noconfirm --cachedir $REPO "$pkg" || fail "yay download for $pkg"
        else
            fail "Package $pkg not found in pacman or yay"
        fi
    fi
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
