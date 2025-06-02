#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(dirname "$SCRIPT_DIR")"
AUR_PKG_DIR="$WORKDIR/temp_aur_pkg_builds"
AIROOTFS_DIR="$WORKDIR/airootfs/usr/bin"

mkdir -p "$AUR_PKG_DIR"
mkdir -p "$AIROOTFS_DIR"

### pkg: neofetch
git clone https://github.com/dylanaraps/neofetch.git "$AUR_PKG_DIR/neofetch"

# Copy the neofetch bash script to airootfs/usr/bin
cp "$AUR_PKG_DIR/neofetch/neofetch" "$AIROOTFS_DIR/"
