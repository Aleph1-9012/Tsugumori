# Desktop design and runtime notes

## Terminal and widgets

The terminal uses the R2-A header, a glyph illustration, bold 704 badge, and
SID0NIA band, separated from the first prompt by one blank line. Kitty uses
JetBrains Mono with a block cursor. The P4 Bash prompt places the current
directory beside a thin divider, with red brackets around the Git branch at
the right. The brackets remain empty outside Git repositories. A red corner
marks the command line below; failed commands also show their exit status.
The welcome script uses Kitty's text-sizing protocol where available and
normal text elsewhere. Neither script prints into pipes or logs, and the
prompt hook runs only in interactive shells.

Player, Quick Notes, Clipboard, and Quickshare share the red illustrated
curtain. The player's opening and closing timing is 25% longer. Quick Notes
has a COPY/COPIED button beside its save status, sized to match the new-note
button. Clipboard keeps the grid inside its content area, leaves its header
and footer plain, and stops keyboard selection at the list boundaries.

The application menu has a redesigned header, search field, selection markers,
and animated footer buttons. IBM Plex Mono is bundled for the menu and Waybar.
Share Tech Mono remains bundled as an optional font. Font licenses stay beside
their respective font files.

The B2 Control Center uses separate components, summary cards, remembered
submenus, queued slider writes, and less background polling. Per-monitor
brightness is software dimming. It does not change a panel's backlight or save
backlight power. Runtime state remains outside the repository.

Volume and mute are available in the Control Center and through the volume
keys. There is no separate left-edge volume popup or hover area.

Quickshare uses a charcoal, light, and red glyph-style QR image. Tests check
module centres and protected QR regions. These checks do not replace scanning
the displayed result with a phone.

## Native lock and wallpaper picker

The lock replaces the old video wave with native Phase drawing. It has the K
glyph's stronger red typing response, a 15% larger panel, and four animated
corners. The username, clock, date, and password field use the approved layout.
Opening takes 1450 ms and closing takes 950 ms. The animation targets 60 fps;
offscreen tests do not measure frame rate on a real GPU.

The lock retains WlSessionLock, PAM authentication, and the supervised Hyprlock
fallback. The visual tests do not authenticate against a real session. The
wallpaper picker shares the visual components only, including the Phase motion
and live corners. It can reverse an early close request and applies a selected
wallpaper after closing.

GPU drawing uses the compiled shaders in
`config/quickshell/widgets/lockscreen/shaders/`. The source and build script
ship beside them. A CPU drawing fallback remains for software-rendered Qt.
`wave-check.sh` keeps its existing startup entry-point name but now checks
native assets. It does not generate videos at login.

The old MP4s, their frame image, unused decorative components, and retired
Waybar Pomodoro scripts are removed from the installed config. Their previous
versions are recoverable from Git history.

## Upgrades

The installer preserves the user's `hypr/user.lua` and Quickshell
`Settings.qml`. On an existing installation, review the latter if the curtain
is still white: the new default is `curtainColor: "#cc1515"`. Do not replace
personal monitor or scaling settings just to update the colour.
