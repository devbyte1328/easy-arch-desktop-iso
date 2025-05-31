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
cp "$CONFDIR/group" airootfs/etc/group

echo "[*] Creating home directory and .dmrc for main user..."
mkdir -p airootfs/home/main
chown -R 1000:998 airootfs/home/main

echo "[*] Adding setup-locale script..."
mkdir -p airootfs/root
cp "$CONFDIR/setup-locale.sh" airootfs/root/setup-locale.sh
chmod +x airootfs/root/setup-locale.sh

echo "[*] Adding locale systemd service..."
mkdir -p airootfs/etc/systemd/system
cp "$CONFDIR/locale-setup.service" airootfs/etc/systemd/system/locale-setup.service

echo "[*] Adding setup-ufw script..."
mkdir -p airootfs/root
cp "$CONFDIR/setup-ufw.sh" airootfs/root/setup-ufw.sh
chmod +x airootfs/root/setup-ufw.sh

echo "[*] Adding ufw systemd service..."
mkdir -p airootfs/etc/systemd/system
cp "$CONFDIR/ufw-setup.service" airootfs/etc/systemd/system/ufw-setup.service

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
ln -sf /etc/systemd/system/ufw-setup.service airootfs/etc/systemd/system/multi-user.target.wants/ufw-setup.service

echo "[*] Setting up sudoers..."
mkdir -p airootfs/etc/sudoers.d
cp "$CONFDIR/00-rootpw" airootfs/etc/sudoers.d/00-rootpw
cp "$CONFDIR/00-main" airootfs/etc/sudoers.d/00-main
chmod 440 airootfs/etc/sudoers.d/00-rootpw
chmod 440 airootfs/etc/sudoers.d/00-main

echo "[*] Copying profile definition..."
cp "$CONFDIR/profiledef.sh" "$WORKDIR/profiledef.sh"

echo "[*] Building ISO..."
sudo mkarchiso -v "$WORKDIR"

echo "[✓] ISO built successfully in ./out/"

