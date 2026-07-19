"""The on-disk install pipeline scripts, authored in Python and emitted as the
real .sh/.desktop/.conf/.service files the ISO ships.

  installer_desktop()        autostart .desktop that launches the installer
  installer_sh()             azarch-iso-installer.sh: partition, pacstrap from
                             the offline repo, copy config, run chroot-setup
  chroot_setup_sh()          runs inside arch-chroot: locale, bootloader, services
  setup_pkgs_sh()            live-ISO oneshot: firewall + theme tweaks
  first_boot_sh/service/conf first-boot-once mechanism on the installed system

The KDE 'Next' wallpaper was removed in the overhaul, so none of these copy a
wallpaper any more (the old code did `cp -r .../Next/. /usr/share/wallpapers/Next`).
The desktop ships KDE's stock Breeze wallpaper.
"""

from __future__ import annotations

from .locale import _detect_and_apply_locale_block


# --- Autostart launcher for the installer -----------------------------------
def installer_desktop() -> str:
    return """\
[Desktop Entry]
Type=Application
Exec=konsole -e bash -c "sudo /home/main/Desktop/azarch-iso-installer.sh; exec bash"
Hidden=false
NoDisplay=false
Name=Run Script
Comment=Run the script on Desktop
"""


# --- The disk installer (runs in the live session) --------------------------
def installer_sh() -> str:
    return """\
#!/bin/bash

set -o pipefail

cd /

# ANSI color codes
LIGHT_BLUE='\\033[1;34m'
RED='\\033[1;31m'
RESET='\\033[0m'

echo -e "${LIGHT_BLUE}Welcome to azarch Installation${RESET}"
echo -e "${RED}WARNING:${RESET} This will erase everything on the targeted disk using wipefs -a, removing all filesystem, RAID, and partition-table signatures${RESET}"
echo "Select an installation option:"
echo "1. Automatically detect largest disk (excludes USB drives) and install azarch"
echo "2. Manually select disk to erase and install azarch"
read -p "Enter option (1 or 2): " choice

# Convert size strings to bytes
convert_to_bytes() {
    local size=$1
    local unit=${size: -1}
    local num=${size%[A-Za-z]*}

    case $unit in
        T) awk "BEGIN {printf \\"%.0f\\", $num * 1024 * 1024 * 1024 * 1024}" ;;
        G) awk "BEGIN {printf \\"%.0f\\", $num * 1024 * 1024 * 1024}" ;;
        M) awk "BEGIN {printf \\"%.0f\\", $num * 1024 * 1024}" ;;
        K) awk "BEGIN {printf \\"%.0f\\", $num * 1024}" ;;
        *) awk "BEGIN {printf \\"%.0f\\", $num}" ;;
    esac
}

if [ "$choice" = "2" ]; then
    echo "Available disks:"
    echo "----------------"
    lsblk -d -e7,11 -o NAME,SIZE,MODEL | while read -r line; do
        echo "$line"
    done
    echo "----------------"
    read -p "Enter the device name (e.g., sda or nvme0n1): " manual_disk
    if [ ! -b "/dev/$manual_disk" ]; then
        echo "Invalid disk selected!"
        exit 1
    fi

    if mount | grep -q "/dev/$manual_disk"; then
        echo "Selected disk is mounted. Aborting."
        exit 1
    fi

    largest_disk="/dev/$manual_disk"
else
    echo "Searching for largest storage device..."

    largest_size=0
    largest_disk=""

    while read -r disk hotplug size; do
        if [[ "$hotplug" -eq 1 || "$disk" == loop* ]]; then
            continue
        fi
        if lsblk -d -o NAME,MOUNTPOINTS -n "/dev/$disk" | grep -q "[[:space:]]\\+/"; then
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
fi

is_uefi=0
if [ -d "/sys/firmware/efi" ]; then
  is_uefi=1
fi

echo "Erasing $largest_disk with 'wipefs -a'..."
wipefs -a "$largest_disk"

if [ $is_uefi -eq 1 ]; then
  echo "Partitioning $largest_disk for UEFI..."
  echo -e "g\\nn\\n\\n\\n+1G\\nt\\n1\\nn\\n\\n\\n\\nw" | fdisk "$largest_disk"
else
  echo "Partitioning $largest_disk for BIOS..."
  echo -e "g\\nn\\n\\n\\n+1M\\nt\\n4\\nn\\n\\n\\n\\nw" | fdisk "$largest_disk"
fi

if [[ $largest_disk =~ ^/dev/nvme ]]; then
    part1="${largest_disk}p1"
    part2="${largest_disk}p2"
else
    part1="${largest_disk}1"
    part2="${largest_disk}2"
fi

echo "Formatting partitions..."
if [ $is_uefi -eq 1 ]; then
  mkfs.fat -F32 "$part1"
fi
mkfs.ext4 "$part2"

echo "Mounting partitions..."
mkdir -p /mnt
mount "$part2" /mnt
if [ $is_uefi -eq 1 ]; then
  mkdir -p /mnt/boot/EFI
  mount "$part1" /mnt/boot/EFI
fi

mkdir -p /mnt/etc/install_info
echo "$largest_disk" > /mnt/etc/install_info/disk
echo "$is_uefi" > /mnt/etc/install_info/is_uefi

echo "Setting up local repository..."
mkdir -p /mnt/pacstrap-azarch-repo
mkdir -p /tmp/pacstrap-azarch-db
cp -r /root/azarch/pacstrap-azarch-repo/. /mnt/pacstrap-azarch-repo/
cp -r /root/azarch/pacstrap-azarch-db/. /tmp/pacstrap-azarch-db/
cp /etc/pacman.conf /etc/pacman.bak
cp /root/azarch/pacstrap-azarch-conf/pacman.conf /etc/pacman.conf

echo "Running pacstrap..."
pacstrap /mnt $(tr '\\n' ' ' < /root/azarch/packages.x86_64)

mv /etc/pacman.bak /etc/pacman.conf

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Copying chroot setup..."
mkdir -p /mnt
cp /root/azarch/chroot-setup.sh /mnt/chroot-setup.sh
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

echo "[*] Adding SDDM config..."
mkdir -p /mnt/home/main
chown -R 1000:998 /mnt/home/main
mkdir -p /mnt/etc
cp /etc/sddm.conf /mnt/etc/sddm.conf

echo "[*] Copying X11 startup file..."
mkdir -p /mnt/usr/share/xsessions
cp /usr/share/xsessions/plasma.desktop /mnt/usr/share/xsessions/plasma.desktop

echo "[*] Copying KDE minimal theme files..."
mkdir -p /mnt/home/main/.config/menus
mkdir -p /mnt/root/azarch/kde
cp /root/azarch/kde/Footer.qml /mnt/root/azarch/Footer.qml
cp /root/azarch/kde/main.qml /mnt/root/azarch/main.qml
cp /root/azarch/kde/plasmashellrc /mnt/home/main/.config/plasmashellrc
cp /root/azarch/kde/kwinrc /mnt/home/main/.config/kwinrc
cp /root/azarch/kde/plasma-org.kde.plasma.desktop-appletsrc /mnt/home/main/.config/plasma-org.kde.plasma.desktop-appletsrc
cp /root/azarch/kde/applications-kmenuedit.menu /mnt/home/main/.config/menus/applications-kmenuedit.menu
cp /root/azarch/kde/kdeglobals /mnt/home/main/.config/kdeglobals

echo "[*] Copying azarch fastfetch config..."
mkdir -p /mnt/home/main/.config/fastfetch
cp /root/azarch/fastfetch/config.jsonc /mnt/home/main/.config/fastfetch/config.jsonc
cp /root/azarch/fastfetch/azarch.ansi /mnt/home/main/.config/fastfetch/azarch.ansi

echo "[*] Copying first boot configuration files..."
mkdir -p /mnt/home/main/.config/first-boot
mkdir -p /mnt/etc/systemd/system
mkdir -p /mnt/etc/profile.d
cp /root/azarch/first-boot-setup.sh /mnt/home/main/.config/first-boot/first-boot-setup.sh
cp /root/azarch/first-boot-setup.service /mnt/etc/systemd/system/first-boot-setup.service
cp /root/azarch/first-boot-setup.conf /mnt/home/main/.config/first-boot/first-boot-setup.conf

echo "[*] Copying pacman config..."
mkdir -p /mnt/etc
cp /root/azarch/pacman-base-conf/pacman.conf /mnt/etc/pacman.conf

echo "Running chroot setup..."
arch-chroot /mnt /bin/bash /chroot-setup.sh
rm /mnt/chroot-setup.sh

umount -R /mnt
"""


