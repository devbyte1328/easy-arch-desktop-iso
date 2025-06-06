#!/bin/bash

set -euo pipefail

WORKDIR="$1"
BUILD_USER="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUR_PKG_DIR="$WORKDIR/.temp/aur_pkg_builds"
AIROOTFS_PKG_DIR="$WORKDIR/airootfs/root/aur_pkgs"
PKG_LIST_FILE="$SCRIPT_DIR/aur-packages.x86_64"

mkdir -p "$AUR_PKG_DIR" "$AIROOTFS_PKG_DIR"
chown -R "$BUILD_USER:$BUILD_USER" "$AUR_PKG_DIR"

install_from_aur() {
    pkgname="$1"
    echo "Cloning and building: $pkgname"

    cd "$AUR_PKG_DIR"
    sudo -u "$BUILD_USER" rm -rf "$pkgname"
    sudo -u "$BUILD_USER" git clone "https://aur.archlinux.org/${pkgname}.git"
    cd "$pkgname"
    sudo -u "$BUILD_USER" makepkg -sfc --noconfirm

    # Copy built packages
    for pkgfile in *.pkg.tar.zst; do
        cp "$pkgfile" "$AIROOTFS_PKG_DIR/"
    done
}

if [[ ! -f "$PKG_LIST_FILE" ]]; then
    echo "Error: Package list file not found at $PKG_LIST_FILE"
    exit 1
fi

while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "${pkg:0:1}" == "#" ]] && continue
    install_from_aur "$pkg"
done < "$PKG_LIST_FILE"

