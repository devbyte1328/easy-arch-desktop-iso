# shellcheck shell=bash
#
# probe_toolchain.sh -- the build toolchain, on two axes:
#
#   * DECLARED: what the Dockerfile installs into the canonical Arch build
#     environment (archiso, base-devel, go, git, sudo, python). This is the
#     reproducible, machine-independent answer -- it is the same everywhere.
#   * DETECTED: the versions actually present on THIS host right now. Useful when
#     you build natively (not via Docker) or want to know what your machine has.
#
# Keeping both is the point: the Dockerfile line tells you what the build is
# guaranteed to run against; the detected line tells you what you personally have,
# which may differ (or be absent) on a non-Arch host -- exactly the situation the
# Docker path exists to fix.
#
# Depends on: common.sh. Reads: the Dockerfile, and the host's tools.

# One-line purpose for each Dockerfile-installed build tool, shown beside it.
_dockertool_note() {
    case "$1" in
        archiso)           echo "provides mkarchiso (the ISO assembler)" ;;
        base-devel)        echo "makepkg and the C/build toolchain" ;;
        go)                echo "builds Go-based ISO components" ;;
        git)               echo "checkout tooling" ;;
        sudo)              echo "the build shells out through sudo internally" ;;
        python)            echo "the build itself (python3 -m azarch.build)" ;;
        archlinux-keyring) echo "refreshes signing keys before install" ;;
        *)                 echo "" ;;
    esac
}

# Print "tool: version" for a host tool, or mark it absent. The version command
# differs per tool, so pass the full argv that emits a version string. Some tools
# (pacman) lead with an ASCII-art banner, so instead of blindly taking line 1 we
# take the first NON-BLANK line that carries a version-looking token; if none
# matches we fall back to the first non-blank line.
_tool_ver() {
    local label="$1"; shift
    if ! have "$1"; then
        kv "$label" "not installed on this host"
        return
    fi
    local raw v
    raw=$("$@" 2>&1)
    v=$(printf '%s\n' "$raw" | grep -m1 -iE 'version|v[0-9]+\.[0-9]' )
    [ -z "$v" ] && v=$(printf '%s\n' "$raw" | grep -m1 -vE '^[[:space:]]*$')
    # Some tools (pacman) lead the version line with ASCII-art punctuation like
    # ".--.   Pacman v7.1.0". Strip a leading run of non-alphanumeric art so the
    # line starts at the first real word, but DON'T relocate past real prefixes
    # like "git version ..." -- a leading [A-Za-z] is kept as-is.
    v=$(printf '%s' "$v" | sed -E 's/^[^[:alnum:]]+[[:space:]]+//')
    # Trim leading/trailing whitespace for tidy output.
    v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    kv "$label" "$v"
}

probe_toolchain() {
    local root="$SPEC_REPO_ROOT"

    h2 "4. Build toolchain"

    h3 "4.1 Declared build environment (Dockerfile)"
    local df="$root/Dockerfile"
    if [ -f "$df" ]; then
        local base
        base=$(grep -iE '^\s*FROM\s' "$df" | head -1 | awk '{print $2}')
        kv "Base image" "\`${base:-unknown}\`"
        kv "Rationale" "mkarchiso resolves the ISO package list against the host's Arch repos; a genuine Arch userland is mandatory"
        blank
        bullet "Packages the image installs for the build:"
        blank
        code_open "text"
        # Pull the pacman -Syu package block out of the Dockerfile so this stays
        # accurate if the toolchain list changes. We look for the known names.
        local t
        for t in archiso base-devel go git sudo python archlinux-keyring; do
            if grep -qE "(^|\s)$t(\s|\\\\|$)" "$df"; then
                code_line "$(printf '%-18s %s' "$t" "$(_dockertool_note "$t")")"
            fi
        done
        code_close
        blank
        kv "Trust setup" "\`pacman-key --init && --populate archlinux\` (required or signed pkgs are rejected)"
        kv "PID 1" "tini via \`docker run --init\` (signal forwarding + orphan reaping for clean Ctrl-C)"
        kv "Privileges" "\`--privileged\` (mkarchiso mounts proc/sys/dev, uses loop devices + squashfs)"
    else
        note "Dockerfile not found -- cannot report the declared build environment."
    fi

    blank
    h3 "4.2 Detected on this host"
    bullet "Versions present on the machine generating this report (may differ from the Docker environment)."
    blank
    # mkarchiso has no clean --version flag, so report presence + the version
    # pacman recorded for the archiso package (clean and accurate on Arch hosts).
    if have mkarchiso; then
        local av=""
        have pacman && av=$(pacman -Q archiso 2>/dev/null)
        kv "archiso (mkarchiso)" "present${av:+ -- $av}"
    else
        kv "archiso (mkarchiso)" "not installed on this host"
    fi
    _tool_ver "pacman"  pacman --version
    _tool_ver "python3" python3 --version
    _tool_ver "go"      go version
    _tool_ver "git"     git --version
    _tool_ver "docker"  docker --version
    _tool_ver "sudo"    sudo --version

    # Where the releng profile the build copies from lives (only on Arch hosts).
    local releng="/usr/share/archiso/configs/releng"
    blank
    if [ -d "$releng" ]; then
        kv "archiso releng profile" "present at \`$releng\` (native builds copy from here)"
    else
        kv "archiso releng profile" "absent on this host -> native build not possible here; use Docker"
    fi
}