# --- Runs inside the arch-chroot after pacstrap -----------------------------
def chroot_setup_sh() -> str:
    return f"""\
#!/bin/bash

{_detect_and_apply_locale_block()}

pacman-key --init
pacman-key --populate archlinux

# Mark setup complete
touch /var/log/.locale_set

# Generate initramfs
mkinitcpio -P

pacman -R --noconfirm discover plasma-welcome

is_uefi=$(cat /etc/install_info/is_uefi)
disk=$(cat /etc/install_info/disk)

if [ $is_uefi -eq 1 ]; then
  grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck --efi-directory=/boot/EFI
else
  grub-install --target=i386-pc "$disk"
fi

grub-mkconfig -o /boot/grub/grub.cfg

mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/
cp /root/azarch/Footer.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml
cp /root/azarch/main.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml

systemctl enable sddm
systemctl enable NetworkManager

mkdir -p /home/main/.config
chown 1000:998 /home/main/.config
chmod 755 /home/main/.config/first-boot/first-boot-setup.sh
chmod 644 /etc/systemd/system/first-boot-setup.service
chmod 666 /home/main/.config/first-boot/first-boot-setup.conf
systemctl enable first-boot-setup.service

chmod 666 /home/main/.config/plasmashellrc

find /home/main -type f -exec chmod 666 {{}} \\;
find /home/main -type d -exec chmod 777 {{}} \\;
find /home/main -type f -exec chmod +x {{}} \\;
chown -R main:main /home/main

pacman -Sy

echo -e "\\e[94mazarch disk installation complete, you can reboot now.\\e[0m"
"""


