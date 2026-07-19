"""
spec_content -- the editorial, hand-authored parts of the specification.

The dependency graph, tables and metrics are *computed* from real package data
(see spec_resolve). But three things are editorial and cannot be derived from
metadata alone:

  * INTRO / GLANCE_NOTE / LAYERS_NOTE -- the framing prose.
  * ASCII_GRAPH -- the base-to-top layered diagram.
  * SUBSYSTEMS -- the grouping of packages by real role, plus a technical
    capability blurb per subsystem.

Following the project's config-as-Python convention, that content lives here as
data. The renderer stitches it together with the computed tables. Version numbers
inside the prose are refreshed at render time against the resolved data (see
spec_render.refresh_versions), so re-running the generator keeps them honest.

To add/adjust a subsystem: edit SUBSYSTEMS. Each entry is:
    (key, title, prose, [(package_or_"a / b", capability), ...])
The renderer validates that every listed package exists in the closure and warns
about anything missing so this file cannot silently drift from reality.
"""

INTRO = """\
A technical specification of the Az'arch operating system: the software that
ships on the ISO. This describes **the distribution itself** -- its package set,
the real dependency hierarchy from the kernel at the base up to the leaf
applications at the top, and what each subsystem actually does.

The dependency data here is **real**, not inferred from package names. It was
resolved from the official Arch Linux `core`, `extra` and `multilib` package
databases -- the same repositories the ISO is assembled against -- by reading
each package's actual `%DEPENDS%` / `%PROVIDES%` fields and walking the full
transitive closure. Every version number below is the real packaged version.\
"""

GLANCE_NOTE = """\
> **How to read "top" and "base".** *Base* packages sit at the bottom of the
> graph: they depend on nothing else in the set, and huge numbers of other
> packages depend on them. *Top* (leaf) packages sit at the surface: nothing
> depends on them, so removing a top package removes only itself (and any deps
> that then become unused) -- nothing else in the system breaks.\
"""

# {leaves}/{bases}/{kernel_version} are filled in by the renderer.
ASCII_GRAPH = """\
```text
                       Az'arch dependency graph  --  base (bottom) to top (leaves)

  TOP / LEAVES ({leaves} pkgs)   nothing depends on these; remove one and nothing else breaks
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
  BASE / SINKS ({bases} pkgs, depend on nothing else in the set)
     iana-etc  tzdata  linux-api-headers  xorgproto  xcb-proto  pambase  xkeyboard-config
     (glibc/libgcc are near-base keystones, not sinks: they still depend on a
      handful of these -- glibc -> linux-api-headers, tzdata, filesystem)

  KERNEL:  linux {kernel_version}  (+ linux-firmware, amd-ucode, intel-ucode)
           the kernel is a root, not a hub: only broadcom-wl and
           virtualbox-guest-utils-nox depend on the linux package itself.
```\
"""

LAYERS_NOTE = """\
- Every explicit manifest entry was resolved to a real Arch package. The two
  group entries were expanded to their members: `xorg` -> {xorg_members} packages,
  `plasma` -> {plasma_members} packages.
- From those roots, the full transitive dependency closure was walked using the
  real `%DEPENDS%` fields (virtual/provides dependencies resolved via
  `%PROVIDES%`). That closure is **{closure} packages** with **{unresolved}
  unresolved dependency edges**.
- *Base / sink* = out-degree 0 within the closure (depends on nothing else in
  the set). *Top / leaf* = in-degree 0 (nothing in the set depends on it).
- "Depended on by (transitive)" counts every package that ultimately reaches a
  package through the dependency graph; it is the true measure of how load-
  bearing a package is.\
"""

KEYSTONE_NOTE = """\
Not every keystone is a sink (some have a few deps of their own), but these are
the packages the largest share of the system ultimately rests on. `glibc` alone
is a direct dependency of {glibc_direct} packages; the C runtime, compression
libraries and core crypto libraries underpin essentially everything.\
"""

