# 🐧 Arch Linux Setup - One Command Installer

![Screenshot of Installed KDE Desktop](screenshot.png)

A fully automated Arch Linux installation script designed for speed, simplicity, and a complete developer environment out-of-the-box.

This script sets up:
- A full Arch Linux system with KDE Plasma desktop
- Display drivers (NVIDIA, AMD, Intel, or VirtualBox)
- Essential developer tools and apps (yay, Brave, Neovim, GIMP, OBS, Docker, etc.)
- Smart timezone & language detection
- Custom KDE configuration, autostart scripts, theming, and more

---

## 🚀 Quick Start

1. Boot into the **latest Arch Linux ISO**.
2. Connect to the internet.
3. Run one of the following commands:

### ✅ Stable Branch
```bash
curl -O https://raw.githubusercontent.com/devbyte1328/arch-setup/refs/heads/stable/setup.sh && chmod +x setup.sh && ./setup.sh
```

### 🧱 Master Branch (Default)
```bash
curl -O https://raw.githubusercontent.com/devbyte1328/arch-setup/refs/heads/master/setup.sh && chmod +x setup.sh && ./setup.sh
```

---

## ⚙️ What It Does

- **Auto-detects** and wipes the largest unmounted disk
- Sets up **EFI partitions** and installs GRUB bootloader
- Installs KDE Plasma + essential desktop utilities
- Configures timezone, locale, and keyboard layout automatically based on IP
- Installs development tools, desktop software, and audio/video utilities
- Detects and installs appropriate GPU drivers (NVIDIA, AMD, Intel, VirtualBox)
- Enables autologin, Docker, NetworkManager, and SDDM
- Customizes KDE desktop and installs autostart scripts
- Applies Brave browser config, Konsole colorscheme, and disables screen locking

---

## 🧑‍💻 Default Users

| User  | Password |
|-------|----------|
| `root` | `root`   |
| `main` | *(no password, set it after boot)* |

📝 A script will appear on the Desktop to help you set the password after first boot.

---

## 📦 Included Software

- **Desktop Environment**: KDE Plasma, SDDM
- **Display Drivers**: auto-detected (NVIDIA, AMD, Intel, VirtualBox)
- **Essentials**: `git`, `base-devel`, `yay`, `curl`, `neovim`, `vim`, `ufw`, `dialog`, `unzip`
- **Desktop Apps**: Brave, GIMP, LibreOffice, OBS, Blender, Openshot, RedoT, Neofetch, Konsole, KCalc, Gwenview, Dolphin, etc.
- **Networking**: NetworkManager, nm-connection-editor, xclip, qbittorrent
- **Audio**: PipeWire, PulseAudio, ALSA, Pavucontrol
- **Virtualization**: VirtualBox (guest additions if VM is detected)
- **KDE Customizations**: panel layout, themes, Konsole color scheme, wallpapers blacked out for performance/look

---

## 🛠 Branches

- `master`: Default installation, always latest packages
- `stable`: Frozen package versions from a known-good date (2025/04/10)
- `test`: Development branch for new features or experimental changes

---

## 📁 Repo Structure

```bash
.
├── setup.sh                  # Main install script
├── screenshot.png            # Desktop preview
└── conf/
    ├── kde/                  # KDE configs and layouts
    ├── brave/                # Brave browser config
    ├── pacman/               # pacman.conf overrides
    └── system/               # System-related scripts
```

---

## ⚠️ Warning

> ⚠️ This script will **erase your disk** and install Arch Linux automatically. Be sure you're using the correct machine and you’ve backed up your data.

---

## 📝 License

MIT License

---

Made with ☕ and Arch 🐧 by [devbyte1328](https://github.com/devbyte1328)
