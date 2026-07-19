# shellcheck shell=bash
#
# common.sh -- shared helpers for pull_specifications.sh.
#
# Everything here is presentation + small utilities: colour handling that
# collapses to nothing when we're not on a TTY (so the Markdown file never gets
# escape codes), Markdown emitters, and a couple of filesystem helpers (human
# sizes, line counts, safe "does this command exist"). The probe_*.sh modules
# build ON TOP of these; they never print raw escape codes themselves.
#
# All output is funnelled through `out`, which writes to the report file AND
# (optionally) to the terminal. That single seam is what lets the same probe
# code produce a clean Markdown artifact and a coloured live view at once.

# --- output plumbing -------------------------------------------------------

# Populated by the entry point before any probe runs.
: "${SPEC_OUT_FILE:=/dev/null}"   # the Markdown artifact path
: "${SPEC_TO_STDOUT:=1}"          # also echo to the terminal?
: "${SPEC_COLOR:=auto}"           # auto|always|never (terminal only; file is never coloured)

# Resolve colour once. Colour is a TERMINAL concern only -- the Markdown file
# is always plain. We therefore keep two ideas separate: whether the terminal
# copy is coloured (_C_*), and the file copy which never is.
_spec_init_color() {
    local want=0
    case "$SPEC_COLOR" in
        always) want=1 ;;
        never)  want=0 ;;
        auto)   [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && want=1 ;;
    esac
    if [ "$want" = 1 ]; then
        _C_RESET=$'\033[0m'; _C_BOLD=$'\033[1m'; _C_DIM=$'\033[2m'
        _C_RED=$'\033[31m'; _C_GREEN=$'\033[32m'; _C_YELLOW=$'\033[33m'
        _C_BLUE=$'\033[34m'; _C_CYAN=$'\033[36m'; _C_MAGENTA=$'\033[35m'
    else
        _C_RESET=""; _C_BOLD=""; _C_DIM=""
        _C_RED=""; _C_GREEN=""; _C_YELLOW=""
        _C_BLUE=""; _C_CYAN=""; _C_MAGENTA=""
    fi
}
_spec_init_color

# out LINE...
# Write one line to the report file (never coloured) and, if enabled, to stdout
# (coloured only when the terminal copy is coloured). Markdown text is passed
# through verbatim to the file; the terminal copy strips nothing because the
# probes emit Markdown, which reads fine raw. Colour is layered by the h*/kv/etc
# helpers, which emit pre-coloured strings ONLY to stdout via `term`.
out() {
    printf '%s\n' "$*" >> "$SPEC_OUT_FILE"
    if [ "$SPEC_TO_STDOUT" = 1 ]; then
        printf '%s\n' "$*"
    fi
}

# term LINE...  -- terminal-only line (coloured banners, progress notes). Never
# lands in the Markdown artifact.
term() {
    [ "$SPEC_TO_STDOUT" = 1 ] && printf '%s\n' "$*" >&2
    return 0
}

# blank -- one empty line in both sinks (Markdown paragraph break).
blank() { out ""; }

# --- Markdown emitters -----------------------------------------------------
# These write GitHub-flavoured Markdown to the file. When stdout is a coloured
# terminal we ALSO print a coloured echo of the same content so the live view is
# readable; the two are kept in lockstep by routing both through `out` for the
# file and a coloured `term`-style print for the screen. To avoid double
# printing we special-case: `out` already handled the plain screen copy when not
# coloured, so the coloured helpers below only add colour when _C_BOLD is set.

_emit() {
    # _emit PLAIN COLOURED -- file gets PLAIN; screen gets COLOURED if colour on,
    # else PLAIN (already covered by writing PLAIN to the file+screen via out).
    local plain="$1" coloured="$2"
    printf '%s\n' "$plain" >> "$SPEC_OUT_FILE"
    if [ "$SPEC_TO_STDOUT" = 1 ]; then
        if [ -n "$_C_BOLD" ]; then printf '%s\n' "$coloured"
        else printf '%s\n' "$plain"; fi
    fi
}

h1() { _emit "# $*" "${_C_BOLD}${_C_MAGENTA}# $*${_C_RESET}"; }
h2() { _emit "## $*" "${_C_BOLD}${_C_CYAN}## $*${_C_RESET}"; }
h3() { _emit "### $*" "${_C_BOLD}${_C_BLUE}### $*${_C_RESET}"; }

# kv KEY VALUE -- a "- **Key:** value" definition line.
kv() {
    local k="$1"; shift
    _emit "- **$k:** $*" "  ${_C_DIM}-${_C_RESET} ${_C_BOLD}$k:${_C_RESET} $*"
}

# bullet TEXT
bullet() { _emit "- $*" "  ${_C_DIM}-${_C_RESET} $*"; }

# note TEXT -- a blockquote caveat.
note() { _emit "> $*" "${_C_YELLOW}> $*${_C_RESET}"; }

# code_open [LANG] / code_line / code_close -- a fenced block.
code_open() { _emit '```'"${1:-}" "${_C_DIM}\`\`\`${1:-}${_C_RESET}"; }
code_line() { _emit "$*" "${_C_DIM}$*${_C_RESET}"; }
code_close() { _emit '```' "${_C_DIM}\`\`\`${_C_RESET}"; }

# rule -- horizontal rule / section separator.
rule() { blank; _emit '---' "${_C_DIM}--------------------------------------------------${_C_RESET}"; blank; }

# --- filesystem / value helpers -------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# hsize PATH -- human-readable size of a file or dir, or "-" if missing.
hsize() {
    [ -e "$1" ] || { printf '%s' "-"; return; }
    du -sh "$1" 2>/dev/null | cut -f1
}

# hsize_total PATH... -- combined human size of several paths.
hsize_total() {
    local existing=()
    local p
    for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
    [ ${#existing[@]} -eq 0 ] && { printf '%s' "-"; return; }
    du -sch "${existing[@]}" 2>/dev/null | tail -1 | cut -f1
}

# loc PATH -- non-blank, non-comment-ish line count of a text file (best effort).
loc() {
    [ -f "$1" ] || { printf '0'; return; }
    wc -l < "$1" | tr -d ' '
}

# count_glob DIR PATTERN -- how many entries match, without nullglob surprises.
count_glob() {
    local dir="$1" pat="$2" n=0 f
    for f in "$dir"/$pat; do [ -e "$f" ] && n=$((n + 1)); done
    printf '%d' "$n"
}

# rel PATH -- path made relative to the repo root for readable output.
rel() {
    local p="$1"
    printf '%s' "${p#"$SPEC_REPO_ROOT"/}"
}

# first_existing PATH... -- echo the first path that exists (for tool lookups).
first_existing() {
    local p
    for p in "$@"; do [ -e "$p" ] && { printf '%s' "$p"; return 0; }; done
    return 1
}
