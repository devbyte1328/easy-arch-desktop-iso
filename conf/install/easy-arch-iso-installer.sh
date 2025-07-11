#!/bin/bash

set -o pipefail

cd /

# ANSI color codes
LIGHT_BLUE='\033[1;34m'
RED='\033[1;31m'
RESET='\033[0m'

echo -e "${LIGHT_BLUE}Welcome to Easy Arch Installation${RESET}"
echo -e "${RED}WARNING:${RESET} This will erase everything on the targeted disk using wipefs -a, removing all filesystem, RAID, and partition-table signatures${RESET}"
echo "Select an installation option:"
echo "1. Automatically detect largest disk (excludes USB drives) and install Easy Arch"
echo "2. Manually select disk to erase and install Easy Arch"
read -p "Enter option (1 or 2): " choice

if [ "$choice" = "2" ]; then
    echo "Manual selection not implemented!"
    exit 0
fi

# Convert size strings to bytes
convert_to_bytes() {
    local size=$1
    local unit=${size: -1}
    local num=${size%[A-Za-z]*}

    case $unit in
        T) awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024 * 1024 * 1024}" ;;
        G) awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024 * 1024}" ;;
        M) awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024}" ;;
        K) awk "BEGIN {printf \"%.0f\", $num * 1024}" ;;
        *) awk "BEGIN {printf \"%.0f\", $num}" ;;
    esac
}

echo "Searching for largest storage device..."

# Identify largest disk
largest_size=0
largest_disk=""

while read -r disk hotplug size; do
    if [[ "$hotplug" -eq 1 || "$disk" == loop* ]]; then
        continue
    fi
    if lsblk -d -o NAME,MOUNTPOINTS -n "/dev/$disk" | grep -q "[[:space:]]\+/"; then
        echo "Skipping $disk (contains mounted partitions)"
        continue
    fi
    size_bytes=$(convert_to_bytes "$size")
    if [ "$size_bytes" -gt "$largest_size" ]; then
        largest_size=$size_bytes
        largest_disk="/dev/$disk"
    fi
done < <(lsblk -d -o NAME,HOTPLUG,SIZE -n)

if [ -z "$largest_disk" ]; then
    echo "No suitable disk found!"
    exit 1
fi

human_size=$(lsblk -d -o SIZE -n "$largest_disk")
echo "Largest disk detected: $largest_disk ($human_size)"

echo "Erasing $largest_disk with 'wipefs -a'..."
wipefs -a "$largest_disk"

echo "Partitioning $largest_disk..."
echo -e "g\nn\n\n\n+1G\nn\n\n\n\nw" | fdisk "$largest_disk"

if [[ $largest_disk =~ ^/dev/nvme ]]; then
    part1="${largest_disk}p1"
    part2="${largest_disk}p2"
else
    part1="${largest_disk}1"
    part2="${largest_disk}2"
fi

echo "Formatting partitions..."
mkfs.fat -F32 "$part1"
mkfs.ext4 "$part2"

echo "Mounting partitions..."
mkdir -p /mnt
mount "$part2" /mnt
mkdir -p /mnt/boot/EFI
mount "$part1" /mnt/boot/EFI

echo "Setting up local repository..."
mkdir -p /mnt/pacstrap-easyarch-repo
mkdir -p /tmp/pacstrap-easyarch-db
cp -r /root/pacstrap-easyarch-repo/. /mnt/pacstrap-easyarch-repo/
cp -r /root/pacstrap-easyarch-db/. /tmp/pacstrap-easyarch-db/
cp /root/pacstrap-easyarch-conf/pacman.conf /etc/pacman.conf

echo "Running pacstrap..."
pacstrap /mnt $(tr '\n' ' ' < /root/packages.x86_64)

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Copying chroot setup..."
mkdir -p /mnt/root
cp /root/chroot-setup.sh /mnt/chroot-setup.sh
chmod +x /mnt/chroot-setup.sh

