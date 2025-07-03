#!/bin/bash

# Get timezone and country from IP
TIMEZONE=$(curl -s https://ipapi.co/timezone)
COUNTRY=$(curl -s https://ipapi.co/country)

# Defaults
PRIMARY_LANG="en_US.UTF-8"
SECONDARY_LANG=""
PRIMARY_KB="us"
SECONDARY_KB=""

# Language mapping
LANGUAGE_MAP=$(cat <<EOF
US|English|en_US.UTF-8
GB|English|en_GB.UTF-8
FR|French|fr_FR.UTF-8
DE|German|de_DE.UTF-8
ES|Spanish|es_ES.UTF-8
IT|Italian|it_IT.UTF-8
UA|Ukrainian|uk_UA.UTF-8
RU|Russian|ru_RU.UTF-8
CN|Chinese|zh_CN.UTF-8
JP|Japanese|ja_JP.UTF-8
KR|Korean|ko_KR.UTF-8
BR|Portuguese|pt_BR.UTF-8
IN|Hindi|hi_IN.UTF-8
IL|Hebrew|he_IL.UTF-8
AR|Arabic|ar_SA.UTF-8
TR|Turkish|tr_TR.UTF-8
NL|Dutch|nl_NL.UTF-8
PL|Polish|pl_PL.UTF-8
SE|Swedish|sv_SE.UTF-8
NO|Norwegian|nb_NO.UTF-8
DK|Danish|da_DK.UTF-8
FI|Finnish|fi_FI.UTF-8
CZ|Czech|cs_CZ.UTF-8
HU|Hungarian|hu_HU.UTF-8
GR|Greek|el_GR.UTF-8
TH|Thai|th_TH.UTF-8
VN|Vietnamese|vi_VN.UTF-8
EOF
)

# Match country code to locale
MATCH=$(echo "$LANGUAGE_MAP" | grep "^$COUNTRY|")
if [ -n "$MATCH" ]; then
  LOCALE_CODE=$(echo "$MATCH" | cut -d'|' -f3)
  KB_LAYOUT=$(echo "$COUNTRY" | tr '[:upper:]' '[:lower:]')

  if [ "$COUNTRY" = "US" ]; then
    PRIMARY_LANG="$LOCALE_CODE"
    PRIMARY_KB="$KB_LAYOUT"
  else
    PRIMARY_LANG="en_US.UTF-8"
    SECONDARY_LANG="$LOCALE_CODE"
    PRIMARY_KB="us"
    SECONDARY_KB="$KB_LAYOUT"
  fi
fi

# Enable locales
sed -i "s/^#\?\s*$PRIMARY_LANG/$PRIMARY_LANG/" /etc/locale.gen
if [ -n "$SECONDARY_LANG" ]; then
  sed -i "s/^#\?\s*$SECONDARY_LANG/$SECONDARY_LANG/" /etc/locale.gen
fi

# Generate locales
locale-gen

# Set system locale
echo "LANG=$PRIMARY_LANG" > /etc/locale.conf

# Set console keyboard
echo "KEYMAP=$PRIMARY_KB" > /etc/vconsole.conf
echo "FONT=lat2-16" >> /etc/vconsole.conf

# Set X11 keyboard layout
mkdir -p /etc/X11/xorg.conf.d
cat <<EOF > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$PRIMARY_KB${SECONDARY_KB:+,}$SECONDARY_KB"
    Option "XkbOptions" "${SECONDARY_KB:+grp:alt_shift_toggle}"
EndSection
EOF

# Set timezone
if [ -n "$TIMEZONE" ] && [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
  ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
else
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi

hwclock --systohc

# Mark setup complete
touch /var/log/.locale_set

# Generate initramfs
mkinitcpio -P

pacman -U --noconfirm /root/aur_pkgs/*.pkg.tar.zst

grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
grub-mkconfig -o /boot/grub/grub.cfg

mkdir -p /tmp/yay-build
chmod 777 /tmp/yay-build
mv /root/yay-build/* /tmp/yay-build/
useradd -m builduser
chown -R builduser:builduser /tmp/yay-build
su - builduser -c "cd /tmp/yay-build && makepkg -si --noconfirm --skippgpcheck -f"
cd /root
userdel -r builduser || true

systemctl enable lightdm
systemctl enable NetworkManager

mkdir -p /home/main/.config
chown 1000:998 /home/main/.config
chmod 755 /home/main/.config/first-boot-setup.sh
chmod 644 /etc/systemd/system/first-boot-setup.service
systemctl enable first-boot-setup.service
