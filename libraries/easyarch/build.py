"""Build entrypoint: `python3 -m easyarch.build`.

Invoked by the thin compile.sh shim AFTER it has set up the PTY (via util-linux
`script`) and primed sudo. This module owns the high-level flow:

  * resolve the cache-first offline policy (BUILD_OFFLINE)
  * start the sudo keepalive + continuous ownership reclaim
  * run the ordered steps (steps.run) with a live progress bar
  * on ANY exit (success / error / Ctrl-C) restore the terminal, unmount the work
    tree, and hand cache/ output/ logs/ back to the host user -- so nothing is
    ever left root-owned and locked.

The heavy PTY/signal nuance the old bash script needed (re-exec on a PTY, group
kills of root children) is split: the PTY + sudo prime stay in compile.sh; here
we handle SIGINT/SIGTERM by terminating the child process group and running the
same teardown.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import threading

from . import paths, steps
from .ownership import Ownership
from .progress import ProgressBar


def _sudo() -> list[str]:
    return [] if paths.is_root() else ["sudo", "-n"]


def cache_is_complete() -> bool:
    """The cache-first verdict: a COMPLETE cache => build with zero server contact.
    Complete = local repo index symlink + at least one indexed pkg + synced DBs.
    FORCE_ONLINE=1 overrides (re-fetch without wiping)."""
    if os.environ.get("FORCE_ONLINE", "0") == "1":
        return False
    if not paths.LOCALREPO_INDEX.exists():
        return False
    if not any(paths.PKG_REPO.glob("*.pkg.tar.zst")):
        return False
    if not paths.PKG_SYNC_DB.is_dir() or not any(paths.PKG_SYNC_DB.glob("*.db")):
        return False
    return True


class SudoKeepalive:
    """Keep the sudo timestamp warm across the long build so the trap/immediate
    `sudo -n chown` still works past sudo's short timeout. No-op when root."""

    def __init__(self) -> None:
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if paths.is_root():
            return

        def loop() -> None:
            while not self._stop.wait(60):
                if subprocess.run(["sudo", "-n", "-v"],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
                    return

        self._thread = threading.Thread(target=loop, name="sudo-keepalive", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()


def _stale_cache_notice(offline: bool) -> None:
    if not offline:
        return
    idx = paths.LOCALREPO_INDEX_TAR
    try:
        if idx.exists() and paths.PACKAGES_FILE.stat().st_mtime > idx.stat().st_mtime:
            sys.stderr.write(
                "[!] packages.x86_64 is newer than the cached package index. If you ADDED\n"
                "    packages, this offline build won't have them and pacstrap may fail with\n"
                "    'target not found'. Re-run with FORCE_ONLINE=1 (or 'git clean -Xdf').\n"
            )
    except OSError:
        pass


def main() -> int:
    paths.LOGDIR.mkdir(parents=True, exist_ok=True)
    paths.CACHEDIR.mkdir(parents=True, exist_ok=True)

    offline = cache_is_complete()
    _stale_cache_notice(offline)

    bar = ProgressBar(steps.STEP_WEIGHTS)
    own = Ownership(_sudo())
    keep = SudoKeepalive()

    # SAFEGUARD 1: startup reclaim (recovers a tree left by a SIGKILL'd prior run).
    own.reclaim_full()
    keep.start()
    own.start_continuous()

    _torn_down = threading.Event()

    def teardown() -> None:
        # Re-entrancy guard: signal + normal/error exit paths must not double-run
        # the chown/unmount (mirrors the old _HANDED_BACK / _KILLED flags).
        if _torn_down.is_set():
            return
        _torn_down.set()
        keep.stop()
        own.stop_continuous()
        steps.kill_active_child(_sudo())  # kill mkarchiso's OWN group, not ours
        steps._unmount_worktree(_sudo())
        bar.cleanup()
        own.reclaim_full()  # SAFEGUARD final

    def on_signal(signum, _frame) -> None:
        # Kill ONLY the mkarchiso child's process group (it is spawned in its own
        # session, see steps._run_mkarchiso), never our own group -- signalling our
        # own group would re-enter this handler and could interrupt teardown
        # mid-chown, leaving cache/build root-owned (the exact old-bash hazard).
        teardown()
        os._exit(130)

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    bar.init()
    try:
        iso = steps.run(bar, offline, reclaim_after_mkarchiso=own.reclaim_full)
    except SystemExit as e:
        teardown()
        msg = str(e)
        if msg and not msg.isdigit():
            sys.stderr.write(msg + "\n")
        return e.code if isinstance(e.code, int) else 1
    except Exception as e:
        teardown()
        sys.stderr.write(f"[x] Build failed: {e}\n")
        return 1

    bar.subfrac = 1000
    bar.finalize()
    iso_size = subprocess.run(["du", "-h", str(iso)], capture_output=True, text=True).stdout.split("\t")[0]
    iso_path = f"output/{iso.name}" if paths.in_docker() else str(iso)
    line = f"\n[ {bar.total_steps}/{bar.total_steps} ] [OK] ISO built successfully: {iso_path}"
    if iso_size:
        line += f" ({iso_size})"
    print(line)
    with paths.STEPS_LOG.open("a") as f:
        f.write(line + "\n")
    if paths.in_docker():
        print(f"           The ISO is at {iso_path} on your host (NOT build/output/).")

    teardown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
