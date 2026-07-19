# Az'arch -- Distribution Specification

A technical specification of the Az'arch operating system: the software that
ships on the ISO. This describes **the distribution itself** -- its package set,
the real dependency hierarchy from the kernel at the base up to the leaf
applications at the top, and what each subsystem actually does.

The dependency data here is **real**, not inferred from package names. It was
resolved from the official Arch Linux `core`, `extra` and `multilib` package
databases -- the same repositories the ISO is assembled against -- by reading
each package's actual `%DEPENDS%` / `%PROVIDES%` fields and walking the full
transitive closure. Every version number below is the real packaged version.

---

## 1. At a glance

- **Base distribution:** Arch Linux (rolling), x86_64
- **Desktop:** KDE Plasma (Wayland + X11) with KDE Gear applications
- **Kernel:** `linux` 7.1.4.arch1-1
- **Init:** `systemd` 261.1-1
- **Purpose:** live / rescue / installer medium with a full KDE desktop

| Metric | Value |
|---|---:|
| Explicit manifest entries | 242 (243 lines; `unzip` listed twice) |
| Explicit entries incl. group members (`xorg`+`plasma`) | 300 |
| **Full package set (transitive closure)** | **1325** |
| &nbsp;&nbsp;from `core` / `extra` / `multilib` | 228 / 986 / 111 |
| Pulled-in-only dependencies (not explicitly listed) | 1025 |
| Top / leaf packages (nothing depends on them) | 203 |
| Base / sink packages (depend on nothing else in the set) | 71 |
| Deepest dependency chain (leaf -> base) | 45 hops |
| Total installed size of the package set | 7.61 GiB |

> **How to read "top" and "base".** *Base* packages sit at the bottom of the
> graph: they depend on nothing else in the set, and huge numbers of other
> packages depend on them. *Top* (leaf) packages sit at the surface: nothing
> depends on them, so removing a top package removes only itself (and any deps
> that then become unused) -- nothing else in the system breaks.

---

## 2. The dependency graph -- base to top

```text
                       Az'arch dependency graph  --  base (bottom) to top (leaves)

  TOP / LEAVES (203 pkgs)   nothing depends on these; remove one and nothing else breaks
  e.g.  plasma-desktop  dolphin  gwenview  konsole  vlc  libreoffice-fresh  neovim
        end-user desktop apps, KDE System Settings modules, the installer tools
            |                          |                        |
            v                          v                        v
  FRAMEWORKS (KDE Frameworks 6, Qt6, GTK, .NET, Go std)
     kio  kservice  kconfig  qt6-base  qt6-declarative  gtk3  gtk4  plasma-workspace
            |                          |                        |
            v                          v                        v
  MID / SYSTEM LIBS
     dbus  polkit  systemd  pipewire  networkmanager  mesa  libglvnd  cups  wayland
            |                          |                        |
            v                          v                        v
  CORE LIBS
     glibc  libgcc  libstdc++  bash  ncurses  readline  zlib  xz  openssl  libxml2
            |                          |                        |
            v                          v                        v
  BASE / SINKS (71 pkgs, depend on nothing else in the set)
     iana-etc  tzdata  linux-api-headers  xorgproto  xcb-proto  pambase  xkeyboard-config
     (glibc/libgcc are near-base keystones, not sinks: they still depend on a
      handful of these -- glibc -> linux-api-headers, tzdata, filesystem)

  KERNEL:  linux 7.1.4.arch1-1  (+ linux-firmware, amd-ucode, intel-ucode)
           the kernel is a root, not a hub: only broadcom-wl and
           virtualbox-guest-utils-nox depend on the linux package itself.
```

### 2.1 How the layers were computed

- Every explicit manifest entry was resolved to a real Arch package. The two
  group entries were expanded to their members: `xorg` -> 49 packages,
  `plasma` -> 70 packages.
- From those roots, the full transitive dependency closure was walked using the
  real `%DEPENDS%` fields (virtual/provides dependencies resolved via
  `%PROVIDES%`). That closure is **1325 packages** with **0
  unresolved dependency edges**.
- *Base / sink* = out-degree 0 within the closure (depends on nothing else in
  the set). *Top / leaf* = in-degree 0 (nothing in the set depends on it).
- "Depended on by (transitive)" counts every package that ultimately reaches a
  package through the dependency graph; it is the true measure of how load-
  bearing a package is.

---

## 3. The base tier (the bottom of the graph)

These **71** packages are the sinks of the dependency graph: they pull in nothing else from the set. They are the foundation everything else is stacked on. Sorted by how many packages ultimately depend on them.

| Package | Version | Repo | Depended on by (transitive) | Installed | What it is |
|---|---|---|---:|---:|---|
| `iana-etc` | 20260530-1 | core | 1239 | 4.0 MiB | /etc/protocols and /etc/services provided by IANA |
| `linux-api-headers` | 7.1-1 | core | 1238 | 6.9 MiB | Kernel headers sanitized for use in userspace |
| `tzdata` | 2026c-1 | core | 1238 | 1.6 MiB | Sources for time zone and daylight saving time data |
| `pambase` | 20260616-1 | core | 416 | 2.7 KiB | Base PAM configuration for services |
| `libsysprof-capture` | 50.0-2 | extra | 377 | 274.1 KiB | Kernel based performance profiler - capture library |
| `xorgproto` | 2025.1-1 | extra | 373 | 1.5 MiB | combined X.Org X11 Protocol headers |
| `xcb-proto` | 1.17.0-4 | extra | 365 | 1.0 MiB | XML-XCB protocol descriptions |
| `default-cursors` | 3-1 | extra | 256 | 30 B | Default cursor set |
| `xkeyboard-config` | 2.48-1 | extra | 227 | 10.2 MiB | X keyboard configuration files |
| `liburing` | 2.15-1 | extra | 189 | 478.2 KiB | Linux-native io_uring I/O access library |
| `qt6-translations` | 6.11.1-1 | extra | 184 | 15.4 MiB | A cross-platform application and UI framework (Translations) |
| `alsa-topology-conf` | 1.2.5.1-4 | extra | 144 | 335.7 KiB | ALSA topology configuration files |
| `alsa-ucm-conf` | 1.2.16.1-1 | extra | 144 | 692.4 KiB | ALSA Use Case Manager configuration (and topologies) |
| `iso-codes` | 4.20.1-1 | extra | 134 | 22.3 MiB | Lists of the country, language, and currency names |
| `hwdata` | 0.409-1 | core | 123 | 10.0 MiB | hardware identification databases |
| `hicolor-icon-theme` | 0.18-1 | extra | 86 | 54.3 KiB | Freedesktop.org Hicolor icon theme |
| `sound-theme-freedesktop` | 0.8-6 | extra | 79 | 461.2 KiB | Freedesktop sound theme |
| `adwaita-fonts` | 50.0-1 | extra | 46 | 7.3 MiB | The typefaces for GNOME |
| `fuse-common` | 3.18.2-1 | extra | 36 | 725 B | Common files for fuse2/3 packages |
| `gnulib-l10n` | 20241231-1 | core | 31 | 629.1 KiB | The Gnulib localizations |
| `adwaita-cursors` | 50.0-1 | extra | 26 | 11.4 MiB | GNOME standard cursors |
| `xorg-fonts-encodings` | 1.1.0-2 | extra | 26 | 629.5 KiB | X.org font encoding files |
| `breeze-cursors` | 6.7.3-1 | extra | 17 | 29.3 MiB | Breeze cursors |
| `noto-fonts` | 1:2026.07.01-1 | extra | 14 | 106.8 MiB | Google Noto TTF fonts |
| `ocean-sound-theme` | 6.7.3-1 | extra | 14 | 2.1 MiB | Ocean Sound Theme for Plasma |
| `ttf-hack` | 3.003-7 | extra | 14 | 1.2 MiB | A hand groomed and optically balanced typeface based on Bitstream Vera Mono. |
| `gnu-free-fonts` | 20120503-9 | extra | 13 | 6.6 MiB | A free family of scalable outline fonts |
| `mobile-broadband-provider-info` | 20251101-1 | extra | 12 | 509.3 KiB | APN configuration presets for mobile broadband connections |
| `linux-firmware-whence` | 20260622-1 | core | 11 | 438.8 KiB | Firmware files for Linux - WHENCE file (vendor licenses) |
| `lv2` | 1.18.10-2 | extra | 9 | 1001.5 KiB | Plugin standard for audio systems |
| `qt5-translations` | 5.15.19-1 | extra | 7 | 14.7 MiB | A cross-platform application and UI framework (Translations) |
| `pacman-mirrorlist` | 20260610-1 | core | 6 | 26.7 KiB | Arch Linux mirror list for use by pacman |
| `alsa-card-profiles` | 1:1.6.8-1 | extra | 5 | 198.8 KiB | Low-latency audio/video router and processor - ALSA card profiles |
| `libsonic` | 0.2.0-2 | extra | 3 | 39.8 KiB | Simple library to speed up or slow down speech |
| `tesseract-data-osd` | 2:4.1.0-5 | extra | 3 | 10.1 MiB | Tesseract OCR data (osd) |
| `dnssec-anchors` | 20250524-1 | core | 2 | 809 B | DNSSEC trust anchors for the root zone |
| `libavtp` | 0.2.0-3 | extra | 2 | 49.4 KiB | Open source implementation of Audio Video Transport Protocol |
| `oniguruma` | 6.9.10-1 | extra | 2 | 901.5 KiB | a regular expressions library |
| `archlinux-appstream-data` | 20260606-1 | extra | 1 | 22.5 MiB | Arch Linux application database for AppStream-based software centers |
| `dotnet-targeting-pack` | 10.0.10.sdk110-1 | extra | 1 | 50.9 MiB | The .NET Core targeting pack |
| `libdnet` | 1.18.2-1 | extra | 1 | 163.9 KiB | A simplified, portable interface to several low-level networking routines |
| `licenses` | 20240728-1 | core | 1 | 1.5 MiB | A set of common license files |
| `linux-firmware-other` | 20260622-1 | core | 1 | 30.2 MiB | Firmware files for Linux - Unsorted firmware for various devices |
| `noto-fonts-emoji` | 1:2.051-1 | extra | 1 | 10.2 MiB | Google Noto Color Emoji font |
| `oxygen-cursors` | 6.7.3-1 | extra | 1 | 17.1 MiB | Oxygen cursors |
| `oxygen-icons` | 1:6.28.0-1 | extra | 1 | 34.6 MiB | The Oxygen Icon Theme |
| `tree-sitter-c` | 0.24.1-2 | extra | 1 | 616.3 KiB | C grammar for tree-sitter |
| `tree-sitter-query` | 0.8.0-2 | extra | 1 | 40.5 KiB | TS query grammar for tree-sitter |
| `tree-sitter-vimdoc` | 4.1.0-2 | extra | 1 | 209.6 KiB | Vim help file grammar for tree-sitter |
| `uriparser` | 1.0.2-1 | extra | 1 | 287.5 KiB | uriparser is a strictly RFC 3986 compliant URI parsing library. uriparser is cross-platform, fast, supports Unicode |
| `vim-runtime` | 9.2.0804-1 | extra | 1 | 38.5 MiB | Vi Improved, a highly configurable, improved version of the vi text editor (shared runtime) |
| `xorg-fonts-alias-100dpi` | 1.0.6-1 | extra | 1 | 3.5 KiB | X.org font alias files - 100dpi font familiy |
| `xorg-fonts-alias-75dpi` | 1.0.6-1 | extra | 1 | 3.4 KiB | X.org font alias files - 75dpi font familiy |
| `xorg-util-macros` | 1.20.2-1 | extra | 1 | 88.1 KiB | X.Org Autotools macros |
| `amd-ucode` | 20260622-1 | core | 0 | 602.9 KiB | Microcode update image for AMD CPUs |
| `breeze-gtk` | 6.7.3-1 | extra | 0 | 1.2 MiB | Breeze widget theme for GTK 2 and 3 |
| `edk2-shell` | 202605-1 | extra | 0 | 6.7 MiB | EDK2 UEFI Shell |
| `go` | 2:1.26.5-1 | extra | 0 | 215.7 MiB | Core compiler tools for the Go programming language |
| `intel-ucode` | 20260512-1 | extra | 0 | 30.7 MiB | Microcode update files for Intel CPUs |
| `livecd-sounds` | 1.0-3 | extra | 0 | 306.3 KiB | Sound files for accessibility features in a boot medium |
| `man-pages` | 6.18-1 | core | 0 | 5.6 MiB | Linux man pages |
| `memtest86+` | 7.20-2 | extra | 0 | 153.5 KiB | Advanced memory diagnostic tool legacy BIOS version |
| `memtest86+-efi` | 7.20-2 | extra | 0 | 154.9 KiB | Advanced memory diagnostic tool EFI version |
| `oxygen-sounds` | 6.7.3-1 | extra | 0 | 2.1 MiB | The Oxygen Sound Theme |
| `plasma-workspace-wallpapers` | 6.7.3-1 | extra | 0 | 255.1 MiB | Additional wallpapers for the Plasma Workspace |
| `rxvt-unicode-terminfo` | 9.31-9 | extra | 0 | 4.9 KiB | Terminfo files for urxvt |
| `sof-firmware` | 2025.12.2-1 | extra | 0 | 42.8 MiB | Sound Open Firmware |
| `syslinux` | 6.04.pre3.r3.g05ac953c-4 | core | 0 | 4.3 MiB | Collection of boot loaders that boot from FAT, ext2/3/4 and btrfs filesystems, from CDs and via PXE |
| `terminus-font` | 4.49.1-8 | extra | 0 | 3.0 MiB | Monospace bitmap font (for X11 and console) |
| `wireless_tools` | 30.pre9-5 | extra | 0 | 346.3 KiB | Tools allowing to manipulate the Wireless Extensions |
| `xorg-server-src` | 21.1.24-1 | extra | 0 | 21.3 MiB | Source files of the X.Org X server |

### 3.1 The load-bearing keystones

Not every keystone is a sink (some have a few deps of their own), but these are
the packages the largest share of the system ultimately rests on. `glibc` alone
is a direct dependency of 915 packages; the C runtime, compression
libraries and core crypto libraries underpin essentially everything.

| Package | Version | Direct dependents | Transitive dependents | What it is |
|---|---|---:|---:|---|
| `iana-etc` | 20260530-1 | 1 | 1239 | /etc/protocols and /etc/services provided by IANA |
| `filesystem` | 2025.10.12-1 | 5 | 1238 | Base Arch Linux files |
| `linux-api-headers` | 7.1-1 | 2 | 1238 | Kernel headers sanitized for use in userspace |
| `tzdata` | 2026c-1 | 2 | 1238 | Sources for time zone and daylight saving time data |
| `glibc` | 2.43+r37+gfdf10644d6ee-1 | 915 | 1237 | GNU C Library |
| `libgcc` | 16.1.1+r346+g4e03491b401d-4 | 254 | 950 | Low-level runtime library shipped by GCC |
| `libstdc++` | 16.1.1+r346+g4e03491b401d-4 | 294 | 938 | C++ runtime libraries shipped by GCC |
| `lib32-glibc` | 2.43+r37+gfdf10644d6ee-1 | 91 | 908 | GNU C Library (32-bit) |
| `lib32-gcc-libs` | 16.1.1+r346+g4e03491b401d-4 | 29 | 872 | 32-bit runtime libraries shipped by GCC |
| `ncurses` | 6.6-2 | 32 | 863 | System V Release 4.0 curses emulation library |
| `lib32-ncurses` | 6.6-2 | 15 | 852 | System V Release 4.0 curses emulation library (32-bit) |
| `readline` | 8.3.003-1 | 31 | 850 | GNU readline library |
| `bash` | 5.3.15-1 | 128 | 822 | The GNU Bourne Again shell |
| `zlib` | 1:1.3.2-3 | 110 | 808 | Compression library implementing the deflate compression method found in gzip and PKZIP |
| `xz` | 5.8.3-1 | 26 | 677 | Library and command line tools for XZ and LZMA compressed files |
| `lz4` | 1:1.10.0-2 | 11 | 671 | Extremely fast compression algorithm |
| `zstd` | 1.5.7-3 | 31 | 669 | Zstandard - Fast real-time compression algorithm |
| `sqlite` | 3.53.3-1 | 10 | 643 | A C library that implements an SQL database engine |
| `util-linux-libs` | 2.42.2-1 | 25 | 640 | util-linux runtime libraries |
| `brotli` | 1.2.0-1 | 12 | 630 | Generic-purpose lossless compression algorithm |
| `libxcrypt` | 4.5.2-1 | 17 | 605 | Modern library for one-way hashing of passwords |
| `openssl` | 3.6.3-1 | 62 | 595 | The Open Source toolkit for cryptography and Transport Layer Security |
| `lib32-libxcrypt` | 4.5.2-1 | 3 | 582 | Modern library for one-way hashing of passwords (32-bit) |
| `gdbm` | 1.26-2 | 6 | 568 | GNU database library |
| `lib32-openssl` | 1:3.6.3-1 | 21 | 562 | The Open Source toolkit for Secure Sockets Layer and Transport Layer Security (32-bit) |
| `libgpg-error` | 1.61-1 | 8 | 555 | Support library for libgcrypt |
| `e2fsprogs` | 1.47.4-1 | 9 | 553 | Ext2/3/4 filesystem utilities |
| `bzip2` | 1.0.8-6 | 26 | 552 | A high-quality data compression program |
| `libevent` | 2.1.13-2 | 4 | 552 | Event notification library |
| `libgcrypt` | 1.12.2-1 | 18 | 551 | General purpose cryptographic library based on the code from GnuPG |

---

## 4. The top tier (the leaves)

These **203** packages are the leaves: nothing in the package set depends on them. Remove any one and nothing else in the system breaks -- only that package (and dependencies that become orphaned) goes away. "Pulls in" is the number of transitive dependencies each leaf drags in behind it.

