"""The small, hand-tuned KDE config files, as Python strings.

These are the minimal-Plasma tweaks that make the desktop stripped-down: a dark
Breeze color scheme, a single panel, a flattened application menu, and the
migration/update bookkeeping Plasma expects. The two LARGE upstream files
(main.qml, Footer.qml) are NOT here -- they stay verbatim under libraries/data/kde/
and are copied by steps.py (wrapping 365 lines of third-party QML in a Python
string is pure escaping risk with no gain).

The KDE 'Next' wallpaper package was removed in the overhaul; nothing here
references it. wallpaperplugin=org.kde.image is Plasma's default image plugin and
falls back to the stock Breeze wallpaper.
"""

from __future__ import annotations

KDEGLOBALS = """\
[ColorEffects:Disabled]
ChangeSelectionColor=
Color=56,56,56
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
Enable=
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=112,111,110
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=30,87,116
BackgroundNormal=49,54,59
DecorationFocus=61,174,233
DecorationHover=61,174,233
ForegroundActive=61,174,233
ForegroundInactive=161,169,177
ForegroundLink=29,153,243
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundNormal=252,252,252
ForegroundPositive=39,174,96
ForegroundVisited=155,89,182

[Colors:Complementary]
BackgroundAlternate=30,87,116
BackgroundNormal=42,46,50
DecorationFocus=61,174,233
DecorationHover=61,174,233
ForegroundActive=61,174,233
ForegroundInactive=161,169,177
ForegroundLink=29,153,243
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundNormal=252,252,252
ForegroundPositive=39,174,96
ForegroundVisited=155,89,182

[Colors:Header]
BackgroundAlternate=42,46,50
BackgroundNormal=49,54,59
DecorationFocus=61,174,233
DecorationHover=61,174,233
ForegroundActive=61,174,233
ForegroundInactive=161,169,177
ForegroundLink=29,153,243
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundNormal=252,252,252
ForegroundPositive=39,174,96
ForegroundVisited=155,89,182

[Colors:Header][Inactive]
BackgroundAlternate=49,54,59
BackgroundNormal=42,46,50
DecorationFocus=61,174,233
DecorationHover=61,174,233
ForegroundActive=61,174,233
ForegroundInactive=161,169,177
ForegroundLink=29,153,243
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundNormal=252,252,252
ForegroundPositive=39,174,96
ForegroundVisited=155,89,182

[Colors:Selection]
BackgroundAlternate=30,87,116
BackgroundNormal=61,174,233
DecorationFocus=61,174,233
DecorationHover=61,174,233
ForegroundActive=252,252,252
ForegroundInactive=161,169,177
ForegroundLink=253,188,75
ForegroundNegative=176,55,69
ForegroundNeutral=198,92,0
ForegroundNormal=252,252,252
ForegroundPositive=23,104,57
ForegroundVisited=155,89,182

[Colors:Tooltip]
BackgroundAlternate=42,46,50
BackgroundNormal=49,54,59
DecorationFocus=61,174,233
DecorationHover=61,174,233
ForegroundActive=61,174,233
ForegroundInactive=161,169,177
ForegroundLink=29,153,243
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundNormal=252,252,252
ForegroundPositive=39,174,96
ForegroundVisited=155,89,182

[Colors:View]
BackgroundAlternate=35,38,41
BackgroundNormal=27,30,32
DecorationFocus=61,174,233
DecorationHover=61,174,233
ForegroundActive=61,174,233
ForegroundInactive=161,169,177
ForegroundLink=29,153,243
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundNormal=252,252,252
ForegroundPositive=39,174,96
ForegroundVisited=155,89,182

[Colors:Window]
BackgroundAlternate=49,54,59
BackgroundNormal=42,46,50
DecorationFocus=61,174,233
DecorationHover=61,174,233
ForegroundActive=61,174,233
ForegroundInactive=161,169,177
ForegroundLink=29,153,243
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundNormal=252,252,252
ForegroundPositive=39,174,96
ForegroundVisited=155,89,182

[General]
ColorSchemeHash=3b0b7b7f6fa70c9f360b5a78837836d8971524f3

[KDE]
LookAndFeelPackage=org.kde.breezedark.desktop

[WM]
activeBackground=49,54,59
activeBlend=252,252,252
activeForeground=252,252,252
inactiveBackground=42,46,50
inactiveBlend=161,169,177
inactiveForeground=161,169,177
"""

