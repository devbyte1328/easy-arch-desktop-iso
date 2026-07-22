# Az'arch


<table width="100%">
<thead>
<tr><th align="left">🚧 UNDER CONSTRUCTION</th></tr>
</thead>
<tbody>
<tr><td>

This is a year-old, neglected, poorly put-together project that is undergoing a massive overhaul. Nothing works correctly yet, so please come back later.

</td></tr>
</tbody>
</table>


## 💽 Install

1. **Download the ISO**  
   The ISO is hosted on **Google Drive** (GitHub does not allow files larger than 2 GB).
   
   **📥Link: [https://drive.google.com/file/d/18nclTLo05_KU7uOfYd_WTnI0LK--mGE6/view?usp=sharing](https://drive.google.com/file/d/18nclTLo05_KU7uOfYd_WTnI0LK--mGE6/view?usp=sharing)**

2. **Create a Bootable USB**  
   Use one of the following tools to write the ISO to a USB drive:
   - **[balenaEtcher](https://etcher.balena.io/)** (Windows/macOS/Linux)
   - **[Rufus](https://rufus.ie/en/)** (Windows only)
   - `dd` command (Linux/macOS):
     ```bash
     sudo dd if=azarch-2025.07.28-x86_64.iso of=/dev/sdX bs=4M status=progress && sync
     ```
     ⚠️ Replace `/dev/sdX` with your actual USB device (this will erase the disk).

3. **Boot from USB**  
   Reboot your machine and use your **BIOS/UEFI boot menu** to boot from the USB drive.

4. **Live Session and Installation**  
   <table width="100%">
   <thead>
   <tr><th align="left">ℹ️ NOTE</th></tr>
   </thead>
   <tbody>
   <tr><td>

   Some considerations when using the live session:
   - Reserves 4 GB of RAM.
   - Runs entirely from RAM, nothing gets saved after reboot.
   - Uses a generic open-source graphics driver.

   </td></tr>
   </tbody>
   </table>

   The ISO boots into a live session and automatically launches the Az'arch
   installer, which is powered by **Calamares**.

   From the live session you can:
   - Install Az'arch.
   - Perform machine rescue tasks.
   - Do general work.

## 🧰 Compile

You can clone this repository and compile the ISO yourself. The **first** build
needs an internet connection to download every component that goes into the ISO;
after that everything is cached and rebuilds run fully offline.

**Build with Docker.** The ISO is assembled with `mkarchiso`, which resolves the
ISO's package list against the build host's Arch Linux repositories. That means
the build only works on a genuine Arch userland with the real Arch `core`,
`extra`, and `multilib` repositories. On anything else those repositories are
wrong or missing and the build fails with errors like
`target not found: archinstall` or endless kernel-provider prompts.

Docker sidesteps all of that: the image is `archlinux:latest`, so the build runs
inside real Arch no matter what machine you are on.

### 🐧 Linux

1. **Install Docker and Git** using your distro's package manager, for example:
   - Arch-based: `sudo pacman -S --needed docker git`
   - Debian/Ubuntu: `sudo apt update && sudo apt install docker.io git`
   - Fedora: `sudo dnf install docker git`
2. **Start the Docker service**
   ```
   sudo systemctl enable --now docker
   ```

### 🍎 macOS

1. **Install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/)** and launch it (wait until the whale icon says Docker is running).
2. **Install Git** if you don't have it — it ships with the Xcode command line tools:
   ```
   xcode-select --install
   ```

### 🪟 Windows

1. **Open PowerShell as Administrator and install WSL2**
   ```
   wsl --install
   ```
   Reboot if prompted.
2. **Install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)**, then in its settings enable **"Use the WSL 2 based engine"**.
3. **Open your WSL distro** (e.g. Ubuntu from the Start menu) and confirm Docker works:
   ```
   docker --version
   ```
4. **Install Git inside WSL**
   ```
   sudo apt update && sudo apt install git
   ```

### 🐋 Compile ISO

Once Docker is installed and running, the steps are the same everywhere.

1. **Clone the repository and enter it**
   ```
   git clone https://github.com/michaelilgiaev/azarch.git
   cd azarch
   ```

2. **Build the Docker image** (creates the Arch build environment)
   ```
   sudo docker build -t azarch .
   ```

3. **Compile the ISO.** `--privileged` is required — `mkarchiso` mounts
   `proc`/`sys`/`dev` and uses loop devices. The finished ISO is written directly
   to the `output/` folder, downloaded packages are kept in `cache/` so re-runs
   don't re-download several GB every time, and build logs land in `logs/`.
   ```
   sudo docker run --rm -it --init --privileged \
     -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
     -v "$PWD/cache:/build/cache" \
     -v "$PWD/output:/build/output" \
     -v "$PWD/logs:/build/logs" \
     azarch
   ```

4. **Collect the ISO.** After the build finishes, the ISO is in `output/`:
   ```
   ls output/*.iso
   ```
   - **Windows (WSL):** the same folder is reachable from File Explorer at
     `\\wsl$\<distro>\home\<your-username>\azarch\output`.


- **Wipe the cache** to force a fresh, fully-online rebuild:
  ```
  git clean -Xdf        # deletes cache/, output/, logs/ (all git-ignored)
  ```
