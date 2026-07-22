"""The ordered build steps: assemble the archiso profile tree from the
config-as-Python modules, cache/stage the packages, and run mkarchiso.

This replaces the long body of the old compile.sh. Each `bar.step(...)` is one
milestone, named for the archiso/pacman/systemd artifact it produces. Trivial
overlay-emit steps are near-instant; the two giants (package cache, mkarchiso)
drive live sub-progress. Ownership handback and the PTY/signal machinery live in
build.py; this module is pure build logic.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import signal

from . import emit, packages, paths
from .config import fastfetch, installer, locale, pacman, profile, system
from .progress import ProgressBar

# Weights: setup/emit steps carry real weight so the bar visibly advances through
# them (at weight 1 they were ~2% of the whole bar and looked frozen); the two giants
# are still the bulk, sized from real log spans. Keep in sync with steps below:
# len(STEP_WEIGHTS) - 1 MUST equal the number of bar.step() calls in run(), and the
# final two weights belong to the package-cache and mkarchiso giants, in that order.
STEP_WEIGHTS = [0] + [8] * 11 + [250, 270]

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

    # 1 -- Reset build workspace
    bar.step("Reset build workspace")
    _unmount_worktree(sudo)
    paths.BUILDDIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(sudo + ["rm", "-rf", str(W)], check=False)
    W.mkdir(parents=True, exist_ok=True)
    os.chdir(W)

    # 2 -- Sync host toolchain
    bar.step("Sync host toolchain")
    _check_host_deps(sudo, offline)

    # 3 -- Scaffold releng profile
    bar.step("Scaffold releng profile")
    _copy_releng(W)

    # 4 -- Brand boot menus (systemd-boot + syslinux)
    bar.step("Brand boot menus (systemd-boot, syslinux)")
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

    # 5 -- Stage pacstrap package manifest
    bar.step("Stage pacstrap package manifest")
    emit.copy_data("packages.x86_64", W / "packages.x86_64")

    # 6 -- Provision airootfs accounts (users/groups + /home/main, chowned for the
    # autologin `main` user the getty drops straight into on the live console).
    bar.step("Provision airootfs accounts (console autologin)")
    emit.write_text(airootfs / "etc/passwd", system.PASSWD)
    emit.write_text(airootfs / "etc/shadow", system.SHADOW, mode=0o600)
    emit.write_text(airootfs / "etc/gshadow", system.GSHADOW, mode=0o600)
    emit.write_text(airootfs / "etc/group", system.GROUP)
    home = airootfs / "home/main"
    emit.mkdir(home)
    subprocess.run(sudo + ["chown", "-R", "1000:998", str(home)], check=False)

    # 7 -- Overlay branding and locale into airootfs.
    # One coherent overlay-population act: locale setup-script + service, the fastfetch
    # logo, and the os-release/hostname rebrand.
    bar.step("Overlay branding and locale")

    # locale: first-run setup script + the systemd unit that runs it.
    emit.write_exec(ea / "setup-locale.sh", locale.setup_locale_sh())
    emit.write_text(airootfs / "etc/systemd/system/locale-setup.service", system.LOCALE_SETUP_SERVICE)

    # the azarch fastfetch logo/config for the live (and installed) user.
    _emit_fastfetch(ea, home)

    # os-release rebrand:
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
    emit.write_exec(airootfs / "root/customize_airootfs.sh", system.CUSTOMIZE_AIROOTFS)
    # Overlay the releng `archiso` hostname with `azarch` (prompt + fastfetch title).
    emit.write_text(airootfs / "etc/hostname", system.HOSTNAME)

    # 8 -- Stage installed-system pacman and pkgs service.
    # The package-management unit of the installed system: its /etc/pacman.conf, the
    # live-session setup-pkgs.sh, and the pkgs-setup.service that runs it.
    bar.step("Stage installed-system pacman and pkgs service")
    emit.write_text(airootfs / "etc/pacman.conf", pacman.installer_base_conf())
    emit.write_exec(ea / "setup-pkgs.sh", installer.setup_pkgs_sh())
    emit.write_text(airootfs / "etc/systemd/system/pkgs-setup.service", system.PKGS_SETUP_SERVICE)

    # 9 -- Enable systemd units and sudoers policy.
    # Activation/policy at profile finalization: the *.target.wants symlinks that enable
    # the units, plus the sudoers.d drop-ins.
    bar.step("Enable systemd units and sudoers policy")
    _link_services(airootfs)
    emit.write_text(airootfs / "etc/sudoers.d/00-rootpw", system.SUDOERS_ROOTPW, mode=0o440)
    emit.write_text(airootfs / "etc/sudoers.d/00-main", system.SUDOERS_MAIN, mode=0o440)

    # 10 -- Emit profiledef and installer payload.
    # profiledef.sh (archiso metadata at the PROFILE ROOT, not airootfs), the installer
    # script, and the first-boot script/service/conf. The old XDG-autostart .desktop
    # (which launched the installer in konsole) was dropped with the desktop -- the ISO
    # now boots to a console, so the installer is run from the shell instead.
    bar.step("Emit profiledef and installer payload")
    emit.write_exec(W / "profiledef.sh", profile.profiledef_sh())
    emit.write_exec(home / "Desktop/azarch-iso-installer.sh", installer.installer_sh())
    emit.write_exec(ea / "first-boot-setup.sh", installer.first_boot_sh())
    emit.write_text(ea / "first-boot-setup.service", installer.first_boot_service())
    emit.write_text(ea / "first-boot-setup.conf", installer.first_boot_conf())

    # 11 -- Resolve build pacman.conf and mirrors.
    # Writes the pacstrap/mkarchiso build pacman.conf, injects the persistent CacheDir,
    # probes mirrors, and switches to the local file:// repo when offline. A distinct
    # pacman-prep stage that gates the cache download below.
    bar.step("Resolve build pacman.conf and mirrors")
    _write_build_pacman_conf(W, offline, bar)

    # 12 -- Warm pacman cache and stage installer payload (GIANT, weight 250).
    # pacman -Sw builds/indexes the local repo (drives bar.sub sub-progress), then the
    # on-disk installer's package manifest + pacman confs + chroot-setup.sh are staged.
    bar.step("Warm pacman cache and stage installer payload")
    packages.build_cache(W, paths.CACHEDIR, offline, bar.sub, bar.phase)
    bar.sub_done()
    bar._arm(); bar.draw()
    # stage the installer-side payload the on-disk installer needs
    emit.copy_data("packages.x86_64", ea / "packages.x86_64")
    emit.write_text(ea / "pacman-base-conf/pacman.conf", pacman.installer_base_conf())
    emit.write_text(ea / "pacstrap-azarch-conf/pacman.conf", pacman.installer_pacstrap_conf())
    emit.write_exec(ea / "chroot-setup.sh", installer.chroot_setup_sh())

    # 13 -- Assemble ISO (GIANT, weight 270).
    # mkarchiso: pacstrap into airootfs, mksquashfs, checksum, build the .iso
    # (drives bar.sub sub-progress via _drive_mkarchiso_progress).
    bar.step("Assemble ISO (mkarchiso)")
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


def _emit_fastfetch(ea: Path, home: Path) -> None:
    """Write the azarch fastfetch config + Az' logo for the live user, and stage
    a copy under root/azarch/fastfetch so the on-disk installer can replant it
    into the installed user's ~/.config/fastfetch."""
    cfg = home / ".config/fastfetch"
    emit.write_text(cfg / "config.jsonc", fastfetch.config_jsonc())
    emit.write_text(cfg / fastfetch.LOGO_FILENAME, fastfetch.logo_txt())
    # staged copy for the installer to plant on the installed system
    staged = ea / "fastfetch"
    emit.write_text(staged / "config.jsonc", fastfetch.config_jsonc())
    emit.write_text(staged / fastfetch.LOGO_FILENAME, fastfetch.logo_txt())


