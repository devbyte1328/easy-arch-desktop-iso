#!/bin/bash

# Fix package configs
sudo ufw enable
sudo ufw default reject incoming
sudo ufw default allow outgoing
sudo chmod +x /usr/bin/yay

# Install prebuilt AUR packages
pacman -U --noconfirm /root/aur_pkgs/*.pkg.tar.zst

# Apply Brave-Browser profile
sudo cp /root/brave /usr/bin/brave
sudo chmod +x /usr/bin/brave

# Apply KDE minimal theme
sudo mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/
sudo cp /root/Footer.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml
sudo cp /root/main.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml
sudo cp -r /root/Next/. /usr/share/wallpapers/Next/

# Fix easy arch iso installer permissions
sudo chmod +x /home/main/Desktop/easy-arch-iso-installer.sh
