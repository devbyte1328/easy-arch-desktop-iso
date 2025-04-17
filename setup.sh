#!/bin/bash

# Hardcode the branch ("test" for test branch, "master" for master branch)
BRANCH="master"

# Set base URL based on selected branch
if [ "$BRANCH" = "test" ]; then
    BASE_URL="https://raw.githubusercontent.com/devbyte1328/arch-setup/refs/heads/test"
    echo "Using config files from test branch"
elif [ "$BRANCH" = "stable" ]; then
    BASE_URL="https://raw.githubusercontent.com/devbyte1328/arch-setup/refs/heads/stable"
    echo "Using config files from stable branch"
else
    BASE_URL="https://raw.githubusercontent.com/devbyte1328/arch-setup/refs/heads/master"
    echo "Using config files from master branch"
fi

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Starting Arch Linux installation..."

# Enable Network Time Protocol
timedatectl set-ntp true

# Function to convert size strings to bytes for comparison
convert_to_bytes() {
    local size=$1
    local unit=${size: -1}
    local num=${size%[A-Za-z]*}

    # Use awk to handle floating-point numbers and convert to integer
    case $unit in
        T) echo $(awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024 * 1024 * 1024}") ;;
        G) echo $(awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024 * 1024}") ;;
        M) echo $(awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024}") ;;
        K) echo $(awk "BEGIN {printf \"%.0f\", $num * 1024}") ;;
        *) echo $(awk "BEGIN {printf \"%.0f\", $num}") ;;
    esac
}

echo "Detecting largest storage device..."

# Find the largest disk (excluding partitions, ROMs, and disks with mounted partitions)
largest_size=0
largest_disk=""

while read -r disk size; do
    # Skip non-disk devices, ROMs, and loop devices
    if [[ ! $disk =~ ^(sd[a-z]|nvme[0-9]n[0-9]) ]] || [[ $disk =~ rom ]] || [[ $disk =~ loop ]]; then
        continue
    fi

    # Check if the disk has mounted partitions
    if lsblk -d -o NAME,MOUNTPOINTS -n "/dev/$disk" | grep -q "[[:space:]]\+/"; then
        echo "Skipping $disk (has mounted partitions)"
        continue
    fi

    size_bytes=$(convert_to_bytes "$size")
    if [ "$size_bytes" -gt "$largest_size" ]; then
        largest_size=$size_bytes
        largest_disk="/dev/$disk"
    fi
done < <(lsblk -d -o NAME,SIZE -n)

if [ -z "$largest_disk" ]; then
    echo "No suitable disk found!"
    exit 1
fi

# Convert largest_size back to human-readable format for display
human_size=$(lsblk -d -o SIZE -n "$largest_disk")

echo "Largest disk found: $largest_disk ($human_size)"

echo "Erasing all existing data..."

if [ "$BRANCH" = "master" ]; then
    echo "Erasing $largest_disk with full wipe (this may take a while)..."
    dd if=/dev/zero of="$largest_disk" bs=4M status=progress || true
else
    echo "Wiping existing filesystem signatures from $largest_disk..."
    wipefs -a "$largest_disk"
fi

# Partition the detected disk
echo "Partitioning $largest_disk..."
echo -e "g\nn\n\n\n+1G\nn\n\n\n\nw" | fdisk "$largest_disk"

# Detect if the disk is NVMe or SATA and set partition names accordingly
if [[ $largest_disk =~ ^/dev/nvme ]]; then
    part1="${largest_disk}p1"
    part2="${largest_disk}p2"
else
    part1="${largest_disk}1"
    part2="${largest_disk}2"
fi

# Format the partitions
echo "Formatting partitions..."
mkfs.fat -F32 "$part1"
mkfs.ext4 "$part2"

# Mount the partitions
echo "Mounting partitions..."
mkdir -p /mnt
mount "$part2" /mnt
mkdir -p /mnt/boot/EFI
mount "$part1" /mnt/boot/EFI


# Install base system with additional utilities
if [ "$BRANCH" = "test" ]; then
  pacstrap /mnt base linux linux-firmware bc curl
elif [ "$BRANCH" = "stable" ]; then
  echo "Server=https://archive.archlinux.org/repos/2025/04/10/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
  pacstrap /mnt base linux linux-firmware util-linux bc curl
else
  pacstrap /mnt base linux linux-firmware bc curl
fi

