#!/bin/bash

set -e

# Function to handle errors
fail() {
    echo [✗] $1
    exit 1
}

DB=/tmp/pacman-easyarch-db
REPO=/tmp/pacman-easyarch-repo
AUR_TEMP_DIR=/tmp/aur_builds
FINAL_OUTPUT_DIR=$PWD/easy-arch-packages-cache

mkdir -p $DB/sync $REPO $AUR_TEMP_DIR
chown -R main:main $AUR_TEMP_DIR

echo "[*] Downloading and caching packages using pacman..."
echo "[*] Initializing pacman database in temporary path..."
sudo pacman -Sy --dbpath $DB --cachedir $REPO --noconfirm

# Package list input
if [[ -n $1 ]]; then
    pkgs=$(echo $1 | tr ',' ' ')
else
    fail "No package list passed to the script."
fi

echo "[*] Attempting to download packages (fallback to AUR if needed)..."

for pkg in $pkgs; do
    echo "    [+] Attempting pacman download: $pkg"
    if sudo pacman -Sw --noconfirm --cachedir $REPO --dbpath $DB $pkg; then
        echo "        [✓] Downloaded via pacman: $pkg"
    else
        echo "        [!] Not found in pacman, falling back to AUR: $pkg"
        cd $AUR_TEMP_DIR
        sudo -u main rm -rf $pkg
        if sudo -u main git clone --depth=1 https://aur.archlinux.org/${pkg}.git; then
            cd $pkg
            if sudo -u main makepkg -sfc --noconfirm; then
                cp ./*.pkg.tar.zst $REPO || fail "Failed to copy AUR package: $pkg"
                echo "        [✓] Built and cached from AUR: $pkg"
            else
                fail "makepkg failed for: $pkg"
            fi
            cd $AUR_TEMP_DIR
            sudo -u main rm -rf $pkg
        else
            fail "AUR clone failed: $pkg"
        fi
    fi
done

echo "[*] Moving cached data to: $FINAL_OUTPUT_DIR"
mkdir -p $FINAL_OUTPUT_DIR
cp -r $REPO/* $FINAL_OUTPUT_DIR/ || fail "copying cache"

echo "[*] Cleaning up temporary files..."
rm -rf $DB $REPO $AUR_TEMP_DIR

echo "[✓] All packages downloaded and cached successfully in 'easy-arch-packages-cache/'."

