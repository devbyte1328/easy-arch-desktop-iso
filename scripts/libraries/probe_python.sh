# shellcheck shell=bash
#
# probe_python.sh -- the core of the specification: the Python build system's
# module hierarchy and the metadata it declares.
#
# The whole ISO is authored in libraries/azarch/. This probe maps that graph:
#   * the top-level package modules (build, steps, emit, packages, paths, ...)
#     each summarised from its own module docstring
#   * the config/ sub-package (config-as-Python: one module per artifact class)
#   * the concrete declared values that define the ISO's identity and layout,
#     extracted straight from the source (ISO name, version scheme, boot modes,
#     the file_permissions map, the declared users)
#
# We read the docstrings and constants FROM THE SOURCE so the spec never drifts
# from the code: change profile.py and re-running this reflects it. A tiny Python
# helper does the AST-accurate extraction (docstring summary line, and literal
# constants) because grepping multi-line Python is brittle.
#
# Depends on: common.sh. Reads: the Python source under libraries/azarch/.

# One embedded Python helper, invoked with a mode argument. Kept minimal and
# dependency-free (stdlib ast only) so it runs under whatever python3 is present.
_py_introspect() {
    python3 - "$@" <<'PY'
import ast, sys, os

mode = sys.argv[1]
path = sys.argv[2]

def _fmt(v):
    # Render an extracted literal compactly for the doc. Containers are only
    # ever counted (mode "count"), so here we just pass scalars through.
    return v

def summary(src):
    """First non-empty line of a module docstring, or ''. """
    try:
        doc = ast.get_docstring(ast.parse(src))
    except Exception:
        return ""
    if not doc:
        return ""
    for line in doc.splitlines():
        line = line.strip()
        if line:
            return line
    return ""

def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()

if mode == "summary":
    # Print the one-line docstring summary for a single file.
    print(summary(read(path)))

elif mode == "const":
    # Print the repr-ish value of a top-level assignment NAME in a module.
    name = sys.argv[3]
    tree = ast.parse(read(path))
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name) and t.id == name:
                    try:
                        print(_fmt(ast.literal_eval(node.value)))
                    except Exception:
                        print(ast.unparse(node.value))
                    sys.exit(0)
    sys.exit(1)

elif mode == "count":
    # Count elements of a top-level list/tuple/dict assignment.
    name = sys.argv[3]
    tree = ast.parse(read(path))
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name) and t.id == name:
                    v = ast.literal_eval(node.value)
                    print(len(v))
                    sys.exit(0)
    sys.exit(1)

elif mode == "defs":
    # List top-level def/class names with their arg count (functions only).
    tree = ast.parse(read(path))
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            print(f"{node.name}()")
        elif isinstance(node, ast.ClassDef):
            print(f"{node.name} (class)")
PY
}

# _module_row FILE  -- "modname   summary" for a top-level azarch/*.py module.
_module_row() {
    local file="$1" name summary
    name=$(basename "$file" .py)
    summary=$(_py_introspect summary "$file" 2>/dev/null)
    code_line "$(printf '%-14s %s' "$name" "$summary")"
}

