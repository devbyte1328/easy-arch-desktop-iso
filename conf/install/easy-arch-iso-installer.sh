#!/bin/bash

# ANSI color code for light blue (Arch Linux logo color)
LIGHT_BLUE='\033[1;34m'
RESET='\033[0m'

echo -e "${LIGHT_BLUE}Welcome to Easy Arch Installation${RESET}"
echo "Select an installation option:"
echo "1. Automatically detect and erase largest hard drive (excludes USB drives) and install Easy Arch"
echo "2. Manually select hard drive to erase and install Easy Arch"
read -p "Enter option (1 or 2): " choice

if [ "$choice" = "2" ]; then
    echo "Hello World!"
    exit 0
fi

# Convert size strings to bytes for comparison
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

# Identify largest disk (excludes partitions, ROMs, and disks with mounted partitions)
largest_size=0
largest_disk=""

while read -r disk hotplug size; do
    # Skip loop devices and USB-connected drives
    if [[ "$hotplug" -eq 1 || "$disk" == loop* ]]; then
        continue
    fi

    # Skip disks with mounted partitions
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

# Convert largest_size to human-readable format for display
human_size=$(lsblk -d -o SIZE -n "$largest_disk")

echo "Largest disk detected: $largest_disk ($human_size)"

echo "Erasing $largest_disk with full wipe (this may take a while)..."
dd if=/dev/zero of="$largest_disk" bs=4M status=progress || true

# Partition the detected disk
echo "Partitioning $largest_disk..."
echo -e "g\nn\n\n\n+1G\nn\n\n\n\nw" | fdisk "$largest_disk"

# Determine partition names based on disk type (NVMe or SATA)
if [[ $largest_disk =~ ^/dev/nvme ]]; then
    part1="${largest_disk}p1"
    part2="${largest_disk}p2"
else
    part1="${largest_disk}1"
    part2="${largest_disk}2"
fi

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 "$part1"
mkfs.ext4 "$part2"

# Mount partitions
echo "Mounting partitions..."
mkdir -p /mnt
mount "$part2" /mnt
mkdir -p /mnt/boot/EFI
mount "$part1" /mnt/boot/EFI