| Package | Version | Repo | Pulls in (transitive deps) | Installed | What it is |
|---|---|---|---:|---:|---|
| `plasma-welcome` | 6.7.3-1 | extra | 630 | 3.5 MiB | A friendly onboarding wizard for Plasma |
| `plasma-bigscreen` | 6.7.3-1 | extra | 604 | 3.9 MiB | Plasma shell for TVs |
| `plasma-vault` | 6.7.3-1 | extra | 604 | 1.2 MiB | Plasma applet and services for creating encrypted vaults |
| `plasma-browser-integration` | 6.7.3-1 | extra | 601 | 614.3 KiB | Components necessary to integrate browsers into the Plasma Desktop |
| `plasma-desktop` | 6.7.3-1 | extra | 599 | 40.1 MiB | KDE Plasma Desktop |
| `plasma-pa` | 6.7.3-1 | extra | 598 | 2.1 MiB | Plasma applet for audio volume management using PulseAudio |
| `kdeplasma-addons` | 6.7.3-1 | extra | 581 | 18.6 MiB | All kind of addons to improve your Plasma experience |
| `plasma-login-manager` | 6.7.3-1 | extra | 576 | 1.7 MiB | Plasma Login Manager |
| `kamoso` | 26.04.3-1 | extra | 537 | 641.5 KiB | A webcam recorder from KDE community |
| `spectacle` | 1:6.7.3-1 | extra | 490 | 6.2 MiB | KDE screenshot capture utility |
| `discover` | 6.7.3-1 | extra | 475 | 7.3 MiB | KDE and Plasma resources management GUI |
| `krdp` | 6.7.3-1 | extra | 473 | 827.5 KiB | Library and examples for creating an RDP server |
| `gwenview` | 26.04.3-1 | extra | 472 | 11.4 MiB | A fast and easy to use image viewer |
| `dolphin` | 26.04.3-1 | extra | 470 | 15.5 MiB | KDE File Manager |
| `plasma-sdk` | 6.7.3-1 | extra | 453 | 3.2 MiB | Applications useful for Plasma development |
| `plasma-systemmonitor` | 6.7.3-1 | extra | 444 | 2.6 MiB | An interface for monitoring system sensors, process information and other system resources |
| `konsole` | 26.04.3-1 | extra | 439 | 9.8 MiB | KDE terminal emulator |
| `kclock` | 26.04.3-1 | extra | 437 | 2.5 MiB | Clock app for Plasma Mobile |
| `plasma-keyboard` | 6.7.3-1 | extra | 437 | 1.5 MiB | Virtual Keyboard for Qt based desktops |
| `print-manager` | 1:6.7.3-1 | extra | 436 | 2.7 MiB | A tool for managing print jobs and printers |
| `kdialog` | 26.04.3-1 | extra | 426 | 763.8 KiB | A utility for displaying dialog boxes from shell scripts |
| `flatpak-kcm` | 6.7.3-1 | extra | 353 | 766.7 KiB | Flatpak Permissions Management KCM |
| `plasma-disks` | 6.7.3-1 | extra | 343 | 624.7 KiB | Monitors S.M.A.R.T. capable devices for imminent failure |
| `vlc-plugin-ffmpeg` | 3.0.23_2-9 | extra | 337 | 247.6 KiB | Free and open source cross-platform multimedia player and framework - FFMPEG plugins |
| `kwin-x11` | 6.7.3-1 | extra | 334 | 25.8 MiB | An easy to use, but flexible, X Window Manager |
| `sddm-kcm` | 6.7.3-1 | extra | 314 | 608.3 KiB | KDE Config Module for SDDM |
| `drkonqi` | 6.7.3-1 | extra | 313 | 3.4 MiB | The KDE crash handler |
| `wacomtablet` | 6.7.3-1 | extra | 312 | 2.6 MiB | GUI for Wacom Linux drivers that supports different button/pen layout profiles |
| `kscreen` | 6.7.3-1 | extra | 311 | 3.4 MiB | KDE screen management software |
| `plymouth-kcm` | 6.7.3-1 | extra | 305 | 314.9 KiB | KCM to manage the Plymouth (Boot) theme |
| `oxygen` | 6.7.3-1 | extra | 296 | 34.3 MiB | KDE Oxygen style |
| `bluedevil` | 1:6.7.3-1 | extra | 295 | 2.6 MiB | Integrate the Bluetooth technology within KDE workspace and applications |
| `plasma-firewall` | 6.7.3-1 | extra | 290 | 1.3 MiB | Control Panel for your system firewall |
| `plasma-thunderbolt` | 6.7.3-1 | extra | 289 | 550.8 KiB | Plasma integration for controlling Thunderbolt devices |
| `kgamma` | 6.7.3-1 | extra | 288 | 382.8 KiB | Adjust your monitor gamma settings |
| `pavucontrol` | 1:6.2-1 | extra | 283 | 1.0 MiB | PulseAudio Volume Control |
| `kde-gtk-config` | 6.7.3-1 | extra | 268 | 324.2 KiB | Syncs KDE settings to GTK applications |
| `libadwaita` | 1:1.9.2-1 | extra | 260 | 5.2 MiB | Building blocks for modern adaptive GNOME applications |
| `lightdm-gtk-greeter` | 1:2.0.9-2 | extra | 244 | 344.1 KiB | GTK+ greeter for LightDM |
| `vlc` | 3.0.23_2-9 | extra | 243 | 42.0 MiB | Free and open source cross-platform multimedia player and framework |
| `ksshaskpass` | 6.7.3-1 | extra | 240 | 130.2 KiB | ssh-add helper that uses kwallet and kpassworddialog |
| `gedit` | 50.0-3 | extra | 232 | 11.6 MiB | Easy-to-use general-purpose text editor |
| `kwallet-pam` | 6.7.3-1 | extra | 226 | 27.7 KiB | KWallet PAM integration |
| `libreoffice-fresh` | 26.2.4-4 | extra | 225 | 421.4 MiB | LibreOffice branch which contains new features and program enhancements |
| `kcalc` | 26.04.3-1 | extra | 217 | 3.0 MiB | Scientific Calculator |
| `nm-connection-editor` | 1.36.0-2 | extra | 214 | 4.5 MiB | NetworkManager GUI connection editor and widgets |
| `kwrited` | 6.7.3-1 | extra | 205 | 43.9 KiB | KDE daemon listening for wall and write messages |
| `gnome-screenshot` | 1:41.0-2 | extra | 204 | 877.6 KiB | Take pictures of your screen |
| `base-devel` | 1-2 | core | 188 | 0 B | Basic tools to build Arch Linux packages |
| `union` | 6.7.3-1 | extra | 188 | 2.6 MiB | A Qt style supporting both QtQuick and QtWidgets |
| `archinstall` | 4.4-1 | extra | 182 | 7.7 MiB | Just another guided/automated Arch Linux installer with a twist |
| `base` | 3-3 | core | 181 | 0 B | Minimal package set to define a basic Arch Linux installation |
| `brltty` | 6.9.1-3 | extra | 180 | 9.5 MiB | Braille display driver for Linux/Unix |
| `openconnect` | 1:9.21-1 | extra | 176 | 4.9 MiB | Open client for Cisco AnyConnect VPN |
| `cloud-init` | 26.1-1 | extra | 175 | 8.5 MiB | Cloud instance initialization |
| `cups` | 2:2.4.19-1 | extra | 161 | 12.8 MiB | OpenPrinting CUPS - daemon package |
| `clonezilla` | 5.16.16-1 | extra | 153 | 3.4 MiB | ncurses partition and disk imaging/cloning program |
| `open-vm-tools` | 6:13.1.0-2 | extra | 152 | 4.8 MiB | The Open Virtual Machine Tools (open-vm-tools) are the open source implementation of VMware Tools |
| `vlc-plugin-x264` | 3.0.23_2-9 | extra | 138 | 91.9 KiB | Free and open source cross-platform multimedia player and framework - H264/AVC encoding |
| `vlc-plugin-upnp` | 3.0.23_2-9 | extra | 137 | 62.0 KiB | Free and open source cross-platform multimedia player and framework - UPnP plugin |
| `vlc-plugin-x265` | 3.0.23_2-9 | extra | 137 | 13.9 KiB | Free and open source cross-platform multimedia player and framework - H265/HEVC encoding |
| `xorg-server-xephyr` | 21.1.24-1 | extra | 132 | 2.4 MiB | A nested X server that runs as an X application |
| `xorg-server-xvfb` | 21.1.24-1 | extra | 131 | 2.0 MiB | Virtual framebuffer X server |
| `pptpclient` | 1.10.0-3 | core | 130 | 103.4 KiB | Client for the proprietary Microsoft Point-to-Point Tunneling Protocol, PPTP. |
| `rp-pppoe` | 4.0-6 | extra | 128 | 234.8 KiB | Roaring Penguin's Point-to-Point Protocol over Ethernet client |
| `openpgp-card-tools` | 0.11.12-1 | extra | 127 | 7.5 MiB | CLI tool to inspect, manage and use OpenPGP cards |
| `mkinitcpio-archiso` | 73-1 | extra | 126 | 47.4 KiB | Initcpio scripts used by archiso |
| `bcachefs-tools` | 3:1.38.8-2 | extra | 123 | 7.8 MiB | BCacheFS filesystem utilities |
| `pipewire-alsa` | 1:1.6.8-1 | extra | 120 | 1.2 KiB | Low-latency audio/video router and processor - ALSA configuration |
| `systemd-resolvconf` | 261.1-1 | core | 114 | 0 B | systemd resolvconf replacement (for use with systemd-resolved) |
| `xorg-server-devel` | 21.1.24-1 | extra | 114 | 1.2 MiB | Development files for the X.Org X server |
| `xorg-xdriinfo` | 1.0.8-1 | extra | 112 | 15.7 KiB | Query configuration information of DRI drivers |
| `webp-pixbuf-loader` | 0.2.7-2 | extra | 100 | 22.2 KiB | WebM GDK Pixbuf Loader library |
| `git` | 2.55.0-1 | extra | 97 | 31.3 MiB | the fast distributed version control system |
| `grub` | 2:2.14-1 | core | 97 | 41.5 MiB | GNU GRand Unified Bootloader (2) |
| `usbmuxd` | 1.1.1-4 | extra | 96 | 89.0 KiB | USB Multiplex Daemon |
| `linux-headers` | 7.1.4.arch1-1 | core | 94 | 282.2 MiB | Headers and scripts for building modules for the Linux kernel |
| `espeakup` | 0.90-4 | extra | 92 | 31.9 KiB | A light weight connector for espeak-ng and speakup |
| `tpm2-tools` | 5.7-1 | extra | 89 | 1.4 MiB | Trusted Platform Module 2.0 tools based on tpm2-tss |
| `openvpn` | 2.7.5-1 | extra | 86 | 1.8 MiB | An easy-to-use, robust and highly configurable VPN (Virtual Private Network) |
| `ufw` | 0.36.2-7 | extra | 76 | 528.1 KiB | Uncomplicated and easy to use CLI tool for managing a netfilter firewall |
| `nfs-utils` | 2.9.1-1 | core | 72 | 1.3 MiB | Support programs for Network File Systems |
| `htop` | 3.5.1-1 | extra | 69 | 404.0 KiB | Interactive process viewer |
| `wvdial` | 1.61-10 | extra | 68 | 182.9 KiB | A dialer program to connect to the Internet |
| `nvme-cli` | 2.16-2 | extra | 67 | 2.0 MiB | NVM-Express user space tooling for Linux |
| `nmap` | 7.99-3 | extra | 66 | 26.2 MiB | Utility for network discovery and security auditing |
| `tcpdump` | 4.99.6-1 | extra | 65 | 1.1 MiB | Powerful command-line packet analyzer |
| `xorg-server-xnest` | 21.1.24-1 | extra | 65 | 1.5 MiB | A nested X server that runs as an X application |
| `breeze-plymouth` | 6.7.3-1 | extra | 63 | 158.9 KiB | Plymouth theme for the Breeze visual style for the Plasma Desktop |
| `dnsmasq` | 2.93-1 | extra | 63 | 1.1 MiB | Lightweight, easy to configure DNS forwarder and DHCP server |
| `xl2tpd` | 1.3.20-1 | extra | 63 | 137.7 KiB | an open source implementation of the L2TP maintained by Xelerance Corporation |
| `jfsutils` | 1.1.15-9 | core | 62 | 952.6 KiB | JFS filesystem utilities |
| `bind` | 9.20.24-1 | extra | 59 | 7.1 MiB | A complete, highly portable implementation of the DNS protocol |
| `grml-zsh-config` | 0.19.28-1 | extra | 57 | 146.7 KiB | grml's zsh setup |
| `bluez-utils` | 5.87-2 | extra | 56 | 3.7 MiB | Development and debugging utilities for the bluetooth protocol stack |
| `virtualbox-guest-utils-nox` | 7.2.12-1 | extra | 55 | 1.9 MiB | VirtualBox Guest userspace utilities without X support |
| `broadcom-wl` | 6.30.223.271-713 | extra | 54 | 1.6 MiB | Broadcom 802.11 Linux STA wireless driver |
| `neovim` | 0.12.4-1 | extra | 54 | 30.5 MiB | Fork of Vim aiming to improve user experience, plugins, and GUIs |
| `python-pip` | 26.1.2-1 | extra | 51 | 16.8 MiB | The PyPA recommended tool for installing Python packages |
| `mc` | 4.8.33-1 | extra | 49 | 7.1 MiB | A file manager that emulates Norton Commander |
| `nbd` | 3.27.1-4 | extra | 49 | 240.3 KiB | tools for network block devices, allowing you to use remote block devices over TCP/IP |
| `reflector` | 2023-5 | extra | 44 | 158.2 KiB | A Python 3 module and script to retrieve and filter the latest Pacman mirror list. |
| `dotnet-sdk` | 10.0.10.sdk110-1 | extra | 42 | 357.9 MiB | The .NET Core SDK |
| `qemu-guest-agent` | 11.0.2-3 | extra | 38 | 1.0 MiB | QEMU Guest Agent |
| `testdisk` | 7.2-4 | extra | 37 | 1.7 MiB | Checks and undeletes partitions + PhotoRec, signature based recovery tool |
| `irssi` | 1.4.5-5 | extra | 35 | 2.1 MiB | Modular text mode IRC client with Perl scripting |
| `xorg-x11perf` | 1.7.0-1 | extra | 35 | 188.0 KiB | Simple X server performance benchmarker |
| `alsa-utils` | 1.2.16-1 | extra | 34 | 2.5 MiB | Advanced Linux Sound Architecture - Utilities |
| `tmux` | 3.7_b-1 | extra | 33 | 1.2 MiB | Terminal multiplexer |
| `fatresize` | 1.1.0-2 | extra | 31 | 23.1 KiB | A utility to resize FAT filesystems using libparted |
| `lftp` | 4.9.3-2 | extra | 31 | 2.3 MiB | Sophisticated command line based FTP client |
| `tk` | 8.6.16-1 | extra | 31 | 12.3 MiB | A windowing toolkit for use with tcl |
| `usbutils` | 019-1 | core | 30 | 377.6 KiB | A collection of USB tools to query connected USB devices |
| `xorg-xsetroot` | 1.1.4-1 | extra | 30 | 25.4 KiB | Classic X utility to set your root window background to a given pattern or color |
| `usb_modeswitch` | 2.6.2.20251207-1 | extra | 29 | 252.9 KiB | Activating switchable USB devices on Linux. |
| `dmraid` | 1.0.0.rc16.3-15 | core | 28 | 314.0 KiB | Device mapper RAID interface |
| `libusb-compat` | 0.1.9-1 | extra | 28 | 40.5 KiB | Library to enable user space application programs to communicate with USB devices |
| `xorg-xkbutils` | 1.0.7-1 | extra | 28 | 66.6 KiB | XKB utility demos |
| `xorg-xpr` | 1.2.0-2 | extra | 27 | 62.2 KiB | Print an X window dump from xwd |
| `open-iscsi` | 2.1.12-1 | extra | 26 | 1.4 MiB | iSCSI userland tools |
| `sequoia-sq` | 1.3.1-3 | extra | 26 | 20.5 MiB | Command-line frontends for Sequoia |
| `wireless-regdb` | 2026.05.30-1 | core | 26 | 21.7 KiB | Central Regulatory Domain Database |
| `xclip` | 0.13-6 | extra | 26 | 30.7 KiB | Command line interface to the X11 clipboard |
| `xorg-smproxy` | 1.0.8-1 | extra | 26 | 28.5 KiB | Allows X applications that do not support X11R6 session management to participate in an X11R6 session |
| `xorg-xhost` | 1.0.10-1 | extra | 26 | 23.8 KiB | Server access control program for X |
| `xorg-xkill` | 1.0.7-1 | extra | 26 | 16.9 KiB | Kill a client by its X resource |
| `xorg-xset` | 1.2.6-1 | extra | 26 | 40.1 KiB | User preference utility for X |
| `xorg-docs` | 1.7.3-3 | extra | 25 | 865.1 KiB | X.org documentations |
| `xorg-xcursorgen` | 1.0.9-1 | extra | 25 | 20.4 KiB | Create an X cursor file from PNG images |
| `fsarchiver` | 0.8.9-1 | extra | 24 | 255.3 KiB | Safe and flexible file-system backup and deployment tool |
| `vim` | 9.2.0804-1 | extra | 24 | 5.4 MiB | Vi Improved, a highly configurable, improved version of the vi text editor |
| `nano` | 9.1-1 | core | 23 | 2.8 MiB | Pico editor clone with enhancements |
| `lynx` | 2.9.3-1 | extra | 22 | 5.2 MiB | A text browser for the World Wide Web |
| `rsync` | 3.4.4-1 | extra | 22 | 726.2 KiB | A fast and versatile file copying tool for remote and local files |
| `squashfs-tools` | 4.7.5-1 | extra | 22 | 939.3 KiB | Tools for squashfs, a highly compressed read-only filesystem for Linux |
| `ldns` | 1.9.2-1 | core | 20 | 1.9 MiB | Fast DNS library supporting recent RFCs |
| `xorg-mkfontscale` | 1.2.4-2 | extra | 20 | 47.9 KiB | Create an index of scalable font files for X |
| `xorg-xinput` | 1.6.4-2 | extra | 18 | 60.2 KiB | Small commandline tool to configure devices |
| `ndisc6` | 1.0.8-1 | extra | 17 | 246.9 KiB | Collection of IPv6 networking utilities |
| `refind` | 0.14.2-3 | extra | 17 | 1.9 MiB | An EFI boot manager |
| `unzip` | 6.0-23 | extra | 14 | 308.1 KiB | For extracting and viewing files in .zip archives |
| `xorg-xev` | 1.2.7-1 | extra | 14 | 36.9 KiB | Print contents of X events |
| `zip` | 3.0-13 | extra | 14 | 579.1 KiB | Compressor/archiver for creating and modifying zipfiles |
| `dialog` | 1:1.3_20260107-1 | extra | 13 | 492.1 KiB | A tool to display dialog boxes from shell scripts |
| `iwd` | 3.12-1 | extra | 13 | 2.2 MiB | Internet Wireless Daemon |
| `mtools` | 1:4.0.49-1 | extra | 13 | 396.7 KiB | A collection of utilities to access MS-DOS disks |
| `os-prober` | 1.84-1 | extra | 13 | 57.6 KiB | Utility to detect other OSes on a set of drives |
| `sdparm` | 1.12-1 | core | 13 | 484.7 KiB | An utility similar to hdparm but for SCSI devices |
| `xorg-xgamma` | 1.0.8-1 | extra | 13 | 17.9 KiB | Alter a monitor's gamma correction |
| `xorg-xvinfo` | 1.1.6-1 | extra | 13 | 20.0 KiB | Prints out the capabilities of any video adaptors associated with the display that are accessible through the X-Video extension |
| `udftools` | 2.3-3 | extra | 12 | 402.0 KiB | Linux tools for UDF filesystems and DVD/CD-R(W) drives |
| `xorg-xkbevd` | 1.1.6-1 | extra | 12 | 41.0 KiB | XKB event daemon |
| `xorg-xwd` | 1.0.10-1 | extra | 12 | 34.4 KiB | X Window System image dumping utility |
| `linux-firmware` | 20260622-1 | core | 11 | 0 B | Firmware files for Linux - Default set |
| `xorg-xbacklight` | 1.2.4-1 | extra | 11 | 20.4 KiB | RandR-based backlight control application |
| `xorg-xcmsdb` | 1.0.7-1 | extra | 11 | 34.0 KiB | Device Color Characterization utility for X Color Management System |
| `xorg-xrefresh` | 1.1.1-1 | extra | 11 | 17.9 KiB | Refresh all or part of an X screen |
| `xorg-xwud` | 1.0.8-1 | extra | 11 | 37.6 KiB | X Window System image undumping utility |
| `xorg-xlsatoms` | 1.1.5-1 | extra | 10 | 16.6 KiB | List interned atoms defined on server |
| `xorg-xlsclients` | 1.1.6-1 | extra | 10 | 21.6 KiB | List client applications running on a display |
| `xorg-xwininfo` | 1.1.6-2 | extra | 10 | 48.5 KiB | Command-line utility to print information about windows on an X server |
| `foot-terminfo` | 1.27.0-1 | extra | 8 | 9.1 KiB | Extra non-standard terminfo files for foot, a Wayland terminal emulator |
| `kitty-terminfo` | 0.48.0-1 | extra | 8 | 3.6 KiB | Terminfo for kitty, an OpenGL-based terminal emulator |
| `ddrescue` | 1.30-2 | extra | 7 | 288.0 KiB | GNU data recovery tool |
| `xorg-iceauth` | 1.0.11-1 | extra | 7 | 37.0 KiB | ICE authority file utility |
| `ethtool` | 1:7.1-1 | extra | 6 | 966.6 KiB | Utility for controlling network drivers and hardware |
| `fastfetch` | 2.66.0-1 | extra | 6 | 1.9 MiB | A feature-rich and performance oriented neofetch like system information tool |
| `lsscsi` | 0.32-2 | extra | 6 | 97.1 KiB | A tool that lists devices connected via SCSI and its transports |
| `b43-fwcutter` | 020-1 | core | 5 | 57.9 KiB | firmware extractor for the b43 kernel module |
| `darkhttpd` | 1.17-1 | extra | 5 | 51.7 KiB | A small and secure static webserver |
| `exfatprogs` | 1.4.2-1 | extra | 5 | 347.1 KiB | exFAT filesystem userspace utilities for the Linux Kernel exfat driver |
| `gpart` | 0.3-6 | extra | 5 | 62.7 KiB | Partition table rescue/guessing tool |
| `hdparm` | 9.65-3 | core | 5 | 182.4 KiB | A shell utility for manipulating Linux IDE drive/driver parameters |
| `hyperv` | 7.1.3-1 | extra | 5 | 221.7 KiB | Hyper-V tools |
| `linux-atm` | 2.5.2-9 | extra | 5 | 1.2 MiB | Drivers and tools to support ATM networking under Linux. |
| `mkinitcpio-nfs-utils` | 0.3-8 | core | 5 | 62.6 KiB | ipconfig and nfsmount tools for NFS root support in mkinitcpio |
| `mmc-utils` | 1.0-1 | extra | 5 | 112.9 KiB | Userspace tools for MMC/SD devices |
| `pv` | 1.11.0-1 | extra | 5 | 367.3 KiB | A terminal-based tool for monitoring the progress of data through a pipeline |
| `sg3_utils` | 1.48-1 | extra | 5 | 3.2 MiB | Generic SCSI utilities |
| `xf86-video-vesa` | 2.6.0-3 | extra | 5 | 33.5 KiB | X.org vesa video driver |
| `xorg-bdftopcf` | 1.1.2-1 | extra | 5 | 45.1 KiB | Convert X font from Bitmap Distribution Format to Portable Compiled Format |
| `xorg-font-util` | 1.4.2-1 | extra | 5 | 228.7 KiB | X.Org font utilities |
| `xorg-sessreg` | 1.1.4-1 | extra | 5 | 18.0 KiB | Register X sessions in system utmp/utmpx databases |
| `linux-firmware-marvell` | 20260622-1 | core | 1 | 79.4 MiB | Firmware files for Linux - Firmware for Marvell devices |
| `xorg-fonts-100dpi` | 1.0.4-3 | extra | 1 | 12.2 MiB | X.org 100dpi fonts |
| `xorg-fonts-75dpi` | 1.0.4-2 | extra | 1 | 10.6 MiB | X.org 75dpi fonts |
| `amd-ucode` | 20260622-1 | core | 0 | 602.9 KiB | Microcode update image for AMD CPUs |
| `breeze-gtk` | 6.7.3-1 | extra | 0 | 1.2 MiB | Breeze widget theme for GTK 2 and 3 |
| `edk2-shell` | 202605-1 | extra | 0 | 6.7 MiB | EDK2 UEFI Shell |
| `go` | 2:1.26.5-1 | extra | 0 | 215.7 MiB | Core compiler tools for the Go programming language |
| `intel-ucode` | 20260512-1 | extra | 0 | 30.7 MiB | Microcode update files for Intel CPUs |
| `livecd-sounds` | 1.0-3 | extra | 0 | 306.3 KiB | Sound files for accessibility features in a boot medium |
| `man-pages` | 6.18-1 | core | 0 | 5.6 MiB | Linux man pages |
| `memtest86+` | 7.20-2 | extra | 0 | 153.5 KiB | Advanced memory diagnostic tool legacy BIOS version |
| `memtest86+-efi` | 7.20-2 | extra | 0 | 154.9 KiB | Advanced memory diagnostic tool EFI version |
| `oxygen-sounds` | 6.7.3-1 | extra | 0 | 2.1 MiB | The Oxygen Sound Theme |
| `plasma-workspace-wallpapers` | 6.7.3-1 | extra | 0 | 255.1 MiB | Additional wallpapers for the Plasma Workspace |
| `rxvt-unicode-terminfo` | 9.31-9 | extra | 0 | 4.9 KiB | Terminfo files for urxvt |
| `sof-firmware` | 2025.12.2-1 | extra | 0 | 42.8 MiB | Sound Open Firmware |
| `syslinux` | 6.04.pre3.r3.g05ac953c-4 | core | 0 | 4.3 MiB | Collection of boot loaders that boot from FAT, ext2/3/4 and btrfs filesystems, from CDs and via PXE |
| `terminus-font` | 4.49.1-8 | extra | 0 | 3.0 MiB | Monospace bitmap font (for X11 and console) |
| `wireless_tools` | 30.pre9-5 | extra | 0 | 346.3 KiB | Tools allowing to manipulate the Wireless Extensions |
| `xorg-server-src` | 21.1.24-1 | extra | 0 | 21.3 MiB | Source files of the X.Org X server |

