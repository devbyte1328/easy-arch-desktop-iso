# shellcheck shell=bash
#
# probe_repo.sh -- repository identity, git state, and the top-level directory
# scheme. This is the "where are we and what is here" section: it establishes
# the repo root, the branch/commit, whether the tree is dirty, and annotates the
# canonical directories (the same cache/ output/ logs/ scheme compile.sh and the
# Dockerfile bind-mount) with a one-line purpose each.
#
# Depends on: common.sh. Reads: git, the filesystem.

probe_repo() {
    local root="$SPEC_REPO_ROOT"

    h2 "1. Repository"

    kv "Name" "azarch (Az'arch Linux) -- Python-driven Arch ISO builder"
    kv "Root" "\`$root\`"

    # Git identity, kept resilient: a tarball export has no .git, so degrade.
    if have git && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        local branch commit subject dirty tags
        branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)
        commit=$(git -C "$root" rev-parse --short HEAD 2>/dev/null)
        subject=$(git -C "$root" log -1 --pretty=%s 2>/dev/null)
        if [ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]; then
            dirty="dirty (uncommitted changes)"
        else
            dirty="clean"
        fi
        kv "Git branch" "\`$branch\`"
        kv "Git HEAD" "\`$commit\` -- $subject"
        kv "Working tree" "$dirty"
        tags=$(git -C "$root" tag --list 2>/dev/null | wc -l | tr -d ' ')
        [ "$tags" -gt 0 ] && kv "Tags" "$tags"
    else
        kv "Git" "not a git checkout (or git unavailable)"
    fi

    # License + top-level docs, detected rather than assumed.
    [ -f "$root/LICENSE.txt" ] && kv "License" "\`LICENSE.txt\` present ($(loc "$root/LICENSE.txt") lines)"
    [ -f "$root/README.md" ]   && kv "Readme" "\`README.md\` present ($(loc "$root/README.md") lines)"

    blank
    h3 "1.1 Directory scheme"
    bullet "The build writes everything under a fixed set of top-level directories."
    bullet "\`cache/\`, \`output/\`, and \`logs/\` are git-ignored and are the three Docker bind-mount points."
    blank

    _repo_dir_table "$root"

    blank
    h3 "1.2 Source vs. generated"
    bullet "**Source of truth:** \`libraries/azarch/\` (Python) + \`libraries/data/\` (verbatim data)."
    bullet "**Generated at build time:** the archiso profile tree under \`cache/build/\`, the ISO in \`output/\`, logs in \`logs/\`. None of it is committed."
    bullet "**This report:** \`scripts/pull_specifications.sh\` -> \`documentation/SPECIFICATIONS.md\`."
}

# Annotated table of the canonical directories. Each row is printed only if the
# directory actually exists, with its on-disk size, so the same code documents a
# clean clone (no cache/output) and a post-build tree (several GB of cache).
_repo_dir_table() {
    local root="$1"
    code_open "text"
    _repo_dir_row "$root" "libraries/azarch/"  "the build system itself (config-as-Python + build logic)"
    _repo_dir_row "$root" "libraries/data/"    "verbatim upstream files: packages.x86_64, big KDE QML"
    _repo_dir_row "$root" "assets/"            "brand assets: logos, fastfetch ASCII art"
    _repo_dir_row "$root" "scripts/"           "auxiliary tooling (this spec generator)"
    _repo_dir_row "$root" "documentation/"     "human-facing docs (incl. the generated spec)"
    _repo_dir_row "$root" "cache/"             "[gen] persistent download cache: pkgs, DBs, disposable build/ tree"
    _repo_dir_row "$root" "output/"            "[gen] the finished .iso lands here"
    _repo_dir_row "$root" "logs/"              "[gen] full.log + steps.log"
    code_close
}

# Pad the directory name to a fixed column so the annotations line up in the
# fenced block. Skips non-existent dirs silently (keeps a clean clone tidy).
_repo_dir_row() {
    local root="$1" name="$2" desc="$3"
    [ -e "$root/$name" ] || return 0
    local size; size=$(hsize "$root/$name")
    code_line "$(printf '%-22s %6s   %s' "$name" "$size" "$desc")"
}