# Generate fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system and configure it
arch-chroot /mnt /bin/bash <<EOF
  # Detect and set timezone automatically
  TIMEZONE=\$(curl -s https://ipapi.co/timezone)
  if [ -n "\$TIMEZONE" ] && [ -f "/usr/share/zoneinfo/\$TIMEZONE" ]; then
    echo "Detected timezone: \$TIMEZONE"
    ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime
  else
    echo "Failed to detect timezone or invalid response, falling back to UTC"
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
  fi
  hwclock --systohc

  # Detect country and configure languages
  COUNTRY=\$(curl -s https://ipapi.co/country)
  LANGUAGE_MAP=\$(curl -s $BASE_URL/conf/kde/language_mappings)
  
  # Default to English settings
  PRIMARY_LANG="en_US.UTF-8"
  SECONDARY_LANG=""
  PRIMARY_KB="us"
  SECONDARY_KB=""
  
  if [[ "\$COUNTRY" != "US" && "\$COUNTRY" != "GB" && "\$COUNTRY" != "AU" && "\$COUNTRY" != "CA" && "\$COUNTRY" != "NZ" ]]; then
    MATCH=\$(echo "\$LANGUAGE_MAP" | grep "^\$COUNTRY|" | head -n 1)
    if [ -n "\$MATCH" ]; then
      SECONDARY_LANG=\$(echo "\$MATCH" | cut -d'|' -f3)
      SECONDARY_KB=\$(echo "\$MATCH" | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]')
    fi
  fi

  # Configure and generate locales
  sed -i "s/#\$PRIMARY_LANG/\$PRIMARY_LANG/" /etc/locale.gen
  if [ -n "\$SECONDARY_LANG" ]; then
    sed -i "s/#\$SECONDARY_LANG/\$SECONDARY_LANG/" /etc/locale.gen
  fi
  locale-gen
  echo "LANG=\$PRIMARY_LANG" > /etc/locale.conf

  # Generate initramfs
  mkinitcpio -P

  # Install essential packages based on BRANCH
  if [ "$BRANCH" = "test" ]; then
    echo "Installing packages for TEST branch..."
    pacman -S --needed --noconfirm git base-devel
    pacman -S --noconfirm grub efibootmgr os-prober mtools dosfstools linux-headers networkmanager nm-connection-editor pipewire pipewire-pulse pipewire-alsa pavucontrol dialog ufw vim neovim htop
  elif [ "$BRANCH" = "stable" ]; then
    echo "Installing packages for STABLE branch..."
    pacman -U --needed --noconfirm https://archive.archlinux.org/packages/g/git/git-2.49.0-1-x86_64.pkg.tar.zst
    pacman -U --needed --noconfirm https://archive.archlinux.org/packages/b/base-devel/base-devel-1-2-any.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/g/git/git-2.49.0-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/b/base-devel/base-devel-1-2-any.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/g/grub/grub-2%3A2.12rc1-7-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/e/efibootmgr/efibootmgr-18-3-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/o/os-prober/os-prober-1.83-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/m/mtools/mtools-4.0.28-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/d/dosfstools/dosfstools-4.2-5-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/l/linux-headers/linux-headers-6.9.arch1-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/n/networkmanager/networkmanager-1.52.0-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/n/nm-connection-editor/nm-connection-editor-1.8.24-1-x86_64.pkg.tar.xz
    pacman -U --noconfirm https://archive.archlinux.org/packages/p/pipewire/pipewire-1%3A1.4.1-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/p/pipewire-pulse/pipewire-pulse-1%3A1.4.1-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/p/pipewire-alsa/pipewire-alsa-1%3A1.4.1-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/p/pavucontrol/pavucontrol-1%3A6.1-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/d/dialog/dialog-1%3A1.3_20250116-1-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/u/ufw/ufw-0.36.2-5-any.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/v/vim/vim-9.1.1236-2-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/n/neovim/neovim-0.9.5-6-x86_64.pkg.tar.zst
    pacman -U --noconfirm https://archive.archlinux.org/packages/h/htop/htop-3.4.1-1-x86_64.pkg.tar.zst
  else
    echo "Installing packages for MASTER branch..."
    pacman -S --needed --noconfirm git base-devel
    pacman -S --noconfirm grub efibootmgr os-prober mtools dosfstools linux-headers networkmanager nm-connection-editor pipewire pipewire-pulse pipewire-alsa pavucontrol dialog ufw vim neovim htop
  fi

  # Create temporary build user for AUR packages
  useradd -m -s /bin/bash builder
  echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/builder
  chown -R builder:builder /home/builder

  # Install yay-bin and brave-bin as the builder user
  su - builder -c "
    git clone https://aur.archlinux.org/yay-bin.git /home/builder/yay-bin
    cd /home/builder/yay-bin
    makepkg -si --noconfirm
    yay -S brave-bin gimp libreoffice-fresh redot-bin neovim virtualbox obs-studio openshot blender rar kclock xclip --noconfirm
  "

  # Remove temporary build user and cleanup
  userdel -r builder
  rm -f /etc/sudoers.d/builder
  rm -rf /home/builder/yay-bin

  # Install and configure GRUB
  grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
  grub-mkconfig -o /boot/grub/grub.cfg

  # Enable NetworkManager service
  systemctl enable NetworkManager

  # Create main user
  useradd -m -G wheel main
  passwd -d main

  # Configure sudo privileges for wheel group
  sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

  # Set root password
  echo "root:root" | chpasswd

  # Detect and install appropriate display drivers
  echo "Detecting graphics hardware and virtualization environment..."
  
  # Check if running in VirtualBox
  if [ "$(systemd-detect-virt)" = "oracle" ]; then
    echo "Running in VirtualBox, installing VirtualBox-specific drivers and utilities..."
    pacman -S --noconfirm xf86-video-vmware virtualbox-guest-utils
    systemctl enable vboxservice
  else
    echo "Not running in VirtualBox, checking physical GPU..."
    # Use lspci to detect GPU
    if lspci | grep -i "vga" | grep -i "nvidia" > /dev/null; then
      echo "NVIDIA GPU detected, installing NVIDIA drivers..."
      pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
    elif lspci | grep -i "vga" | grep -i "amd" > /dev/null || lspci | grep -i "vga" | grep -i "ati" > /dev/null; then
      echo "AMD GPU detected, installing AMD drivers..."
      pacman -S --noconfirm xf86-video-amdgpu
    elif lspci | grep -i "vga" | grep -i "intel" > /dev/null; then
      echo "Intel GPU detected, installing Intel drivers..."
      pacman -S --noconfirm xf86-video-intel
    else
      echo "No specific GPU detected or unsupported hardware, falling back to generic VESA driver..."
      pacman -S --noconfirm xf86-video-vesa
    fi
  fi

  # Install Xorg and KDE Plasma desktop environment
  pacman -S --noconfirm xorg sddm plasma konsole nano gedit dolphin kcalc gwenview neofetch htop docker docker-compose ttf-0xproto-nerd unzip kamoso qbittorrent deskflow tesseract tesseract-data-eng python-pip
  pacman -R --noconfirm plasma-welcome discover
  systemctl enable sddm
  systemctl enable docker
  systemctl start docker

  # Configure SDDM for autologin
  mkdir -p /etc/sddm.conf.d
  cat << 'SDDM' > /etc/sddm.conf.d/autologin.conf
[Autologin]
User=main
Session=plasma.desktop
SDDM

  # Set console keyboard layout
  echo "KEYMAP=us" > /etc/vconsole.conf
  echo "FONT=lat2-16" >> /etc/vconsole.conf

  # Configure X11 keyboard layout
  mkdir -p /etc/X11/xorg.conf.d
  cat << KEYBOARD > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "\$PRIMARY_KB\${SECONDARY_KB:+,}\$SECONDARY_KB"
    Option "XkbOptions" "\${SECONDARY_KB:+grp:alt_shift_toggle}"
EndSection
KEYBOARD

  # Set up user config files
  mkdir -p /home/main/.config/menus
  curl -o /home/main/.config/plasma-org.kde.plasma.desktop-appletsrc $BASE_URL/conf/kde/plasma-org.kde.plasma.desktop-appletsrc
  curl -o /home/main/.config/plasmashellrc $BASE_URL/conf/kde/plasmashellrc
  curl -o /home/main/.config/menus/applications-kmenuedit.menu $BASE_URL/conf/kde/applications-kmenuedit.menu
  chown -R main:main /home/main/.config
  mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui
  curl -o /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml $BASE_URL/conf/kde/main.qml
  curl -o /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml $BASE_URL/conf/kde/Footer.qml
  curl -o /home/main/.config/kwalletrc $BASE_URL/conf/brave/kwalletrc
  curl -o /etc/pacman.conf $BASE_URL/conf/pacman/pacman.conf
  curl -o /home/main/.config/kwinrc $BASE_URL/conf/kde/kwinrc

  mkdir -p /home/main/Desktop
  curl -o /home/main/Desktop/set-password.sh $BASE_URL/conf/system/set-password.sh
  chmod +x /home/main/Desktop/set-password.sh
  chown main:main /home/main/Desktop/set-password.sh

  # Install Python and modify wallpapers
  pacman -S --noconfirm python-pip
  python -m venv /root/temp_env
  /root/temp_env/bin/python -m pip install pillow
  cat << 'PYTHON' > /root/blackout.py
from PIL import Image
import os

directories = [
    "/usr/share/wallpapers/Next/contents/images/",
    "/usr/share/wallpapers/Next/contents/images_dark/"
]

for directory in directories:
    if os.path.exists(directory):
        for filename in os.listdir(directory):
            filepath = os.path.join(directory, filename)
            if os.path.isfile(filepath):
                with Image.open(filepath) as img:
                    black_img = Image.new(img.mode, img.size, "black")
                    black_img.save(filepath)
PYTHON
  /root/temp_env/bin/python /root/blackout.py
  rm -rf /root/temp_env /root/blackout.py

  # Create autostart script for look and feel
  mkdir -p /home/main/.config/autostart-scripts
  cat << 'AUTOSTART' > /home/main/.config/autostart-scripts/set-lookandfeel.sh
#!/bin/bash
FLAG_FILE="/home/main/.lookandfeel_set"

if [ ! -f "\$FLAG_FILE" ]; then
    lookandfeeltool -a org.kde.breezedark.desktop
    touch "\$FLAG_FILE"
fi
AUTOSTART
  chmod +x /home/main/.config/autostart-scripts/set-lookandfeel.sh
  chown main:main /home/main/.config/autostart-scripts/set-lookandfeel.sh

  # Create autostart script for Brave configuration
  cat << 'AUTOSTART_BRAVE' > /home/main/.config/autostart-scripts/set-brave.sh
#!/bin/bash
FLAG_FILE="/home/main/.brave_set"

if [ ! -f "\$FLAG_FILE" ]; then
    git clone -b "$BRANCH" https://github.com/devbyte1328/arch-setup.git
    cd arch-setup/conf/brave
    mkdir -p /home/main/.config/BraveSoftware/Brave-Browser
    cp -r BraveSoftware/ /home/main/.config/
    cd ../../..
    rm -rf arch-setup/
    touch "\$FLAG_FILE"
fi
AUTOSTART_BRAVE
  chmod +x /home/main/.config/autostart-scripts/set-brave.sh
  chown main:main /home/main/.config/autostart-scripts/set-brave.sh

  # Create autostart script for kscreenlockerrc configuration
  cat << 'AUTOSTART_KSCREEN' > /home/main/.config/autostart-scripts/set-kscreenlockerrc.sh
#!/bin/bash
FLAG_FILE="/home/main/.kscreenlockerrc_set"

if [ ! -f "\$FLAG_FILE" ]; then
    cat << 'KSCREEN' > /home/main/.config/kscreenlockerrc
[Daemon]
Autolock=false
Timeout=0
KSCREEN
    chown main:main /home/main/.config/kscreenlockerrc
    touch "\$FLAG_FILE"
fi
AUTOSTART_KSCREEN
  chmod +x /home/main/.config/autostart-scripts/set-kscreenlockerrc.sh
  chown main:main /home/main/.config/autostart-scripts/set-kscreenlockerrc.sh

  # Create autostart script for downloading Konsole colorscheme
  cat << 'AUTOSTART_KONSOLE' > /home/main/.config/autostart-scripts/set-konsole-colorscheme.sh
#!/bin/bash
FLAG_FILE="/home/main/.konsole_colorscheme_set"

if [ ! -f "\$FLAG_FILE" ]; then
    mkdir -p /home/main/.local/share/konsole
    curl -o /home/main/.local/share/konsole/catppuccin-mocha.colorscheme https://raw.githubusercontent.com/catppuccin/konsole/refs/heads/main/themes/catppuccin-mocha.colorscheme
    chown main:main /home/main/.local/share/konsole/catppuccin-mocha.colorscheme
    touch "\$FLAG_FILE"
fi
AUTOSTART_KONSOLE
  chmod +x /home/main/.config/autostart-scripts/set-konsole-colorscheme.sh
  chown main:main /home/main/.config/autostart-scripts/set-konsole-colorscheme.sh

  if [ "$BRANCH" = "test" ]; then
    pacman -Syu --noconfirm
  elif [ "$BRANCH" = "stable" ]; then
    pacman -Sy --noconfirm
  else
    pacman -Syu --noconfirm
  fi
EOF

# Unmount partitions and reboot
umount -R /mnt
reboot
