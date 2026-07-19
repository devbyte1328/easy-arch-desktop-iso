"""fastfetch config + the azarch "Az'" ASCII logo, authored as Python strings.

fastfetch ships in the ISO's package list; this module provides the two files
that make `fastfetch` render the azarch brand instead of the stock Arch logo:

  logo_txt()     the "Az'" ASCII art. `type: "file"` in fastfetch means the art
                 is a plain text file with $N color-code replacement, so the
                 gradient is expressed with $1..$4 placeholders mapped to real
                 colors by config_jsonc()'s `logo.color` block.
  config_jsonc() ~/.config/fastfetch/config.jsonc pointing fastfetch at the logo
                 (type=file, source=azarch.txt) and mapping $1..$4 -> the
                 cyan->blue gradient sampled from the azarch logo PNG
                 (assets/azarch_logo.png), using truecolor codes for an exact hue.

Both land in the user's ~/.config/fastfetch/ on the live ISO and, via the
installer copy path, on the installed system. The config keys (type/source/
color) are the fastfetch JSON-schema names; `type: "file"` does $N replacement.
"""

from __future__ import annotations

# The "Az'" logo: STRICT ASCII in the stock Arch logo's own glyph palette
# (space ' + . / \ o s -- no @ blocks, no Unicode), because azarch is
# Arch-based and this must read as a sibling of the arch fastfetch logo.
#
# It is NOT hand-drawn. It is reverse-engineered from assets/azarch_logo.png by
# tools/logo_to_ascii.py: the bright "Az'" strokes are thresholded off the dark
# navy background, downsampled to a character grid, and mapped to the arch
# palette (diagonals -> / and \, interiors -> o/s/+, faint edges -> . :). The
# shape: a bold capital A (apex, splayed legs, hollow counter, solid crossbar),
# a lowercase z on the same baseline (top bar, a continuous diagonal sweeping
# top-right -> bottom-left, bottom bar), and a slanted apostrophe tick standing
# at cap-height above and to the RIGHT of the z's shoulder. Sized 15 rows x 30
# cols to sit alongside the real distro logos (arch is ~19 rows, ~40 cols).
#
# The four gradient bands $1..$4 are sampled straight from the PNG's stroke
# pixels (top -> bottom): #06b8fd, #03a5fc, #0185fb, #0065f9 -- a bright
# cyan-blue fading to deep blue. config_jsonc() maps them with truecolor codes
# so the terminal hue matches the logo exactly. The trailing spaces on every row
# are intentional and REQUIRED: they keep the block a clean rectangle so the info
# column fastfetch prints to the right stays aligned.
LOGO = (
    "$1  /ssss\\                      \n"
    "$1   ssssss                  /  \n"
    "$1  /ssssss\\                /'  \n"
    "$1   ssssssss               '   \n"
    "$2  /sss/\\sss\\    ssssssssssss  \n"
    "$2  sss/  \\sss    ssssssssssss  \n"
    "$2 /sss    sss\\            sss  \n"
    "$2 sss.    .sss           sss   \n"
    "$3/ssso    osss\\         sss    \n"
    "$3sssssooosssss         sss     \n"
    "$3sss+ooooo+sss        sss      \n"
    "$3ssssssssssss        sss       \n"
    "$4sss      sss       sss        \n"
    "$4sss      sss    ssssssssssss  \n"
    "$4sss      sss    ssssssssssss  \n"
)


def logo_txt() -> str:
    return LOGO


def config_jsonc() -> str:
    """fastfetch config: use the bundled Az' art with the azarch gradient.

    `source` is a bare filename; fastfetch resolves it relative to
    ~/.config/fastfetch/, where logo_txt() is written alongside this file.
    The color map turns the $1..$4 placeholders into the cyan->blue gradient.
    """
    return """\
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "file",
        "source": "azarch.txt",
        "color": {
            "1": "38;2;6;184;253",
            "2": "38;2;3;165;252",
            "3": "38;2;1;133;251",
            "4": "38;2;0;101;249"
        },
        "padding": {
            "top": 1,
            "left": 2
        }
    },
    "modules": [
        "title",
        "separator",
        "os",
        "host",
        "kernel",
        "uptime",
        "packages",
        "shell",
        "de",
        "wm",
        "terminal",
        "cpu",
        "gpu",
        "memory",
        "disk",
        "break",
        "colors"
    ]
}
"""