echo "Setting up users and sudo config..."
mkdir -p /mnt/etc
mkdir -p /mnt/etc/sudoers.d
cp /etc/passwd /mnt/etc/passwd
cp /etc/shadow /mnt/etc/shadow
cp /etc/gshadow /mnt/etc/gshadow
cp /etc/group /mnt/etc/group
cp /etc/sudoers.d/00-rootpw /mnt/etc/sudoers.d/00-rootpw
cp /etc/sudoers.d/00-main /mnt/etc/sudoers.d/00-main
chmod 440 /mnt/etc/sudoers.d/00-rootpw
chmod 440 /mnt/etc/sudoers.d/00-main

echo "[*] Adding LightDM config..."
mkdir -p /mnt/home/main
chown -R 1000:998 /mnt/home/main
mkdir -p /mnt/etc/lightdm
cp /etc/lightdm/lightdm.conf /mnt/etc/lightdm/lightdm.conf

echo "[*] Copying over yay build files..."
mkdir -p /mnt/root/yay-build
cp -r /root/yay-build/. /mnt/root/yay-build/

echo "[*] Copying over aur pkg build files..."
mkdir -p /mnt/root/aur_pkgs
cp -r /root/aur_pkgs/. /mnt/root/aur_pkgs/

echo "[*] Copying over KDE minimal theme files..."
mkdir -p /mnt/home/main/.config/menus
mkdir -p /mnt/root/kde
mkdir -p /mnt/usr/share/wallpapers/Next
cp /root/kde/Footer.qml /mnt/root/Footer.qml
cp /root/kde/main.qml /mnt/root/main.qml
cp /root/kde/plasmashellrc /mnt/home/main/.config/plasmashellrc
cp /root/kde/kwinrc /mnt/home/main/.config/kwinrc
cp /root/kde/plasma-org.kde.plasma.desktop-appletsrc /mnt/home/main/.config/plasma-org.kde.plasma.desktop-appletsrc
cp /root/kde/applications-kmenuedit.menu /mnt/home/main/.config/menus/applications-kmenuedit.menu
cp /root/kde/kdeglobals /mnt/home/main/.config/kdeglobals
cp -r /root/kde/Next/. /mnt/usr/share/wallpapers/Next

echo "[*] Copying over first boot configuration files..."
mkdir -p /mnt/home/main/.config
mkdir -p /mnt/etc/systemd/system
mkdir -p /mnt/etc/profile.d
cp /root/first-boot-setup.sh /mnt/home/main/.config/first-boot-setup.sh
cp /root/first-boot-setup.service /mnt/etc/systemd/system/first-boot-setup.service

echo "[*] Copying over Brave browser profile..."
mkdir -p /mnt/root/BraveSoftware_Profile
mkdir -p /mnt/root/BraveSoftware_Config
cp -r /home/main/.config/BraveSoftware_Profile/. /mnt/root/BraveSoftware_Profile/
cp /home/main/.config/kwalletrc /mnt/root/BraveSoftware_Config/kwalletrc
cp /home/main/.config/brave-profile /mnt/root/BraveSoftware_Config/brave-profile
cp /root/brave /mnt/root/BraveSoftware_Config/brave

echo "[*] Building yay and copying over bin file..."
mkdir -p /tmp/yay-build
chmod 777 /tmp/yay-build
cp -r /root/yay-build/* /tmp/yay-build/.
cd /tmp/yay-build
sudo -u main makepkg -s --noconfirm --skippgpcheck
cd /root
mkdir -p /mnt/usr/bin
cp /tmp/yay-build/pkg/yay/usr/bin/yay /mnt/usr/bin/yay
chmod +x /mnt/usr/bin/yay

echo "Running chroot setup..."
arch-chroot /mnt /bin/bash /chroot-setup.sh
rm /mnt/chroot-setup.sh

umount -R /mnt
