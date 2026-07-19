"""The ordered build steps: assemble the archiso profile tree from the
config-as-Python modules, cache/stage the packages, and run mkarchiso.

This replaces the long body of the old compile.sh. Each `bar.step(...)` is one
milestone. Trivial emit steps are near-instant; the two giants (package cache,
mkarchiso) drive live sub-progress. Ownership handback and the PTY/signal
machinery live in build.py; this module is pure build logic.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import signal

from . import emit, packages, paths
from .config import fastfetch, installer, kde, locale, pacman, profile, system
from .progress import ProgressBar

# Weights: trivial emit steps = 1 unit; the two giants sized from real log spans.
# 23 trivial steps + package-cache(250) + mkarchiso(270). Keep in sync with steps below.
STEP_WEIGHTS = [0] + [1] * 23 + [250, 270]

# PGID of the currently-running mkarchiso child (0 = none). mkarchiso is spawned in
# its own session/process group so the signal handler can kill THAT group (and all
# its pacstrap descendants) without touching our own shell -- see build.on_signal.
_ACTIVE_CHILD_PGID = 0


def _sudo() -> list[str]:
    # `-n` (non-interactive) so a chown/unmount during Ctrl-C teardown after the
    # sudo timestamp expired fails fast instead of blocking on a password prompt.
    return [] if paths.is_root() else ["sudo", "-n"]


def kill_active_child(sudo: list[str]) -> None:
    """Kill the running mkarchiso child's process group (TERM then KILL). Root
    children (pacstrap under mkarchiso on a native run) are reaped via sudo."""
    pgid = _ACTIVE_CHILD_PGID
    if pgid <= 0:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pgid, sig)
        except (ProcessLookupError, PermissionError):
            pass
        if sudo:
            subprocess.run(sudo + ["kill", f"-{sig}", f"-{pgid}"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def run(bar: ProgressBar, offline: bool, reclaim_after_mkarchiso) -> Path:
    """Execute all steps; return the path to the built ISO. Raises on failure."""
    W = paths.WORKDIR
    airootfs = W / "airootfs"
    ea = airootfs / "root/azarch"  # the azarch payload dir baked into the ISO
    sudo = _sudo()

    # 1
    bar.step("Cleaning up previous build directory...")
    _unmount_worktree(sudo)
    paths.BUILDDIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(sudo + ["rm", "-rf", str(W)], check=False)
    W.mkdir(parents=True, exist_ok=True)
    os.chdir(W)

    # 2
    bar.step("Checking for build-host dependencies...")
    _check_host_deps(sudo, offline)

    # 3
    bar.step("Copying releng base into working directory...")
    _copy_releng(W)

    # 4
    bar.step("Adding custom bootloader entries and config files...")
    # Overwrite the releng UEFI entries in place (same filenames) rather than adding
    # differently-named ones alongside them -- otherwise the menu shows BOTH the stock
    # "Arch Linux install medium" entries AND ours, i.e. duplicated rows all reading
    # "Arch Linux". Writing over 01-archiso-linux.conf / 02-archiso-speech-linux.conf
    # replaces them with the rebranded Az'arch entries.
    emit.write_text(W / "efiboot/loader/entries/01-archiso-linux.conf", system.BOOT_UEFI_LINUX)
    emit.write_text(W / "efiboot/loader/entries/02-archiso-speech-linux.conf", system.BOOT_UEFI_SPEECH)
    emit.write_text(W / "syslinux/archiso_sys-linux.cfg", system.BOOT_BIOS_SYSLINUX)
    # Overlay the syslinux (BIOS) menu head so its `MENU TITLE` reads Az'arch instead
    # of the releng default "Arch Linux".
    emit.write_text(W / "syslinux/archiso_head.cfg", system.BOOT_BIOS_SYSLINUX_HEAD)

    # 5
    bar.step("Copying custom package list...")
    emit.copy_data("packages.x86_64", W / "packages.x86_64")

    # 6
    bar.step("Setting up users...")
    emit.write_text(airootfs / "etc/passwd", system.PASSWD)
    emit.write_text(airootfs / "etc/shadow", system.SHADOW, mode=0o600)
    emit.write_text(airootfs / "etc/gshadow", system.GSHADOW, mode=0o600)
    emit.write_text(airootfs / "etc/group", system.GROUP)

    # 7
    bar.step("Creating home directory and configuring permissions for SDDM autologin...")
    home = airootfs / "home/main"
    emit.mkdir(home)
    subprocess.run(sudo + ["chown", "-R", "1000:998", str(home)], check=False)

    # 8
    bar.step("Adding setup-locale script...")
    emit.write_exec(ea / "setup-locale.sh", locale.setup_locale_sh())

    # 9
    bar.step("Adding locale systemd service...")
    emit.write_text(airootfs / "etc/systemd/system/locale-setup.service", system.LOCALE_SETUP_SERVICE)

    # 10
    bar.step("Applying KDE minimal theme...")
    _emit_kde(airootfs, ea, home)

    # 10b
    bar.step("Applying azarch fastfetch logo...")
    _emit_fastfetch(ea, home)

    # 10c
    bar.step("Branding os-release as Az'arch Linux...")
    # Live ISO: the build pacman.conf NoExtracts usr/lib/os-release (config/pacman.py)
    # so the `filesystem` package's stock "Arch Linux" file never lands. We must NOT
    # pre-place our replacement in the airootfs overlay, though: mkarchiso copies the
    # overlay into the work root BEFORE pacstrap, and pacman's file-conflict check
    # (which runs before extraction and is NOT suppressed by NoExtract) then aborts
    # with "filesystem: usr/lib/os-release exists in filesystem". Instead we plant it
    # AFTER pacstrap via customize_airootfs.sh -- the same after-pacstrap ordering the
    # on-disk installer already uses (config/installer.py copies it into /mnt post-
    # pacstrap). The branded file is staged read-only under root/azarch/os-release and
    # the hook copies it into place inside the pacstrapped rootfs.
    emit.write_text(ea / "os-release", system.OS_RELEASE)
    # X11 Plasma session entry: also owned by a package (plasma-workspace), so it hits
    # the same pre-pacstrap conflict if overlaid directly. Stage it and let the hook
    # plant it post-pacstrap too. (NoExtract for it lives in config/pacman.py.)
    emit.write_text(ea / "plasma.desktop", system.PLASMA_DESKTOP)
    emit.write_exec(airootfs / "root/customize_airootfs.sh", system.CUSTOMIZE_AIROOTFS)
    # Overlay the releng `archiso` hostname with `azarch` (prompt + fastfetch title).
    emit.write_text(airootfs / "etc/hostname", system.HOSTNAME)

    # 11
    bar.step("Configuring pacman...")
    emit.write_text(airootfs / "etc/pacman.conf", pacman.installer_base_conf())

    # 12
    bar.step("Adding setup-pkgs script...")
    emit.write_exec(ea / "setup-pkgs.sh", installer.setup_pkgs_sh())

    # 13
    bar.step("Adding pkgs systemd service...")
    emit.write_text(airootfs / "etc/systemd/system/pkgs-setup.service", system.PKGS_SETUP_SERVICE)

    # 14
    bar.step("Adding SDDM config...")
    emit.write_text(airootfs / "etc/sddm.conf", system.SDDM_CONF)

    # 15
    bar.step("Configuring X11 session...")
    # NOTE: the actual session file is planted post-pacstrap by customize_airootfs.sh
    # (staged at root/azarch/plasma.desktop in step 10c) -- overlaying it here would
    # collide with plasma-workspace's copy during pacstrap. This step is retained as a
    # milestone; the SDDM autologin Session= key still points at plasma.desktop.

    # 16
    bar.step("Linking systemd services...")
    _link_services(airootfs)

    # 17
    bar.step("Setting up sudoers...")
    emit.write_text(airootfs / "etc/sudoers.d/00-rootpw", system.SUDOERS_ROOTPW, mode=0o440)
    emit.write_text(airootfs / "etc/sudoers.d/00-main", system.SUDOERS_MAIN, mode=0o440)

    # 18
    bar.step("Copying profile definition...")
    emit.write_exec(W / "profiledef.sh", profile.profiledef_sh())

    # 19
    bar.step("Setting up the ISO installer autostart...")
    emit.write_exec(home / "Desktop/azarch-iso-installer.sh", installer.installer_sh())
    emit.write_text(home / ".config/autostart/azarch-iso-install.desktop", installer.installer_desktop())

    # 20
    bar.step("Copying first-boot configuration...")
    emit.write_exec(ea / "first-boot-setup.sh", installer.first_boot_sh())
    emit.write_text(ea / "first-boot-setup.service", installer.first_boot_service())
    emit.write_text(ea / "first-boot-setup.conf", installer.first_boot_conf())

    # 21
    bar.step("Preparing the build pacman.conf (X11 session, cache)...")
    _write_build_pacman_conf(W, offline, bar)

    # 22 (giant)
    bar.step("Setting up packages for hard-drive installation...")
    packages.build_cache(W, paths.CACHEDIR, offline, bar.sub)
    bar.sub_done()
    bar._arm(); bar.draw()
    # stage the installer-side payload the on-disk installer needs
    emit.copy_data("packages.x86_64", ea / "packages.x86_64")
    emit.write_text(ea / "pacman-base-conf/pacman.conf", pacman.installer_base_conf())
    emit.write_text(ea / "pacstrap-azarch-conf/pacman.conf", pacman.installer_pacstrap_conf())
    emit.write_exec(ea / "chroot-setup.sh", installer.chroot_setup_sh())

    # 23 (giant)
    bar.step("Building ISO...")
    iso = _run_mkarchiso(sudo, W, bar, reclaim_after_mkarchiso)
    return iso


# --- helpers ---------------------------------------------------------------

def _unmount_worktree(sudo) -> None:
    aw = paths.AIROOTFS
    if not aw.is_dir():
        return
    for m in ("proc", "sys", "dev", "run"):
        p = aw / m
        if subprocess.run(["mountpoint", "-q", str(p)]).returncode == 0:
            subprocess.run(sudo + ["umount", "-lf", str(p)], check=False)
    subprocess.run(sudo + ["umount", "-R", str(aw)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def _check_host_deps(sudo, offline: bool) -> None:
    host_pkgs = ["archiso", "git", "base-devel", "go"]
    if subprocess.run(["pacman", "-Qq", *host_pkgs],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        print("    [+] Build-host dependencies already present, skipping sync (offline).")
        return
    if offline:
        sys.stderr.write(
            "[x] Missing build-host dependencies but the package cache is complete, so\n"
            "    this run must stay fully offline. Install them yourself:\n"
            f"    {'sudo ' if sudo else ''}pacman -Sy --needed {' '.join(host_pkgs)}\n"
            "    or re-run with FORCE_ONLINE=1 (or after 'git clean -Xdf').\n"
        )
        raise SystemExit(1)
    print("    [+] Installing missing build-host dependencies...")
    subprocess.run(sudo + ["pacman", "-Sy", "--noconfirm", "--needed", *host_pkgs], check=True)


def _copy_releng(W: Path) -> None:
    src = Path("/usr/share/archiso/configs/releng")
    if not src.is_dir():
        raise SystemExit(f"[x] archiso releng profile not found at {src}; is archiso installed?")
    emit.copy_tree(src, W)


def _emit_kde(airootfs: Path, ea: Path, home: Path) -> None:
    cfg = home / ".config"
    emit.write_text(cfg / "plasmashellrc", kde.PLASMASHELLRC)
    emit.write_text(cfg / "kwinrc", kde.KWINRC)
    emit.write_text(cfg / "plasma-org.kde.plasma.desktop-appletsrc", kde.APPLETSRC)
    emit.write_text(cfg / "menus/applications-kmenuedit.menu", kde.APPLICATIONS_MENU)
    emit.write_text(cfg / "kdeglobals", kde.KDEGLOBALS)
    # The two big upstream QML files stay verbatim data; the live ISO copies them
    # into the plasmoid via setup-pkgs. They live under root/azarch and kde/.
    emit.copy_data("kde/Footer.qml", ea / "Footer.qml")
    emit.copy_data("kde/main.qml", ea / "main.qml")
    kde_dir = ea / "kde"
    for name in ("Footer.qml", "main.qml"):
        emit.copy_data(f"kde/{name}", kde_dir / name)
    # the on-disk installer copies these KDE configs from root/azarch/kde too
    emit.write_text(kde_dir / "plasmashellrc", kde.PLASMASHELLRC)
    emit.write_text(kde_dir / "kwinrc", kde.KWINRC)
    emit.write_text(kde_dir / "plasma-org.kde.plasma.desktop-appletsrc", kde.APPLETSRC)
    emit.write_text(kde_dir / "applications-kmenuedit.menu", kde.APPLICATIONS_MENU)
    emit.write_text(kde_dir / "kdeglobals", kde.KDEGLOBALS)


def _emit_fastfetch(ea: Path, home: Path) -> None:
    """Write the azarch fastfetch config + Az' logo for the live user, and stage
    a copy under root/azarch/fastfetch so the on-disk installer can replant it
    into the installed user's ~/.config/fastfetch (parity with the KDE configs)."""
    cfg = home / ".config/fastfetch"
    emit.write_text(cfg / "config.jsonc", fastfetch.config_jsonc())
    emit.write_text(cfg / fastfetch.LOGO_FILENAME, fastfetch.logo_txt())
    # staged copy for the installer to plant on the installed system
    staged = ea / "fastfetch"
    emit.write_text(staged / "config.jsonc", fastfetch.config_jsonc())
    emit.write_text(staged / fastfetch.LOGO_FILENAME, fastfetch.logo_txt())


