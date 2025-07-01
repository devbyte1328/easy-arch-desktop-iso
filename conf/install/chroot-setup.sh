#!/bin/bash

# Detect and set timezone automatically
TIMEZONE=$(curl -s https://ipapi.co/timezone)
if [ -n "$TIMEZONE" ] && [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
  echo "Detected timezone: $TIMEZONE"
  ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
else
  echo "Failed to detect timezone or invalid response, falling back to UTC"
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi

hwclock --systohc

# Detect country and configure languages
COUNTRY=$(curl -s https://ipapi.co/country)
LANGUAGE_MAP=$(cat /root/language_mappings)

# Default to English settings
PRIMARY_LANG="en_US.UTF-8"
SECONDARY_LANG=""
PRIMARY_KB="us"
SECONDARY_KB=""

if [[ "$COUNTRY" != "US" && "$COUNTRY" != "GB" && "$COUNTRY" != "AU" && "$COUNTRY" != "CA" && "$COUNTRY" != "NZ" ]]; then
  MATCH=$(echo "$LANGUAGE_MAP" | grep "^$COUNTRY|" | head -n 1)
  if [ -n "$MATCH" ]; then
    SECONDARY_LANG=$(echo "$MATCH" | cut -d'|' -f3)
    SECONDARY_KB=$(echo "$MATCH" | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]')
  fi
fi

# Configure and generate locales
sed -i "s/#$PRIMARY_LANG/$PRIMARY_LANG/" /etc/locale.gen
if [ -n "$SECONDARY_LANG" ]; then
  sed -i "s/#$SECONDARY_LANG/$SECONDARY_LANG/" /etc/locale.gen
fi
locale-gen
echo "LANG=$PRIMARY_LANG" > /etc/locale.conf

# Generate initramfs
mkinitcpio -P

grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable lightdm
systemctl enable NetworkManager

mkdir -p /home/main/.config
chown 1000:998 /home/main/.config
chmod 755 /home/main/.config/first-boot-setup.sh
chmod 644 /etc/systemd/system/first-boot-setup.service
systemctl enable first-boot-setup.service
