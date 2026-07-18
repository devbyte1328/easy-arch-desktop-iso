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
# Run:    docker run --rm -it --privileged -v "$PWD/out:/build/output/out" easyarch
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

# The build runs as root inside the container (sudo calls in compile.sh become
# no-ops). Provide a passwordless sudo entry anyway so any tooling that shells
# out through sudo keeps working.
RUN echo "root ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/00-root \
    && chmod 0440 /etc/sudoers.d/00-root

# Project lives here. The finished ISO is written to /build/output/out, which
# you bind-mount to the host with -v "$PWD/out:/build/output/out".
# compile.sh re-execs itself on a PTY (via util-linux `script`) and draws a
# pinned progress bar with tput. Inside a bare container there is no TERM, so
# tput has no terminfo entry and hangs/errors, freezing the build. Give it a
# valid terminal type (xterm terminfo ships with the base ncurses package).
ENV TERM=xterm

WORKDIR /build
COPY . /build

# Build the ISO. The result appears in the mounted out/ directory on the host.
CMD ["./compile.sh"]