def _link_services(airootfs: Path) -> None:
    base = airootfs / "etc/systemd/system"
    emit.mkdir(base / "multi-user.target.wants")
    emit.mkdir(base / "graphical.target.wants")
    emit.link("/usr/lib/systemd/system/sddm.service", base / "graphical.target.wants/sddm.service")
    for svc in ("NetworkManager.service", "bluetooth.service", "org.cups.cupsd.service"):
        emit.link(f"/usr/lib/systemd/system/{svc}", base / f"multi-user.target.wants/{svc}")
    emit.link("/etc/systemd/system/locale-setup.service", base / "multi-user.target.wants/locale-setup.service")
    emit.link("/etc/systemd/system/pkgs-setup.service", base / "multi-user.target.wants/pkgs-setup.service")


def _switch_offline(W: Path, conf: str, localrepo: Path) -> None:
    """Drop stale partial downloads, rewrite to the local file:// repo, write it,
    and assert the rewrite actually landed (parity with the old bash guards)."""
    # A file:// directory listing must not trip over a zero-byte *.part left by an
    # interrupted -Sw; drop them first (harmless if none exist).
    for part in localrepo.glob("*.part"):
        part.unlink(missing_ok=True)
    conf = pacman.switch_to_local_repo(conf, str(localrepo))
    emit.write_text(W / "pacman.conf", conf)
    if "[pacstrap-azarch-repo]" not in conf:
        sys.stderr.write(
            "    [!] Offline conf rewrite did not inject the local repo -- check config/pacman.py.\n"
        )


