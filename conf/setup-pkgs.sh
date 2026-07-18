#!/bin/bash

# Fix firewall config
sudo ufw enable
sudo ufw default reject incoming
sudo ufw default allow outgoing

# Apply KDE minimal theme
sudo mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/
sudo cp /root/Easy-Arch/Footer.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml
sudo cp /root/Easy-Arch/main.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml
sudo cp -r /root/Easy-Arch/Next/. /usr/share/wallpapers/Next/

# Fix easy arch iso installer permissions
sudo chmod +x /home/main/Desktop/easy-arch-iso-installer.sh

# Remove unnecesary packages
sudo pacman -R --noconfirm discover plasma-welcome
pkill plasma-welcome
