#!/bin/bash

set -e

# Function to handle errors
fail() {
    echo "[✗] $1"
    exit 1
}

# User to build AUR packages
BUILD_USER="main"

# Working directory (script is run from here)
WORKDIR="$PWD"

# Temp paths
DB="/tmp/pacman-easyarch-db"
REPO="/tmp/pacman-easyarch-repo"
AUR_TEMP_DIR="/tmp/aur_builds"

# Final output directory inside working directory
FINAL_OUTPUT_DIR="$WORKDIR/easy-arch-packages-cache"
FINALDB="$FINAL_OUTPUT_DIR/pacman-easyarch-db"
FINALCACHE="$FINAL_OUTPUT_DIR/pacman-easyarch-repo"

# Ensure tools are available
if ! command -v git &>/dev/null || ! command -v makepkg &>/dev/null; then
    fail "'git' and/or 'makepkg' not found. Please install 'base-devel' and 'git'."
fi

# Create temp dirs
mkdir -p "$DB/sync" "$REPO" "$AUR_TEMP_DIR"
chown -R "$BUILD_USER:$BUILD_USER" "$AUR_TEMP_DIR"

echo "[*] Downloading and caching packages using pacman..."
echo "[*] Initializing pacman database in temporary path..."
sudo pacman -Sy --dbpath "$DB" --cachedir "$REPO" --noconfirm

# Package list input
if [[ -n "$1" ]]; then
    pkgs=$(echo "$1" | tr ',' ' ')
else
    fail "No package list passed to the script."
fi

echo "[*] Attempting to download packages (fallback to AUR if needed)..."

for pkg in $pkgs; do
    echo "    [+] Attempting pacman download: $pkg"
    if sudo pacman -Sw --noconfirm --cachedir "$REPO" --dbpath "$DB" "$pkg"; then
        echo "        [✓] Downloaded via pacman: $pkg"
    else
        echo "        [!] Not found in pacman, falling back to AUR: $pkg"
        cd "$AUR_TEMP_DIR"
        sudo -u "$BUILD_USER" rm -rf "$pkg"
        if sudo -u "$BUILD_USER" git clone --depth=1 "https://aur.archlinux.org/${pkg}.git"; then
            cd "$pkg"
            if sudo -u "$BUILD_USER" makepkg -sfc --noconfirm; then
                cp ./*.pkg.tar.zst "$REPO" || fail "Failed to copy AUR package: $pkg"
                echo "        [✓] Built and cached from AUR: $pkg"
            else
                fail "makepkg failed for: $pkg"
            fi
            cd "$AUR_TEMP_DIR"
            sudo -u "$BUILD_USER" rm -rf "$pkg"
        else
            fail "AUR clone failed: $pkg"
        fi
    fi
done

echo "[*] Creating local repository..."
repo-add "$REPO/pacman-easyarch-repo.db.tar.gz" "$REPO"/*.pkg.tar.zst || fail "repo-add"

# Move downloaded data back to working directory
echo "[*] Moving cached data to: $FINAL_OUTPUT_DIR"
mkdir -p "$FINALDB" "$FINALCACHE"
cp -r "$DB"/* "$FINALDB/" || fail "copying DB"
cp -r "$REPO"/* "$FINALCACHE/" || fail "copying cache"

# Cleanup
echo "[*] Cleaning up temporary files..."
rm -rf "$DB" "$REPO" "$AUR_TEMP_DIR"

echo "[✓] All packages downloaded and cached successfully in 'easy-arch-packages-cache/'."

