# shellcheck shell=bash
#
# probe_packages.sh -- the ISO package manifest (libraries/data/packages.x86_64).
#
# This is the single user-facing knob that decides what software the ISO ships.
# The probe counts it, then bins the packages into human categories by name
# pattern so the spec shows the SHAPE of the system (how much is KDE, how much is
# dev toolchain, how much is base/kernel/firmware) instead of a flat 240-line
# wall. Uncategorised names are listed under "other" so nothing is hidden.
#
# The bucket for each package is decided by the first matching rule in
# _pkg_category, so order there is precedence. It is a heuristic for a HUMAN
# overview, deliberately not a dependency solver.
#
# Depends on: common.sh. Reads: libraries/data/packages.x86_64.

# Classify one package name into a category label. FIRST MATCHING ARM WINS, so
# arm order is precedence: a Plasma applet like `plasma-nm` deliberately lands in
# "KDE Plasma desktop" rather than "networking" because the KDE arm is listed
# first. Each package name therefore appears in exactly one arm below (no literal
# is repeated across arms), which keeps the tally deterministic.
#
# shellcheck disable=SC2221,SC2222  # glob-before-literal precedence is intentional:
# broad globs (plasma*, kde*, kf*) are meant to swallow related packages we did
# not enumerate; the few literals after them are just documentation of notable
# members. The "overrides/never matches" warnings are the desired behaviour here.
_pkg_category() {
    case "$1" in
        base|linux|linux-headers|linux-firmware*|*-ucode|mkinitcpio*|memtest86*|edk2-shell|efibootmgr|grub|syslinux|refind|os-prober)
            echo "base / kernel / boot" ;;
        plasma*|kwin*|kde*|kf*|breeze*|oxygen*|kwallet*|kscreen*|kglobal*|kactivity*|kinfocenter|kmenuedit|kpipewire|krdp|kwrited|kgamma|ksystemstats|ksshaskpass|kscreenlocker|libk*|libplasma|layer-shell-qt|milou|drkonqi|powerdevil|polkit-kde-agent|sddm*|systemsettings|spectacle|dolphin|konsole|kcalc|gwenview|kclock|kamoso|kdialog|kdecoration|kwayland|qqc2-breeze-style|wacomtablet|xdg-desktop-portal-kde|print-manager|flatpak-kcm|plymouth*|ocean-sound-theme)
            echo "KDE Plasma desktop" ;;
        xorg|mesa|libglvnd|libadwaita|hicolor-icon-theme|webp-pixbuf-loader|lightdm*)
            echo "graphics / display stack" ;;
        networkmanager|nm-connection-editor|wpa_supplicant|iwd|iw|wireless*|dhcpcd|dnsmasq|openssh|openvpn|openconnect|vpnc|ppp|pptpclient|xl2tpd|rp-pppoe|wvdial|modemmanager|usb_modeswitch|bind|ldns|ndisc6|nfs-utils|open-iscsi|nbd|darkhttpd|reflector|curl|lftp|rsync|nmap|tcpdump|ethtool|b43-fwcutter|broadcom-wl|linux-atm|systemd-resolvconf)
            echo "networking" ;;
        btrfs-progs|xfsprogs|e2fsprogs|f2fs-tools|jfsutils|nilfs-utils|ntfs-3g|exfatprogs|dosfstools|udftools|bcachefs-tools|cryptsetup|lvm2|mdadm|dmraid|parted|gptfdisk|gpart|fatresize|fsarchiver|partclone|partimage|clonezilla|ddrescue|testdisk|squashfs-tools|mtools|nvme-cli|sdparm|hdparm|smartmontools|sg3_utils|lsscsi|mmc-utils|usbmuxd|libusb-compat|arch-install-scripts|archinstall)
            echo "storage / filesystems / install" ;;
        dotnet*|go|python|python-pip|tk|git|base-devel|bc|jq|gedit)
            echo "dev toolchain" ;;
        vlc*|pipewire*|pavucontrol|alsa-utils|ffmpeg|libreoffice*|gnome-screenshot|livecd-sounds|sof-firmware|espeakup|brltty)
            echo "multimedia / office / a11y" ;;
        bluez*|bluedevil|cups|pcsclite|pcsc*|usbutils|dmidecode|bolt|tpm2-*|libfido2|openpgp-card-tools|sequoia-sq|hyperv|qemu-guest-agent|open-vm-tools|virtualbox-guest-utils-nox)
            echo "hardware / peripherals / VM" ;;
        vim|neovim|nano|micro|htop|fastfetch|tmux|screen|mc|less|man-db|man-pages|zsh|grml-zsh-config|irssi|lynx|xclip|unzip|zip|dialog|ufw|gpm|pv|diffutils|xdg-utils|*-terminfo|terminus-font|noto-fonts|sudo|cloud-init)
            echo "CLI / shell / utilities" ;;
        *)
            echo "other" ;;
    esac
}