probe_python() {
    local az="$SPEC_REPO_ROOT/libraries/azarch"

    h2 "2. Build system (Python)"

    if [ ! -d "$az" ]; then
        note "libraries/azarch/ not found -- Python build system missing."
        return
    fi

    kv "Package" "\`azarch\` (import root: \`libraries/\`, set as PYTHONPATH by compile.sh)"
    kv "Entrypoint" "\`python3 -m azarch.build\` (invoked by the \`compile.sh\` PTY/sudo shim)"
    kv "Design" "config-as-Python: every ISO artifact is a Python string/function, emitted into the archiso profile tree"
    local pyver; pyver=$(python3 --version 2>&1 | awk '{print $2}')
    [ -n "$pyver" ] && kv "python3 (this host)" "$pyver"

    blank
    h3 "2.1 Core modules -- \`libraries/azarch/\`"
    bullet "Each line is the module's own one-line docstring summary (read from source)."
    blank
    code_open "text"
    # Deterministic, dependency-first-ish ordering rather than raw glob order.
    local ordered=(paths.py emit.py progress.py ownership.py packages.py steps.py build.py)
    local seen=" "
    local m
    for m in "${ordered[@]}"; do
        [ -f "$az/$m" ] && { _module_row "$az/$m"; seen+="$m "; }
    done
    # Any module not in the curated order (future-proofing) appended after.
    for m in "$az"/*.py; do
        local b; b=$(basename "$m")
        [ "$b" = "__init__.py" ] && continue
        case "$seen" in *" $b "*) continue ;; esac
        _module_row "$m"
    done
    code_close

    blank
    h3 "2.2 Config-as-Python -- \`libraries/azarch/config/\`"
    bullet "One module per class of ISO artifact. Content lives here as variables/builders; \`steps.py\` places it."
    blank
    if [ -d "$az/config" ]; then
        code_open "text"
        local c
        for c in pacman.py system.py locale.py kde.py installer.py profile.py fastfetch.py; do
            [ -f "$az/config/$c" ] && _module_row "$az/config/$c"
        done
        # any others not in the curated list above (future-proofing)
        for c in "$az"/config/*.py; do
            local b; b=$(basename "$c")
            case "$b" in
                pacman.py|system.py|locale.py|kde.py|installer.py|profile.py|fastfetch.py|__init__.py) continue ;;
            esac
            _module_row "$c"
        done
        code_close
    fi

    blank
    _probe_declared_identity "$az"
}

# Pull the ISO's declared identity + layout straight out of the source constants.
# This is the part that makes the doc authoritative: these are THE values the
# build uses, not a restatement.
_probe_declared_identity() {
    local az="$1"
    local prof="$az/config/profile.py"

    h3 "2.3 Declared ISO identity & layout"

    if [ -f "$prof" ]; then
        local iso_name iso_app publisher install_dir nboot nperm
        iso_name=$(_py_introspect const "$prof" ISO_NAME 2>/dev/null)
        iso_app=$(_py_introspect const "$prof" ISO_APPLICATION 2>/dev/null)
        publisher=$(_py_introspect const "$prof" ISO_PUBLISHER 2>/dev/null)
        install_dir=$(_py_introspect const "$prof" INSTALL_DIR 2>/dev/null)
        nboot=$(_py_introspect count "$prof" BOOTMODES 2>/dev/null)
        nperm=$(_py_introspect count "$prof" FILE_PERMISSIONS 2>/dev/null)

        [ -n "$iso_name" ]     && kv "iso_name" "\`$iso_name\`"
        [ -n "$iso_app" ]      && kv "iso_application" "$iso_app"
        [ -n "$publisher" ]    && kv "iso_publisher" "$publisher"
        [ -n "$install_dir" ]  && kv "install_dir" "\`$install_dir\`"
        kv "iso_version scheme" "date-based \`%Y.%m.%d\` (from SOURCE_DATE_EPOCH at build time)"
        [ -n "$nboot" ]        && kv "boot modes" "$nboot (BIOS syslinux + UEFI ia32/x64 systemd-boot, esp+eltorito)"
        [ -n "$nperm" ]        && kv "file_permissions entries" "$nperm (locked shadow/gshadow/sudoers/azarch payload in the squashfs)"
        kv "airootfs image" "squashfs, zstd -Xcompression-level 15 (xz error-9 workaround)"
    else
        note "config/profile.py not found -- cannot read declared ISO identity."
    fi

    # Declared users, from config/system.py's passwd string if present.
    local sysmod="$az/config/system.py"
    if [ -f "$sysmod" ]; then
        blank
        h3 "2.4 Declared users (from \`config/system.py\`)"
        # The passwd content is a here-string; grep the "name:x:uid:gid" lines
        # out of it. Keep it best-effort: show login, uid, gid, shell.
        code_open "text"
        code_line "$(printf '%-12s %-6s %-6s %s' LOGIN UID GID SHELL)"
        # Match typical passwd lines inside the Python string literal.
        grep -oE '^[a-z_][a-z0-9_-]*:x:[0-9]+:[0-9]+:[^:]*:[^:]*:[^"]*' "$sysmod" 2>/dev/null \
            | while IFS=: read -r login _ uid gid _ _ shell; do
                printf '%s\n' "$(printf '%-12s %-6s %-6s %s' "$login" "$uid" "$gid" "$shell")"
            done | while read -r l; do code_line "$l"; done
        code_close
        bullet "(Parsed from the embedded \`/etc/passwd\` string; the live ISO also autologins via SDDM.)"
    fi
}