# (key, title, prose, [(package(s), capability)])
SUBSYSTEMS = [
    (
        "kernel", "Kernel, firmware & boot",
        "The absolute foundation of the OS. The kernel is `linux` (mainline Linux, "
        "Arch patchset), shipped with matching `linux-headers` for out-of-tree "
        "module builds and the full `linux-firmware` set (plus the Marvell split-out "
        "package) for network, GPU and platform device firmware. CPU microcode is "
        "loaded early from `amd-ucode` and `intel-ucode`; `sof-firmware` provides "
        "DSP firmware for modern Intel/AMD audio. The initramfs is built by "
        "`mkinitcpio` with the `mkinitcpio-archiso` hooks that make the live medium "
        "boot, and `booster` is present as an alternative generator. The medium "
        "boots on both firmware types: BIOS via `syslinux`, UEFI via `grub`, "
        "`refind`, `efibootmgr` and the bundled `edk2-shell`; "
        "`memtest86+`/`memtest86+-efi` provide RAM diagnostics and `os-prober` "
        "detects already-installed operating systems for dual-boot menus.",
        [
            ("linux", "The Linux kernel and loadable modules"),
            ("linux-headers", "Kernel headers/build scripts for out-of-tree modules"),
            ("linux-firmware", "Device firmware blobs (Wi-Fi, GPU, etc.)"),
            ("linux-firmware-marvell", "Firmware for Marvell devices"),
            ("amd-ucode", "Early microcode updates for AMD CPUs"),
            ("intel-ucode", "Early microcode updates for Intel CPUs"),
            ("sof-firmware", "Sound Open Firmware for modern audio DSPs"),
            ("mkinitcpio", "Modular initramfs image generator"),
            ("mkinitcpio-archiso", "archiso hooks that make the live image boot"),
            ("booster", "Alternative fast initramfs generator"),
            ("grub", "GRUB2 bootloader (BIOS + UEFI)"),
            ("syslinux", "BIOS boot loaders (FAT/ext/btrfs/PXE/CD)"),
            ("refind", "Graphical EFI boot manager"),
            ("efibootmgr", "Edit UEFI boot entries from userspace"),
            ("edk2-shell", "EDK2 UEFI interactive shell"),
            ("memtest86+ / memtest86+-efi", "RAM diagnostic (BIOS and EFI builds)"),
            ("os-prober", "Detect other installed OSes for boot menus"),
        ],
    ),
    (
        "base", "Base system & shell",
        "The minimal Unix userland the desktop and installer sit on. `systemd` is "
        "the init system, service manager and journal; `base`/`base-devel` pull in "
        "the standard GNU coreutils/toolchain set, and `sudo` handles privilege "
        "escalation. Two shells ship: `bash` (the default) and `zsh` with the "
        "polished `grml-zsh-config`. Terminal editors (`nano`, `vim`), pagers "
        "(`less`), the manual system (`man-db` + `man-pages`), a terminal file "
        "manager (`mc`), a process monitor (`htop`), terminal multiplexers (`tmux`, "
        "`screen`), and staples like `rsync`, `diffutils`, `bc` and `pv` round out "
        "a self-sufficient command line.",
        [
            ("systemd", "init, service manager, journald, logind"),
            ("bash", "Default POSIX shell"),
            ("zsh", "Advanced interactive shell"),
            ("grml-zsh-config", "Batteries-included zsh setup"),
            ("sudo", "Privilege escalation"),
            ("vim / nano", "Terminal text editors"),
            ("less", "Terminal pager"),
            ("man-db / man-pages", "Manual page reader + Linux man pages"),
            ("mc", "Norton-Commander-style file manager"),
            ("htop", "Interactive process viewer"),
            ("tmux / screen", "Terminal multiplexers"),
            ("rsync", "Fast local/remote file sync"),
            ("bc / pv / diffutils", "Calculator, pipe meter, patch tools"),
            ("xdg-utils", "Desktop integration helpers"),
        ],
    ),
    (
        "plasma", "KDE Plasma desktop",
        "The graphical environment the ISO boots into: KDE Plasma with KDE Gear "
        "applications. `plasma-desktop`/`plasma-workspace` provide the shell, panel "
        "and session; `kwin` is the Wayland compositor with `kwin-x11` as the X11 "
        "window manager; `kdecoration`/`aurorae` handle window decorations. Session "
        "services include screen management (`kscreen`), power management "
        "(`powerdevil`), the lock screen (`kscreenlocker`), global shortcuts "
        "(`kglobalacceld`), activity tracking (`kactivitymanagerd`), the KWallet PAM "
        "bridge (`kwallet-pam`) and the polkit authentication agent "
        "(`polkit-kde-agent`). Look and feel is Breeze/Oxygen. Bundled KDE apps: "
        "`konsole` (terminal), `dolphin` (file manager), `gwenview` (image viewer), "
        "`spectacle` (screenshots), `kcalc`, `kclock`, `kinfocenter`, "
        "`plasma-systemmonitor`, `discover` (software center), plus `krdp` for an "
        "RDP server and `xdg-desktop-portal-kde` for sandboxed-app portals.",
        [
            ("plasma-desktop", "KDE Plasma desktop shell"),
            ("plasma-workspace", "Panel, session, workspace services"),
            ("kwin", "Wayland compositor"),
            ("kwin-x11", "X11 window manager"),
            ("systemsettings", "Unified settings application"),
            ("kscreen / powerdevil", "Display + power management"),
            ("kscreenlocker", "Secure lock screen"),
            ("polkit-kde-agent", "polkit authentication UI"),
            ("breeze / oxygen", "Visual styles / themes"),
            ("konsole", "Terminal emulator"),
            ("dolphin", "File manager"),
            ("gwenview / spectacle", "Image viewer / screenshots"),
            ("kcalc / kclock", "Calculator / clock"),
            ("plasma-systemmonitor", "System resource monitor"),
            ("discover", "Graphical package/Flatpak manager"),
            ("krdp", "Built-in RDP server"),
            ("xdg-desktop-portal-kde", "Portal backend for sandboxed apps"),
        ],
    ),
    (
        "display", "Display server, graphics & login",
        "The graphics stack under the desktop. `mesa` supplies the open-source "
        "OpenGL/Vulkan drivers and `libglvnd` provides vendor-neutral GL dispatch. "
        "A full X.Org server (`xorg-server`) is present alongside `xorg-xwayland`, "
        "which runs legacy X clients under the Wayland session; the `xorg` group "
        "also brings the complete set of X utilities (`xrandr`, `xinput`, "
        "`setxkbmap`, etc.) and the generic `xf86-video-vesa` fallback driver. Login "
        "is handled by `lightdm` with the `lightdm-gtk-greeter`, while "
        "`plasma-login-manager` and the `sddm-kcm` configuration module are also "
        "present for Plasma's own login manager.",
        [
            ("mesa", "Open-source OpenGL/Vulkan drivers"),
            ("libglvnd", "GL vendor-neutral dispatch"),
            ("xorg-server", "X.Org X11 display server"),
            ("xorg-xwayland", "Run X clients under Wayland"),
            ("xorg-xrandr / xorg-xinput", "Display + input configuration"),
            ("xf86-video-vesa", "Generic VESA fallback video driver"),
            ("lightdm", "Display/login manager"),
            ("lightdm-gtk-greeter", "GTK login greeter"),
            ("plasma-login-manager", "Plasma's login manager"),
            ("sddm-kcm", "SDDM configuration module"),
        ],
    ),
    (
        "audio", "Audio (PipeWire)",
        "Audio is served by PipeWire, the low-latency media graph that replaces "
        "PulseAudio and JACK. `pipewire-pulse` provides the PulseAudio-compatible "
        "daemon and `pipewire-alsa` the ALSA routing config, so both PulseAudio and "
        "ALSA clients play through PipeWire transparently. `alsa-utils` gives "
        "kernel-level mixer/control tools, while `pavucontrol` and the `plasma-pa` "
        "applet provide graphical volume and device control. `livecd-sounds` "
        "supplies accessibility sound cues on the live medium.",
        [
            ("pipewire", "Low-latency audio/video graph server"),
            ("pipewire-pulse", "PulseAudio-compatible daemon"),
            ("pipewire-alsa", "ALSA client routing into PipeWire"),
            ("alsa-utils", "Kernel ALSA mixer/control utilities"),
            ("pavucontrol", "Graphical volume control"),
            ("plasma-pa", "Plasma volume applet"),
        ],
    ),
    (
        "networking", "Networking & VPN",
        "A broad connectivity and diagnostics stack. `networkmanager` is the "
        "connection manager, driven from the desktop by `plasma-nm` or the "
        "`nm-connection-editor` GUI. Wireless is backed by `wpa_supplicant`, the "
        "newer `iwd` daemon, and the `iw`/`wireless_tools` CLIs. Remote access and "
        "tunnelling: `openssh`, plus VPN clients `openvpn`, `openconnect` (Cisco "
        "AnyConnect) and `vpnc`; dial-up/DSL/mobile paths via `ppp`, `pptpclient`, "
        "`rp-pppoe`, `xl2tpd`, `wvdial` and `modemmanager`. DNS tooling includes "
        "`bind` utilities, the `dnsmasq` forwarder/DHCP server and the `ldns` "
        "library. Diagnostics: `tcpdump` (packet capture), `nmap` (scanning), "
        "`ethtool`, `ndisc6` (IPv6), and transfer tools `curl` and `lftp`.",
        [
            ("networkmanager", "Connection manager"),
            ("plasma-nm", "Plasma network applet"),
            ("iwd / wpa_supplicant", "Wi-Fi daemons"),
            ("iw / wireless_tools", "Wireless CLI configuration"),
            ("openssh", "SSH client/server"),
            ("openvpn / openconnect / vpnc", "VPN clients"),
            ("modemmanager / ppp / pptpclient", "Mobile/dial-up connectivity"),
            ("bind / dnsmasq / ldns", "DNS server/forwarder/library"),
            ("tcpdump / nmap / ethtool", "Capture, scan, NIC control"),
            ("curl / lftp", "HTTP(S)/FTP transfer clients"),
        ],
    ),
    (
        "storage", "Storage, filesystems & installation",
        "This is the core rescue-and-install mission of the medium. Two installers "
        "ship: `archinstall` (guided) and `arch-install-scripts` "
        "(`pacstrap`/`arch-chroot`). Partitioning and block-layer: `parted`, "
        "`gptfdisk`, `cryptsetup` (LUKS/dm-crypt), `lvm2`, `mdadm` (software RAID) "
        "and `dmraid`. Filesystem userspace tools cover ext2/3/4 (`e2fsprogs`), "
        "Btrfs, XFS, F2FS, exFAT, FAT (`dosfstools`), NTFS (`ntfs-3g`), NILFS, JFS "
        "and bcachefs, plus `nfs-utils`, `open-iscsi` and `nbd` for networked "
        "storage and `squashfs-tools` for the live image format. Imaging, recovery "
        "and health: `clonezilla`, `partclone`, `fsarchiver`, `testdisk`, "
        "`ddrescue`, `smartmontools` and `nvme-cli`.",
        [
            ("archinstall", "Guided Arch installer (TUI)"),
            ("arch-install-scripts", "`pacstrap` / `arch-chroot` / `genfstab`"),
            ("parted / gptfdisk", "MBR/GPT partitioning"),
            ("cryptsetup", "LUKS/dm-crypt full-disk encryption"),
            ("lvm2 / mdadm / dmraid", "LVM, software + BIOS RAID"),
            ("btrfs-progs / xfsprogs / e2fsprogs", "Btrfs, XFS, ext2/3/4 tools"),
            ("f2fs-tools / exfatprogs / ntfs-3g", "F2FS, exFAT, NTFS"),
            ("nilfs-utils / jfsutils / bcachefs-tools", "NILFS, JFS, bcachefs"),
            ("nfs-utils / open-iscsi / nbd", "Network filesystems and block devices"),
            ("squashfs-tools", "SquashFS (live image) tools"),
            ("clonezilla / partclone / fsarchiver", "Disk imaging/cloning/backup"),
            ("testdisk / ddrescue", "Partition + data recovery"),
            ("smartmontools / nvme-cli", "SMART monitoring, NVMe control"),
        ],
    ),
    (
        "security", "Security, firewall & crypto hardware",
        "Host firewalling is provided by `ufw` (a netfilter front end) with the "
        "`plasma-firewall` control panel. Trusted-computing and hardware-token "
        "support: `tpm2-tss` (the TSS2 stack) and `tpm2-tools` for TPM 2.0; "
        "`libfido2` for FIDO2/U2F security keys; `pcsclite` smartcard middleware; "
        "and `openpgp-card-tools` for OpenPGP smartcards. `sequoia-sq` is a modern "
        "OpenPGP CLI. On the desktop, `plasma-vault` creates encrypted vaults and "
        "`kwallet-pam` unlocks the KDE wallet at login.",
        [
            ("ufw", "netfilter firewall front end"),
            ("plasma-firewall", "Firewall control panel"),
            ("tpm2-tss / tpm2-tools", "TPM 2.0 software stack + tools"),
            ("libfido2", "FIDO2 / U2F security-key support"),
            ("pcsclite", "PC/SC smartcard middleware"),
            ("sequoia-sq", "OpenPGP command-line tool"),
            ("openpgp-card-tools", "Manage OpenPGP smartcards"),
            ("plasma-vault", "Encrypted vaults on the desktop"),
            ("kwallet-pam", "Unlock KWallet at login (PAM)"),
        ],
    ),
    (
        "devtools", "Developer toolchain & runtimes",
        "The OS ships end-user development runtimes out of the box. `python` with "
        "`python-pip`; `go`; and a complete .NET stack (`dotnet-sdk`, "
        "`dotnet-runtime`, `dotnet-host`). `git` provides version control, `neovim` "
        "a modern editor, `jq` JSON processing, and `tk` the Tcl/Tk GUI toolkit "
        "(which also backs Python's tkinter).",
        [
            ("python", "CPython interpreter"),
            ("python-pip", "Python package installer"),
            ("go", "Go compiler and toolchain"),
            ("dotnet-sdk", ".NET SDK (build + CLI)"),
            ("dotnet-runtime", ".NET runtime"),
            ("git", "Distributed version control"),
            ("neovim", "Extensible modal editor"),
            ("jq", "Command-line JSON processor"),
            ("tk", "Tcl/Tk GUI toolkit (backs tkinter)"),
        ],
    ),
    (
        "multimedia", "Multimedia & office",
        "Media playback centres on `vlc` with codec plugins for FFmpeg decode and "
        "x264/x265 (H.264/H.265) encode, plus UPnP streaming. `libreoffice-fresh` "
        "is the full office suite (documents, spreadsheets, presentations). "
        "`kamoso` records from webcams and `gnome-screenshot` captures the screen.",
        [
            ("vlc", "Multimedia player and framework"),
            ("vlc-plugin-ffmpeg", "FFmpeg-based decode for VLC"),
            ("vlc-plugin-x264 / vlc-plugin-x265", "H.264 / H.265 encoding"),
            ("vlc-plugin-upnp", "UPnP/DLNA media browsing"),
            ("libreoffice-fresh", "Full office productivity suite"),
            ("kamoso", "Webcam capture/recording"),
            ("gnome-screenshot", "Screenshot capture"),
        ],
    ),
    (
        "hardware", "Hardware, virtualization & peripherals",
        "Bluetooth is provided by the `bluez` stack with the `bluedevil` KDE "
        "integration; printing by `cups` with the `print-manager` front end. The "
        "medium runs well as a guest under every major hypervisor: `open-vm-tools` "
        "(VMware), `qemu-guest-agent` (QEMU/KVM), `virtualbox-guest-utils-nox` "
        "(VirtualBox) and `hyperv` (Microsoft Hyper-V). Hardware inspection and "
        "control: `usbutils`, `usb_modeswitch`, `dmidecode` (DMI/SMBIOS), and "
        "Thunderbolt via `bolt` + `plasma-thunderbolt`. Accessibility is served by "
        "`brltty` (braille displays) and `espeakup` (console speech).",
        [
            ("bluez / bluez-utils", "Bluetooth stack + tools"),
            ("bluedevil", "Bluetooth integration in Plasma"),
            ("cups / print-manager", "Printing daemon + GUI"),
            ("open-vm-tools", "VMware guest integration"),
            ("qemu-guest-agent", "QEMU/KVM guest agent"),
            ("virtualbox-guest-utils-nox", "VirtualBox guest utilities"),
            ("hyperv", "Hyper-V guest tools"),
            ("usbutils / usb_modeswitch", "USB inspection + mode switching"),
            ("dmidecode", "DMI/SMBIOS hardware table dump"),
            ("bolt / plasma-thunderbolt", "Thunderbolt device management"),
            ("brltty / espeakup", "Braille + speech accessibility"),
        ],
    ),
]
