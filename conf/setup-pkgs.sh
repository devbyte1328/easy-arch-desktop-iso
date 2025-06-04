#!/bin/bash

sudo ufw enable
sudo ufw default reject incoming
sudo ufw default allow outgoing
sudo chmod +x /usr/bin/yay
sudo chmod +x /usr/bin/neofetch
sudo chmod +x /usr/bin/rar
sudo chmod +x /usr/bin/pinta
sudo mkdir -p /var/lib/pacman/local
sudo cp -r /root/temp/var/lib/pacman/local/* /var/lib/pacman/local/
sudo rm -rf /root/temp
