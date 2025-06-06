#!/bin/bash

WORKDIR="$1"
BUILD_USER="$2"
YAY_BUILD_DIR="$WORKDIR/.temp/yay_build"

echo "[*] Downloading yay from AUR..."
git clone https://aur.archlinux.org/yay.git "$YAY_BUILD_DIR"

echo "[*] Changing ownership of yay build dir to $BUILD_USER..."
chown -R "$BUILD_USER:$BUILD_USER" "$YAY_BUILD_DIR"

echo "[*] Building yay as user: $BUILD_USER..."
cd "$YAY_BUILD_DIR"
sudo -u "$BUILD_USER" makepkg -s --noconfirm --skippgpcheck

echo "[*] Copying yay binary into airootfs..."
mkdir -p "$WORKDIR/airootfs/usr/bin"
cp "$YAY_BUILD_DIR/pkg/yay/usr/bin/yay" "$WORKDIR/airootfs/usr/bin/yay"
chmod +x "$WORKDIR/airootfs/usr/bin/yay"

echo "[✓] yay setup complete."

