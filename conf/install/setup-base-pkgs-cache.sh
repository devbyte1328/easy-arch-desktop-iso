#!/bin/bash

mkdir -p "airootfs/root/base-pkgs-cache"
MIRROR="https://mirror.pkgbuild.com"
PKGS=("base" "linux" "linux-firmware" "bc" "curl")
for PKG in "${PKGS[@]}"; do
    PKG_PATH=$(curl -s "$MIRROR/core/os/x86_64/" | grep -oP "${PKG}-[0-9][^ ]*?\.pkg\.tar\.zst" | head -1)
    curl -L "$MIRROR/core/os/x86_64/$PKG_PATH" -o "airootfs/root/base-pkgs-cache/$PKG_PATH"
done
