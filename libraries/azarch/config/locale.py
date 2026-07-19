"""Locale auto-detection: the country->locale map (as a Python dict, the single
source of truth) plus the two scripts that consume it -- setup-locale.sh (runs on
the LIVE ISO) and the locale portion of chroot-setup.sh (runs in the INSTALL
chroot). Both derive their bash LANGUAGE_MAP heredoc from LANGUAGE_MAP below, so
adding a language is a one-line Python edit.
"""

from __future__ import annotations

# country code -> (language name, locale). Order preserved (matches the original).
LANGUAGE_MAP: dict[str, tuple[str, str]] = {
    "US": ("English", "en_US.UTF-8"),
    "GB": ("English", "en_GB.UTF-8"),
    "FR": ("French", "fr_FR.UTF-8"),
    "DE": ("German", "de_DE.UTF-8"),
    "ES": ("Spanish", "es_ES.UTF-8"),
    "IT": ("Italian", "it_IT.UTF-8"),
    "UA": ("Ukrainian", "uk_UA.UTF-8"),
    "RU": ("Russian", "ru_RU.UTF-8"),
    "CN": ("Chinese", "zh_CN.UTF-8"),
    "JP": ("Japanese", "ja_JP.UTF-8"),
    "KR": ("Korean", "ko_KR.UTF-8"),
    "BR": ("Portuguese", "pt_BR.UTF-8"),
    "IN": ("Hindi", "hi_IN.UTF-8"),
    "IL": ("Hebrew", "he_IL.UTF-8"),
    "AR": ("Arabic", "ar_SA.UTF-8"),
    "TR": ("Turkish", "tr_TR.UTF-8"),
    "NL": ("Dutch", "nl_NL.UTF-8"),
    "PL": ("Polish", "pl_PL.UTF-8"),
    "SE": ("Swedish", "sv_SE.UTF-8"),
    "NO": ("Norwegian", "nb_NO.UTF-8"),
    "DK": ("Danish", "da_DK.UTF-8"),
    "FI": ("Finnish", "fi_FI.UTF-8"),
    "CZ": ("Czech", "cs_CZ.UTF-8"),
    "HU": ("Hungarian", "hu_HU.UTF-8"),
    "GR": ("Greek", "el_GR.UTF-8"),
    "TH": ("Thai", "th_TH.UTF-8"),
    "VN": ("Vietnamese", "vi_VN.UTF-8"),
}


def _language_map_heredoc() -> str:
    """Render LANGUAGE_MAP as the ``CC|Language|locale`` lines the bash scripts grep."""
    return "\n".join(f"{cc}|{name}|{loc}" for cc, (name, loc) in LANGUAGE_MAP.items())


# Shared bash block: query IP geo, match country -> locale/keyboard, enable and
# generate locales, set locale.conf / vconsole / X11 keyboard, set timezone.
# Both the live-ISO script and the installer chroot script start from this.
def _detect_and_apply_locale_block() -> str:
    return f"""\
# Get timezone and country from IP
TIMEZONE=$(curl -s https://ipapi.co/timezone)
COUNTRY=$(curl -s https://ipapi.co/country)

# Defaults
PRIMARY_LANG="en_US.UTF-8"
SECONDARY_LANG=""
PRIMARY_KB="us"
SECONDARY_KB=""

# Language mapping (generated from azarch.config.locale.LANGUAGE_MAP)
LANGUAGE_MAP=$(cat <<EOF
{_language_map_heredoc()}
EOF
)

# Match country code to locale
MATCH=$(echo "$LANGUAGE_MAP" | grep "^$COUNTRY|")
if [ -n "$MATCH" ]; then
  LOCALE_CODE=$(echo "$MATCH" | cut -d'|' -f3)
  KB_LAYOUT=$(echo "$COUNTRY" | tr '[:upper:]' '[:lower:]')

  if [ "$COUNTRY" = "US" ]; then
    PRIMARY_LANG="$LOCALE_CODE"
    PRIMARY_KB="$KB_LAYOUT"
  else
    PRIMARY_LANG="en_US.UTF-8"
    SECONDARY_LANG="$LOCALE_CODE"
    PRIMARY_KB="us"
    SECONDARY_KB="$KB_LAYOUT"
  fi
fi

# Enable locales
sed -i "s/^#\\?\\s*$PRIMARY_LANG/$PRIMARY_LANG/" /etc/locale.gen
if [ -n "$SECONDARY_LANG" ]; then
  sed -i "s/^#\\?\\s*$SECONDARY_LANG/$SECONDARY_LANG/" /etc/locale.gen
fi

# Generate locales
locale-gen

# Set system locale
echo "LANG=$PRIMARY_LANG" > /etc/locale.conf

# Set console keyboard
echo "KEYMAP=$PRIMARY_KB" > /etc/vconsole.conf
echo "FONT=lat2-16" >> /etc/vconsole.conf

# Set X11 keyboard layout
mkdir -p /etc/X11/xorg.conf.d
cat <<EOF > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$PRIMARY_KB${{SECONDARY_KB:+,}}$SECONDARY_KB"
    Option "XkbOptions" "${{SECONDARY_KB:+grp:alt_shift_toggle}}"
EndSection
EOF

# Set timezone
if [ -n "$TIMEZONE" ] && [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
  ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
else
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi

hwclock --systohc"""


def setup_locale_sh() -> str:
    """The live-ISO oneshot: detect + apply locale, then mark complete."""
    return f"""\
#!/bin/bash

{_detect_and_apply_locale_block()}

# Mark setup complete
touch /var/log/.locale_set
"""
