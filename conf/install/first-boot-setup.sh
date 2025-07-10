#!/bin/bash

mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/
cp /root/Footer.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml
cp /root/main.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml

timeout 15s bash -c "until ping -c 1 archlinux.org >/dev/null 2>&1; do sleep 1; done" || { echo "No internet connection after 15s"; }
[ $? -eq 0 ] && timedatectl set-ntp true
