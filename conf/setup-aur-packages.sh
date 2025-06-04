#!/bin/bash

WORKDIR="$1"
BUILD_USER="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUR_PKG_DIR="$WORKDIR/temp_aur_pkg_builds"
AIROOTFS_DIR="$WORKDIR/airootfs"
PKG_LIST_FILE="$SCRIPT_DIR/aur-packages.x86_64"

mkdir -p "$AUR_PKG_DIR"
chown -R "$BUILD_USER:$BUILD_USER" "$AUR_PKG_DIR"

install_from_aur() {
    pkgname="$1"
    echo "Installing: $pkgname"

    cd "$AUR_PKG_DIR"
    rm -rf "$pkgname"
    sudo -u "$BUILD_USER" git clone "https://aur.archlinux.org/${pkgname}.git"
    cd "$pkgname"

    # Build package (fetch deps separately)
    sudo -u "$BUILD_USER" makepkg -o --noconfirm
    sudo -u "$BUILD_USER" makepkg -e --noconfirm

    pkgfile=$(ls *.pkg.tar.zst | grep -v debug | head -n1)
    if [[ ! -f "$pkgfile" ]]; then
        echo "Error: Failed to find package file for $pkgname"
        exit 1
    fi

    # Extract package contents
    rootdir="${AUR_PKG_DIR}/${pkgname}-root"
    mkdir -p "$rootdir"
    bsdtar -xf "$pkgfile" -C "$rootdir"

    # Extract name/version from filename
    pkgbase=$(basename "$pkgfile" .pkg.tar.zst)
    pkgname_stripped=$(echo "$pkgbase" | sed -E 's/-[0-9][^-]*-[^-]*$//')
    version=$(echo "$pkgbase" | sed -E "s/^${pkgname_stripped}-//; s/-any$//")

    # Create pacman DB metadata
    dbdir="$rootdir/root/temp/var/lib/pacman/local/${pkgname_stripped}-${version}"
    mkdir -p "$dbdir"

    bsdtar -xOf "$pkgfile" .MTREE > "$dbdir/mtree" 2>/dev/null || true

    {
        echo "%FILES%"
        bsdtar -tf "$pkgfile" | grep -v '^\.' | sed 's|^|/|'
    } > "$dbdir/files"

    {
        echo "%NAME%"
        echo "$pkgname_stripped"
        echo
        echo "%VERSION%"
        echo "$version"
        echo
        echo "%DESC%"
        echo "Auto-generated entry"
        echo
        echo "%ARCH%"
        echo "any"
        echo
        echo "%BUILDDATE%"
        date +%s
        echo
        echo "%PACKAGER%"
        echo "manual <none@example.com>"
        echo
        echo "%SIZE%"
        stat --printf="%s\n" "$pkgfile"
        echo
        echo "%URL%"
        echo "https://aur.archlinux.org/packages/$pkgname_stripped"
        echo
        echo "%LICENSE%"
        echo "MIT"
        echo
        echo "%DEPENDS%"
        echo "bash"
    } > "$dbdir/desc"

    # Copy full extracted root into airootfs
    cp -rv "$rootdir"/* "$AIROOTFS_DIR/"

    # Copy package to ISO's pkg cache
    mkdir -p "$AIROOTFS_DIR/var/cache/pacman/pkg"
    cp "$pkgfile" "$AIROOTFS_DIR/var/cache/pacman/pkg/"
}

if [[ ! -f "$PKG_LIST_FILE" ]]; then
    echo "Error: Package list file not found at $PKG_LIST_FILE"
    exit 1
fi

while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    # Skip empty lines and lines starting with '#'
    if [[ -z "$pkg" || "${pkg:0:1}" == "#" ]]; then
        continue
    fi
    install_from_aur "$pkg"
done < "$PKG_LIST_FILE"

