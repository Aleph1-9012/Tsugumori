# Configuration map

The installer copies these folders into `~/.config`. You do not need to
understand every file to customize Tsugumori.

| I want to change... | Open... |
|---|---|
| Hyprland keybindings, monitors, or input | `hypr/user.lua` |
| Hyprland defaults | `hypr/hyprland.lua` |
| Lock and idle timing | `hypr/hypridle.conf` |
| Emergency lock-screen appearance | `hypr/hyprlock.conf` |
| Terminal colors and font | `kitty/kitty.conf` |
| Quickshell colors, fonts, and spacing | `quickshell/theme/Theme.qml` |
| Quickshell user options | `quickshell/settings/Settings.qml` |
| Launcher, Control Center, or panels | `quickshell/widgets/` |
| Waybar modules | `waybar/config.jsonc` |
| Waybar appearance | `waybar/style.css` |

## What upgrades preserve

The installer preserves these two personal files:

- `~/.config/hypr/user.lua`
- `~/.config/quickshell/settings/Settings.qml`

Other files inside the installed configuration can be replaced during an
upgrade. Keep long-term Hyprland changes in `user.lua`, and keep a copy of any
larger theme changes in your own fork.

The folders named `components`, `services`, `theme`, and `widgets` are internal
parts of Quickshell. Their `qmldir` files register QML types and should normally
be left in place.

For examples, see the [customization guide](../docs/customize.md).
