![Screenshot](screenshot.png)

# Easy Arch Linux

Easy Arch Linux is a lightweight, Arch-based distribution that stays close to upstream. It's built for ease of installation, allowing users to quickly set up and reproduce their development environment. It starts off stable, with the option to easily update to a rolling release using `sudo pacman -Syu`.

It comes with only the essential packages needed for any system. The desktop environment is a stripped-down, minimal version of KDE Plasma, designed to stay out of your way and let you get straight to work.  
**No bloat. No distractions.**


## 💽 How to Install Easy Arch Linux

1. **Download the ISO**  
   The ISO is hosted on **Google Drive** (GitHub does not allow files larger than 2 GB).
   
   **📥Link: [https://drive.google.com/file/d/18nclTLo05_KU7uOfYd_WTnI0LK--mGE6/view?usp=sharing](https://drive.google.com/file/d/18nclTLo05_KU7uOfYd_WTnI0LK--mGE6/view?usp=sharing)**

3. **Create a Bootable USB**  
   Use one of the following tools to write the ISO to a USB drive:
   - **[balenaEtcher](https://etcher.balena.io/)** (Windows/macOS/Linux)
   - **[Rufus](https://rufus.ie/en/)** (Windows only)
   - Or use the `dd` command (Linux/macOS):
     ```bash
     sudo dd if=easy_archlinux-2025.07.28-x86_64.iso of=/dev/sdX bs=4M status=progress && sync
     ```
     ⚠️ Replace `/dev/sdX` with your actual USB device (this will erase the disk).

4. **Boot from USB**  
   Reboot your machine and use your **BIOS/UEFI boot menu** to boot from the USB drive.

5. **Live Environment and Installation**  
   The ISO boots into a live session. A terminal window (Konsole) will appear, offering to begin disk installation.  
   You can either:
   - Use the live environment temporarily  
   - Or start the installation immediately by following the terminal prompts

## 🧰 How to Compile Easy Arch Linux

You can clone this repository and compile the ISO yourself. This requires an internet connection to download all the components needed to build the ISO.

Packages will be the latest version so there is a possibility for bugs/issues to appear unlike the provided ISO which was briefly examined before being uploaded.

There are two ways to compile the ISO:

## 🐋 Option 1: Compile Using Docker (Highly Recommended)

### 🪟 Windows
1. **Open CMD/Powershell as administrator and install WSL**
   ```
   wsl --install
   ```
2. **Install [Docker](https://www.docker.com/)**

3. **Open the Microsoft Store app, then search for and install Ubuntu**

4. **Open Ubuntu, then confirm Docker is working**
   ```
   docker --version
   ```

5. **Updates package index and install git**
   ```
   sudo apt update
   sudo apt install git
   ```

6. **Clone repository and enter directory**
   ```
   git clone https://github.com/devbyte1328/easy-arch-desktop-iso.git
   cd easy-arch-desktop-iso
   ```
   
6. **Build the Docker image**
   ```
   sudo docker build -t easyarch .
   ```
   
7. **Compile the ISO**
   ```
   sudo docker run --rm -t --privileged -v "$PWD/out:/build/out" easyarch
   ```
   
8. **(Optional) For debugging**
   ```
   { sudo docker build -t easyarch . && sudo docker run --rm -t --privileged -v "$PWD/out:/build/out" easyarch; } 2>&1 | tee logs.txt
   ```

9. **After compiling the ISO, navigate to File Explorer and retrieve the ISO**
   ```
   \\wsl$\Ubuntu\home\<your-username>\easy-arch-desktop-iso\out
   ```
   
### 🍎🐧 Linux/macOS
    
1. **Install [Docker](https://www.docker.com/)**

2. **Clone repository and enter directory**
   ```
   git clone https://github.com/devbyte1328/easy-arch-desktop-iso.git
   cd easy-arch-desktop-iso
   ```

3. **Build the Docker image**
   ```
   sudo docker build -t easyarch .
   ```

4. **Run the Docker container to compile the ISO**
   ```
   sudo docker run --rm -t --privileged -v "$PWD/out:/build/out" easyarch
   ```

5. **(Optional) For debugging**
   ```
   { sudo docker build -t easyarch . && sudo docker run --rm -t --privileged -v "$PWD/out:/build/out" easyarch; } 2>&1 | tee logs.txt
   ```

## 🖥️ Option 2: Compile Natively on Arch Linux or an Arch-based Distro (Not Recommended)

> ⚠️This method is not recommended because the script:
> - Installs packages directly to your system
> - Creates temporary build files
> - Leaves dependencies behind

Use Docker unless you know what you're doing.

1. **Clone repository and enter directory**
   ```
   git clone https://github.com/devbyte1328/easy-arch-desktop-iso.git
   cd easy-arch-desktop-iso
   ```

2. **Run the build script**
   ```
   sudo ./compile-iso.sh
   ```

3. **(Optional) For debugging**
   ```
   sudo ./compile-iso.sh 2>&1 | tee logs.txt
   ```
