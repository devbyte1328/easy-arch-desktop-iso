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

3. **Create a Bootable USB**  
   Use one of the following tools to write the ISO to a USB drive:
   - **[balenaEtcher](https://etcher.balena.io/)** (Windows/macOS/Linux)
   - **[Rufus](https://rufus.ie/en/)** (Windows only)
   - Or use the `dd` command (Linux/macOS):
     ```bash
     sudo dd if=azarch-2025.07.28-x86_64.iso of=/dev/sdX bs=4M status=progress && sync
     ```
     ⚠️ Replace `/dev/sdX` with your actual USB device (this will erase the disk).

4. **Boot from USB**  
   Reboot your machine and use your **BIOS/UEFI boot menu** to boot from the USB drive.

5. **Live Environment and Installation**  
   The ISO boots to a console (autologin, no desktop yet — the desktop is being
   reworked as part of the overhaul). From the shell you can either:
   - Use the live environment temporarily  
   - Or start the installation by running the installer script on the Desktop:
     `sudo ~/Desktop/azarch-iso-installer.sh`

## 🧰 Compile

You can clone this repository and compile the ISO yourself. The **first** build
needs an internet connection to download every component that goes into the ISO;
after that everything is cached and rebuilds run fully offline (see
[Offline rebuilds from cache](#-offline-rebuilds-from-cache)).

> **Project layout.** The build is Python. Everything that goes into the ISO is
> authored in `libraries/azarch/` (the config files are Python modules holding
> their content as variables) and emitted into the archiso profile tree by
> `python3 -m azarch.build`. `compile.sh` is a thin shim that sets up the PTY +
> sudo and hands off to it. The main user-facing knob is the plain data file
> `libraries/data/packages.x86_64` (the package list).

Packages are pulled at their latest version, so the ISO you build may contain
bugs the pre-built download does not (that one was briefly examined before being
uploaded).

**Build with Docker.** The ISO is assembled with `mkarchiso`, which resolves the
ISO's package list against the build host's Arch Linux repositories. That means
the build only works on a genuine Arch userland with the real Arch `core`,
`extra`, and `multilib` repos. On anything else — Manjaro, EndeavourOS, Ubuntu,
Fedora, macOS, Windows — those repos are wrong or missing and the build fails
with errors like `target not found: archinstall` or endless kernel-provider
prompts.

Docker sidesteps all of that: the image is `archlinux:latest`, so the build runs
inside real Arch no matter what machine you are on. **Follow the steps for your
OS to install Docker, then the shared build steps are identical everywhere.**

### 🐧 Linux

1. **Install Docker and Git** using your distro's package manager, for example:
   - Arch-based: `sudo pacman -S --needed docker git`
   - Debian/Ubuntu: `sudo apt update && sudo apt install docker.io git`
   - Fedora: `sudo dnf install docker git`
2. **Start the Docker service**
   ```
   sudo systemctl enable --now docker
   ```
3. Continue with **[Build the ISO](#-build-the-iso-all-platforms)** below.

### 🍎 macOS

1. **Install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/)** and launch it (wait until the whale icon says Docker is running).
2. **Install Git** if you don't have it — it ships with the Xcode command line tools:
   ```
   xcode-select --install
   ```
3. Continue with **[Build the ISO](#-build-the-iso-all-platforms)** below.
   (On macOS you can drop the `sudo` in front of the `docker` commands.)

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
5. Continue with **[Build the ISO](#-build-the-iso-all-platforms)** below, running the commands **inside your WSL terminal**. (With Docker Desktop you can usually drop the `sudo`.)

### 🐋 Build the ISO (all platforms)

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
   `--init` runs the container under tini as PID 1. Without it the build's PID 1
   is the `script` logging process, and the kernel drops unhandled signals to
   PID 1 / never reaps orphans, so **Ctrl-C** leaves the container hanging with
   the download/build still running. With tini forwarding signals and reaping
   orphans, Ctrl-C tears the whole build down promptly.

   The `-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)"` flags hand the finished
   `output/` (incl. the `.iso`), the `cache/`, and `logs/` back to **your** user
   when the build exits — on success, on failure, or on Ctrl-C — so nothing is
   left `root:root` and you can read/delete it without `sudo`. These flags are
   **required** for the handback: the host user id cannot be detected from inside
   the container. If you omit them the build still produces the ISO but prints a
   warning and leaves `output/ cache/ logs/` root-owned (you'd then need `sudo` to
   delete them).

4. **Collect the ISO.** After the build finishes, the ISO is in `output/`:
   ```
   ls output/*.iso
   ```
   - **Windows (WSL):** the same folder is reachable from File Explorer at
     `\\wsl$\<distro>\home\<your-username>\azarch\output`.

   Every run already writes its full build log to `logs/` (a complete `full.log`
   and a milestone-only `steps.log`), so there is no separate step to capture it.

### 📦 Offline rebuilds from cache

Once you have built the ISO successfully at least once, the `cache/` folder holds
every package the build needs (several GB), plus the synced package databases and
a local package index. From then on **you can rely entirely on the cache**: as
long as `cache/` is intact, the build contacts **no server at all** — no database
sync, no download, not even a connectivity probe. It builds straight from the
local cache, so rebuilds work fully offline and are much faster.

The mirrors are only contacted again when you explicitly ask for it:

- **Wipe the cache** to force a fresh, fully-online rebuild:
  ```
  git clean -Xdf        # deletes cache/, output/, logs/ (all git-ignored)
  ```
  (Or just `rm -rf cache/` to clear only the package cache.)
- **Refresh without wiping** — pull the latest upstream package versions while
  keeping the cache — by passing `-e FORCE_ONLINE=1` to the build:
  ```
  sudo docker run --rm -it --init --privileged \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -e FORCE_ONLINE=1 \
    -v "$PWD/cache:/build/cache" \
    -v "$PWD/output:/build/output" \
    -v "$PWD/logs:/build/logs" \
    azarch
  ```

> ⚠️ **If you edit `libraries/data/packages.x86_64` to add packages** while a full cache exists,
> the offline build won't have the new packages and may fail. Rebuild with
> `FORCE_ONLINE=1` (or wipe the cache first) so they get fetched. The build prints
> a warning when it detects the package list is newer than the cache.

> 💡 The build downloads several GB of packages. The `-v "$PWD/cache:/build/cache"`
> mount keeps those downloads on your machine between runs, so a rebuild only
> fetches what changed instead of everything again.
