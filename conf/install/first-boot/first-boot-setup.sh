#!/bin/bash

CONFIG_FILE="/home/main/.config/first-boot/first-boot-setup.conf"

# Check if config file exists and contains First_Boot=TRUE
if grep -q '^First_Boot=TRUE' "$CONFIG_FILE"; then
    echo "First boot setup enabled. Running setup..."

    # Create plasmoid directory and copy files
    mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/
    cp /root/Easy-Arch/Footer.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml
    cp /root/Easy-Arch/main.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml

    # Wait up to 15 seconds for internet connection
    timeout 15s bash -c "until ping -c 1 archlinux.org >/dev/null 2>&1; do sleep 1; done" || { echo "No internet connection after 15s"; }
    [ $? -eq 0 ] && timedatectl set-ntp true

    # Set First_Boot=FALSE
    sed -i 's/^First_Boot=TRUE/First_Boot=FALSE/' "$CONFIG_FILE"
    echo "First boot setup complete. Config updated."
else
    echo "First boot setup not enabled. Skipping."
fi

