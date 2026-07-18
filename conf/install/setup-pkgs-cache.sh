#!/bin/bash

set -e

# ---------------------------------------------------------------------------
# Real-time, resumable package cache.
#
# pacman -Sw --cachedir <DIR> downloads ONLY the packages not already present
# in <DIR> and verifies each one, so pointing --cachedir straight at the
# PERSISTENT cache makes caching incremental:
#   * every package that finishes downloading is durable the instant it lands;
#   * Ctrl-C mid-download leaves the finished packages cached;
#   * a re-run skips what is already there and fetches only what is missing;
#   * a corrupt partial from a hard kill is re-fetched by pacman's own check.
#
# Args:
#   $1 = build dir   (scratch that IS wiped every build; holds the sync DB)
#   $2 = cache dir   (persistent cache root; survives cleanup — the resume store)
# ---------------------------------------------------------------------------

fail() {
    echo "[✗] $1"
    exit 1
}

# Root-aware sudo wrapper (see compile.sh). In the all-root build container this
# drops sudo entirely so pacman is a DIRECT child of this shell and dies with the
# process group on Ctrl-C; on a non-root host it stays "sudo" for the privileged
# db/cache writes.
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

BUILDDIR=${1:-$PWD}
CACHEDIR=${2:-$BUILDDIR/cache}

# Persistent, resumable stores (survive `rm -rf output/`, wiped only by user via
# `rm -rf cache/`). REPO holds the .pkg.tar.zst files; DB holds the sync database.
PKGREPO=$CACHEDIR/pkgs/repo
PKGDB=$CACHEDIR/pkgs/db

# Where the finished cache is staged for mkarchiso to bake into the ISO. The
# airootfs is wiped every build, so this copy always runs (it is fast, local,
# and offline).
FINALDB=airootfs/root/Easy-Arch/pacstrap-easyarch-db
FINALCACHE=airootfs/root/Easy-Arch/pacstrap-easyarch-repo

# Self-contained Arch download config lives next to this script. Using it (instead
# of the host /etc/pacman.conf) makes the download work regardless of what distro
# the build host runs (e.g. Manjaro), and pins Arch's official mirrors.
SELFDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DLCONF=$SELFDIR/setup-pkgs-cache-pacman.conf

# Fresh, empty GPG dir so no host keyring is ever consulted for the download step
# (a non-Arch host's keyring would not trust Arch package signatures). Transient,
# lives in the build dir.
GPGDIR=$BUILDDIR/.pkgs-gnupg

# The persistent stores are created once and then reused across runs — NOT wiped
# here (that is the whole point of resuming). Only the transient gpg dir is fresh.
mkdir -p "$PKGREPO" "$PKGDB/sync"
rm -rf "$GPGDIR"; mkdir -p "$GPGDIR"

# Clear a stale lock left by a pacman that was Ctrl-C'd or hard-killed on a prior
# run. This --dbpath is private to the build and single-threaded, so a lingering
# db.lck is never a live lock — it only ever blocks the resume it is meant to
# enable. Needs sudo because a crashed root pacman leaves a root-owned lock.
$SUDO rm -f "$PKGDB/db.lck"

echo "[*] Syncing package databases..."
# Refresh the sync DB into the PERSISTENT db path. If the network is down but the
# cache is already complete we still want to proceed offline, so a failed -Sy is
# non-fatal as long as a previously synced DB exists.
if ! $SUDO pacman -Sy --config "$DLCONF" --gpgdir "$GPGDIR" \
        --dbpath "$PKGDB" --cachedir "$PKGREPO" --noconfirm; then
    if [ -n "$(ls -A "$PKGDB/sync" 2>/dev/null)" ]; then
        echo "    [+] DB sync failed but a cached DB exists — continuing offline."
    else
        fail "Could not sync package databases and no cached DB to fall back on."
    fi
fi

echo "[*] Preparing package list..."
pkgs=$(tr '\n' ' ' < packages.x86_64)

echo "[*] Downloading missing packages into the persistent cache (resumable)..."
# One non-interactive call for the whole list. pacman resolves dependencies once,
# skips every package already in $PKGREPO, and downloads only what is missing —
# so this is where real-time, resumable caching happens. --noconfirm suppresses
# the "Proceed with download? [Y/n]" prompt.
$SUDO pacman -Sw --config "$DLCONF" --gpgdir "$GPGDIR" --noconfirm \
    --cachedir "$PKGREPO" --dbpath "$PKGDB" $pkgs || fail "package download"

# pacman ran as root, so newly downloaded files are root-owned. Hand the cache
# back to the invoking user so later unprivileged steps (repo-add, the staging
# copy, mkarchiso) can read it and so the user can `rm -rf cache/` freely.
$SUDO chown -R "$(id -u):$(id -g)" "$PKGREPO" "$PKGDB"

echo "[*] Building local repository index from the cache..."
# Idempotent: refreshes the .db from whatever .pkg.tar.zst files are present.
rm -f "$PKGREPO"/pacstrap-easyarch-repo.db* "$PKGREPO"/pacstrap-easyarch-repo.files*
repo-add "$PKGREPO/pacstrap-easyarch-repo.db.tar.gz" "$PKGREPO"/*.pkg.tar.zst || fail "repo-add"

echo "[*] Staging cached packages into the ISO working tree..."
# Always runs (airootfs is wiped each build); pure local copy, no network.
mkdir -p "$FINALDB" "$FINALCACHE"
cp -r "$PKGDB"/.   "$FINALDB"/   || fail "staging DB"
cp -r "$PKGREPO"/. "$FINALCACHE"/ || fail "staging packages"

# Verify the staged repo is non-empty before declaring success.
if [ -z "$(ls -A "$FINALCACHE" 2>/dev/null)" ]; then
    fail "Package cache is empty after staging."
fi

# Transient cleanup only — the persistent cache is intentionally kept.
rm -rf "$GPGDIR"

echo "[✓] Package cache is complete and staged (offline-ready, resumable)."
