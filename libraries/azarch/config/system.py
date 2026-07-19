"""System-level configs: users, sudoers, display manager, session, boot menus,
and systemd units. Each is authored here as a Python string.

Kept byte-faithful to the originals under the old conf/system/. The user/group
databases and sudoers files in particular are security-sensitive; the modes are
applied by steps.py / profiledef (shadow 0400, sudoers 0440).
"""

from __future__ import annotations

# --- User / group databases -------------------------------------------------
# Baked into airootfs/etc so the live ISO has the `main` autologin user (uid 1000,
# gid 998=autologin) and a passwordless root. Blank password fields = no password.

PASSWD = """\
root:x:0:0:root:/root:/usr/bin/bash
main:x:1000:998::/home/main:/usr/bin/bash
"""

SHADOW = """\
root::14871::::::
main::14871::::::
"""

GSHADOW = """\
root:!*::
autologin:!*::
main:!*::
"""

GROUP = """\
root:x:0:
autologin:x:998:
main:x:1000:
"""

# --- sudoers ----------------------------------------------------------------
# 00-main: passwordless sudo for the live user. 00-rootpw: sudo asks for the ROOT
# password, not the user's (matches the blank-password live setup). Mode 0440.

SUDOERS_MAIN = "main ALL=(ALL) NOPASSWD: ALL\n"
SUDOERS_ROOTPW = "Defaults rootpw\n"

# --- OS branding ------------------------------------------------------------
# What fastfetch (and any os-release reader) shows as the distro name. Written to
# airootfs/usr/lib/os-release, the REAL file that /etc/os-release symlinks to.
# The stock file comes from the `filesystem` package and says "Arch Linux"; our
# airootfs copy overlays on top of the pacstrapped rootfs so it wins. mkarchiso
# still appends IMAGE_ID / IMAGE_VERSION lines of its own after this.
#
# ID stays `arch` on purpose: pacman, AUR helpers, and countless scripts key on
# ID=arch to treat the system as Arch. Only NAME/PRETTY_NAME (the human strings
# fastfetch prints) change to the azarch brand. ID_LIKE reinforces the lineage.
OS_RELEASE = """\
NAME="Az'arch Linux"
PRETTY_NAME="Az'arch Linux"
ID=arch
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;6;184;253"
HOME_URL="https://github.com/michaelilgiaev/azarch"
SUPPORT_URL="https://github.com/michaelilgiaev/azarch"
BUG_REPORT_URL="https://github.com/michaelilgiaev/azarch/issues"
LOGO=archlinux-logo
"""

# System hostname. The archiso releng base ships `archiso`; we overlay `azarch`
# so the shell prompt and fastfetch title read main@azarch instead of main@archiso.
# (We deliberately do NOT rename the `archiso` build TOOLING or the ISO's internal
# install_dir -- those are functional identifiers from the archiso project, not
# branding.) The plain `azarch` here is the live-ISO hostname; the on-disk
# installer sets the installed system's hostname separately.
HOSTNAME = "azarch\n"

# --- SDDM / session ---------------------------------------------------------
# Autologin `main` straight into the X11 Plasma session (no Wayland — the build's
# pacman NoExtract drops the wayland session file; see config/pacman.py).

SDDM_CONF = """\
[Autologin]
User=main
Session=plasma.desktop

[General]
DisplayServer=x11
"""

PLASMA_DESKTOP = """\
[Desktop Entry]
Name=Plasma
Comment=KDE Plasma (X11)
Exec=startplasma-x11
TryExec=startplasma-x11
Type=Application
DesktopNames=KDE
X-KDE-SessionType=x11
"""

# --- Boot menu entries ------------------------------------------------------
# systemd-boot (UEFI) entries + syslinux (BIOS) config. %INSTALL_DIR% and
# %ARCHISO_UUID% are archiso placeholders substituted by mkarchiso.

BOOT_UEFI_LINUX = """\
title    Arch Linux install medium (x86_64, UEFI)
sort-key 01
linux    /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux
initrd   /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% cow_spacesize=4G
"""

BOOT_UEFI_SPEECH = """\
title    Arch Linux install medium (x86_64, UEFI) with speech
sort-key 02
linux    /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux
initrd   /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% accessibility=on cow_spacesize=4G
"""

BOOT_BIOS_SYSLINUX = """\
LABEL arch64
TEXT HELP
Boot the Arch Linux install medium on BIOS.
It allows you to install Arch Linux or perform system maintenance.
ENDTEXT
MENU LABEL Arch Linux install medium (x86_64, BIOS)
LINUX /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% cow_spacesize=4G

# Accessibility boot option
LABEL arch64speech
TEXT HELP
Boot the Arch Linux install medium on BIOS with speakup screen reader.
It allows you to install Arch Linux or perform system maintenance with speech feedback.
ENDTEXT
MENU LABEL Arch Linux install medium (x86_64, BIOS) with ^speech
LINUX /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% accessibility=on cow_spacesize=4G
"""

# --- systemd units ----------------------------------------------------------
# Two oneshot services baked into the LIVE ISO: setup-locale (auto-detect
# locale/keyboard/timezone from IP) and setup-pkgs (firewall + theme tweaks).

LOCALE_SETUP_SERVICE = """\
[Unit]
Description=Auto-detect locale, keyboard, and timezone
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/azarch/setup-locale.sh
StandardOutput=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""

PKGS_SETUP_SERVICE = """\
[Unit]
Description=Configure Packages
After=network.target
ConditionPathExists=/root/azarch/setup-pkgs.sh

[Service]
Type=oneshot
ExecStart=/root/azarch/setup-pkgs.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
"""