KWINRC = """\
[Desktops]
Id_1=9d116a43-4825-442c-abbf-41ac8d5d6a71
Number=1
Rows=1

[Plugins]
shakecursorEnabled=false

[Tiling]
padding=4

[Tiling][4c85f5bb-4dcb-5bec-8433-5c0e6860d679]
tiles={"layoutDirection":"horizontal","tiles":[{"width":0.25},{"width":0.5},{"width":0.25}]}

[Xwayland]
Scale=1
"""

# The [Updates] performed= line is a single very long comma-joined path list that
# Plasma writes to mark which migration scripts have already run. Assembled from a
# list so it stays readable and is guaranteed to be one line with no stray breaks.
_PLASMA_UPDATES = ",".join(
    "/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/" + name
    for name in (
        "migrate_font_weights.js",
        "unlock_widgets.js",
        "maintain_existing_desktop_icon_sizes.js",
        "folderview_fix_recursive_screenmapping.js",
        "digitalclock_rename_timezonedisplay_key.js",
        "containmentactions_middlebutton.js",
        "digitalclock_migrate_font_settings.js",
        "mediaframe_migrate_useBackground_setting.js",
        "systemloadviewer_systemmonitor.js",
        "keyboardlayout_migrateiconsetting.js",
        "move_desktop_layout_config.js",
        "keyboardlayout_remove_shortcut.js",
        "klipper_clear_config.js",
        "digitalclock_migrate_showseconds_setting.js",
        "no_middle_click_paste_on_panels.js",
    )
)

PLASMASHELLRC = f"""\
[PlasmaViews][Panel 2]
floating=0

[PlasmaViews][Panel 2][Defaults]
thickness=44

[Updates]
performed={_PLASMA_UPDATES}
"""

# Flattened application menu: everything visible, dev/debug .desktop files pushed
# into a hidden submenu. The exclude list and the hidden-include list are the same
# set, so it's authored once and reused for both.
_HIDDEN_DESKTOPS = (
    "lftp.desktop",
    "stoken-gui.desktop",
    "stoken-gui-small.desktop",
    "org.kde.kmenuedit.desktop",
    "bssh.desktop",
    "nm-connection-editor.desktop",
    "bvnc.desktop",
    "avahi-discover.desktop",
    "org.kde.drkonqi.coredump.gui.desktop",
    "lstopo.desktop",
    "org.kde.plasmaengineexplorer.desktop",
    "org.kde.plasma.themeexplorer.desktop",
    "assistant.desktop",
    "qdbusviewer.desktop",
    "linguist.desktop",
    "qv4l2.desktop",
    "qvidcap.desktop",
    "designer.desktop",
    "org.kde.kuserfeedback-console.desktop",
)


def _menu_filenames(indent: str) -> str:
    return "\n".join(f"{indent}<Filename>{d}</Filename>" for d in _HIDDEN_DESKTOPS)


APPLICATIONS_MENU = f"""\
<!DOCTYPE Menu PUBLIC '-//freedesktop//DTD Menu 1.0//EN' 'http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd'>
<Menu>
 <Name>Applications</Name>
 <!-- No merging of defaults -->
 <Include>
  <All/>
 </Include>
 <!-- Explicitly flatten everything -->
 <Exclude>
{_menu_filenames("  ")}
 </Exclude>
 <Menu>
  <Name>.hidden</Name>
  <Include>
{_menu_filenames("   ")}
  </Include>
 </Menu>
 <Layout>
  <Merge type="files"/>
 </Layout>
</Menu>
"""

