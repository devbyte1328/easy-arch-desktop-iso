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

echo "[*] Apply KDE minimal theme..."
sudo mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/
sudo cp /root/Footer.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml
sudo cp /root/main.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml
