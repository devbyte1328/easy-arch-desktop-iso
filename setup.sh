#!/bin/bash
set -euo pipefail

WORKDIR="$(pwd)"
CONFDIR="$WORKDIR/conf"

echo "[*] Cleaning up old build directories..."
rm -rf "$WORKDIR/out" "$WORKDIR/work"

echo "[*] Installing archiso if needed..."
sudo pacman -Sy --noconfirm --needed archiso

echo "[*] Copying releng base into working directory..."
cp -r /usr/share/archiso/configs/releng/* "$WORKDIR"

echo "[*] Copying custom package list..."
cp "$CONFDIR/packages.x86_64" "$WORKDIR/packages.x86_64"

echo "[*] Setting up users..."
mkdir -p airootfs/etc
cp "$CONFDIR/passwd" airootfs/etc/passwd
cp "$CONFDIR/shadow" airootfs/etc/shadow
cp "$CONFDIR/gshadow" airootfs/etc/gshadow

echo "[*] Adding setup-locale script..."
mkdir -p airootfs/root
cp "$CONFDIR/setup-locale.sh" airootfs/root/setup-locale.sh
chmod +x airootfs/root/setup-locale.sh

echo "[*] Adding locale systemd service..."
mkdir -p airootfs/etc/systemd/system
cp "$CONFDIR/locale-setup.service" airootfs/etc/systemd/system/locale-setup.service

echo "[*] Adding LightDM config..."
mkdir -p airootfs/etc/lightdm
cp "$CONFDIR/lightdm.conf" airootfs/etc/lightdm/lightdm.conf

echo "[*] Linking systemd services..."
mkdir -p airootfs/etc/systemd/system/{multi-user.target.wants,graphical.target.wants}
ln -sf /usr/lib/systemd/system/lightdm.service airootfs/etc/systemd/system/graphical.target.wants/lightdm.service
ln -sf /usr/lib/systemd/system/NetworkManager.service airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service
ln -sf /usr/lib/systemd/system/bluetooth.service airootfs/etc/systemd/system/multi-user.target.wants/bluetooth.service
ln -sf /usr/lib/systemd/system/org.cups.cupsd.service airootfs/etc/systemd/system/multi-user.target.wants/org.cups.cupsd.service
ln -sf /etc/systemd/system/locale-setup.service airootfs/etc/systemd/system/multi-user.target.wants/locale-setup.service

echo "[*] Copying profile definition..."
cp "$CONFDIR/profiledef.sh" "$WORKDIR/profiledef.sh"

echo "[*] Building ISO..."
sudo mkarchiso -v "$WORKDIR"

echo "[✓] ISO built successfully in ./out/"

