# Customize Tsugumori

Most personal Hyprland changes belong in `~/.config/hypr/user.lua`. The
installer preserves this file during upgrades and loads it after Tsugumori's
defaults.

## Common files

| Change | File |
|---|---|
| Monitors, keyboard layout, and keybindings | `~/.config/hypr/user.lua` |
| Quickshell options | `~/.config/quickshell/settings/Settings.qml` |
| Quickshell theme | `~/.config/quickshell/theme/Theme.qml` |
| Kitty | `~/.config/kitty/kitty.conf` |
| Fastfetch | `~/.config/fastfetch/config.jsonc` |
| btop | `~/.config/btop/btop.conf` and `~/.config/btop/themes/tsugumori.theme` |
| Waybar modules | `~/.config/waybar/config.jsonc` |
| Waybar style | `~/.config/waybar/style.css` |
| Nautilus appearance | `~/.config/nautilus/tsugumori/style.css` |
| GTK file-dialog appearance | `~/.config/nautilus/tsugumori/filechooser-gtk3.css` and `filechooser-gtk4.css` |
| Wallpapers | `~/Pictures/wallpapers/` |

Within the managed desktop configuration, `user.lua` and `Settings.qml` are
preserved automatically. An existing legacy `hypr/user.conf` is retained for
migration but is not loaded. Personal Bash overrides in `~/.bashrc.local` are
left untouched. Keep a backup or use your own fork for changes to other files.

## Hyprland examples

```lua
hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
hl.config({ input = { kb_layout = "us" } })
hl.unbind("SUPER + T")
hl.bind("SUPER + T", hl.dsp.exec_cmd("foot"))
```

Unbind a bundled shortcut before assigning a replacement to the same keys.

## Desktop GPU selection

Open the **Control Center** with `SUPER + Tab`, then **Audio / Display → GPU**.
With multiple PCI graphics cards, choose **Automatic** or a GPU, then
**Save for next login**. Log out and back in
when ready, or reboot yourself. Saving never switches a running desktop or
triggers logout, reboot, driver changes, a hardware MUX switch, or GPU power-off.

This selects Hyprland's primary renderer, not a forced GPU for every application.
Other detected GPUs stay in the device list so their connected displays remain
available. Multi-GPU rendering still depends on driver support.

**ACTIVE** marks the desktop's primary GPU, read from the current Hyprland
session log and matched to a detected device. **NEXT LOGIN** marks a saved
change that is pending. Selecting a row alone does not save or activate it.
**UNKNOWN** means the active GPU could not be verified, for example when the
session log is missing or does not contain a primary-device marker. The panel
never treats a saved preference as proof of the active GPU. It refreshes when
opened or when **Refresh GPUs** is pressed. Applications can use a different
GPU from the desktop's primary renderer.

Selection requires a Hyprland session launched with **UWSM**. Other launch
methods show an explanation without changing anything. The helper adds a marked
block to `~/.config/uwsm/env-hyprland`, preserving unrelated contents and refusing
to overwrite an existing manual `AQ_DRM_DEVICES` setting there. Do not combine
this selector with GPU overrides in shell profiles, Hyprland config, or other
environment files. Symlinked startup files must be managed in your dotfiles.

PCI identity is saved instead of a changing `card0`/`card1` number. Device paths
are resolved again at login. If the selected card is absent, or the helper cannot
run, the block leaves normal GPU selection in place. **Automatic** removes only
Tsugumori's marked block. It can also clear a saved selection after unplugging a
GPU or leaving a UWSM session. This startup file is outside the installer's
managed directories, so the choice survives theme upgrades.

If a selection prevents login, use a TTY to remove the block between
`# BEGIN TSUGUMORI GPU PREFERENCE` and `# END TSUGUMORI GPU PREFERENCE` in
`~/.config/uwsm/env-hyprland`, then log in again. Keep the rest of that file.

The selector follows [Hyprland's GPU priority mechanism](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Multi-GPU/)
and [UWSM's startup environment](https://github.com/Vladimir-csp/uwsm#4-environments-and-shell-profile).

## Battery indicator

Waybar shows `BAT 75%` beside volume, with a `+` while charging. Below 20% the
text turns red; below 10% the module uses a red background. Change these levels
in the `battery.states` section of `~/.config/waybar/config.jsonc`.

## Nautilus and file dialogs

Nautilus is the default file manager, including the menu's Files button.
Quickshare uses a GTK file picker. Both are installed with the base desktop.

Choose the optional Nautilus theme during installation to add the dark slash
header, sidebar dividers, red selection marks, outline icons and matching
menus. The extension preserves Nautilus's native file operations. Its font
settings also include the label-clipping fix used by the live theme.

The theme option adds `nautilus-python`, `fontconfig`, `gcc` and `pkgconf`
from the current Arch repositories. These optional theme packages are
not pinned, even with `--pinned`. The GTK 3 module is built from source on the
destination machine. No compiled module is bundled in the repository.

The installer copies only Tsugumori-owned files, leaves other extensions and
Nautilus settings alone, and adds one import to existing GTK 4 CSS. Existing
files changed by this step follow the installer's backup choice. Custom
symlinks at shared configuration files must be managed manually.

Installed locations, relative to the normal XDG config and data directories:

- `~/.config/nautilus/tsugumori/`: styles, icons, IBM Plex Sans font, licenses
  and the locally built GTK 3 module.
- `~/.local/share/nautilus-python/extensions/tsugumori.py`: Nautilus appearance
  extension, using the [standard extension location](https://gnome.pages.gitlab.gnome.org/nautilus-python/nautilus-python-overview.html).
- `~/.config/gtk-4.0/gtk.css`: one import for styles scoped to GTK 4 file choosers.
- `~/.config/environment.d/80-tsugumori-filechooser.conf`: adds the GTK 3 module
  through [GTK3_MODULES](https://docs.gtk.org/gtk3/running.html#environment-variables),
  preserving other modules. The module styles file chooser dialogs only.

Log out and back in after installing the theme. The theme does not change the
global icon theme. Qt, browser-built and sandboxed file dialogs
may use their own appearance. The Nautilus styling uses internal widget names
and was checked with Nautilus 50 and GTK 4.22; future versions may need updates.

To disable the theme, move `tsugumori.py` out of the extensions directory,
remove only the Tsugumori import from `gtk.css`, and remove its `GTK3_MODULES`
line from `80-tsugumori-filechooser.conf`. Leave any other settings intact, then
log out and back in. Theme assets can remain in place while disabled.

## Lock at login

Tsugumori locks the screen right after Hyprland starts, so an autologin
session still asks for a password. To turn this off, add this line to
`~/.config/hypr/user.lua`:

```lua
tsugumori.lock_at_login = false
```

It takes effect at the next login. `SUPER + L`, idle locking, and the menu's
LOCK button are unaffected.

## Wallpapers

Place JPG, PNG, or WebP images in `~/Pictures/wallpapers/`, then press
`SUPER + P`. The installer can copy the bundled wallpapers into that folder for
you.

See the [configuration map](../config/README.md) when you are unsure which file
controls a feature.
