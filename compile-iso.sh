#!/bin/bash

set -o pipefail

WORKDIR="$(pwd)"
CONFDIR="$WORKDIR/conf"

echo "[*] Cleaning up previous build directories..."
# Define airootfs path
AIROOTFS="$WORKDIR/work/x86_64/airootfs"
# Unmount any virtual filesystems if mounted
for mount in proc sys dev run; do
    if mountpoint -q "$AIROOTFS/$mount"; then
        echo "[*] Unmounting $AIROOTFS/$mount..."
        sudo umount -lf "$AIROOTFS/$mount"
    fi
done
# Ensure recursive unmount in case of nested mounts
sudo umount -R "$AIROOTFS" 2>/dev/null || true
# Now safely remove build directories
rm -rfv "$WORKDIR/out" "$WORKDIR/work" "$WORKDIR/.temp" "$WORKDIR/airootfs" "$WORKDIR/efiboot" "$WORKDIR/grub" "$WORKDIR/syslinux" "$WORKDIR/bootstrap_packages.x86_64" "$WORKDIR/packages.x86_64" "$WORKDIR/pacman.conf" "$WORKDIR/profiledef.sh"  

echo "[*] Installing archiso and git if needed..."
sudo pacman -Sy --noconfirm --needed archiso git base-devel

echo "[*] Copying releng base into working directory..."
cp -r /usr/share/archiso/configs/releng/* "$WORKDIR"

echo "[*] Adding custom bootloader entries and config files..."
cp "$CONFDIR/system/01-archiso-x86_64-linux.conf" "$WORKDIR/efiboot/loader/entries/"
cp "$CONFDIR/system/02-archiso-x86_64-speech-linux.conf" "$WORKDIR/efiboot/loader/entries/"
cp "$CONFDIR/system/archiso_sys-linux.cfg" "$WORKDIR/syslinux/"

echo "[*] Copying custom package list..."
cp "$CONFDIR/packages.x86_64" "$WORKDIR/packages.x86_64"

echo "[*] Running setup-yay script (handles build and copy)..."
bash "$CONFDIR/system/setup-yay.sh" "$WORKDIR" "$SUDO_USER"

echo "[*] Running setup-aur-packages.sh (download and build packages)..."
bash "$CONFDIR/system/setup-aur-packages.sh" "$WORKDIR" "$SUDO_USER"

echo "[*] Setting up users..."
mkdir -p airootfs/etc
cp "$CONFDIR/system/passwd" airootfs/etc/passwd
cp "$CONFDIR/system/shadow" airootfs/etc/shadow
cp "$CONFDIR/system/gshadow" airootfs/etc/gshadow
cp "$CONFDIR/system/group" airootfs/etc/group

echo "[*] Creating home directory and configuring permissions to allow LightDM autologin..."
mkdir -p airootfs/home/main
chown -R 1000:998 airootfs/home/main

echo "[*] Adding setup-locale script..."
mkdir -p airootfs/root
cp "$CONFDIR/system/setup-locale.sh" airootfs/root/setup-locale.sh
chmod +x airootfs/root/setup-locale.sh

echo "[*] Adding locale systemd service..."
mkdir -p airootfs/etc/systemd/system
cp "$CONFDIR/system/locale-setup.service" airootfs/etc/systemd/system/locale-setup.service

echo "[*] Apply KDE minimal theme..."
mkdir -p airootfs/home/main/.config/menus
cp "$CONFDIR/kde/Footer.qml" airootfs/root/Footer.qml
cp "$CONFDIR/kde/main.qml" airootfs/root/main.qml
cp "$CONFDIR/kde/plasmashellrc" airootfs/home/main/.config/plasmashellrc
cp "$CONFDIR/kde/kwinrc" airootfs/home/main/.config/kwinrc
cp "$CONFDIR/kde/plasma-org.kde.plasma.desktop-appletsrc" airootfs/home/main/.config/plasma-org.kde.plasma.desktop-appletsrc
cp "$CONFDIR/kde/applications-kmenuedit.menu" airootfs/home/main/.config/menus/applications-kmenuedit.menu

echo "[*] Configure pacman..."
cp "$CONFDIR/system/pacman.conf" airootfs/etc/pacman.conf

echo "[*] Adding setup-pkgs script..."
cp "$CONFDIR/setup-pkgs.sh" airootfs/root/setup-pkgs.sh
chmod +x airootfs/root/setup-pkgs.sh

echo "[*] Adding pkgs systemd service..."
cp "$CONFDIR/system/pkgs-setup.service" airootfs/etc/systemd/system/pkgs-setup.service

echo "[*] Copying Brave-Browser profile..."
mkdir -p airootfs/home/main/.config/BraveSoftware_Profile/
cp -r "$CONFDIR/brave/BraveSoftware_Profile/." airootfs/home/main/.config/BraveSoftware_Profile/
cp "$CONFDIR/brave/kwalletrc" airootfs/home/main/.config/kwalletrc
cp "$CONFDIR/brave/brave-profile" airootfs/home/main/.config/brave-profile
cp "$CONFDIR/brave/brave" airootfs/root/brave

echo "[*] Adding LightDM config..."
mkdir -p airootfs/etc/lightdm
cp "$CONFDIR/system/lightdm.conf" airootfs/etc/lightdm/lightdm.conf

echo "[*] Linking systemd services..."
mkdir -p airootfs/etc/systemd/system/{multi-user.target.wants,graphical.target.wants}
ln -sf /usr/lib/systemd/system/lightdm.service airootfs/etc/systemd/system/graphical.target.wants/lightdm.service
ln -sf /usr/lib/systemd/system/NetworkManager.service airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service
ln -sf /usr/lib/systemd/system/bluetooth.service airootfs/etc/systemd/system/multi-user.target.wants/bluetooth.service
ln -sf /usr/lib/systemd/system/org.cups.cupsd.service airootfs/etc/systemd/system/multi-user.target.wants/org.cups.cupsd.service
ln -sf /etc/systemd/system/locale-setup.service airootfs/etc/systemd/system/multi-user.target.wants/locale-setup.service
ln -sf /etc/systemd/system/pkgs-setup.service airootfs/etc/systemd/system/multi-user.target.wants/pkgs-setup.service

echo "[*] Setting up sudoers..."
mkdir -p airootfs/etc/sudoers.d
cp "$CONFDIR/system/00-rootpw" airootfs/etc/sudoers.d/00-rootpw
cp "$CONFDIR/system/00-main" airootfs/etc/sudoers.d/00-main
chmod 440 airootfs/etc/sudoers.d/00-rootpw
chmod 440 airootfs/etc/sudoers.d/00-main

echo "[*] Copying profile definition..."
cp "$CONFDIR/system/profiledef.sh" "$WORKDIR/profiledef.sh"

echo "[*] Cleaning up temp directory..."
rm -rfv "$WORKDIR/.temp"

echo "[*] Building ISO..."
sudo mkarchiso -v "$WORKDIR"
echo "[✓] ISO built successfully in out/"

