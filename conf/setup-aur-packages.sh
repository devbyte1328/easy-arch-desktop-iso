#!/bin/bash

WORKDIR="$1"
BUILD_USER="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUR_PKG_DIR="$WORKDIR/temp_aur_pkg_builds"
AIROOTFS_DIR="$WORKDIR/airootfs/usr/bin"
mkdir -p "$AUR_PKG_DIR"
mkdir -p "$AIROOTFS_DIR"
chown -R "$BUILD_USER:$BUILD_USER" "$AUR_PKG_DIR"

### pkg: neofetch
git clone https://github.com/dylanaraps/neofetch.git "$AUR_PKG_DIR/neofetch"
cp "$AUR_PKG_DIR/neofetch/neofetch" "$AIROOTFS_DIR/"

### pkg: rar
sudo -u "$BUILD_USER" git clone https://aur.archlinux.org/rar.git "$AUR_PKG_DIR/rar"
sudo -u "$BUILD_USER" bash -c "cd '$AUR_PKG_DIR/rar' && makepkg -o -C"
make -C "$AUR_PKG_DIR/rar/src/rar"
cp "$AUR_PKG_DIR/rar/src/rar/rar" "$AIROOTFS_DIR/"

