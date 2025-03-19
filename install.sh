#!/bin/bash

# Hardcode the branch (set to "test" for test branch, "master" for master branch)
BRANCH="test"

# Set base URL based on branch
if [ "$BRANCH" = "test" ]; then
  BASE_URL="https://raw.githubusercontent.com/devbyte1328/arch-setup/refs/heads/test"
  echo "Using config files from test branch"
else
  BASE_URL="https://raw.githubusercontent.com/devbyte1328/arch-setup/refs/heads/master"
  echo "Using config files from master branch"
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Starting Arch Linux installation..."

# Set NTP
timedatectl set-ntp true

# Function to convert size to bytes for comparison
convert_to_bytes() {
    local size=$1
    local unit=${size: -1}
    local num=${size%[A-Za-z]*}
    
    case $unit in
        G) echo $(bc <<< "scale=0; $num * 1024 * 1024 * 1024") ;;
        M) echo $(bc <<< "scale=0; $num * 1024 * 1024") ;;
        K) echo $(bc <<< "scale=0; $num * 1024") ;;
        *) echo "$num" ;;
    esac
}

echo "Detecting largest storage device..."

# Get list of disks (excluding partitions and ROMs)
largest_size=0
largest_disk=""

while read -r disk size; do
    if [[ ! $disk =~ ^(sd[a-z]|nvme[0-9]n[0-9]) ]] || [[ $disk =~ rom ]]; then
        continue
    fi
    
    size_bytes=$(convert_to_bytes "$size")
    if (( size_bytes > largest_size )); then
        largest_size=$size_bytes
        largest_disk="/dev/$disk"
    fi
done < <(lsblk -d -o NAME,SIZE -n | grep -v "loop")

if [ -z "$largest_disk" ]; then
    echo "No suitable disk found!"
    exit 1
fi

echo "Largest disk found: $largest_disk ($size)"
echo "Erasing $largest_disk..."
dd if=/dev/zero of="$largest_disk" bs=4M status=progress || true

# Partitioning the detected disk
echo "Partitioning $largest_disk..."
echo -e "g\nn\n\n\n+1G\nn\n\n\n\nw" | fdisk "$largest_disk"

# Format partitions
mkfs.fat -F32 "${largest_disk}1"
mkfs.ext4 "${largest_disk}2"

# Mount partitions
mkdir -p /mnt
mount "${largest_disk}2" /mnt
mkdir -p /mnt/boot/EFI
mount "${largest_disk}1" /mnt/boot/EFI

# Install base system with curl for timezone detection
pacstrap /mnt base linux linux-firmware bc curl

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the system
arch-chroot /mnt /bin/bash <<EOF
  # Automatically detect timezone using ipapi.co
  TIMEZONE=\$(curl -s https://ipapi.co/timezone)
  if [ -n "\$TIMEZONE" ] && [ -f "/usr/share/zoneinfo/\$TIMEZONE" ]; then
    echo "Detected timezone: \$TIMEZONE"
    ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime
  else
    echo "Failed to detect timezone or invalid response, falling back to UTC"
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
  fi
  hwclock --systohc

  # Detect country and set languages
  COUNTRY=\$(curl -s https://ipapi.co/country)
  LANGUAGE_MAP=\$(curl -s $BASE_URL/conf/language_mappings)
  
  # Default to English
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

  # Configure locales
  sed -i "s/#\$PRIMARY_LANG/\$PRIMARY_LANG/" /etc/locale.gen
  if [ -n "\$SECONDARY_LANG" ]; then
    sed -i "s/#\$SECONDARY_LANG/\$SECONDARY_LANG/" /etc/locale.gen
  fi
  locale-gen
  echo "LANG=\$PRIMARY_LANG" > /etc/locale.conf

  # Initramfs
  mkinitcpio -P

  # Install additional packages
  pacman -S --needed --noconfirm git base-devel
  pacman -S --noconfirm grub efibootmgr os-prober mtools dosfstools linux-headers networkmanager nm-connection-editor pipewire pipewire-pulse pipewire-alsa pavucontrol dialog

  # Create a temporary build user for AUR packages
  useradd -m -s /bin/bash builder
  echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/builder
  chown -R builder:builder /home/builder

  # Install yay-bin as the builder user
  su - builder -c "
    git clone https://aur.archlinux.org/yay-bin.git /home/builder/yay-bin
    cd /home/builder/yay-bin
    makepkg -si --noconfirm
  "

  # Clean up the temporary build user
  userdel -r builder
  rm -f /etc/sudoers.d/builder
  rm -rf /home/builder/yay-bin

  # GRUB setup
  grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
  grub-mkconfig -o /boot/grub/grub.cfg

  # Enable NetworkManager
  systemctl enable NetworkManager

  # Create user 'main'
  useradd -m -G wheel main
  passwd -d main

  # Uncomment wheel group in sudoers with NOPASSWD (optional)
  sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

  # Set root password
  echo "root:1" | chpasswd

  # Install display driver
  pacman -S --noconfirm xf86-video-vmware

  # Install Xorg and desktop environment
  pacman -S --noconfirm xorg sddm plasma konsole nano gedit dolphin firefox
  pacman -R --noconfirm plasma-welcome discover
  systemctl enable sddm

  # Configure SDDM autologin
  mkdir -p /etc/sddm.conf.d
  cat << 'SDDM' > /etc/sddm.conf.d/autologin.conf
[Autologin]
User=main
Session=plasma.desktop
SDDM

  # Set keyboard layout for console
  echo "KEYMAP=us" > /etc/vconsole.conf
  echo "FONT=lat2-16" >> /etc/vconsole.conf

  # Set X11 keyboard layout dynamically
  mkdir -p /etc/X11/xorg.conf.d
  cat << KEYBOARD > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "\$PRIMARY_KB\${SECONDARY_KB:+,}\$SECONDARY_KB"
    Option "XkbOptions" "\${SECONDARY_KB:+grp:alt_shift_toggle}"
EndSection
KEYBOARD

  # Create .config directory for user 'main' and download config files
  mkdir -p /home/main/.config/menus
  curl -o /home/main/.config/plasma-org.kde.plasma.desktop-appletsrc $BASE_URL/conf/plasma-org.kde.plasma.desktop-appletsrc
  curl -o /home/main/.config/plasmashellrc $BASE_URL/conf/plasmashellrc
  curl -o /home/main/.config/menus/applications-kmenuedit.menu $BASE_URL/conf/applications-kmenuedit.menu
  chown -R main:main /home/main/.config
  mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui
  curl -o /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml $BASE_URL/conf/main.qml
  curl -o /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/Footer.qml $BASE_URL/conf/Footer.qml

  # Install python-pip and change wallpapers to black
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

  # Create autostart script to set look and feel only once
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
EOF

# Unmount and reboot
umount -R /mnt
reboot
