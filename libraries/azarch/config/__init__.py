"""Config-as-Python: every hand-authored artifact baked into the ISO, held as a
Python variable (string) or produced by a small builder function.

Modules:
  pacman     - the pacman.conf variants (download / pacstrap / build profile)
  system     - users, sudoers, sddm, plasma session, boot entries, systemd units
  locale     - country->locale/keyboard map + setup-locale.sh
  kde        - the small KDE INI/XML configs
  installer  - the disk installer, chroot-setup, first-boot, setup-pkgs scripts
  profile    - profiledef.sh (archiso profile definition + file_permissions)
"""
