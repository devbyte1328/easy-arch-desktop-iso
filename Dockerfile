# Easy Arch Linux - ISO build environment
#
# This image gives compile.sh a clean, genuine Arch Linux userland with the
# real Arch core/extra/multilib repositories. That is the whole point: the ISO
# is built with mkarchiso, which resolves the ISO's package list against the
# HOST's pacman repos. On a non-Arch host (Manjaro, Ubuntu+WSL, macOS, etc.)
# those repos are wrong or absent, so the build must happen inside Arch. This
# container provides that regardless of the machine you run it on.
#
# Build:  docker build -t easyarch .
# Run:    docker run --rm -it --privileged \
#           -v "$PWD/cache:/build/cache" \
#           -v "$PWD/output:/build/output" \
#           -v "$PWD/logs:/build/logs" \
#           easyarch
#         These three mounts mirror compile.sh's own directory scheme so the
#         host keeps the persistent download cache (cache/), the build output
#         incl. the finished ISO under output/out/ (output/), and both build
#         logs (logs/). No stray host-side out/ dir is created.
#         (--privileged is required: mkarchiso mounts proc/sys/dev and uses
#          loop devices + squashfs inside the airootfs.)

FROM archlinux:latest

# Refresh the keyring and sync the toolchain compile.sh needs on the build host:
#   archiso       -> mkarchiso
#   base-devel    -> makepkg and friends
#   go            -> building Go-based ISO components
#   python/pip    -> downloading the finalizer's Python wheels
#   git, sudo     -> checkout tooling; compile.sh calls sudo internally
# --noconfirm keeps the build non-interactive.
RUN pacman -Sy --needed --noconfirm archlinux-keyring \
    && pacman -Syu --needed --noconfirm \
        archiso \
        base-devel \
        go \
        python \
        python-pip \
        git \
        sudo \
    && pacman -Scc --noconfirm

# Initialize pacman's trust database. Installing archlinux-keyring above only
# lays the key FILES on disk; it does NOT create the GnuPG trust store pacman
# checks at install time. Without this, `SigLevel = Required` (set by the ISO's
# pacman.conf) makes pacman reject every signed package: explicitly-requested
# targets then surface as the misleading "error: target not found: <pkg>", and
# pacstrap dies with "There is no secret key available to sign with." mkarchiso
# runs pacstrap internally, so the keyring must be live in this image.
#   --init     generates the local signing key and empty trust db
#   --populate imports and locally-signs the official Arch developer keys
RUN pacman-key --init \
    && pacman-key --populate archlinux

# The build runs as root inside the container (sudo calls in compile.sh become
# no-ops). Provide a passwordless sudo entry anyway so any tooling that shells
# out through sudo keeps working.
RUN echo "root ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/00-root \
    && chmod 0440 /etc/sudoers.d/00-root

# Project lives here. compile.sh writes everything under three dirs at the build
# root: cache/ (persistent downloads), output/ (build tree + the finished ISO in
# output/out/) and logs/. Bind-mount those to the host to persist them:
#   -v "$PWD/cache:/build/cache" -v "$PWD/output:/build/output" -v "$PWD/logs:/build/logs"
# compile.sh re-execs itself on a PTY (via util-linux `script`) and draws a
# pinned progress bar with tput. Inside a bare container there is no TERM, so
# tput has no terminfo entry and hangs/errors, freezing the build. Give it a
# valid terminal type (xterm terminfo ships with the base ncurses package).
ENV TERM=xterm

WORKDIR /build
COPY . /build

# Build the ISO. The result appears in the mounted out/ directory on the host.
CMD ["./compile.sh"]
