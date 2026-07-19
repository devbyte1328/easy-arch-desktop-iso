"""Filesystem layout for the build.

Mirrors the directory scheme the old compile.sh used, so the Docker bind mounts
(cache/ output/ logs/) and the on-disk artifacts land in exactly the same places:

  REPODIR/                 repo root (where compile.sh lives)
    libraries/data/        verbatim data files (packages.x86_64, big QML)
    cache/                 persistent download cache (git-ignored, survives builds)
      build/               WORKDIR: disposable mkarchiso profile+scratch tree
      pkgs/                persistent package repo + synced DBs (the offline store)
      pacman-pkg/          pacstrap CacheDir injected into the profile pacman.conf
    output/                BUILDDIR: the finished .iso lands here
    logs/                  full.log + steps.log
"""

from __future__ import annotations

import os
from pathlib import Path

# libraries/azarch/paths.py -> repo root is three parents up.
REPODIR = Path(__file__).resolve().parents[2]

LIBDIR = REPODIR / "libraries"
DATADIR = LIBDIR / "data"
ASSETSDIR = REPODIR / "assets"

CACHEDIR = REPODIR / "cache"
BUILDDIR = REPODIR / "output"
LOGDIR = REPODIR / "logs"
WORKDIR = CACHEDIR / "build"

# Persistent package stores (the offline-rebuild cache).
PKG_REPO = CACHEDIR / "pkgs" / "repo"
PKG_DB = CACHEDIR / "pkgs" / "db"
PKG_SYNC_DB = PKG_DB / "sync"
LOCALREPO_INDEX = PKG_REPO / "pacstrap-azarch-repo.db"
LOCALREPO_INDEX_TAR = PKG_REPO / "pacstrap-azarch-repo.db.tar.gz"

# pacstrap's CacheDir, injected into the profile pacman.conf so the ~1200 live-ISO
# packages are reused across builds instead of re-downloaded.
PACSTRAP_CACHE = CACHEDIR / "pacman-pkg"

# Logs.
FULL_LOG = LOGDIR / "full.log"
STEPS_LOG = LOGDIR / "steps.log"

# Verbatim data files.
PACKAGES_FILE = DATADIR / "packages.x86_64"

# Inside the archiso profile tree, the airootfs root and the azarch payload dir
# baked into the live/installed system.
AIROOTFS = WORKDIR / "work" / "x86_64" / "airootfs"


def is_root() -> bool:
    return os.geteuid() == 0


def in_docker() -> bool:
    return Path("/.dockerenv").exists()