def _link_services(airootfs: Path) -> None:
    # Console-only live medium: no display manager, no graphical.target. The archiso
    # releng base already autologins on tty1, so we only enable the multi-user daemons
    # and the two azarch oneshots. (KDE/SDDM and graphical.target.wants were removed in
    # the overhaul; a desktop/WM is layered back on later, not here.)
    base = airootfs / "etc/systemd/system"
    emit.mkdir(base / "multi-user.target.wants")
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
    # stdin from /dev/null: pacstrap under mkarchiso hits the `xorg` package group and
    # prints "Enter a selection (default=all):" on stdin. With no input it stalls for a
    # minute before defaulting; feeding EOF makes it take default=all immediately
    # instead of hanging.
    proc = subprocess.Popen(
        sudo + ["mkarchiso", "-v", "-w", str(W / "work"), "-o", str(paths.BUILDDIR), str(W)],
        env=env, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
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

    # Heartbeat: pacman/mksquashfs suppress their (N/M) progress frames when their
    # output is not a TTY (it is a pipe here), so whole phases -- pacstrap install and
    # the minute-long SquashFS pack -- produce many log lines but no parseable frame,
    # and the bar froze between milestone jumps. Between two milestones we creep toward
    # (but never reach) the next milestone, one notch per output line, so the bar keeps
    # visibly moving even with no frames. `hb` holds (floor, ceil) for the live phase.
    hb = {"floor": 0, "ceil": 0, "at": 0}

    def creep() -> None:
        # asymptotic: close ~1/16 of the remaining gap to the ceiling per line.
        room = hb["ceil"] - max(hb["at"], hb["floor"])
        if room > 0:
            hb["at"] = max(hb["at"], hb["floor"]) + max(1, room // 16)
            bar.sub(hb["at"])

    def phase_span(floor: int, ceil: int) -> None:
        hb["floor"], hb["ceil"], hb["at"] = floor, ceil, floor

    def emit_line(line: str) -> None:
        nonlocal inpac
        if not line:
            return
        log.write(line + "\n")           # full line to the log
        sys.stdout.write(bar._clip(line) + "\n")  # clipped echo so it fits the screen
        if "Installing packages to" in line:
            inpac = True
            bar.sub(20)
            bar.phase("pacstrap: installing packages into airootfs")
            phase_span(20, 810)   # creep across the install phase, stop short of 820
        elif "Done! Packages installed" in line:
            inpac = False
            bar.sub(820)
            bar.phase("pacstrap done, running customize hooks")
            phase_span(840, 930)  # next visible work is SquashFS; creep toward it
        elif "Creating SquashFS image" in line:
            inpac = False
            bar.sub(840)
            bar.phase("mksquashfs: compressing root filesystem (slow)")
            phase_span(840, 925)  # the long silent pack: creep so the minute animates
        elif "Creating checksum file" in line:
            bar.sub(930)
            bar.phase("writing SquashFS checksum")
            phase_span(930, 958)
        elif "Creating ISO image" in line:
            bar.sub(960)
            bar.phase("xorriso: writing bootable ISO image")
            phase_span(960, 995)
        elif inpac and (m := frame.search(line)):
            n, mm, ph = int(m.group(1)), int(m.group(2)), m.group(3)
            base, span = _PACMAN_BANDS[ph]
            if mm > 0:
                bar.sub(base + n * span // mm)
        else:
            # no milestone, no frame -- keep the bar alive within the current phase.
            creep()

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