# --- Live-ISO post-boot tweaks ----------------------------------------------
def setup_pkgs_sh() -> str:
    """Firewall + KDE theme + installer perms. The 'Next' wallpaper copy that used
    to live here was removed with the wallpaper."""
    return """\
#!/bin/bash

# Fix firewall config
sudo ufw enable
sudo ufw default reject incoming
sudo ufw default allow outgoing

# Apply KDE minimal theme
sudo mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/
sudo cp /root/azarch/Footer.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml
sudo cp /root/azarch/main.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml

# Fix azarch iso installer permissions
sudo chmod +x /home/main/Desktop/azarch-iso-installer.sh

# Remove unnecesary packages
sudo pacman -R --noconfirm discover plasma-welcome
pkill plasma-welcome
"""


# --- First-boot-once mechanism (installed system) ---------------------------
def first_boot_conf() -> str:
    return """\
# Set to TRUE to enable first boot shell script.
# as the name suggests, first boot will only run once after boot and then disable itself.
# This file is checked upon startup.
First_Boot=TRUE
"""


def first_boot_service() -> str:
    return """\
[Unit]
Description=First boot configuration
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/home/main/.config/first-boot/first-boot-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""


def first_boot_sh() -> str:
    return """\
#!/bin/bash

CONFIG_FILE="/home/main/.config/first-boot/first-boot-setup.conf"

# Check if config file exists and contains First_Boot=TRUE
if grep -q '^First_Boot=TRUE' "$CONFIG_FILE"; then
    echo "First boot setup enabled. Running setup..."

    # Create plasmoid directory and copy files
    mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/
    cp /root/azarch/Footer.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml
    cp /root/azarch/main.qml /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml

    # Wait up to 15 seconds for internet connection
    timeout 15s bash -c "until ping -c 1 archlinux.org >/dev/null 2>&1; do sleep 1; done" || { echo "No internet connection after 15s"; }
    [ $? -eq 0 ] && timedatectl set-ntp true

    # Set First_Boot=FALSE
    sed -i 's/^First_Boot=TRUE/First_Boot=FALSE/' "$CONFIG_FILE"
    echo "First boot setup complete. Config updated."
else
    echo "First boot setup not enabled. Skipping."
fi
"""