---

## 5. Subsystems -- what the software actually is

The package set grouped by real function, with concrete technical capabilities and real versions. (Grouping is by role in the OS, not by string-matching names.)

### Kernel, firmware & boot

The absolute foundation of the OS. The kernel is `linux` (mainline Linux, Arch patchset), shipped with matching `linux-headers` for out-of-tree module builds and the full `linux-firmware` set (plus the Marvell split-out package) for network, GPU and platform device firmware. CPU microcode is loaded early from `amd-ucode` and `intel-ucode`; `sof-firmware` provides DSP firmware for modern Intel/AMD audio. The initramfs is built by `mkinitcpio` with the `mkinitcpio-archiso` hooks that make the live medium boot, and `booster` is present as an alternative generator. The medium boots on both firmware types: BIOS via `syslinux`, UEFI via `grub`, `refind`, `efibootmgr` and the bundled `edk2-shell`; `memtest86+`/`memtest86+-efi` provide RAM diagnostics and `os-prober` detects already-installed operating systems for dual-boot menus.

| Package | Version | Capability |
|---|---|---|
| `linux` | 7.1.4.arch1-1 | The Linux kernel and loadable modules |
| `linux-headers` | 7.1.4.arch1-1 | Kernel headers/build scripts for out-of-tree modules |
| `linux-firmware` | 20260622-1 | Device firmware blobs (Wi-Fi, GPU, etc.) |
| `linux-firmware-marvell` | 20260622-1 | Firmware for Marvell devices |
| `amd-ucode` | 20260622-1 | Early microcode updates for AMD CPUs |
| `intel-ucode` | 20260512-1 | Early microcode updates for Intel CPUs |
| `sof-firmware` | 2025.12.2-1 | Sound Open Firmware for modern audio DSPs |
| `mkinitcpio` | 41-4 | Modular initramfs image generator |
| `mkinitcpio-archiso` | 73-1 | archiso hooks that make the live image boot |
| `booster` | 0.13-1 | Alternative fast initramfs generator |
| `grub` | 2:2.14-1 | GRUB2 bootloader (BIOS + UEFI) |
| `syslinux` | 6.04.pre3.r3.g05ac953c-4 | BIOS boot loaders (FAT/ext/btrfs/PXE/CD) |
| `refind` | 0.14.2-3 | Graphical EFI boot manager |
| `efibootmgr` | 18-4 | Edit UEFI boot entries from userspace |
| `edk2-shell` | 202605-1 | EDK2 UEFI interactive shell |
| `memtest86+` / `memtest86+-efi` | 7.20-2 | RAM diagnostic (BIOS and EFI builds) |
| `os-prober` | 1.84-1 | Detect other installed OSes for boot menus |

### Base system & shell

The minimal Unix userland the desktop and installer sit on. `systemd` is the init system, service manager and journal; `base`/`base-devel` pull in the standard GNU coreutils/toolchain set, and `sudo` handles privilege escalation. Two shells ship: `bash` (the default) and `zsh` with the polished `grml-zsh-config`. Terminal editors (`nano`, `vim`), pagers (`less`), the manual system (`man-db` + `man-pages`), a terminal file manager (`mc`), a process monitor (`htop`), terminal multiplexers (`tmux`, `screen`), and staples like `rsync`, `diffutils`, `bc` and `pv` round out a self-sufficient command line.

| Package | Version | Capability |
|---|---|---|
| `systemd` | 261.1-1 | init, service manager, journald, logind |
| `bash` | 5.3.15-1 | Default POSIX shell |
| `zsh` | 5.9.2-1 | Advanced interactive shell |
| `grml-zsh-config` | 0.19.28-1 | Batteries-included zsh setup |
| `sudo` | 1.9.17.p2-6 | Privilege escalation |
| `vim` / `nano` | 9.2.0804-1 / 9.1-1 | Terminal text editors |
| `less` | 1:704-1 | Terminal pager |
| `man-db` / `man-pages` | 2.13.1-2 / 6.18-1 | Manual page reader + Linux man pages |
| `mc` | 4.8.33-1 | Norton-Commander-style file manager |
| `htop` | 3.5.1-1 | Interactive process viewer |
| `tmux` / `screen` | 3.7_b-1 / 5.0.1-3 | Terminal multiplexers |
| `rsync` | 3.4.4-1 | Fast local/remote file sync |
| `bc` / `pv` / `diffutils` | 1.08.2-1 / 1.11.0-1 / 3.12-2 | Calculator, pipe meter, patch tools |
| `xdg-utils` | 1.2.1-2 | Desktop integration helpers |

### KDE Plasma desktop

The graphical environment the ISO boots into: KDE Plasma with KDE Gear applications. `plasma-desktop`/`plasma-workspace` provide the shell, panel and session; `kwin` is the Wayland compositor with `kwin-x11` as the X11 window manager; `kdecoration`/`aurorae` handle window decorations. Session services include screen management (`kscreen`), power management (`powerdevil`), the lock screen (`kscreenlocker`), global shortcuts (`kglobalacceld`), activity tracking (`kactivitymanagerd`), the KWallet PAM bridge (`kwallet-pam`) and the polkit authentication agent (`polkit-kde-agent`). Look and feel is Breeze/Oxygen. Bundled KDE apps: `konsole` (terminal), `dolphin` (file manager), `gwenview` (image viewer), `spectacle` (screenshots), `kcalc`, `kclock`, `kinfocenter`, `plasma-systemmonitor`, `discover` (software center), plus `krdp` for an RDP server and `xdg-desktop-portal-kde` for sandboxed-app portals.

| Package | Version | Capability |
|---|---|---|
| `plasma-desktop` | 6.7.3-1 | KDE Plasma desktop shell |
| `plasma-workspace` | 6.7.3-1 | Panel, session, workspace services |
| `kwin` | 6.7.3-1 | Wayland compositor |
| `kwin-x11` | 6.7.3-1 | X11 window manager |
| `systemsettings` | 6.7.3-1 | Unified settings application |
| `kscreen` / `powerdevil` | 6.7.3-1 | Display + power management |
| `kscreenlocker` | 6.7.3-1 | Secure lock screen |
| `polkit-kde-agent` | 6.7.3-1 | polkit authentication UI |
| `breeze` / `oxygen` | 6.7.3-1 | Visual styles / themes |
| `konsole` | 26.04.3-1 | Terminal emulator |
| `dolphin` | 26.04.3-1 | File manager |
| `gwenview` / `spectacle` | 26.04.3-1 / 1:6.7.3-1 | Image viewer / screenshots |
| `kcalc` / `kclock` | 26.04.3-1 | Calculator / clock |
| `plasma-systemmonitor` | 6.7.3-1 | System resource monitor |
| `discover` | 6.7.3-1 | Graphical package/Flatpak manager |
| `krdp` | 6.7.3-1 | Built-in RDP server |
| `xdg-desktop-portal-kde` | 6.7.3-1 | Portal backend for sandboxed apps |

### Display server, graphics & login

The graphics stack under the desktop. `mesa` supplies the open-source OpenGL/Vulkan drivers and `libglvnd` provides vendor-neutral GL dispatch. A full X.Org server (`xorg-server`) is present alongside `xorg-xwayland`, which runs legacy X clients under the Wayland session; the `xorg` group also brings the complete set of X utilities (`xrandr`, `xinput`, `setxkbmap`, etc.) and the generic `xf86-video-vesa` fallback driver. Login is handled by `lightdm` with the `lightdm-gtk-greeter`, while `plasma-login-manager` and the `sddm-kcm` configuration module are also present for Plasma's own login manager.

| Package | Version | Capability |
|---|---|---|
| `mesa` | 1:26.1.5-1 | Open-source OpenGL/Vulkan drivers |
| `libglvnd` | 1.7.0-3 | GL vendor-neutral dispatch |
| `xorg-server` | 21.1.24-1 | X.Org X11 display server |
| `xorg-xwayland` | 24.1.13-1 | Run X clients under Wayland |
| `xorg-xrandr` / `xorg-xinput` | 1.5.4-1 / 1.6.4-2 | Display + input configuration |
| `xf86-video-vesa` | 2.6.0-3 | Generic VESA fallback video driver |
| `lightdm` | 1:1.32.0-9 | Display/login manager |
| `lightdm-gtk-greeter` | 1:2.0.9-2 | GTK login greeter |
| `plasma-login-manager` | 6.7.3-1 | Plasma's login manager |
| `sddm-kcm` | 6.7.3-1 | SDDM configuration module |

### Audio (PipeWire)

Audio is served by PipeWire, the low-latency media graph that replaces PulseAudio and JACK. `pipewire-pulse` provides the PulseAudio-compatible daemon and `pipewire-alsa` the ALSA routing config, so both PulseAudio and ALSA clients play through PipeWire transparently. `alsa-utils` gives kernel-level mixer/control tools, while `pavucontrol` and the `plasma-pa` applet provide graphical volume and device control. `livecd-sounds` supplies accessibility sound cues on the live medium.

| Package | Version | Capability |
|---|---|---|
| `pipewire` | 1:1.6.8-1 | Low-latency audio/video graph server |
| `pipewire-pulse` | 1:1.6.8-1 | PulseAudio-compatible daemon |
| `pipewire-alsa` | 1:1.6.8-1 | ALSA client routing into PipeWire |
| `alsa-utils` | 1.2.16-1 | Kernel ALSA mixer/control utilities |
| `pavucontrol` | 1:6.2-1 | Graphical volume control |
| `plasma-pa` | 6.7.3-1 | Plasma volume applet |

### Networking & VPN

A broad connectivity and diagnostics stack. `networkmanager` is the connection manager, driven from the desktop by `plasma-nm` or the `nm-connection-editor` GUI. Wireless is backed by `wpa_supplicant`, the newer `iwd` daemon, and the `iw`/`wireless_tools` CLIs. Remote access and tunnelling: `openssh`, plus VPN clients `openvpn`, `openconnect` (Cisco AnyConnect) and `vpnc`; dial-up/DSL/mobile paths via `ppp`, `pptpclient`, `rp-pppoe`, `xl2tpd`, `wvdial` and `modemmanager`. DNS tooling includes `bind` utilities, the `dnsmasq` forwarder/DHCP server and the `ldns` library. Diagnostics: `tcpdump` (packet capture), `nmap` (scanning), `ethtool`, `ndisc6` (IPv6), and transfer tools `curl` and `lftp`.

| Package | Version | Capability |
|---|---|---|
| `networkmanager` | 1.56.1-2 | Connection manager |
| `plasma-nm` | 6.7.3-1 | Plasma network applet |
| `iwd` / `wpa_supplicant` | 3.12-1 / 2:2.11-5 | Wi-Fi daemons |
| `iw` / `wireless_tools` | 6.17-1 / 30.pre9-5 | Wireless CLI configuration |
| `openssh` | 10.4p1-2 | SSH client/server |
| `openvpn` / `openconnect` / `vpnc` | 2.7.5-1 / 1:9.21-1 / 1:0.5.3.r557.r241-1 | VPN clients |
| `modemmanager` / `ppp` / `pptpclient` | 1.24.2-1 / 2.5.3-1 / 1.10.0-3 | Mobile/dial-up connectivity |
| `bind` / `dnsmasq` / `ldns` | 9.20.24-1 / 2.93-1 / 1.9.2-1 | DNS server/forwarder/library |
| `tcpdump` / `nmap` / `ethtool` | 4.99.6-1 / 7.99-3 / 1:7.1-1 | Capture, scan, NIC control |
| `curl` / `lftp` | 8.21.0-1 / 4.9.3-2 | HTTP(S)/FTP transfer clients |

### Storage, filesystems & installation

This is the core rescue-and-install mission of the medium. Two installers ship: `archinstall` (guided) and `arch-install-scripts` (`pacstrap`/`arch-chroot`). Partitioning and block-layer: `parted`, `gptfdisk`, `cryptsetup` (LUKS/dm-crypt), `lvm2`, `mdadm` (software RAID) and `dmraid`. Filesystem userspace tools cover ext2/3/4 (`e2fsprogs`), Btrfs, XFS, F2FS, exFAT, FAT (`dosfstools`), NTFS (`ntfs-3g`), NILFS, JFS and bcachefs, plus `nfs-utils`, `open-iscsi` and `nbd` for networked storage and `squashfs-tools` for the live image format. Imaging, recovery and health: `clonezilla`, `partclone`, `fsarchiver`, `testdisk`, `ddrescue`, `smartmontools` and `nvme-cli`.

| Package | Version | Capability |
|---|---|---|
| `archinstall` | 4.4-1 | Guided Arch installer (TUI) |
| `arch-install-scripts` | 31-1 | `pacstrap` / `arch-chroot` / `genfstab` |
| `parted` / `gptfdisk` | 3.7-1 / 1.0.10-2 | MBR/GPT partitioning |
| `cryptsetup` | 2.8.6-1 | LUKS/dm-crypt full-disk encryption |
| `lvm2` / `mdadm` / `dmraid` | 2.03.41-1 / 4.6-2 / 1.0.0.rc16.3-15 | LVM, software + BIOS RAID |
| `btrfs-progs` / `xfsprogs` / `e2fsprogs` | 7.1-1 / 7.0.1-1 / 1.47.4-1 | Btrfs, XFS, ext2/3/4 tools |
| `f2fs-tools` / `exfatprogs` / `ntfs-3g` | 1.16.0-3 / 1.4.2-1 / 2026.7.7-1 | F2FS, exFAT, NTFS |
| `nilfs-utils` / `jfsutils` / `bcachefs-tools` | 2.3.0-1 / 1.1.15-9 / 3:1.38.8-2 | NILFS, JFS, bcachefs |
| `nfs-utils` / `open-iscsi` / `nbd` | 2.9.1-1 / 2.1.12-1 / 3.27.1-4 | Network filesystems and block devices |
| `squashfs-tools` | 4.7.5-1 | SquashFS (live image) tools |
| `clonezilla` / `partclone` / `fsarchiver` | 5.16.16-1 / 0.3.47-3 / 0.8.9-1 | Disk imaging/cloning/backup |
| `testdisk` / `ddrescue` | 7.2-4 / 1.30-2 | Partition + data recovery |
| `smartmontools` / `nvme-cli` | 7.5-1 / 2.16-2 | SMART monitoring, NVMe control |