APPLETSRC = """\
[ActionPlugins][0]
MiddleButton;NoModifier=org.kde.paste
RightButton;NoModifier=org.kde.contextmenu

[ActionPlugins][1]
RightButton;NoModifier=org.kde.contextmenu

[Containments][2]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][2][Applets][20]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][2][Applets][20][Configuration]
popupHeight=400
popupWidth=560

[Containments][2][Applets][21]
immutability=1
plugin=org.kde.plasma.showdesktop

[Containments][2][Applets][3]
immutability=1
plugin=org.kde.plasma.kickoff

[Containments][2][Applets][3][Configuration]
PreloadWeight=100
popupHeight=508
popupWidth=647

[Containments][2][Applets][3][Configuration][General]
favoritesPortedToKAstats=true

[Containments][2][Applets][4]
immutability=1
plugin=org.kde.plasma.pager

[Containments][2][Applets][5]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][2][Applets][5][Configuration][General]
launchers=

[Containments][2][Applets][6]
immutability=1
plugin=org.kde.plasma.marginsseparator

[Containments][2][Applets][7]
activityId=
formfactor=0
immutability=1
lastScreen=-1
location=0
plugin=org.kde.plasma.systemtray
popupHeight=432
popupWidth=432
wallpaperplugin=org.kde.image

[Containments][2][Applets][7][Applets][10]
immutability=1
plugin=org.kde.plasma.devicenotifier

[Containments][2][Applets][7][Applets][11]
immutability=1
plugin=org.kde.plasma.cameraindicator

[Containments][2][Applets][7][Applets][12]
immutability=1
plugin=org.kde.plasma.keyboardindicator

[Containments][2][Applets][7][Applets][13]
immutability=1
plugin=org.kde.plasma.printmanager

[Containments][2][Applets][7][Applets][14]
immutability=1
plugin=org.kde.plasma.keyboardlayout

[Containments][2][Applets][7][Applets][15]
immutability=1
plugin=org.kde.plasma.clipboard

[Containments][2][Applets][7][Applets][16]
immutability=1
plugin=org.kde.plasma.vault

[Containments][2][Applets][7][Applets][17]
immutability=1
plugin=org.kde.plasma.notifications

[Containments][2][Applets][7][Applets][18]
immutability=1
plugin=org.kde.plasma.volume

[Containments][2][Applets][7][Applets][18][Configuration][General]
migrated=true

[Containments][2][Applets][7][Applets][19]
immutability=1
plugin=org.kde.kscreen

[Containments][2][Applets][7][Applets][22]
immutability=1
plugin=org.kde.plasma.battery

[Containments][2][Applets][7][Applets][23]
immutability=1
plugin=org.kde.plasma.brightness

[Containments][2][Applets][7][Applets][24]
immutability=1
plugin=org.kde.plasma.networkmanagement

[Containments][2][Applets][7][Applets][8]
immutability=1
plugin=org.kde.plasma.manage-inputmethod

[Containments][2][Applets][7][Applets][9]
immutability=1
plugin=org.kde.plasma.weather

[Containments][2][Applets][7][General]
extraItems=org.kde.plasma.manage-inputmethod,org.kde.plasma.weather,org.kde.plasma.battery,org.kde.plasma.brightness,org.kde.plasma.devicenotifier,org.kde.plasma.cameraindicator,org.kde.plasma.keyboardindicator,org.kde.plasma.printmanager,org.kde.plasma.keyboardlayout,org.kde.plasma.bluetooth,org.kde.plasma.clipboard,org.kde.plasma.vault,org.kde.plasma.notifications,org.kde.plasma.networkmanagement,org.kde.plasma.volume,org.kde.kscreen,org.kde.plasma.mediacontroller,org.kde.plasma.kclock_1x2
knownItems=org.kde.plasma.manage-inputmethod,org.kde.plasma.weather,org.kde.plasma.battery,org.kde.plasma.brightness,org.kde.plasma.devicenotifier,org.kde.plasma.cameraindicator,org.kde.plasma.keyboardindicator,org.kde.plasma.printmanager,org.kde.plasma.keyboardlayout,org.kde.plasma.bluetooth,org.kde.plasma.clipboard,org.kde.plasma.vault,org.kde.plasma.notifications,org.kde.plasma.networkmanagement,org.kde.plasma.volume,org.kde.kscreen,org.kde.plasma.mediacontroller,org.kde.plasma.kclock_1x2

[Containments][2][General]
AppletOrder=3;4;5;6;7;20;21

[Containments][22]
ItemGeometries-1280x800=
ItemGeometriesHorizontal=
activityId=3995334c-a0f0-4ad0-bae0-76dfcc7ad726
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][22][General]
positions={"1280x800":[]}

[ScreenMapping]
itemsOnDisabledScreens=
screenMapping=
"""