def _write_build_pacman_conf(W: Path, offline: bool, bar: ProgressBar) -> None:
    """Write the profile pacman.conf mkarchiso's pacstrap uses. Injects the
    persistent CacheDir, and (offline) rewrites to the local file:// repo."""
    paths.PACSTRAP_CACHE.mkdir(parents=True, exist_ok=True)
    conf = pacman.build_profile_conf(cachedir=str(paths.PACSTRAP_CACHE) + "/")
    localrepo = paths.PKG_REPO
    if offline:
        print(f"    [+] Complete cache present -- building OFFLINE from {localrepo} (no mirror).")
        _switch_offline(W, conf, localrepo)
    else:
        _probe_and_maybe_switch(W, conf, localrepo, bar)


def _probe_and_maybe_switch(W: Path, conf: str, localrepo: Path, bar: ProgressBar) -> None:
    sudo = _sudo()
    probe = W / ".netprobe-db"
    subprocess.run(["rm", "-rf", str(probe)], check=False)
    (probe / "sync").mkdir(parents=True, exist_ok=True)
    # write the network-repo conf first so the probe uses the exact mirror set.
    emit.write_text(W / "pacman.conf", conf)
    ok = subprocess.run(
        sudo + ["pacman", "-Sy", "--config", str(W / "pacman.conf"), "--dbpath", str(probe),
                "--cachedir", str(probe), "--disable-sandbox", "--noconfirm"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    if ok:
        print("    [+] Mirrors reachable -- building online (new packages will be fetched).")
    elif paths.LOCALREPO_INDEX.exists():
        print(f"    [!] Mirrors unreachable -- building OFFLINE from {localrepo}.")
        _switch_offline(W, conf, localrepo)
    else:
        sys.stderr.write(
            f"    [!] Mirrors unreachable and no local repo cached at {localrepo} --\n"
            "        run once online to populate the cache, then offline rebuilds work.\n"
        )
    subprocess.run(["rm", "-rf", str(probe)], check=False)


def _run_mkarchiso(sudo, W: Path, bar: ProgressBar, reclaim_after) -> Path:
    # temp dir cleanup (matches the old "Cleaning up temp directory" step)
    subprocess.run(["rm", "-rf", str(W / ".temp")], check=False)
    env = dict(os.environ)
    # Fixes sporadic "xz uncompress failed with error code 9" (kept from old build).
    env["MKSQUASHFS_OPTIONS"] = "-processors 4"
    # Binary pipe on purpose: _drive_mkarchiso_progress wraps it in a TextIOWrapper
    # with newline="" so it can split on BOTH \r and \n (pacman redraws with \r).
    # text=True here would hand us a pre-decoded stream that TextIOWrapper rejects.
    # start_new_session=True puts mkarchiso (and its pacstrap children) in their OWN
    # process group so a Ctrl-C can group-kill THEM without hitting our shell.
    global _ACTIVE_CHILD_PGID
    proc = subprocess.Popen(
        sudo + ["mkarchiso", "-v", "-w", str(W / "work"), "-o", str(paths.BUILDDIR), str(W)],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
    )
    _ACTIVE_CHILD_PGID = proc.pid  # PID == PGID for a session leader
    try:
        _drive_mkarchiso_progress(proc, bar)
        rc = proc.wait()
    finally:
        _ACTIVE_CHILD_PGID = 0
    bar.sub_done()
    # immediate reclaim: unmount, then hand the work tree back while sudo is fresh.
    _unmount_worktree(sudo)
    reclaim_after()
    if rc != 0:
        raise SystemExit(f"[x] mkarchiso failed (exit {rc})")
    isos = sorted(paths.BUILDDIR.glob("*.iso"))
    if not isos:
        raise SystemExit("[x] ISO build failed: no .iso found in output/")
    return isos[0]


# pacman phase -> (base, span) sub-band within 20..820 for live mkarchiso progress.
_PACMAN_BANDS = {
    "checking keys in keyring": (20, 90),
    "checking package integrity": (110, 70),
    "loading package files": (180, 20),
    "checking for file conflicts": (200, 20),
    "checking available disk space": (220, 20),
    "installing": (240, 580),
    "upgrading": (240, 580),
    "reinstalling": (240, 580),
    "downgrading": (240, 580),
}


def _drive_mkarchiso_progress(proc, bar: ProgressBar) -> None:
    """Parse mkarchiso/pacstrap live output and drive the bar. pacman redraws its
    progress with carriage returns (not newlines), so we split on BOTH \\r and \\n
    to see each (N/M) frame live. Every line is echoed to stdout (so it scrolls in
    the region above the pinned bar) and appended to full.log."""
    import io
    import re

    frame = re.compile(
        r"\(\s*(\d+)/(\d+)\)\s+(" + "|".join(re.escape(k) for k in _PACMAN_BANDS) + r")"
    )
    inpac = False
    log = paths.FULL_LOG.open("a", encoding="utf-8", errors="replace")
    reader = io.TextIOWrapper(proc.stdout, encoding="utf-8", errors="replace", newline="")
    buf = ""

    def emit_line(line: str) -> None:
        nonlocal inpac
        if not line:
            return
        log.write(line + "\n")
        sys.stdout.write(line + "\n")
        if "Installing packages to" in line:
            inpac = True
            bar.sub(20)
        elif "Done! Packages installed" in line:
            inpac = False
            bar.sub(820)
        elif "Creating SquashFS image" in line:
            inpac = False
            bar.sub(840)
        elif "Creating checksum file" in line:
            bar.sub(930)
        elif "Creating ISO image" in line:
            bar.sub(960)
        elif inpac:
            m = frame.search(line)
            if m:
                n, mm, ph = int(m.group(1)), int(m.group(2)), m.group(3)
                base, span = _PACMAN_BANDS[ph]
                if mm > 0:
                    bar.sub(base + n * span // mm)

    try:
        while True:
            ch = reader.read(1)
            if not ch:
                break
            if ch in ("\n", "\r"):
                emit_line(buf)
                buf = ""
            else:
                buf += ch
        emit_line(buf)
    finally:
        log.flush()
        log.close()
