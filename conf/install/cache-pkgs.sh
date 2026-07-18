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
DLCONF=$SELFDIR/cache-pkgs-pacman.conf

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

# pacman ran as root, so newly downloaded files are root-owned. Hand this cache
# subtree back so the later UNPRIVILEGED steps in THIS script (repo-add, staging
# cp) can read it, and so the host user isn't locked out mid-build. Prefer the
# host uid/gid exported by compile.sh (correct across the Docker bind mount);
# fall back to the current user for a native/standalone run. compile.sh's final
# sweep chowns cache/ again on exit anyway, so this is belt-and-braces.
_OWN_UID=${HOST_UID:-$(id -u)}
_OWN_GID=${HOST_GID:-$(id -g)}
$SUDO chown -R "$_OWN_UID:$_OWN_GID" "$PKGREPO" "$PKGDB" 2>/dev/null || true

echo "[*] Reconciling local repository index with the cache..."
# INCREMENTAL by design: the .db is PERSISTENT (kept across runs, like the .pkg
# files) and we only touch what actually changed. The old code deleted the .db
# then re-ran repo-add over ALL ~1200 packages every build, so every run printed
# "Adding package / Computing checksums / Creating desc/files db entry" for the
# whole set even when nothing was downloaded — it looked like the cache was unused.
# repo-add re-hashes every package you hand it (even one already identical in the
# db; -n only skips AFTER still printing a warning per pkg), so the only way to
# avoid the redundant work AND the noise is to compute the delta ourselves and
# pass repo-add just the genuinely-new/changed files. Result is byte-for-byte the
# same .db a full rebuild would produce: it always ends up describing EXACTLY the
# .pkg.tar.zst files present, with no stale entries.
DB="$PKGREPO/pacstrap-easyarch-repo.db.tar.gz"

# db-key of a package file = its name-ver-rel, i.e. the basename minus the trailing
# "-<arch>.pkg.tar.zst". That is exactly the entry-dir name repo-add stores, so we
# can compare on-disk files against db entries without unpacking anything.
declare -A have_key      # db-key            -> file basename   (what's on disk now)
declare -A have_name     # pkgname           -> 1               (names present on disk)
declare -A file_of_name  # pkgname           -> newest file for that name (dup guard)
declare -A ver_of_name   # pkgname           -> newest ver-rel  (dup guard)
declare -A key_of_name   # pkgname           -> newest db-key   (dup guard)
superseded=()            # older duplicate .pkg files to delete from the cache