probe_packages() {
    local mf="$SPEC_REPO_ROOT/libraries/data/packages.x86_64"

    h2 "3. Package manifest"

    if [ ! -f "$mf" ]; then
        note "libraries/data/packages.x86_64 not found -- cannot describe the package set."
        return
    fi

    kv "File" "\`libraries/data/packages.x86_64\`"

    # Strip comments/blank lines into an array once.
    local pkgs=()
    local line
    while IFS= read -r line; do
        line="${line%%#*}"; line="${line// /}"
        [ -n "$line" ] && pkgs+=("$line")
    done < "$mf"
    kv "Total packages" "${#pkgs[@]}"
    kv "Architecture" "x86_64"

    # Tally categories. Bash 4 assoc arrays (the host is Arch/Manjaro, fine).
    declare -A tally
    local p cat
    for p in "${pkgs[@]}"; do
        cat=$(_pkg_category "$p")
        tally["$cat"]=$(( ${tally["$cat"]:-0} + 1 ))
    done

    blank
    h3 "3.1 Composition by category"
    bullet "Heuristic binning by package name (for a human overview, not a dependency graph)."
    blank
    code_open "text"
    # Print in a fixed, meaningful order; skip empty buckets.
    local order=(
        "base / kernel / boot"
        "KDE Plasma desktop"
        "graphics / display stack"
        "networking"
        "storage / filesystems / install"
        "dev toolchain"
        "multimedia / office / a11y"
        "hardware / peripherals / VM"
        "CLI / shell / utilities"
        "other"
    )
    local o n
    for o in "${order[@]}"; do
        n=${tally["$o"]:-0}
        [ "$n" -gt 0 ] || continue
        code_line "$(printf '%-34s %3d' "$o" "$n")"
    done
    code_line "$(printf '%-34s %3d' "TOTAL" "${#pkgs[@]}")"
    code_close

    blank
    h3 "3.2 Toolchain & desktop highlights"
    _pkg_highlight "${pkgs[@]}"
}

# Call out the packages a reader most wants confirmed present (and note if any
# expected keystone is absent), matched against the actual manifest.
_pkg_highlight() {
    local pkgs=("$@")
    local present=" ${pkgs[*]} "
    _hl() { case "$present" in *" $1 "*) kv "$2" "\`$1\` (present)";; *) kv "$2" "not in manifest";; esac; }
    _hl linux            "Kernel"
    _hl plasma           "Desktop meta"
    _hl plasma-desktop   "Plasma desktop"
    _hl sddm             "Display manager"
    _hl networkmanager   "Network stack"
    _hl pipewire         "Audio"
    _hl python           "Python"
    _hl go               "Go"
    _hl dotnet-sdk       ".NET SDK"
    _hl git              "Git"
    _hl neovim           "Editor (nvim)"
    _hl fastfetch        "Fetch tool"
    _hl libreoffice-fresh "Office suite"
    _hl vlc              "Media player"
    _hl archinstall      "Installer (upstream)"

    # NOTE: sddm is pulled in transitively by the plasma group even though it is
    # not an explicit manifest line; flag that nuance so "not in manifest" is not
    # misread as "the ISO has no display manager".
    case "$present" in
        *" sddm "*) : ;;
        *) bullet "_Note:_ \`sddm\` is not an explicit manifest entry but is pulled in by the \`plasma\` group; the build configures SDDM autologin regardless." ;;
    esac
}