### Security, firewall & crypto hardware

Host firewalling is provided by `ufw` (a netfilter front end) with the `plasma-firewall` control panel. Trusted-computing and hardware-token support: `tpm2-tss` (the TSS2 stack) and `tpm2-tools` for TPM 2.0; `libfido2` for FIDO2/U2F security keys; `pcsclite` smartcard middleware; and `openpgp-card-tools` for OpenPGP smartcards. `sequoia-sq` is a modern OpenPGP CLI. On the desktop, `plasma-vault` creates encrypted vaults and `kwallet-pam` unlocks the KDE wallet at login.

| Package | Version | Capability |
|---|---|---|
| `ufw` | 0.36.2-7 | netfilter firewall front end |
| `plasma-firewall` | 6.7.3-1 | Firewall control panel |
| `tpm2-tss` / `tpm2-tools` | 4.1.3-1 / 5.7-1 | TPM 2.0 software stack + tools |
| `libfido2` | 1.17.0-1 | FIDO2 / U2F security-key support |
| `pcsclite` | 2.5.1-1 | PC/SC smartcard middleware |
| `sequoia-sq` | 1.3.1-3 | OpenPGP command-line tool |
| `openpgp-card-tools` | 0.11.12-1 | Manage OpenPGP smartcards |
| `plasma-vault` | 6.7.3-1 | Encrypted vaults on the desktop |
| `kwallet-pam` | 6.7.3-1 | Unlock KWallet at login (PAM) |

### Developer toolchain & runtimes

