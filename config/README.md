# Configuration map

The paths below are relative to your installed `~/.config` directory.
They can differ from the source locations in this repository.

| I want to change... | Open... |
|---|---|
| Hyprland keybindings, monitors, or input | `hypr/user.lua` |
| Hyprland defaults | `hypr/hyprland.lua` |
| Lock and idle timing | `hypr/hypridle.conf` |
| Emergency lock-screen appearance | `hypr/hyprlock.conf` |
| Terminal colors and font | `kitty/kitty.conf` |
| Fastfetch layout | `fastfetch/config.jsonc` |
| btop colors and layout | `btop/themes/tsugumori.theme` and `btop/btop.conf` |
| Quickshell colors, fonts, and spacing | `quickshell/theme/Theme.qml` |
| Quickshell user options | `quickshell/settings/Settings.qml` |
| Launcher, Control Center, or panels | `quickshell/widgets/` |
| Waybar modules | `waybar/config.jsonc` |
| Waybar appearance | `waybar/style.css` |
| Nautilus appearance | `nautilus/tsugumori/style.css` |
| GTK file-dialog appearance | `nautilus/tsugumori/filechooser-gtk3.css` and `filechooser-gtk4.css` |

Kitty, Fastfetch, and btop files share `kitty/` in the repository. The installer
puts each file in its application's normal location: `~/.config/kitty/`,
`~/.config/fastfetch/config.jsonc`, and `~/.config/btop/`.

The optional Nautilus theme stays together in `nautilus/` in the repository.
The installer places its extension in the user data directory, copies the theme
assets into `~/.config/nautilus/tsugumori/`, builds the GTK 3 dialog module, and
adds the scoped GTK 4 stylesheet import. See the
[customization guide](../docs/customize.md#nautilus-and-file-dialogs) for details.

## What upgrades preserve

The installer preserves these personal desktop files:

- `~/.config/hypr/user.lua`
- `~/.config/quickshell/settings/Settings.qml`

It also retains an existing `hypr/user.conf` for migration, though the Lua
configuration does not load it. Personal Bash overrides in `~/.bashrc.local`
are left untouched.

Other files inside the installed configuration can be replaced during an
upgrade. Keep long-term Hyprland changes in `user.lua`, and keep a copy of any
larger theme changes in your own fork.

The folders named `components`, `services`, `theme`, and `widgets` are internal
parts of Quickshell. Their `qmldir` files register QML types and should normally
be left in place.

For examples, see the [customization guide](../docs/customize.md).
