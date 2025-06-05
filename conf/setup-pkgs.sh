#!/bin/bash

echo "[*] Fixing package configs..."
sudo ufw enable
sudo ufw default reject incoming
sudo ufw default allow outgoing
sudo chmod +x /usr/bin/yay

echo "[*] Installing prebuilt AUR packages..."
pacman -U --noconfirm /root/aur_pkgs/*.pkg.tar.zst

echo "[*] Apply Brave-Browser profile..."
sudo cp /root/brave /usr/bin/brave
sudo chmod +x /usr/bin/brave