The OS ships end-user development runtimes out of the box. `python` with `python-pip`; `go`; and a complete .NET stack (`dotnet-sdk`, `dotnet-runtime`, `dotnet-host`). `git` provides version control, `neovim` a modern editor, `jq` JSON processing, and `tk` the Tcl/Tk GUI toolkit (which also backs Python's tkinter).

| Package | Version | Capability |
|---|---|---|
| `python` | 3.14.6-1 | CPython interpreter |
| `python-pip` | 26.1.2-1 | Python package installer |
| `go` | 2:1.26.5-1 | Go compiler and toolchain |
| `dotnet-sdk` | 10.0.10.sdk110-1 | .NET SDK (build + CLI) |
| `dotnet-runtime` | 10.0.10.sdk110-1 | .NET runtime |
| `git` | 2.55.0-1 | Distributed version control |
| `neovim` | 0.12.4-1 | Extensible modal editor |
| `jq` | 1.8.2-1 | Command-line JSON processor |
| `tk` | 8.6.16-1 | Tcl/Tk GUI toolkit (backs tkinter) |

### Multimedia & office

Media playback centres on `vlc` with codec plugins for FFmpeg decode and x264/x265 (H.264/H.265) encode, plus UPnP streaming. `libreoffice-fresh` is the full office suite (documents, spreadsheets, presentations). `kamoso` records from webcams and `gnome-screenshot` captures the screen.

| Package | Version | Capability |
|---|---|---|
| `vlc` | 3.0.23_2-9 | Multimedia player and framework |
| `vlc-plugin-ffmpeg` | 3.0.23_2-9 | FFmpeg-based decode for VLC |
| `vlc-plugin-x264` / `vlc-plugin-x265` | 3.0.23_2-9 | H.264 / H.265 encoding |
| `vlc-plugin-upnp` | 3.0.23_2-9 | UPnP/DLNA media browsing |
| `libreoffice-fresh` | 26.2.4-4 | Full office productivity suite |
| `kamoso` | 26.04.3-1 | Webcam capture/recording |
| `gnome-screenshot` | 1:41.0-2 | Screenshot capture |

### Hardware, virtualization & peripherals

Bluetooth is provided by the `bluez` stack with the `bluedevil` KDE integration; printing by `cups` with the `print-manager` front end. The medium runs well as a guest under every major hypervisor: `open-vm-tools` (VMware), `qemu-guest-agent` (QEMU/KVM), `virtualbox-guest-utils-nox` (VirtualBox) and `hyperv` (Microsoft Hyper-V). Hardware inspection and control: `usbutils`, `usb_modeswitch`, `dmidecode` (DMI/SMBIOS), and Thunderbolt via `bolt` + `plasma-thunderbolt`. Accessibility is served by `brltty` (braille displays) and `espeakup` (console speech).

| Package | Version | Capability |
|---|---|---|
| `bluez` / `bluez-utils` | 5.87-2 | Bluetooth stack + tools |
| `bluedevil` | 1:6.7.3-1 | Bluetooth integration in Plasma |
| `cups` / `print-manager` | 2:2.4.19-1 / 1:6.7.3-1 | Printing daemon + GUI |
| `open-vm-tools` | 6:13.1.0-2 | VMware guest integration |
| `qemu-guest-agent` | 11.0.2-3 | QEMU/KVM guest agent |
| `virtualbox-guest-utils-nox` | 7.2.12-1 | VirtualBox guest utilities |
| `hyperv` | 7.1.3-1 | Hyper-V guest tools |
| `usbutils` / `usb_modeswitch` | 019-1 / 2.6.2.20251207-1 | USB inspection + mode switching |
| `dmidecode` | 3.7-1 | DMI/SMBIOS hardware table dump |
| `bolt` / `plasma-thunderbolt` | 0.9.11-1 / 6.7.3-1 | Thunderbolt device management |
| `brltty` / `espeakup` | 6.9.1-3 / 0.90-4 | Braille + speech accessibility |

---

## 6. Explicit manifest tier

The **source of truth** is `libraries/data/packages.x86_64`. These are the packages the ISO explicitly requests; everything else in the graph is pulled in as a dependency. Below, each manifest entry is mapped to the real package it resolves to, with its tier in the resolved graph.

| # | Manifest entry | Resolves to | Tier | Version |
|---:|---|---|---|---|
| 1 | `alsa-utils` | `alsa-utils` | top/leaf | 1.2.16-1 |
| 2 | `amd-ucode` | `amd-ucode` | top/leaf, base/sink | 20260622-1 |
| 3 | `arch-install-scripts` | `arch-install-scripts` | interior | 31-1 |
| 4 | `archinstall` | `archinstall` | top/leaf | 4.4-1 |
| 5 | `b43-fwcutter` | `b43-fwcutter` | top/leaf | 020-1 |
| 6 | `base` | `base` | top/leaf | 3-3 |
| 7 | `bcachefs-tools` | `bcachefs-tools` | top/leaf | 3:1.38.8-2 |
| 8 | `bind` | `bind` | top/leaf | 9.20.24-1 |
| 9 | `bolt` | `bolt` | interior | 0.9.11-1 |
| 10 | `brltty` | `brltty` | top/leaf | 6.9.1-3 |
| 11 | `broadcom-wl` | `broadcom-wl` | top/leaf | 6.30.223.271-713 |
| 12 | `btrfs-progs` | `btrfs-progs` | interior | 7.1-1 |
| 13 | `clonezilla` | `clonezilla` | top/leaf | 5.16.16-1 |
| 14 | `cloud-init` | `cloud-init` | top/leaf | 26.1-1 |
| 15 | `cryptsetup` | `cryptsetup` | interior | 2.8.6-1 |
| 16 | `darkhttpd` | `darkhttpd` | top/leaf | 1.17-1 |
| 17 | `ddrescue` | `ddrescue` | top/leaf | 1.30-2 |
| 18 | `diffutils` | `diffutils` | interior | 3.12-2 |
| 19 | `dmidecode` | `dmidecode` | interior | 3.7-1 |
| 20 | `dmraid` | `dmraid` | top/leaf | 1.0.0.rc16.3-15 |
| 21 | `dnsmasq` | `dnsmasq` | top/leaf | 2.93-1 |
| 22 | `dosfstools` | `dosfstools` | interior | 4.2-5 |
| 23 | `e2fsprogs` | `e2fsprogs` | interior | 1.47.4-1 |
| 24 | `edk2-shell` | `edk2-shell` | top/leaf, base/sink | 202605-1 |
| 25 | `efibootmgr` | `efibootmgr` | interior | 18-4 |
| 26 | `espeakup` | `espeakup` | top/leaf | 0.90-4 |
| 27 | `ethtool` | `ethtool` | top/leaf | 1:7.1-1 |
| 28 | `exfatprogs` | `exfatprogs` | top/leaf | 1.4.2-1 |
| 29 | `f2fs-tools` | `f2fs-tools` | interior | 1.16.0-3 |
| 30 | `fatresize` | `fatresize` | top/leaf | 1.1.0-2 |
| 31 | `foot-terminfo` | `foot-terminfo` | top/leaf | 1.27.0-1 |
| 32 | `fsarchiver` | `fsarchiver` | top/leaf | 0.8.9-1 |
| 33 | `gpart` | `gpart` | top/leaf | 0.3-6 |
| 34 | `gpm` | `gpm` | interior | 1.20.7.r38.ge82d1a6-6 |
| 35 | `gptfdisk` | `gptfdisk` | interior | 1.0.10-2 |
| 36 | `grml-zsh-config` | `grml-zsh-config` | top/leaf | 0.19.28-1 |
| 37 | `grub` | `grub` | top/leaf | 2:2.14-1 |
| 38 | `hdparm` | `hdparm` | top/leaf | 9.65-3 |
| 39 | `hyperv` | `hyperv` | top/leaf | 7.1.3-1 |
| 40 | `intel-ucode` | `intel-ucode` | top/leaf, base/sink | 20260512-1 |
| 41 | `irssi` | `irssi` | top/leaf | 1.4.5-5 |
| 42 | `iw` | `iw` | interior | 6.17-1 |
| 43 | `iwd` | `iwd` | top/leaf | 3.12-1 |
| 44 | `jfsutils` | `jfsutils` | top/leaf | 1.1.15-9 |
| 45 | `kitty-terminfo` | `kitty-terminfo` | top/leaf | 0.48.0-1 |
| 46 | `ldns` | `ldns` | top/leaf | 1.9.2-1 |
| 47 | `less` | `less` | interior | 1:704-1 |
| 48 | `lftp` | `lftp` | top/leaf | 4.9.3-2 |
| 49 | `libfido2` | `libfido2` | interior | 1.17.0-1 |
| 50 | `libusb-compat` | `libusb-compat` | top/leaf | 0.1.9-1 |
| 51 | `linux` | `linux` | interior | 7.1.4.arch1-1 |
| 52 | `linux-atm` | `linux-atm` | top/leaf | 2.5.2-9 |
| 53 | `linux-firmware` | `linux-firmware` | top/leaf | 20260622-1 |
| 54 | `linux-firmware-marvell` | `linux-firmware-marvell` | top/leaf | 20260622-1 |
| 55 | `livecd-sounds` | `livecd-sounds` | top/leaf, base/sink | 1.0-3 |
| 56 | `lsscsi` | `lsscsi` | top/leaf | 0.32-2 |
| 57 | `lvm2` | `lvm2` | interior | 2.03.41-1 |
| 58 | `lynx` | `lynx` | top/leaf | 2.9.3-1 |
| 59 | `man-db` | `man-db` | interior | 2.13.1-2 |
| 60 | `man-pages` | `man-pages` | top/leaf, base/sink | 6.18-1 |
| 61 | `mc` | `mc` | top/leaf | 4.8.33-1 |
| 62 | `mdadm` | `mdadm` | interior | 4.6-2 |
| 63 | `memtest86+` | `memtest86+` | top/leaf, base/sink | 7.20-2 |
| 64 | `memtest86+-efi` | `memtest86+-efi` | top/leaf, base/sink | 7.20-2 |
| 65 | `mkinitcpio` | `mkinitcpio` | interior | 41-4 |
| 66 | `mkinitcpio-archiso` | `mkinitcpio-archiso` | top/leaf | 73-1 |
| 67 | `mkinitcpio-nfs-utils` | `mkinitcpio-nfs-utils` | top/leaf | 0.3-8 |
| 68 | `mmc-utils` | `mmc-utils` | top/leaf | 1.0-1 |
| 69 | `modemmanager` | `modemmanager` | interior | 1.24.2-1 |
| 70 | `mtools` | `mtools` | top/leaf | 1:4.0.49-1 |
| 71 | `nano` | `nano` | top/leaf | 9.1-1 |
| 72 | `nbd` | `nbd` | top/leaf | 3.27.1-4 |
| 73 | `ndisc6` | `ndisc6` | top/leaf | 1.0.8-1 |
| 74 | `nfs-utils` | `nfs-utils` | top/leaf | 2.9.1-1 |
| 75 | `nilfs-utils` | `nilfs-utils` | interior | 2.3.0-1 |
| 76 | `nmap` | `nmap` | top/leaf | 7.99-3 |
| 77 | `ntfs-3g` | `ntfs-3g` | interior | 2026.7.7-1 |
| 78 | `nvme-cli` | `nvme-cli` | top/leaf | 2.16-2 |
| 79 | `open-iscsi` | `open-iscsi` | top/leaf | 2.1.12-1 |
| 80 | `open-vm-tools` | `open-vm-tools` | top/leaf | 6:13.1.0-2 |
| 81 | `openconnect` | `openconnect` | top/leaf | 1:9.21-1 |
| 82 | `openpgp-card-tools` | `openpgp-card-tools` | top/leaf | 0.11.12-1 |
| 83 | `openssh` | `openssh` | interior | 10.4p1-2 |
| 84 | `openvpn` | `openvpn` | top/leaf | 2.7.5-1 |
| 85 | `partclone` | `partclone` | interior | 0.3.47-3 |
| 86 | `parted` | `parted` | interior | 3.7-1 |
| 87 | `partimage` | `partimage` | interior | 0.6.9-16 |
| 88 | `pcsclite` | `pcsclite` | interior | 2.5.1-1 |
| 89 | `ppp` | `ppp` | interior | 2.5.3-1 |
| 90 | `pptpclient` | `pptpclient` | top/leaf | 1.10.0-3 |
| 91 | `pv` | `pv` | top/leaf | 1.11.0-1 |
| 92 | `qemu-guest-agent` | `qemu-guest-agent` | top/leaf | 11.0.2-3 |
| 93 | `refind` | `refind` | top/leaf | 0.14.2-3 |
| 94 | `reflector` | `reflector` | top/leaf | 2023-5 |
| 95 | `rsync` | `rsync` | top/leaf | 3.4.4-1 |
| 96 | `rxvt-unicode-terminfo` | `rxvt-unicode-terminfo` | top/leaf, base/sink | 9.31-9 |
| 97 | `screen` | `screen` | interior | 5.0.1-3 |
| 98 | `sdparm` | `sdparm` | top/leaf | 1.12-1 |
| 99 | `sequoia-sq` | `sequoia-sq` | top/leaf | 1.3.1-3 |
| 100 | `sg3_utils` | `sg3_utils` | top/leaf | 1.48-1 |
| 101 | `smartmontools` | `smartmontools` | interior | 7.5-1 |
| 102 | `sof-firmware` | `sof-firmware` | top/leaf, base/sink | 2025.12.2-1 |
| 103 | `squashfs-tools` | `squashfs-tools` | top/leaf | 4.7.5-1 |
| 104 | `sudo` | `sudo` | interior | 1.9.17.p2-6 |
| 105 | `syslinux` | `syslinux` | top/leaf, base/sink | 6.04.pre3.r3.g05ac953c-4 |
| 106 | `systemd-resolvconf` | `systemd-resolvconf` | top/leaf | 261.1-1 |
| 107 | `tcpdump` | `tcpdump` | top/leaf | 4.99.6-1 |
| 108 | `terminus-font` | `terminus-font` | top/leaf, base/sink | 4.49.1-8 |
| 109 | `testdisk` | `testdisk` | top/leaf | 7.2-4 |
| 110 | `tmux` | `tmux` | top/leaf | 3.7_b-1 |
| 111 | `tpm2-tools` | `tpm2-tools` | top/leaf | 5.7-1 |
| 112 | `tpm2-tss` | `tpm2-tss` | interior | 4.1.3-1 |
| 113 | `udftools` | `udftools` | top/leaf | 2.3-3 |
| 114 | `usb_modeswitch` | `usb_modeswitch` | top/leaf | 2.6.2.20251207-1 |
| 115 | `usbmuxd` | `usbmuxd` | top/leaf | 1.1.1-4 |
| 116 | `usbutils` | `usbutils` | top/leaf | 019-1 |
| 117 | `vim` | `vim` | top/leaf | 9.2.0804-1 |
| 118 | `virtualbox-guest-utils-nox` | `virtualbox-guest-utils-nox` | top/leaf | 7.2.12-1 |
| 119 | `vpnc` | `vpnc` | interior | 1:0.5.3.r557.r241-1 |
| 120 | `wireless-regdb` | `wireless-regdb` | top/leaf | 2026.05.30-1 |
| 121 | `wireless_tools` | `wireless_tools` | top/leaf, base/sink | 30.pre9-5 |
| 122 | `wpa_supplicant` | `wpa_supplicant` | interior | 2:2.11-5 |
| 123 | `wvdial` | `wvdial` | top/leaf | 1.61-10 |
| 124 | `xdg-utils` | `xdg-utils` | interior | 1.2.1-2 |
| 125 | `xfsprogs` | `xfsprogs` | interior | 7.0.1-1 |
| 126 | `xl2tpd` | `xl2tpd` | top/leaf | 1.3.20-1 |
| 127 | `zsh` | `zsh` | interior | 5.9.2-1 |
| 128 | `os-prober` | `os-prober` | top/leaf | 1.84-1 |
| 129 | `linux-headers` | `linux-headers` | top/leaf | 7.1.4.arch1-1 |
| 130 | `networkmanager` | `networkmanager` | interior | 1.56.1-2 |
| 131 | `nm-connection-editor` | `nm-connection-editor` | top/leaf | 1.36.0-2 |
| 132 | `xorg` | *group -> 49 pkgs* | root (group) | -- |
| 133 | `plasma` | *group -> 70 pkgs* | root (group) | -- |
| 134 | `base-devel` | `base-devel` | top/leaf | 1-2 |
| 135 | `konsole` | `konsole` | top/leaf | 26.04.3-1 |
| 136 | `plasma-desktop` | `plasma-desktop` | top/leaf | 6.7.3-1 |
| 137 | `lightdm` | `lightdm` | interior | 1:1.32.0-9 |
| 138 | `lightdm-gtk-greeter` | `lightdm-gtk-greeter` | top/leaf | 1:2.0.9-2 |
| 139 | `rp-pppoe` | `rp-pppoe` | top/leaf | 4.0-6 |
| 140 | `bc` | `bc` | interior | 1.08.2-1 |
| 141 | `curl` | `curl` | interior | 8.21.0-1 |
| 142 | `git` | `git` | top/leaf | 2.55.0-1 |
| 143 | `pipewire` | `pipewire` | interior | 1:1.6.8-1 |
| 144 | `pipewire-pulse` | `pipewire-pulse` | interior | 1:1.6.8-1 |
| 145 | `pipewire-alsa` | `pipewire-alsa` | top/leaf | 1:1.6.8-1 |
| 146 | `pavucontrol` | `pavucontrol` | top/leaf | 1:6.2-1 |
| 147 | `dialog` | `dialog` | top/leaf | 1:1.3_20260107-1 |
| 148 | `ufw` | `ufw` | top/leaf | 0.36.2-7 |
| 149 | `neovim` | `neovim` | top/leaf | 0.12.4-1 |
| 150 | `htop` | `htop` | top/leaf | 3.5.1-1 |
| 151 | `fastfetch` | `fastfetch` | top/leaf | 2.66.0-1 |
| 152 | `bluedevil` | `bluedevil` | top/leaf | 1:6.7.3-1 |
| 153 | `breeze` | `breeze` | interior | 6.7.3-1 |
| 154 | `breeze-gtk` | `breeze-gtk` | top/leaf, base/sink | 6.7.3-1 |
| 155 | `breeze-plymouth` | `breeze-plymouth` | top/leaf | 6.7.3-1 |
| 156 | `drkonqi` | `drkonqi` | top/leaf | 6.7.3-1 |
| 157 | `flatpak-kcm` | `flatpak-kcm` | top/leaf | 6.7.3-1 |
| 158 | `kactivitymanagerd` | `kactivitymanagerd` | interior | 6.7.3-1 |
| 159 | `kde-cli-tools` | `kde-cli-tools` | interior | 6.7.3-1 |
| 160 | `kde-gtk-config` | `kde-gtk-config` | top/leaf | 6.7.3-1 |
| 161 | `kdecoration` | `kdecoration` | interior | 6.7.3-1 |
| 162 | `kdeplasma-addons` | `kdeplasma-addons` | top/leaf | 6.7.3-1 |
| 163 | `kgamma` | `kgamma` | top/leaf | 6.7.3-1 |
| 164 | `kglobalacceld` | `kglobalacceld` | interior | 6.7.3-1 |
| 165 | `kinfocenter` | `kinfocenter` | interior | 6.7.3-1 |
| 166 | `kmenuedit` | `kmenuedit` | interior | 6.7.3-1 |
| 167 | `kpipewire` | `kpipewire` | interior | 6.7.3-1 |
| 168 | `krdp` | `krdp` | top/leaf | 6.7.3-1 |
| 169 | `kscreen` | `kscreen` | top/leaf | 6.7.3-1 |
| 170 | `kscreenlocker` | `kscreenlocker` | interior | 6.7.3-1 |
| 171 | `ksshaskpass` | `ksshaskpass` | top/leaf | 6.7.3-1 |
| 172 | `ksystemstats` | `ksystemstats` | interior | 6.7.3-1 |
| 173 | `kwallet-pam` | `kwallet-pam` | top/leaf | 6.7.3-1 |
| 174 | `kwayland` | `kwayland` | interior | 6.7.3-1 |
| 175 | `kwin` | `kwin` | interior | 6.7.3-1 |
| 176 | `kwrited` | `kwrited` | top/leaf | 6.7.3-1 |
| 177 | `layer-shell-qt` | `layer-shell-qt` | interior | 6.7.3-1 |
| 178 | `libkscreen` | `libkscreen` | interior | 6.7.3-1 |
| 179 | `libksysguard` | `libksysguard` | interior | 6.7.3-1 |
| 180 | `libplasma` | `libplasma` | interior | 6.7.3-1 |
| 181 | `milou` | `milou` | interior | 6.7.3-1 |
| 182 | `ocean-sound-theme` | `ocean-sound-theme` | base/sink | 6.7.3-1 |
| 183 | `oxygen` | `oxygen` | top/leaf | 6.7.3-1 |
| 184 | `oxygen-sounds` | `oxygen-sounds` | top/leaf, base/sink | 6.7.3-1 |
| 185 | `plasma-activities` | `plasma-activities` | interior | 6.7.3-1 |
| 186 | `plasma-activities-stats` | `plasma-activities-stats` | interior | 6.7.3-1 |
| 187 | `plasma-browser-integration` | `plasma-browser-integration` | top/leaf | 6.7.3-1 |
| 188 | `plasma-disks` | `plasma-disks` | top/leaf | 6.7.3-1 |
| 189 | `plasma-firewall` | `plasma-firewall` | top/leaf | 6.7.3-1 |
| 190 | `plasma-integration` | `plasma-integration` | interior | 6.7.3-1 |
| 191 | `plasma-nm` | `plasma-nm` | interior | 6.7.3-1 |
| 192 | `plasma-pa` | `plasma-pa` | top/leaf | 6.7.3-1 |
| 193 | `plasma-sdk` | `plasma-sdk` | top/leaf | 6.7.3-1 |
| 194 | `plasma-systemmonitor` | `plasma-systemmonitor` | top/leaf | 6.7.3-1 |
| 195 | `plasma-thunderbolt` | `plasma-thunderbolt` | top/leaf | 6.7.3-1 |
| 196 | `plasma-vault` | `plasma-vault` | top/leaf | 6.7.3-1 |
| 197 | `plasma-workspace` | `plasma-workspace` | interior | 6.7.3-1 |
| 198 | `plasma-workspace-wallpapers` | `plasma-workspace-wallpapers` | top/leaf, base/sink | 6.7.3-1 |
| 199 | `plasma5support` | `plasma5support` | interior | 6.7.3-1 |
| 200 | `plymouth-kcm` | `plymouth-kcm` | top/leaf | 6.7.3-1 |
| 201 | `polkit-kde-agent` | `polkit-kde-agent` | interior | 6.7.3-1 |
| 202 | `powerdevil` | `powerdevil` | interior | 6.7.3-1 |
| 203 | `print-manager` | `print-manager` | top/leaf | 1:6.7.3-1 |
| 204 | `qqc2-breeze-style` | `qqc2-breeze-style` | interior | 6.7.3-1 |
| 205 | `sddm-kcm` | `sddm-kcm` | top/leaf | 6.7.3-1 |
| 206 | `spectacle` | `spectacle` | top/leaf | 1:6.7.3-1 |
| 207 | `systemsettings` | `systemsettings` | interior | 6.7.3-1 |
| 208 | `wacomtablet` | `wacomtablet` | top/leaf | 6.7.3-1 |
| 209 | `xdg-desktop-portal-kde` | `xdg-desktop-portal-kde` | interior | 6.7.3-1 |
| 210 | `gedit` | `gedit` | top/leaf | 50.0-3 |
| 211 | `dolphin` | `dolphin` | top/leaf | 26.04.3-1 |
| 212 | `kcalc` | `kcalc` | top/leaf | 26.04.3-1 |
| 213 | `gwenview` | `gwenview` | top/leaf | 26.04.3-1 |
| 214 | `unzip` | `unzip` | top/leaf | 6.0-23 |
| 215 | `kamoso` | `kamoso` | top/leaf | 26.04.3-1 |
| 216 | `bluez` | `bluez` | interior | 5.87-2 |
| 217 | `bluez-utils` | `bluez-utils` | top/leaf | 5.87-2 |
| 218 | `cups` | `cups` | top/leaf | 2:2.4.19-1 |
| 219 | `mesa` | `mesa` | interior | 1:26.1.5-1 |
| 220 | `libglvnd` | `libglvnd` | interior | 1.7.0-3 |
| 221 | `kclock` | `kclock` | top/leaf | 26.04.3-1 |
| 222 | `dotnet-sdk` | `dotnet-sdk` | top/leaf | 10.0.10.sdk110-1 |
| 223 | `dotnet-runtime` | `dotnet-runtime` | interior | 10.0.10.sdk110-1 |
| 224 | `dotnet-host` | `dotnet-host` | interior | 10.0.10.sdk110-1 |
| 225 | `libadwaita` | `libadwaita` | top/leaf | 1:1.9.2-1 |
| 226 | `hicolor-icon-theme` | `hicolor-icon-theme` | base/sink | 0.18-1 |
| 227 | `webp-pixbuf-loader` | `webp-pixbuf-loader` | top/leaf | 0.2.7-2 |
| 228 | `libreoffice-fresh` | `libreoffice-fresh` | top/leaf | 26.2.4-4 |
| 229 | `xclip` | `xclip` | top/leaf | 0.13-6 |
| 230 | `go` | `go` | top/leaf, base/sink | 2:1.26.5-1 |
| 231 | `zip` | `zip` | top/leaf | 3.0-13 |
| 232 | `kdialog` | `kdialog` | top/leaf | 26.04.3-1 |
| 233 | `jq` | `jq` | interior | 1.8.2-1 |
| 234 | `gnome-screenshot` | `gnome-screenshot` | top/leaf | 1:41.0-2 |
| 235 | `python` | `python` | interior | 3.14.6-1 |
| 236 | `python-pip` | `python-pip` | top/leaf | 26.1.2-1 |
| 237 | `tk` | `tk` | top/leaf | 8.6.16-1 |
| 238 | `vlc` | `vlc` | top/leaf | 3.0.23_2-9 |
| 239 | `vlc-plugin-ffmpeg` | `vlc-plugin-ffmpeg` | top/leaf | 3.0.23_2-9 |
| 240 | `vlc-plugin-x264` | `vlc-plugin-x264` | top/leaf | 3.0.23_2-9 |
| 241 | `vlc-plugin-x265` | `vlc-plugin-x265` | top/leaf | 3.0.23_2-9 |
| 242 | `vlc-plugin-upnp` | `vlc-plugin-upnp` | top/leaf | 3.0.23_2-9 |

---

## 7. Appendix -- full resolved package set

All **1325** packages in the transitive closure, with real versions and source repo. A leading `*` marks an explicitly-requested package (a root / group member); unmarked packages are pulled in purely as dependencies.

```text
  a52dec 0.8.0-3 [extra]
  aalib 1.4rc5-19 [extra]
  abseil-cpp 20260526.0-2 [extra]
  accountsservice 26.27.3-1 [extra]
  acl 2.4.0-1 [core]
  adwaita-cursors 50.0-1 [extra]
  adwaita-fonts 50.0-1 [extra]
  adwaita-icon-theme 50.0-1 [extra]
  adwaita-icon-theme-legacy 46.2-3 [extra]
  aha 0.5.1-3 [extra]
  alsa-card-profiles 1:1.6.8-1 [extra]
  alsa-lib 1.2.16.1-1 [extra]
  alsa-topology-conf 1.2.5.1-4 [extra]
  alsa-ucm-conf 1.2.16.1-1 [extra]
* alsa-utils 1.2.16-1 [extra]
* amd-ucode 20260622-1 [core]
  aom 3.14.1-1 [extra]
  appstream 1.1.3-1 [extra]
  appstream-qt 1.1.3-1 [extra]
* arch-install-scripts 31-1 [extra]
* archinstall 4.4-1 [extra]
  archlinux-appstream-data 20260606-1 [extra]
  archlinux-keyring 20260707.1-1 [core]
  argon2 20190702-6 [extra]
  at-spi2-core 2.60.5-1 [extra]
  attica 6.28.0-1 [extra]
  attr 2.6.0-1 [core]
  audit 4.1.4-2 [core]
* aurorae 6.7.3-1 [extra]
  autoconf 2.73-1 [core]
  automake 1.18.1-1 [core]
  avahi 1:0.9rc5-1 [extra]
* b43-fwcutter 020-1 [core]
  baloo 6.28.0-1 [extra]
  baloo-widgets 26.04.3-1 [extra]
* base 3-3 [core]
* base-devel 1-2 [core]
  bash 5.3.15-1 [core]
* bc 1.08.2-1 [extra]
* bcachefs-tools 3:1.38.8-2 [extra]
* bind 9.20.24-1 [extra]
  binutils 2.46.1+r3+g046eeeef4721-1 [core]
  bison 3.8.2-8 [core]
  blas 3.12.1-2 [extra]
* bluedevil 1:6.7.3-1 [extra]
* bluez 5.87-2 [extra]
  bluez-libs 5.87-2 [extra]
  bluez-qt 6.28.0-1 [extra]
* bluez-utils 5.87-2 [extra]
* bolt 0.9.11-1 [extra]
  boost-libs 1.91.0-1 [extra]
  booster 0.13-1 [extra]
* breeze 6.7.3-1 [extra]
* breeze-cursors 6.7.3-1 [extra]
* breeze-gtk 6.7.3-1 [extra]
  breeze-icons 6.28.0-1 [extra]
* breeze-plymouth 6.7.3-1 [extra]
* brltty 6.9.1-3 [extra]
* broadcom-wl 6.30.223.271-713 [extra]
  brotli 1.2.0-1 [core]
* btrfs-progs 7.1-1 [core]
  bubblewrap 0.11.2-1 [extra]
  bzip2 1.0.8-6 [core]
  ca-certificates 20240618-1 [core]
  ca-certificates-mozilla 3.126-1 [core]
  ca-certificates-utils 20240618-1 [core]
  cairo 1.18.4-1 [extra]
  cairomm-1.16 1.18.1-1 [extra]
  cblas 3.12.1-2 [extra]
  ccid 1.8.2-1 [extra]
  cdparanoia 10.2-10 [extra]
  cfitsio 1:4.6.4-1 [extra]
  chromaprint 1.6.0-3 [extra]
  cifs-utils 7.5-1 [extra]
  clinfo 3.0.25.02.14-1 [extra]
* clonezilla 5.16.16-1 [extra]
* cloud-init 26.1-1 [extra]
  clucene 2.3.3.4-17 [extra]
  composefs 1.0.8-1 [extra]
  convertlit 1.8-13 [extra]
  coreutils 9.11-2 [core]
  cpio 2.15-3 [extra]
* cryptsetup 2.8.6-1 [core]
* cups 2:2.4.19-1 [extra]
  cups-filters 2.0.1-2 [extra]
* curl 8.21.0-1 [core]
  cxx-rust-cssparser 1.0.0-1 [extra]
* darkhttpd 1.17-1 [extra]
  dav1d 1.5.4-1 [extra]
  db5.3 5.3.28-7 [core]
  dbus 1.16.2-1 [core]
  dbus-broker 37-3 [core]
  dbus-broker-units 37-3 [core]
  dbus-units 37-3 [core]
  dconf 0.49.0-1 [extra]
  ddcutil 2.2.7-1 [extra]
* ddrescue 1.30-2 [extra]
  debugedit 5.3-1 [core]
  default-cursors 3-1 [extra]
  desktop-file-utils 0.28-1 [extra]
  device-mapper 2.03.41-1 [core]
  dhclient 4.4.3.P1-4 [extra]
* dialog 1:1.3_20260107-1 [extra]
* diffutils 3.12-2 [core]
  ding-libs 0.7.0-1 [core]
  discount 3.0.1.3-1 [extra]
* discover 6.7.3-1 [extra]
* dmidecode 3.7-1 [extra]
* dmraid 1.0.0.rc16.3-15 [core]
* dnsmasq 2.93-1 [extra]
  dnssec-anchors 20250524-1 [core]
* dolphin 26.04.3-1 [extra]
* dosfstools 4.2-5 [core]
* dotnet-host 10.0.10.sdk110-1 [extra]
* dotnet-runtime 10.0.10.sdk110-1 [extra]
* dotnet-sdk 10.0.10.sdk110-1 [extra]
  dotnet-targeting-pack 10.0.10.sdk110-1 [extra]
  double-conversion 3.4.0-1 [extra]
  drbl 5.9.11-1 [extra]
* drkonqi 6.7.3-1 [extra]
  duktape 2.7.0-7 [extra]
* e2fsprogs 1.47.4-1 [core]
  ebook-tools 0.2.2-9 [extra]
  ecryptfs-utils 111-9 [extra]
  editorconfig-core-c 0.12.11-1 [extra]
* edk2-shell 202605-1 [extra]
* efibootmgr 18-4 [core]
  efivar 39-2 [core]
  elfutils 0.195-1 [core]
  ell 0.83-1 [extra]
  enchant 2.8.15-2 [extra]
  espeak-ng 1.52.0-1 [extra]
* espeakup 0.90-4 [extra]
* ethtool 1:7.1-1 [extra]
* exfatprogs 1.4.2-1 [extra]
  exiv2 0.28.8-2 [extra]
  expat 2.8.2-1 [core]
* f2fs-tools 1.16.0-3 [extra]
  faac 1.50-1 [extra]
  faad2 2.11.2-1 [extra]
  fakeroot 1:1.37.2-2 [core]
* fastfetch 2.66.0-1 [extra]
* fatresize 1.1.0-2 [extra]
  ffmpeg 2:8.1.2-10 [extra]
  fftw 3.3.11-1 [extra]
  file 5.48-1 [core]
  filesystem 2025.10.12-1 [core]
  findutils 4.11.0-1 [core]
  flac 1.5.0-1 [extra]
  flatpak 1:1.18.0-1 [extra]
* flatpak-kcm 6.7.3-1 [extra]
  flex 2.6.4-6 [core]
  fluidsynth 2.5.6-1 [extra]
  fontconfig 2:2.18.2-1 [extra]
* foot-terminfo 1.27.0-1 [extra]
  frameworkintegration 6.28.0-1 [extra]
  freeglut 3.8.0-1 [extra]
  freerdp 2:3.30.0-1 [extra]
  freetype2 2.14.3-1 [extra]
  fribidi 1.0.16-2 [extra]
* fsarchiver 0.8.9-1 [extra]
  fuse-common 3.18.2-1 [extra]
  fuse2 2.9.9-5 [extra]
  fuse3 3.18.2-1 [extra]
  gawk 5.4.1-1 [core]
  gc 8.2.12-1 [core]
  gcc 16.1.1+r346+g4e03491b401d-4 [core]
  gcc-libs 16.1.1+r346+g4e03491b401d-4 [core]
  gcr 3.41.2-2 [extra]
  gcr-4 4.4.0.1-1 [extra]
  gdb 17.2-1 [extra]
  gdb-common 17.2-1 [extra]
  gdbm 1.26-2 [core]
  gdk-pixbuf2 2.44.7-1 [extra]
* gedit 50.0-3 [extra]
  gettext 1.0-2 [core]
  giflib 6.1.3-1 [extra]
* git 2.55.0-1 [extra]
  glib-networking 1:2.80.1-1 [extra]
  glib2 2.88.2-1 [core]
  glibc 2.43+r37+gfdf10644d6ee-1 [core]
  glibmm-2.68 2.88.1-1 [extra]
  glslang 1:1.4.350.1-1 [extra]
  glu 9.0.3-3 [extra]
  glycin 2.1.5-2 [extra]
  gmp 6.3.0-3 [core]
  gnome-keyring 1:50.0-1 [extra]
* gnome-screenshot 1:41.0-2 [extra]
  gnu-free-fonts 20120503-9 [extra]
  gnulib-l10n 20241231-1 [core]
  gnupg 2.4.9-2 [core]
  gnutls 3.8.13-2 [core]
* go 2:1.26.5-1 [extra]
  gobject-introspection-runtime 1.86.0-2 [extra]
  gocryptfs 2.6.1-1 [extra]
* gpart 0.3-6 [extra]
  gperftools 2.18.1-1 [extra]
  gpgme 2.1.2-1 [core]
  gpgmepp 2.1.0-1 [extra]
* gpm 1.20.7.r38.ge82d1a6-6 [core]
* gptfdisk 1.0.10-2 [extra]
  graphene 1.10.8-2 [extra]
  graphite 1:1.3.15-1 [extra]
  grep 3.12-2 [core]
* grml-zsh-config 0.19.28-1 [extra]
  groff 1.24.1-1 [core]
* grub 2:2.14-1 [core]
  gsettings-desktop-schemas 50.1-1 [extra]
  gsettings-system-schemas 50.1-1 [extra]
  gsm 1.0.24-1 [extra]
  gspell 1.14.4-1 [extra]
  gssdp 1.6.6-1 [extra]
  gssproxy 0.9.2-3 [core]
  gst-plugin-qml6 1.28.5-2 [extra]
  gst-plugins-bad 1.28.5-2 [extra]
  gst-plugins-bad-libs 1.28.5-2 [extra]
  gst-plugins-base 1.28.5-2 [extra]
  gst-plugins-base-libs 1.28.5-2 [extra]
  gst-plugins-good 1.28.5-2 [extra]
  gstreamer 1.28.5-2 [extra]
  gtest 1.17.0-2 [extra]
  gtk-update-icon-cache 1:4.22.4-1 [extra]
  gtk3 1:3.24.52-1 [extra]
  gtk4 1:4.22.4-1 [extra]
  gtkmm-4.0 4.22.0-2 [extra]
  guile 3.0.11-1 [core]
  gumbo-parser 0.13.2-1 [extra]
  gupnp 1:1.6.10-1 [extra]
  gupnp-igd 1.6.0-2 [extra]
* gwenview 26.04.3-1 [extra]
  gzip 1.14-2 [core]
  harfbuzz 14.2.1-1 [extra]
  harfbuzz-icu 14.2.1-1 [extra]
* hdparm 9.65-3 [core]
* hicolor-icon-theme 0.18-1 [extra]
  hidapi 0.15.0-1 [extra]
  highway 1.4.0-1 [extra]
* htop 3.5.1-1 [extra]
  hunspell 1.7.3-1 [extra]
  hwdata 0.409-1 [core]
  hwloc 2.14.0-1 [extra]
* hyperv 7.1.3-1 [extra]
  hyphen 2.8.9-1 [extra]
  i2c-tools 4.4-4 [extra]
  iana-etc 20260530-1 [core]
  icu 78.3-1 [core]
  iio-sensor-proxy 3.9-1 [extra]
  imagemagick 7.1.2.27-1 [extra]
  imath 3.2.2-6 [extra]
  imlib2 1.12.6-2 [extra]
* intel-ucode 20260512-1 [extra]
  iproute2 7.1.0-1 [core]
  iptables 1:1.8.13-1 [core]
  iputils 20250605-1 [core]
* irssi 1.4.5-5 [extra]
  iso-codes 4.20.1-1 [extra]
* iw 6.17-1 [core]
* iwd 3.12-1 [extra]
  jack2 1.9.22-2 [extra]
  jansson 2.15.0-1 [core]
  jasper 4.2.9-1 [extra]
  jbigkit 2.1-8 [extra]
  jemalloc 1:5.3.1-2 [extra]
* jfsutils 1.1.15-9 [core]
* jq 1.8.2-1 [extra]
  json-c 0.19-1 [core]
  json-glib 1.10.8-1 [extra]
  jsoncpp 1.9.6-3 [extra]
  kaccounts-integration 26.04.3-1 [extra]
* kactivitymanagerd 6.7.3-1 [extra]
* kamoso 26.04.3-1 [extra]
  karchive 6.28.0-1 [extra]
  kauth 6.28.0-1 [extra]
  kbd 2.10.0-1 [core]
  kbookmarks 6.28.0-1 [extra]
* kcalc 26.04.3-1 [extra]
* kclock 26.04.3-1 [extra]
  kcmutils 6.28.0-1 [extra]
  kcodecs 6.28.0-1 [extra]
  kcolorpicker 0.3.1-6 [extra]
  kcolorscheme 6.28.0-1 [extra]
  kcompletion 6.28.0-1 [extra]
  kconfig 6.28.0-1 [extra]
  kconfigwidgets 6.28.0-1 [extra]
  kcontacts 1:6.28.0-1 [extra]
  kcoreaddons 6.28.0-1 [extra]
  kcrash 6.28.0-1 [extra]
  kdbusaddons 6.28.0-1 [extra]
* kde-cli-tools 6.7.3-1 [extra]
* kde-gtk-config 6.7.3-1 [extra]
  kdeclarative 6.28.0-1 [extra]
  kdeconnect 26.04.3-1 [extra]
* kdecoration 6.7.3-1 [extra]
  kded 6.28.0-1 [extra]
* kdeplasma-addons 6.7.3-1 [extra]
  kdesu 6.28.0-1 [extra]
* kdialog 26.04.3-1 [extra]
  kdnssd 6.28.0-1 [extra]
  kdsoap 2.3.0-1 [extra]
  kdsoap-ws-discovery-client 0.4.0-3 [extra]
  keyutils 1.6.3-4 [core]
  kfilemetadata 6.28.0-1 [extra]
* kgamma 6.7.3-1 [extra]
  kglobalaccel 6.28.0-1 [extra]
* kglobalacceld 6.7.3-1 [extra]
  kguiaddons 6.28.0-1 [extra]
  kholidays 1:6.28.0-1 [extra]
  ki18n 6.28.0-1 [extra]
  kiconthemes 6.28.0-1 [extra]
  kidletime 6.28.0-1 [extra]
  kimageannotator 0.7.2-2 [extra]
  kimageformats 6.28.0-1 [extra]
* kinfocenter 6.7.3-1 [extra]
  kio 6.28.0-1 [extra]
  kio-extras 26.04.3-1 [extra]
  kio-fuse 5.1.1-2 [extra]
  kirigami 6.28.0-1 [extra]
  kirigami-addons 1.13.0-1 [extra]
  kitemmodels 6.28.0-1 [extra]
  kitemviews 6.28.0-1 [extra]
* kitty-terminfo 0.48.0-1 [extra]
  kjobwidgets 6.28.0-1 [extra]
* kmenuedit 6.7.3-1 [extra]
  kmod 34.2-1 [core]
  knewstuff 6.28.0-1 [extra]
* knighttime 6.7.3-1 [extra]
  knotifications 6.28.0-1 [extra]
  knotifyconfig 6.28.0-1 [extra]
* konsole 26.04.3-1 [extra]
  kpackage 6.28.0-1 [extra]
  kparts 6.28.0-1 [extra]
  kpeople 6.28.0-1 [extra]
* kpipewire 6.7.3-1 [extra]
  kpty 6.28.0-1 [extra]
  kquickcharts 6.28.0-1 [extra]
  kquickimageeditor 0.6.2.1-2 [extra]
  krb5 1.22.2-1 [core]
* krdp 6.7.3-1 [extra]
  krunner 6.28.0-1 [extra]
* kscreen 6.7.3-1 [extra]
* kscreenlocker 6.7.3-1 [extra]
  kservice 6.28.0-1 [extra]
* ksshaskpass 6.7.3-1 [extra]
  kstatusnotifieritem 6.28.0-1 [extra]
  ksvg 6.28.0-1 [extra]
* ksystemstats 6.7.3-1 [extra]
  ktexteditor 6.28.0-1 [extra]
  ktextwidgets 6.28.0-1 [extra]
  kunitconversion 6.28.0-1 [extra]
  kuserfeedback 6.28.0-1 [extra]
  kwallet 6.28.0-1 [extra]
* kwallet-pam 6.7.3-1 [extra]
* kwayland 6.7.3-1 [extra]
  kwidgetsaddons 6.28.0-1 [extra]
* kwin 6.7.3-1 [extra]
* kwin-x11 6.7.3-1 [extra]
  kwindowsystem 6.28.0-1 [extra]
* kwrited 6.7.3-1 [extra]
  kxmlgui 6.28.0-1 [extra]
  l-smash 2.14.5-4 [extra]
  lame 3.101.r6531-2 [extra]
  lapack 3.12.1-2 [extra]
* layer-shell-qt 6.7.3-1 [extra]
  lbzip2 2.5-6 [extra]
  lcms2 2.19.1-1 [extra]
  ldb 2:4.24.4-1 [extra]
* ldns 1.9.2-1 [core]
  leancrypto 1.8.0-1 [core]
  leptonica 1.87.0-1 [extra]
* less 1:704-1 [core]
* lftp 4.9.3-2 [extra]
  lib32-acl 2.4.0-1 [multilib]
  lib32-alsa-lib 1.2.16.1-1 [multilib]
  lib32-audit 4.1.4-1 [multilib]
  lib32-brotli 1.2.0-2 [multilib]
  lib32-bzip2 1.0.8-4 [multilib]
  lib32-cairo 1.18.4-1 [multilib]
  lib32-curl 8.21.0-1 [multilib]
  lib32-dbus 1.16.2-1 [multilib]
  lib32-duktape 2.7.0-7 [multilib]
  lib32-e2fsprogs 1.47.4-1 [multilib]
  lib32-expat 2.8.2-1 [multilib]
  lib32-flac 1.5.0-1 [multilib]
  lib32-fontconfig 2:2.18.2-1 [multilib]
  lib32-freetype2 2.14.3-1 [multilib]
  lib32-fribidi 1.0.16-2 [multilib]
  lib32-gcc-libs 16.1.1+r346+g4e03491b401d-4 [core]
  lib32-gdk-pixbuf2 2.44.7-1 [multilib]
  lib32-glib-networking 1:2.80.1-1 [multilib]
  lib32-glib2 2.88.2-1 [multilib]
  lib32-glibc 2.43+r37+gfdf10644d6ee-1 [core]
  lib32-gmp 6.3.0-2 [multilib]
  lib32-gnutls 3.8.13-3 [multilib]
  lib32-harfbuzz 14.2.1-1 [multilib]
  lib32-icu 78.3-1 [multilib]
  lib32-jack2 1.9.22-2 [multilib]
  lib32-json-c 0.19-1 [multilib]
  lib32-keyutils 1.6.3-4 [multilib]
  lib32-krb5 1.22.2-1 [multilib]
  lib32-libaio 0.3.113-5 [multilib]
  lib32-libarchive 3.8.8-2 [multilib]
  lib32-libbpf 1.7.0-1 [multilib]
  lib32-libcap 2.78-1 [multilib]
  lib32-libdatrie 0.2.14-1 [multilib]
  lib32-libdrm 2.4.134-1 [multilib]
  lib32-libelf 0.195-1 [multilib]
  lib32-libevent 2.1.12-4 [multilib]
  lib32-libffi 3.7.1-1 [multilib]
  lib32-libgcrypt 1.12.2-1 [multilib]
  lib32-libglvnd 1.7.0-1 [multilib]
  lib32-libgpg-error 1.61-1 [multilib]
  lib32-libgudev 238-3 [multilib]
  lib32-libidn2 2.3.8-1 [multilib]
  lib32-libjpeg-turbo 3.2.0-1 [multilib]
  lib32-libldap 2.6.13-1 [multilib]
  lib32-libnghttp2 1.69.0-1 [multilib]
  lib32-libnghttp3 1.17.0-1 [multilib]
  lib32-libngtcp2 1.24.0-1 [multilib]
  lib32-libnl 3.12.0-1 [multilib]
  lib32-libnsl 2.0.1-2 [multilib]
  lib32-libogg 1.3.6-1 [multilib]
  lib32-libpcap 1.10.6-1 [multilib]
  lib32-libpciaccess 0.19-1 [multilib]
  lib32-libpipewire 1:1.6.8-1 [multilib]
  lib32-libpng 1.6.58-2 [multilib]
  lib32-libproxy 0.5.12-1 [multilib]
  lib32-libpsl 0.21.5-1 [multilib]
  lib32-librsvg 2:2.62.3-1 [multilib]
  lib32-libsamplerate 0.2.2-3 [multilib]
  lib32-libsndfile 1.2.2-3 [multilib]
  lib32-libsodium 1.0.22-1 [multilib]
  lib32-libsoup3 3.6.6-2 [multilib]
  lib32-libssh2 1.11.1-4 [multilib]
  lib32-libtasn1 4.21.0-1 [multilib]
  lib32-libthai 0.1.30-1 [multilib]
  lib32-libtiff 4.7.2-1 [multilib]
  lib32-libtirpc 1.3.7-1 [multilib]
  lib32-libunistring 1.4.2-1 [multilib]
  lib32-libunwind 1.8.2-1 [multilib]
  lib32-libusb 1.0.30-1 [multilib]
  lib32-libva 2.22.0-1 [multilib]
  lib32-libvorbis 1.3.7-4 [multilib]
  lib32-libvpx 1.16.0-2 [multilib]
  lib32-libwebp 1.6.0-1 [multilib]
  lib32-libx11 1.8.13-1 [multilib]
  lib32-libxau 1.0.12-1 [multilib]
  lib32-libxcb 1.17.0-1 [multilib]
  lib32-libxcrypt 4.5.2-1 [multilib]
  lib32-libxdmcp 1.1.5-1 [multilib]
  lib32-libxext 1.3.7-1 [multilib]
  lib32-libxfixes 6.0.1-2 [multilib]
  lib32-libxft 2.3.9-1 [multilib]
  lib32-libxkbcommon 1.13.2-1 [multilib]
  lib32-libxml2 2.15.3-1 [multilib]
  lib32-libxrender 0.9.11-2 [multilib]
  lib32-libxshmfence 1.3.3-1 [multilib]
  lib32-libxxf86vm 1.1.5-2 [multilib]
  lib32-llvm-libs 1:22.1.8-1 [multilib]
  lib32-lm_sensors 1:3.6.2-2 [multilib]
  lib32-lz4 1.10.0-3 [multilib]
  lib32-mesa 1:26.1.5-1 [multilib]
  lib32-mpg123 1.33.5-1 [multilib]
  lib32-ncurses 6.6-2 [multilib]
  lib32-nettle 4.0-2 [multilib]
  lib32-openssl 1:3.6.3-1 [multilib]
  lib32-opus 1.6.1-1 [multilib]
  lib32-p11-kit 0.26.4-1 [multilib]
  lib32-pam 1.7.2-1 [multilib]
  lib32-pango 1:1.58.0-1 [multilib]
  lib32-pcre2 10.47-1 [multilib]
  lib32-pcsclite 2.5.1-1 [multilib]
  lib32-pixman 0.46.4-1 [multilib]
  lib32-polkit 127-1 [multilib]
  lib32-portaudio 1:19.7.0-3 [multilib]
  lib32-speexdsp 1.2.1-2 [multilib]
  lib32-spirv-tools 1:1.4.350.1-1 [multilib]
  lib32-sqlite 3.53.3-1 [multilib]
  lib32-systemd 261.1-1 [multilib]
  lib32-util-linux 2.42.2-1 [multilib]
  lib32-vulkan-icd-loader 1.4.350.1-1 [multilib]
  lib32-wayland 1.25.0-1 [multilib]
  lib32-xz 5.8.3-1 [multilib]
  lib32-zlib 1.3.2-1 [multilib]
  lib32-zstd 1.5.7-2 [multilib]
  libabw 0.1.4-1 [extra]
  libaccounts-glib 1.27-3 [extra]
  libaccounts-qt 1.17-2 [extra]
* libadwaita 1:1.9.2-1 [extra]
  libaio 0.3.113-4 [core]
  libarchive 3.8.8-2 [core]
  libasan 16.1.1+r346+g4e03491b401d-4 [core]
  libass 0.17.5-1 [extra]
  libassuan 3.0.0-1 [core]
  libasyncns 1:0.8+r3+g68cd5af-3 [extra]
  libatasmart 0.19-8 [extra]
  libatomic 16.1.1+r346+g4e03491b401d-4 [core]
  libatomic_ops 7.8.2-2 [extra]
  libavc1394 0.5.4-7 [extra]
  libavtp 0.2.0-3 [extra]
  libb2 0.98.1-3 [extra]
  libblake3 1.8.4-1 [extra]
  libblockdev 3.5.0-2 [extra]
  libblockdev-crypto 3.5.0-2 [extra]
  libblockdev-fs 3.5.0-2 [extra]
  libblockdev-loop 3.5.0-2 [extra]
  libblockdev-mdraid 3.5.0-2 [extra]
  libblockdev-nvme 3.5.0-2 [extra]
  libblockdev-part 3.5.0-2 [extra]
  libblockdev-smart 3.5.0-2 [extra]
  libblockdev-swap 3.5.0-2 [extra]
  libbluray 1.4.1-1 [extra]
  libbpf 1.7.0-1 [core]
  libbs2b 3.1.0-10 [extra]
  libbsd 0.12.2-2 [extra]
  libbytesize 2.12-3 [extra]
  libcaca 0.99.beta20-7 [extra]
  libcanberra 1:0.30+r2+gc0620e4-6 [extra]
  libcap 2.78-1 [core]
  libcap-ng 0.9.3-1 [core]
  libcbor 0.14.0-1 [extra]
  libcdr 0.1.9-1 [extra]
  libcloudproviders 0.4.0-1 [extra]
  libcmis 0.6.3-1 [extra]
  libcolord 1.4.8-1 [extra]
  libcups 2:2.4.19-1 [extra]
  libcupsfilters 2.1.1-4 [extra]
  libdaemon 0.14-6 [extra]
  libdatrie 0.2.14-1 [extra]
  libdc1394 2.2.7-2 [extra]
  libdca 0.0.7-3 [extra]
  libde265 1.1.1-1 [extra]
  libdecor 0.2.5-1 [extra]
  libdeflate 1.25-1 [extra]
  libdisplay-info 0.3.0-1 [extra]
  libdmtx 0.7.8-1 [extra]
  libdnet 1.18.2-1 [extra]
  libdovi 3.4.0-1 [extra]
  libdrm 2.4.134-1 [extra]
  libdv 1.0.0-12 [extra]
  libdvdnav 7.0.0-1 [extra]
  libdvdread 7.1.0-1 [extra]
  libe-book 0.1.3-20 [extra]
  libebml 1.4.5-3 [extra]
  libebur128 1.2.6-2 [extra]
  libedit 20260512_3.1-1 [core]
  libei 1.6.0-1 [extra]
  libelf 0.195-1 [core]
  libepoxy 1.5.10-3 [extra]
  libepubgen 0.1.1-6 [extra]
  libetonyek 0.1.13-2 [extra]
  libevdev 1.13.6-1 [extra]
  libevent 2.1.13-2 [core]
  libexif 0.6.26-1 [extra]
  libexttextcat 3.4.8-1 [extra]
  libfakekey 0.3-4 [extra]
  libfdk-aac 2.0.3-2 [extra]
  libffi 3.7.1-1 [core]
* libfido2 1.17.0-1 [extra]
  libfontenc 1.1.9-1 [extra]
  libfreeaptx 0.2.2-1 [extra]
  libfreehand 0.1.3-1 [extra]
  libfyaml 0.9.6-2 [extra]
  libgcc 16.1.1+r346+g4e03491b401d-4 [core]
  libgcrypt 1.12.2-1 [core]
  libgedit-amtk 5.10.0-1 [extra]
  libgedit-gfls 1:0.4.2-1 [extra]
  libgedit-gtksourceview 299.7.1-1 [extra]
  libgedit-tepl 6.14.0-2 [extra]
  libgfortran 16.1.1+r346+g4e03491b401d-4 [core]
  libgirepository 1.86.0-2 [extra]
* libglvnd 1.7.0-3 [extra]
  libgme 0.6.5-1 [extra]
  libgomp 16.1.1+r346+g4e03491b401d-4 [core]
  libgpg-error 1.61-1 [core]
  libgudev 238-3 [extra]
  libhandy 1.8.3-2 [extra]
  libhwasan 16.1.1+r346+g4e03491b401d-4 [core]
  libice 1.1.2-1 [extra]
  libidn2 2.3.8-1 [core]
  libiec61883 1.2.0-9 [extra]
  libimobiledevice 1.4.0-2 [extra]
  libimobiledevice-glue 1.3.2-1 [extra]
  libinih 62-2 [core]
  libinput 1.31.3-1 [extra]
  libisl 0.28-1 [core]
  libixion 0.20.0-7 [extra]
  libjpeg-turbo 3.2.0-2 [extra]
  libjxl 0.12.0-1 [extra]
  libkdcraw 26.04.3-1 [extra]
  libkexiv2 26.04.3-1 [extra]
  libksba 1.8.0-1 [core]
* libkscreen 6.7.3-1 [extra]
* libksysguard 6.7.3-1 [extra]
  liblangtag 0.6.8-1 [extra]
  liblc3 1.1.3-2 [extra]
  libldac 2.0.2.6-1 [extra]
  libldap 2.6.13-1 [core]
  liblouis 3.38.0-1 [extra]
  liblqr 0.4.3-1 [extra]
  liblrdf 0.6.1-5 [extra]
  liblsan 16.1.1+r346+g4e03491b401d-4 [core]
  libltc 1.3.2-2 [extra]
  libluv 1.52.1-1 [extra]
  libmakepkg-dropins 20-1 [core]
  libmalcontent 0.14.0-4 [extra]
  libmatroska 1.7.1-2 [extra]
  libmaxminddb 1.13.3-1 [extra]
  libmbim 1.34.0-1 [extra]
  libmd 1.2.0-1 [extra]
  libmicrodns 0.2.0-2 [extra]
  libmm-glib 1.24.2-1 [extra]
  libmng 2.0.3-4 [extra]
  libmnl 1.0.5-2 [core]
  libmodplug 0.8.9.0-7 [extra]
  libmpc 1.4.1-1 [core]
  libmpcdec 1:0.1+r475-6 [extra]
  libmspack 1:1.11-2 [extra]
  libmspub 0.1.5-1 [extra]
  libmtp 1.1.23-1 [extra]
  libmwaw 0.3.22-4 [extra]
  libmysofa 1.3.4-1 [extra]
  libndp 1.9-1 [extra]
  libnetfilter_conntrack 1.1.1-1 [core]
  libnewt 0.52.25-2 [extra]
  libnfnetlink 1.0.2-2 [core]
  libnftnl 1.3.1-1 [core]
  libnghttp2 1.69.0-1 [core]
  libnghttp3 1.17.0-1 [core]
  libngtcp2 1.24.0-1 [core]
  libnice 0.1.23-1 [extra]
  libnl 3.12.0-1 [core]
  libnm 1.56.1-2 [extra]
  libnma 1.10.6-3 [extra]
  libnma-common 1.10.6-3 [extra]
  libnotify 0.8.8-1 [extra]
  libnsl 2.0.1-2 [core]
  libntfs-3g 2026.7.7-1 [extra]
  libnumbertext 1.0.11-3 [extra]
  libnvme 1.16.2-1 [extra]
  libobjc 16.1.1+r346+g4e03491b401d-4 [core]
  libodfgen 0.1.8-5 [extra]
  libogg 1.3.6-1 [extra]
  libopenmpt 0.8.7-1 [extra]
  liborcus 0.21.0-6 [extra]
  libotr 4.1.1-6 [extra]
  libp11-kit 0.26.4-1 [core]
  libpagemaker 0.0.4-5 [extra]
  libpaper 2.2.8-1 [extra]
  libpcap 1.10.6-1 [core]
  libpciaccess 0.19-1 [extra]
  libpeas 1.38.1-1 [extra]
  libpgm 5.3.128-4 [extra]
  libpipeline 1.5.8-1 [core]
  libpipewire 1:1.6.8-1 [extra]
  libplacebo 7.360.1-3 [extra]
* libplasma 6.7.3-1 [extra]
  libplist 2.7.0-3 [extra]
  libpng 1.6.58-2 [extra]
  libppd 2.1.1-2 [extra]
  libproxy 0.5.12-1 [extra]
  libpsl 0.21.5-2 [core]
  libpulse 17.0+r98+gb096704c0-1 [extra]
  libqaccessibilityclient-qt6 0.6.0-4 [extra]
  libqalculate 5.12.0-1 [extra]
  libqmi 1.38.0-1 [extra]
  libqrtr-glib 1.4.0-1 [extra]
  libquadmath 16.1.1+r346+g4e03491b401d-4 [core]
  libqxp 0.0.3-1 [extra]
  libraqm 0.10.5-1 [extra]
  libraw 0.22.2-1 [extra]
  libraw1394 2.1.2-4 [extra]
* libreoffice-fresh 26.2.4-4 [extra]
  librevenge 0.0.6-1 [extra]
  librsvg 2:2.62.3-1 [extra]
  libsamplerate 0.2.2-3 [extra]
  libsasl 2.1.28-5 [core]
  libseccomp 2.6.0-1 [core]
  libsecret 0.21.7-1 [core]
  libshout 1:2.4.6-5 [extra]
  libsigc++ 2.12.2-1 [extra]
  libsigc++-3.0 3.8.1-1 [extra]
  libsm 1.2.6-1 [extra]
  libsndfile 1.2.2-4 [extra]
  libsodium 1.0.22-1 [extra]
  libsonic 0.2.0-2 [extra]
  libsoup3 3.6.6-2 [extra]
  libsoxr 0.1.3-5 [extra]
  libspeechd 0.12.1-3 [extra]
  libsrtp 1:2.8.0-1 [extra]
  libssc 0.4.4-1 [extra]
  libssh 0.12.0-1 [extra]
  libssh2 1.11.1-6 [core]
  libstaroffice 0.0.8-1 [extra]
  libstdc++ 16.1.1+r346+g4e03491b401d-4 [core]
  libstemmer 3.1.1-1 [extra]
  libsysprof-capture 50.0-2 [extra]
  libtasn1 4.21.0-1 [core]
  libtatsu 1.0.5-1 [extra]
  libteam 1.32-3 [extra]
  libthai 0.1.30-1 [extra]
  libtheora 1.2.0-1 [extra]
  libtiff 4.7.2-1 [extra]
  libtirpc 1.3.7-1 [core]
  libtommath 1.3.0-2 [extra]
  libtool 2.6.1-2 [core]
  libtorrent-rasterbar 1:2.1.0-3 [extra]
  libtsan 16.1.1+r346+g4e03491b401d-4 [core]
  libubsan 16.1.1+r346+g4e03491b401d-4 [core]
  libunibreak 7.0-1 [extra]
  libunistring 1.4.2-1 [core]
  libunwind 1.8.2-1 [extra]
  libupnp 1.14.31-1 [extra]
  liburcu 0.15.6-1 [extra]
  liburing 2.15-1 [extra]
  libusb 1.0.30-1 [core]
* libusb-compat 0.1.9-1 [extra]
  libusbmuxd 2.1.1-2 [extra]
  libutempter 1.2.3-1 [extra]
  libutf8proc 2.11.3-1 [extra]
  libuv 1.52.1-1 [extra]
  libva 2.24.1-1 [extra]
  libvdpau 1.5-4 [extra]
  libverto 0.3.2-6 [core]
  libvisio 0.1.11-1 [extra]
  libvlc 3.0.23_2-9 [extra]
  libvorbis 1.3.7-4 [extra]
  libvpl 2.17.0-1 [extra]
  libvpx 1.16.0-3 [extra]
  libvterm 0.3.3-2 [extra]
  libwacom 2.19.0-1 [extra]
  libwbclient 2:4.24.4-1 [extra]
  libwebp 1.6.0-2 [extra]
  libwireplumber 0.5.15-1 [extra]
  libwpd 0.10.3-6 [extra]
  libwps 0.4.14-4 [extra]
  libx11 1.8.13-1 [extra]
  libxau 1.0.12-1 [extra]
  libxaw 1.0.16-2 [extra]
  libxcb 1.17.0-1 [extra]
  libxcomposite 0.4.7-1 [extra]
  libxcrypt 4.5.2-1 [core]
  libxcursor 1.2.3-1 [extra]
  libxcvt 0.1.3-1 [extra]
  libxdamage 1.1.7-1 [extra]
  libxdmcp 1.1.5-2 [extra]
  libxext 1.3.7-1 [extra]
  libxfixes 6.0.2-1 [extra]
  libxfont2 2.0.8-1 [extra]
  libxft 2.3.9-1 [extra]
  libxi 1.8.3-1 [extra]
  libxinerama 1.1.6-1 [extra]
  libxkbcommon 1.13.2-1 [extra]
  libxkbcommon-x11 1.13.2-1 [extra]
  libxkbfile 1.2.0-1 [extra]
  libxklavier 5.4-7 [extra]
  libxml2 2.15.3-1 [core]
  libxmlb 0.3.28-1 [extra]
  libxmu 1.3.1-1 [extra]
  libxpm 3.5.19-1 [extra]
  libxrandr 1.5.5-1 [extra]
  libxrender 0.9.12-1 [extra]
  libxshmfence 1.3.3-1 [extra]
  libxslt 1.1.45-2 [extra]
  libxss 1.2.5-1 [extra]
  libxt 1.3.1-1 [extra]
  libxtst 1.2.5-1 [extra]
  libxv 1.0.13-1 [extra]
  libxxf86vm 1.1.7-1 [extra]
  libyaml 0.2.5-3 [extra]
  libzip 1.11.4-1 [extra]
  libzmf 0.0.2-20 [extra]
  licenses 20240728-1 [core]
* lightdm 1:1.32.0-9 [extra]
* lightdm-gtk-greeter 1:2.0.9-2 [extra]
  lilv 0.28.0-1 [extra]
* linux 7.1.4.arch1-1 [core]
  linux-api-headers 7.1-1 [core]
* linux-atm 2.5.2-9 [extra]
* linux-firmware 20260622-1 [core]
  linux-firmware-amdgpu 20260622-1 [core]
  linux-firmware-atheros 20260622-1 [core]
  linux-firmware-broadcom 20260622-1 [core]
  linux-firmware-cirrus 20260622-1 [core]
  linux-firmware-intel 20260622-1 [core]
* linux-firmware-marvell 20260622-1 [core]
  linux-firmware-mediatek 20260622-1 [core]
  linux-firmware-nvidia 20260622-1 [core]
  linux-firmware-other 20260622-1 [core]
  linux-firmware-radeon 20260622-1 [core]
  linux-firmware-realtek 20260622-1 [core]
  linux-firmware-whence 20260622-1 [core]
* linux-headers 7.1.4.arch1-1 [core]
  litehtml0.9 0.9-2 [extra]
* livecd-sounds 1.0-3 [extra]
  llvm-libs 22.1.8-2 [extra]
  lm_sensors 1:3.6.2-1 [extra]
  lmdb 0.9.35-1 [extra]
  lpsolve 5.5.2.14-1 [extra]
  lrzip 0.660-1 [extra]
  lsb-release 2.0.r55.a25a4fc-1 [extra]
* lsscsi 0.32-2 [extra]
  lua 5.5.0-2 [extra]
  lua51 5.1.5-13 [extra]
  lua51-lpeg 1.1.0-5 [extra]
  lua54 5.4.8-6 [extra]
  luajit 2.1.1784360928+14d8a7a-1 [extra]
  lv2 1.18.10-2 [extra]
* lvm2 2.03.41-1 [core]
* lynx 2.9.3-1 [extra]
  lz4 1:1.10.0-2 [core]
  lzo 2.10-5 [core]
  lzop 1.04-4 [extra]
  m4 1.4.21-2 [core]
  make 4.4.1-3 [core]
* man-db 2.13.1-2 [core]
* man-pages 6.18-1 [core]
* mc 4.8.33-1 [extra]
  md4c 0.5.3-1 [extra]
* mdadm 4.6-2 [core]
  media-player-info 26-1 [extra]
* memtest86+ 7.20-2 [extra]
* memtest86+-efi 7.20-2 [extra]
* mesa 1:26.1.5-1 [extra]
  mesa-utils 9.0.0-7 [extra]
* milou 6.7.3-1 [extra]
  minizip 1:1.3.2-3 [core]
  mjpegtools 2.2.1-4 [extra]
* mkinitcpio 41-4 [core]
* mkinitcpio-archiso 73-1 [extra]
  mkinitcpio-busybox 1.36.1-1 [core]
* mkinitcpio-nfs-utils 0.3-8 [core]
* mmc-utils 1.0-1 [extra]
  mobile-broadband-provider-info 20251101-1 [extra]
* modemmanager 1.24.2-1 [extra]
  modemmanager-qt 6.28.0-1 [extra]
  mpdecimal 4.0.1-3 [core]
  mpfr 4.2.2-1 [core]
  mpg123 1.33.5-1 [extra]
  msgpack-c 7.0.1-1 [extra]
  mtdev 1.1.7-1 [extra]
* mtools 1:4.0.49-1 [extra]
* nano 9.1-1 [core]
* nbd 3.27.1-4 [extra]
  ncurses 6.6-2 [core]
* ndisc6 1.0.8-1 [extra]
  neon 0.37.1-1 [extra]
* neovim 0.12.4-1 [extra]
  net-tools 2.10-3 [core]
  nettle 4.0-1 [core]
  nettle3 3.10.2-2 [extra]
* networkmanager 1.56.1-2 [extra]
  networkmanager-qt 6.28.0-1 [extra]
* nfs-utils 2.9.1-1 [core]
  nfsidmap 2.9.1-1 [core]
  nftables 1:1.1.6-3 [extra]
* nilfs-utils 2.3.0-1 [core]
* nm-connection-editor 1.36.0-2 [extra]
* nmap 7.99-3 [extra]
  noto-fonts 1:2026.07.01-1 [extra]
  noto-fonts-emoji 1:2.051-1 [extra]
  npth 1.8-1 [core]
  nspr 4.39-1 [core]
  nss 3.126-1 [core]
* ntfs-3g 2026.7.7-1 [extra]
  ntfsprogs 2026.7.7-1 [extra]
  numactl 2.0.19-1 [extra]
* nvme-cli 2.16-2 [extra]
  oath-toolkit 2.6.14-4 [extra]
* ocean-sound-theme 6.7.3-1 [extra]
  ocl-icd 2.3.4-1 [extra]
  onetbb 2023.1.0-1 [extra]
  oniguruma 6.9.10-1 [extra]
* open-iscsi 2.1.12-1 [extra]
  open-isns 0.103-1 [extra]
* open-vm-tools 6:13.1.0-2 [extra]
  openal 1.25.2-1 [extra]
  openbsd-netcat 1.238_1-1 [extra]
* openconnect 1:9.21-1 [extra]
  opencore-amr 0.1.6-2 [extra]
  opencv 5.0.0-6 [extra]
  openexr 3.4.13-2 [extra]
  openh264 2.6.0-2 [extra]
  openjpeg2 2.5.4-1 [extra]
  openjph 0.30.1-1 [extra]
* openpgp-card-tools 0.11.12-1 [extra]
* openssh 10.4p1-2 [core]
  openssl 3.6.3-1 [core]
* openvpn 2.7.5-1 [extra]
  openxr 1.1.60-1 [extra]
  opus 1.6.1-1 [extra]
  orc 0.4.42-1 [extra]
* os-prober 1.84-1 [extra]
  ostree 2026.2-1 [extra]
* oxygen 6.7.3-1 [extra]
* oxygen-cursors 6.7.3-1 [extra]
  oxygen-icons 1:6.28.0-1 [extra]
* oxygen-sounds 6.7.3-1 [extra]
  p11-kit 0.26.4-1 [core]
  pacman 7.1.0.r9.g54d9411-2 [core]
  pacman-mirrorlist 20260610-1 [core]
  pahole 1:1.31-2 [extra]
  pam 1.7.2-2 [core]
  pambase 20260616-1 [core]
  pango 1:1.58.0-1 [extra]
  pangomm-2.48 2.56.2-1 [extra]
* partclone 0.3.47-3 [extra]
* parted 3.7-1 [extra]
* partimage 0.6.9-16 [extra]
  patch 2.8-1 [core]
* pavucontrol 1:6.2-1 [extra]
  pbzip2 1.1.13-5 [extra]
  pcaudiolib 1.3-1 [extra]
  pciutils 3.15.0-1 [core]
  pcre 8.45-4 [core]
  pcre2 10.47-1 [core]
* pcsclite 2.5.1-1 [extra]
  perl 5.42.2-1 [core]
  perl-error 0.17030-3 [extra]
  perl-mailtools 2.22-3 [extra]
  perl-timedate 2.35-1 [extra]
  pigz 2.8-2 [extra]
  pinentry 1.3.3-1 [core]
* pipewire 1:1.6.8-1 [extra]
* pipewire-alsa 1:1.6.8-1 [extra]
  pipewire-audio 1:1.6.8-1 [extra]
* pipewire-pulse 1:1.6.8-1 [extra]
  pipewire-session-manager 1:1.6.8-1 [extra]
  pixman 0.46.4-1 [extra]
  pixz 1.0.7-5 [extra]
  pkcs11-helper 1.31.0-1 [extra]
  pkgconf 3.0.3-1 [core]
* plasma-activities 6.7.3-1 [extra]
* plasma-activities-stats 6.7.3-1 [extra]
* plasma-bigscreen 6.7.3-1 [extra]
* plasma-browser-integration 6.7.3-1 [extra]
* plasma-desktop 6.7.3-1 [extra]
* plasma-disks 6.7.3-1 [extra]
* plasma-firewall 6.7.3-1 [extra]
* plasma-integration 6.7.3-1 [extra]
* plasma-keyboard 6.7.3-1 [extra]
* plasma-login-manager 6.7.3-1 [extra]
  plasma-nano 6.7.3-1 [extra]
* plasma-nm 6.7.3-1 [extra]
* plasma-pa 6.7.3-1 [extra]
* plasma-sdk 6.7.3-1 [extra]
* plasma-systemmonitor 6.7.3-1 [extra]
* plasma-thunderbolt 6.7.3-1 [extra]
* plasma-vault 6.7.3-1 [extra]
* plasma-welcome 6.7.3-1 [extra]
* plasma-workspace 6.7.3-1 [extra]
* plasma-workspace-wallpapers 6.7.3-1 [extra]
* plasma5support 6.7.3-1 [extra]
  plymouth 26.134.222-2 [extra]
* plymouth-kcm 6.7.3-1 [extra]
  polkit 127-3 [extra]
* polkit-kde-agent 6.7.3-1 [extra]
  polkit-qt6 0.201.1-1 [extra]
  poppler 26.07.0-1 [extra]
  poppler-qt6 26.07.0-1 [extra]
  popt 1.19-2 [core]
  portaudio 1:19.7.0-4 [extra]
* powerdevil 6.7.3-1 [extra]
* ppp 2.5.3-1 [core]
* pptpclient 1.10.0-3 [core]
* print-manager 1:6.7.3-1 [extra]
  prison 6.28.0-1 [extra]
  procps-ng 4.0.6-3 [core]
  protobuf 35.1-1 [extra]
  protobuf-c 1.5.2-12 [extra]
  psmisc 23.7-2 [core]
  pulse-native-provider 1:1.6.8-1 [extra]
  pulseaudio-qt 1.8.1-1 [extra]
  purpose 6.28.0-1 [extra]
* pv 1.11.0-1 [extra]
* python 3.14.6-1 [core]
  python-annotated-types 0.7.0-3 [extra]
  python-attrs 26.1.0-1 [extra]
  python-certifi 2026.06.17-1 [extra]
  python-cffi 2.1.0-1 [extra]
  python-charset-normalizer 3.4.7-1 [extra]
  python-configobj 5.0.9-6 [extra]
  python-cryptography 49.0.0-1 [extra]
  python-filelock 3.29.3-1 [extra]
  python-gobject 3.56.3-1 [extra]
  python-idna 3.18-1 [extra]
  python-jinja 1:3.1.6-3 [extra]
  python-jsonpatch 1.33-6 [extra]
  python-jsonpointer 3.1.1-1 [extra]
  python-jsonschema 4.26.0-1 [extra]
  python-jsonschema-specifications 2025.9.1-2 [extra]
  python-linkify-it-py 2.1.0-1 [extra]
  python-markdown-it-py 4.2.0-1 [extra]
  python-markupsafe 3.0.3-1 [extra]
  python-mdurl 0.1.2-9 [extra]
  python-netifaces 0.11.0-9 [extra]
  python-oauthlib 3.3.1-2 [extra]
  python-packaging 26.2-1 [extra]
* python-pip 26.1.2-1 [extra]
  python-platformdirs 4.10.1-1 [extra]
  python-psutil 7.2.2-1 [extra]
  python-pycparser 3.00-1 [extra]
  python-pydantic 2.13.4-1 [extra]
  python-pydantic-core 3:2.46.4-1 [extra]
  python-pygdbmi 0.11.0.0-6 [extra]
  python-pygments 2.20.0-1 [extra]
  python-pyparted 3.13.0-6 [extra]
  python-pyserial 3.5-8 [extra]
  python-referencing 0.37.0-3 [extra]
  python-requests 2.34.2-1 [extra]
  python-rich 15.0.0-1 [extra]
  python-rpds-py 2026.6.3-1 [extra]
  python-sentry_sdk 2.65.0-1 [extra]
  python-textual 8.2.8-1 [extra]
  python-typing-inspection 0.4.2-2 [extra]
  python-typing_extensions 4.16.0-1 [extra]
  python-uc-micro-py 2.0.0-1 [extra]
  python-urllib3 2.7.0-1 [extra]
  python-wheel 0.47.0-1 [extra]
  python-yaml 6.0.3-2 [extra]
  qca-qt6 2.3.10-7 [extra]
  qcoro 0.13.0-2 [extra]
* qemu-guest-agent 11.0.2-3 [extra]
  qpdf 12.3.2-2 [extra]
* qqc2-breeze-style 6.7.3-1 [extra]
  qqc2-desktop-style 6.28.0-1 [extra]
  qrencode 4.1.1-4 [extra]
  qt5-base 5.15.19+kde+r96-1 [extra]
  qt5-declarative 5.15.19+kde+r23-1 [extra]
  qt5-svg 5.15.19+kde+r5-1 [extra]
  qt5-translations 5.15.19-1 [extra]
  qt5-wayland 5.15.19+kde+r55-1 [extra]
  qt5-x11extras 5.15.19-1 [extra]
  qt6-5compat 6.11.1-1 [extra]
  qt6-base 6.11.1-1 [extra]
  qt6-connectivity 6.11.1-1 [extra]
  qt6-declarative 6.11.1-3 [extra]
  qt6-imageformats 6.11.1-1 [extra]
  qt6-location 6.11.1-1 [extra]
  qt6-multimedia 6.11.1-1 [extra]
  qt6-multimedia-ffmpeg 6.11.1-1 [extra]
  qt6-positioning 6.11.1-1 [extra]
  qt6-quick3d 6.11.1-1 [extra]
  qt6-quicktimeline 6.11.1-1 [extra]
  qt6-sensors 6.11.1-1 [extra]
  qt6-shadertools 6.11.1-1 [extra]
  qt6-speech 6.11.1-1 [extra]
  qt6-svg 6.11.1-1 [extra]
  qt6-tools 6.11.1-3 [extra]
  qt6-translations 6.11.1-1 [extra]
  qt6-virtualkeyboard 6.11.1-1 [extra]
  qt6-webchannel 6.11.1-1 [extra]
  qt6-webengine 6.11.1-4 [extra]
  qt6-websockets 6.11.1-1 [extra]
  qt6-webview 6.11.1-1 [extra]
  qtkeychain-qt6 0.17.0-1 [extra]
  raptor 2.0.16-9 [extra]
  rasqal 1:0.9.33-9 [extra]
  rav1e 0.8.1-3 [extra]
  re2 2:2025.11.05-5 [extra]
  readline 8.3.003-1 [core]
  redland 1:1.0.17-10 [extra]
* refind 0.14.2-3 [extra]
* reflector 2023-5 [extra]
  ripgrep 15.2.0-1 [extra]
  ripgrep-all 0.10.10-1 [extra]
* rp-pppoe 4.0-6 [extra]
  rpcbind 1.2.9-1 [core]
* rsync 3.4.4-1 [extra]
  rtmpdump 1:2.6-2 [extra]
  rubberband 4.0.0-2 [extra]
  run-parts 5.23.2-1 [extra]
* rxvt-unicode-terminfo 9.31-9 [extra]
  sbc 2.2-1 [extra]
* screen 5.0.1-3 [extra]
  sddm 0.21.0-7 [extra]
* sddm-kcm 6.7.3-1 [extra]
  sdl2-compat 2.32.70-1 [extra]
  sdl3 3.4.12-1 [extra]
  sdl3_ttf 3.2.2-3 [extra]
* sdparm 1.12-1 [core]
  sed 4.10-1 [core]
* sequoia-sq 1.3.1-3 [extra]
  serd 0.32.10-1 [extra]
* sg3_utils 1.48-1 [extra]
  shaderc 2026.2-2 [extra]
  shadow 4.19.4.arch1-1 [core]
  shared-mime-info 2.5.1-2 [extra]
  signon-kwallet-extension 26.04.3-1 [extra]
  signon-plugin-oauth2 0.25-4 [extra]
  signon-ui 0.17+20231016-4 [extra]
  signond 8.61-4 [extra]
  slang 2.3.3-4 [extra]
* smartmontools 7.5-1 [extra]
  smbclient 2:4.24.4-1 [extra]
  snappy 1.2.2-3 [extra]
  sndio 1.10.0-1 [extra]
  socat 1.8.1.3-1 [extra]
* sof-firmware 2025.12.2-1 [extra]
  solid 6.28.0-1 [extra]
  sonnet 6.28.0-1 [extra]
  sord 0.16.22-1 [extra]
  sound-theme-freedesktop 0.8-6 [extra]
  soundtouch 2.4.1-1 [extra]
  source-highlight 3.1.9-18 [extra]
  spandsp 0.0.6-7 [extra]
* spectacle 1:6.7.3-1 [extra]
  speex 1.2.1-2 [extra]
  speexdsp 1.2.1-2 [extra]
  spirv-tools 1:1.4.350.1-1 [extra]
  sqlite 3.53.3-1 [core]
* squashfs-tools 4.7.5-1 [extra]
  sratom 0.6.22-1 [extra]
  srt 1.5.5-1 [extra]
  sshfs 3.7.6-1 [extra]
  stoken 0.92-6 [extra]
* sudo 1.9.17.p2-6 [core]
  svt-av1 4.1.0-1 [extra]
  svt-hevc 1.5.1-4 [extra]
  syndication 6.28.0-1 [extra]
  syntax-highlighting 6.28.0-1 [extra]
  sysfsutils 2.1.1-2 [extra]
* syslinux 6.04.pre3.r3.g05ac953c-4 [core]
  systemd 261.1-1 [core]
  systemd-libs 261.1-1 [core]
* systemd-resolvconf 261.1-1 [core]
  systemd-sysvcompat 261.1-1 [core]
* systemsettings 6.7.3-1 [extra]
  taglib 2.3-1 [extra]
  talloc 2.4.4-1 [extra]
  tar 1.35-2 [core]
  tcl 8.6.16-1 [extra]
* tcpdump 4.99.6-1 [extra]
  tdb 1.4.15-1 [extra]
* terminus-font 4.49.1-8 [extra]
  tesseract 5.5.2-1 [extra]
  tesseract-data-afr 2:4.1.0-5 [extra]
  tesseract-data-osd 2:4.1.0-5 [extra]
* testdisk 7.2-4 [extra]
  tevent 1:0.17.1-2 [extra]
  texinfo 7.3-1 [core]
  thin-provisioning-tools 1.3.3-1 [core]
  tinysparql 3.11.1-1 [extra]
* tk 8.6.16-1 [extra]
* tmux 3.7_b-1 [extra]
* tpm2-tools 5.7-1 [extra]
* tpm2-tss 4.1.3-1 [core]
  tree-sitter 0.26.9-1 [extra]
  tree-sitter-c 0.24.1-2 [extra]
  tree-sitter-lua 0.5.0-3 [extra]
  tree-sitter-markdown 0.5.3-2 [extra]
  tree-sitter-query 0.8.0-2 [extra]
  tree-sitter-vim 0.8.1-3 [extra]
  tree-sitter-vimdoc 4.1.0-2 [extra]
  tslib 1.24-1 [extra]
  ttf-hack 3.003-7 [extra]
  twolame 0.4.0-4 [extra]
  tzdata 2026c-1 [core]
* udftools 2.3-3 [extra]
  udisks2 2.11.1-2 [extra]
* ufw 0.36.2-7 [extra]
  unibilium 2.1.2-1 [extra]
* union 6.7.3-1 [extra]
* unzip 6.0-23 [extra]
  upower 1.91.3-1 [extra]
  uriparser 1.0.2-1 [extra]
* usb_modeswitch 2.6.2.20251207-1 [extra]
* usbmuxd 1.1.1-4 [extra]
* usbutils 019-1 [core]
  util-linux 2.42.2-1 [core]
  util-linux-libs 2.42.2-1 [core]
  v4l-utils 1.32.0-2 [extra]
  vapoursynth 77-2 [extra]
  verdict 1.4.5-2 [extra]
  vid.stab 1.1.1-3 [extra]
* vim 9.2.0804-1 [extra]
  vim-runtime 9.2.0804-1 [extra]
* virtualbox-guest-utils-nox 7.2.12-1 [extra]
* vlc 3.0.23_2-9 [extra]
  vlc-cli 3.0.23_2-9 [extra]
  vlc-gui-qt 3.0.23_2-9 [extra]
  vlc-plugin-a52dec 3.0.23_2-9 [extra]
  vlc-plugin-alsa 3.0.23_2-9 [extra]
  vlc-plugin-archive 3.0.23_2-9 [extra]
  vlc-plugin-dav1d 3.0.23_2-9 [extra]
  vlc-plugin-dbus 3.0.23_2-9 [extra]
  vlc-plugin-dbus-screensaver 3.0.23_2-9 [extra]
  vlc-plugin-faad2 3.0.23_2-9 [extra]
* vlc-plugin-ffmpeg 3.0.23_2-9 [extra]
  vlc-plugin-flac 3.0.23_2-9 [extra]
  vlc-plugin-gnutls 3.0.23_2-9 [extra]
  vlc-plugin-inflate 3.0.23_2-9 [extra]
  vlc-plugin-journal 3.0.23_2-9 [extra]
  vlc-plugin-jpeg 3.0.23_2-9 [extra]
  vlc-plugin-lua 3.0.23_2-9 [extra]
  vlc-plugin-matroska 3.0.23_2-9 [extra]
  vlc-plugin-mpg123 3.0.23_2-9 [extra]
  vlc-plugin-ogg 3.0.23_2-9 [extra]
  vlc-plugin-opus 3.0.23_2-9 [extra]
  vlc-plugin-png 3.0.23_2-9 [extra]
  vlc-plugin-pulse 3.0.23_2-9 [extra]
  vlc-plugin-shout 3.0.23_2-9 [extra]
  vlc-plugin-speex 3.0.23_2-9 [extra]
  vlc-plugin-tag 3.0.23_2-9 [extra]
  vlc-plugin-theora 3.0.23_2-9 [extra]
  vlc-plugin-twolame 3.0.23_2-9 [extra]
* vlc-plugin-upnp 3.0.23_2-9 [extra]
  vlc-plugin-vorbis 3.0.23_2-9 [extra]
  vlc-plugin-vpx 3.0.23_2-9 [extra]
* vlc-plugin-x264 3.0.23_2-9 [extra]
* vlc-plugin-x265 3.0.23_2-9 [extra]
  vlc-plugin-xml 3.0.23_2-9 [extra]
  vlc-plugins-base 3.0.23_2-9 [extra]
  vlc-plugins-video-output 3.0.23_2-9 [extra]
  vmaf 3.2.0-1 [extra]
  volume_key 0.3.12-12 [extra]
* vpnc 1:0.5.3.r557.r241-1 [extra]
  vulkan-icd-loader 1.4.350.1-1 [extra]
  vulkan-tools 1.4.350.1-1 [extra]
* wacomtablet 6.7.3-1 [extra]
  wavpack 5.9.0-1 [extra]
  wayland 1.25.0-1 [extra]
  wayland-utils 1.3.0-1 [extra]
* webp-pixbuf-loader 0.2.7-2 [extra]
  webrtc-audio-processing-1 1.3-5 [extra]
  which 2.25-1 [core]
  wildmidi 0.4.6-1 [extra]
* wireless-regdb 2026.05.30-1 [core]
* wireless_tools 30.pre9-5 [extra]
  wireplumber 0.5.15-1 [extra]
* wpa_supplicant 2:2.11-5 [core]
* wvdial 1.61-10 [extra]
  wvstreams 4.6.1-21 [extra]
  x264 3:0.165.r3222.b35605a-2 [extra]
  x265 4.2-2 [extra]
  xcb-proto 1.17.0-4 [extra]
  xcb-util 0.4.1-2 [extra]
  xcb-util-cursor 0.1.6-1 [extra]
  xcb-util-image 0.4.1-3 [extra]
  xcb-util-keysyms 0.4.1-5 [extra]
  xcb-util-renderutil 0.3.10-2 [extra]
  xcb-util-wm 0.4.2-2 [extra]
* xclip 0.13-6 [extra]
  xdg-dbus-proxy 0.1.7-1 [extra]
  xdg-desktop-portal 1.22.1-2 [extra]
  xdg-desktop-portal-gtk 1.15.3-1 [extra]
* xdg-desktop-portal-kde 6.7.3-1 [extra]
  xdg-user-dirs 0.20-1 [extra]
* xdg-utils 1.2.1-2 [extra]
  xf86-input-libinput 1.5.0-1 [extra]
  xf86-input-wacom 1.2.4-1 [extra]
* xf86-video-vesa 2.6.0-3 [extra]
* xfsprogs 7.0.1-1 [core]
  xkeyboard-config 2.48-1 [extra]
* xl2tpd 1.3.20-1 [extra]
  xmlsec 1.3.12-1 [extra]
* xorg-bdftopcf 1.1.2-1 [extra]
* xorg-docs 1.7.3-3 [extra]
* xorg-font-util 1.4.2-1 [extra]
* xorg-fonts-100dpi 1.0.4-3 [extra]
* xorg-fonts-75dpi 1.0.4-2 [extra]
  xorg-fonts-alias-100dpi 1.0.6-1 [extra]
  xorg-fonts-alias-75dpi 1.0.6-1 [extra]
* xorg-fonts-encodings 1.1.0-2 [extra]
* xorg-iceauth 1.0.11-1 [extra]
* xorg-mkfontscale 1.2.4-2 [extra]
* xorg-server 21.1.24-1 [extra]
* xorg-server-common 21.1.24-1 [extra]
* xorg-server-devel 21.1.24-1 [extra]
* xorg-server-src 21.1.24-1 [extra]
* xorg-server-xephyr 21.1.24-1 [extra]
* xorg-server-xnest 21.1.24-1 [extra]
* xorg-server-xvfb 21.1.24-1 [extra]
* xorg-sessreg 1.1.4-1 [extra]
* xorg-setxkbmap 1.3.5-1 [extra]
* xorg-smproxy 1.0.8-1 [extra]
  xorg-util-macros 1.20.2-1 [extra]
* xorg-x11perf 1.7.0-1 [extra]
* xorg-xauth 1.1.5-1 [extra]
* xorg-xbacklight 1.2.4-1 [extra]
* xorg-xcmsdb 1.0.7-1 [extra]
* xorg-xcursorgen 1.0.9-1 [extra]
* xorg-xdpyinfo 1.4.0-1 [extra]
* xorg-xdriinfo 1.0.8-1 [extra]
* xorg-xev 1.2.7-1 [extra]
* xorg-xgamma 1.0.8-1 [extra]
* xorg-xhost 1.0.10-1 [extra]
* xorg-xinput 1.6.4-2 [extra]
* xorg-xkbcomp 1.5.0-1 [extra]
* xorg-xkbevd 1.1.6-1 [extra]
* xorg-xkbutils 1.0.7-1 [extra]
* xorg-xkill 1.0.7-1 [extra]
* xorg-xlsatoms 1.1.5-1 [extra]
* xorg-xlsclients 1.1.6-1 [extra]
  xorg-xmessage 1.0.7-2 [extra]
* xorg-xmodmap 1.0.11-2 [extra]
* xorg-xpr 1.2.0-2 [extra]
* xorg-xprop 1.2.8-1 [extra]
* xorg-xrandr 1.5.4-1 [extra]
* xorg-xrdb 1.2.3-1 [extra]
* xorg-xrefresh 1.1.1-1 [extra]
* xorg-xset 1.2.6-1 [extra]
* xorg-xsetroot 1.1.4-1 [extra]
* xorg-xvinfo 1.1.6-1 [extra]
* xorg-xwayland 24.1.13-1 [extra]
* xorg-xwd 1.0.10-1 [extra]
* xorg-xwininfo 1.1.6-2 [extra]
* xorg-xwud 1.0.8-1 [extra]
  xorgproto 2025.1-1 [extra]
  xsettingsd 1.0.4-1 [extra]
  xvidcore 1.3.7-4 [extra]
  xxhash 0.8.3-1 [extra]
  xz 5.8.3-1 [core]
  yyjson 0.12.0-1 [extra]
  zbar 0.23.93-7 [extra]
  zeromq 4.3.5-3 [extra]
  zimg 3.0.6-2 [extra]
  zint 2.16.0-2 [extra]
* zip 3.0-13 [extra]
  zix 0.8.2-1 [extra]
  zlib 1:1.3.2-3 [core]
  zlib-ng 2.3.3-1 [extra]
* zsh 5.9.2-1 [extra]
  zstd 1.5.7-3 [core]
  zvbi 0.2.44-1 [extra]
  zxing-cpp 3.1.0-1 [extra]
```