shopt -s nullglob
_pkgfiles=( "$PKGREPO"/*.pkg.tar.zst )
shopt -u nullglob
(( ${#_pkgfiles[@]} )) || fail "no packages in cache to index"

for f in "${_pkgfiles[@]}"; do
    b=${f##*/}
    key=${b%-*.pkg.tar.zst}          # name-ver-rel  (arch + suffix stripped)
    verrel=${key##*-}                # pkgrel
    nv=${key%-*}                     # name-ver
    verrel=${nv##*-}-$verrel; name=${nv%-*}   # full ver-rel, and pkgname
    # pacman -Sw never prunes old versions, so the cache can hold two versions of
    # one package. Keep the newest (vercmp-correct) and mark the other for deletion
    # so the cache and db stay single-version. Without this the db would end up
    # indexing whichever version repo-add saw last (glob order = wrong for e.g.
    # 2.0 vs 10.0) and the loser file would linger forever.
    if [[ -n ${ver_of_name[$name]:-} ]]; then
        if (( $(vercmp "$verrel" "${ver_of_name[$name]}") > 0 )); then
            # This file is newer than the one we picked earlier: retire the old pick
            # (drop its basename-keyed have_key entry and queue its file for deletion).
            superseded+=( "${file_of_name[$name]}" ); unset "have_key[${key_of_name[$name]}]"
        else
            superseded+=( "$f" ); continue
        fi
    fi
    have_key[$key]=$b; have_name[$name]=1
    file_of_name[$name]=$f; ver_of_name[$name]=$verrel; key_of_name[$name]=$key
done

# Self-heal: if the db is missing or unreadable (first run, deleted, or a corrupt
# partial from a killed run) rebuild it cleanly from the winning files only.
if [[ ! -f $DB ]] || ! bsdtar -tf "$DB" >/dev/null 2>&1; then
    _add=(); for k in "${!have_key[@]}"; do _add+=( "$PKGREPO/${have_key[$k]}" ); done
    echo "    [+] No usable index — building fresh from ${#_add[@]} package(s) (one-time)."
    rm -f "$PKGREPO"/pacstrap-easyarch-repo.db* "$PKGREPO"/pacstrap-easyarch-repo.files*
    # Seed the persistent db in CHUNKS so the build SHOWS live progress instead of
    # freezing on a single silent multi-minute repo-add. After each chunk we print
    # "[+] Indexing N/TOTAL packages..." -- that line is both human-visible AND what
    # the compile.sh progress reader parses to advance the step-20 bar. We chunk
    # (not one-package-at-a-time) because repo-add re-gzips the whole .db on every
    # call, so per-package is ~2x slower and grows superlinearly; a chunk of 50 is
    # as fast as a single batched call while still updating ~24 times over the seed.
    # repo-add -q keeps each call quiet (no per-package wall of text). This is the
    # ONLY path that loops (runs once, when there is no db); the steady-state
    # incremental path below stays a single fast batched call.
    _tot=${#_add[@]} _n=0 _CHUNK=50
    for (( _i=0; _i<_tot; _i+=_CHUNK )); do
        repo-add -q "$DB" "${_add[@]:_i:_CHUNK}" >/dev/null 2>&1 || fail "repo-add (fresh)"
        _n=$(( _i + _CHUNK )); (( _n > _tot )) && _n=$_tot
        printf '    [+] Indexing %d/%d packages...\n' "$_n" "$_tot"
    done
else
    # Which name-ver-rel keys (and which names) the db already indexes.
    declare -A db_key db_name
    while IFS= read -r ekey; do
        db_key[$ekey]=1; db_name[${ekey%-*-*}]=1
    done < <(bsdtar -tf "$DB" 2>/dev/null | sed -n 's,/desc$,,p')

    # Add only files whose exact key is NOT already indexed (new pkg or new version).
    _add=()
    for k in "${!have_key[@]}"; do
        [[ -z ${db_key[$k]:-} ]] && _add+=( "$PKGREPO/${have_key[$k]}" )
    done
    # Remove any indexed name that no longer has a file on disk (package dropped, or
    # its old version was just superseded) so the db never advertises a missing file.
    _rm=()
    for n in "${!db_name[@]}"; do
        [[ -z ${have_name[$n]:-} ]] && _rm+=( "$n" )
    done

    if (( ${#_rm[@]} )); then
        echo "    [-] Dropping ${#_rm[@]} stale entr(y/ies) from the index."
        repo-remove -q "$DB" "${_rm[@]}" || fail "repo-remove"
    fi
    if (( ${#_add[@]} )); then
        echo "    [+] Indexing ${#_add[@]} new/updated package(s)."
        repo-add -q "$DB" "${_add[@]}" || fail "repo-add (delta)"
    fi
    if (( ${#_rm[@]} == 0 && ${#_add[@]} == 0 )); then
        echo "    [=] Index already up to date — nothing to re-index."
    fi
fi

# Prune the superseded duplicate .pkg files so the cache stays single-version and
# doesn't grow without bound. Their db entries (if any) were dropped by the reconcile
# above via the name-not-on-disk / key-not-indexed logic.
if (( ${#superseded[@]} )); then
    echo "    [-] Removing ${#superseded[@]} superseded package file(s) from cache."
    rm -f "${superseded[@]}"
fi

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
