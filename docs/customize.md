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
| Waybar modules | `~/.config/waybar/config.jsonc` |
| Waybar style | `~/.config/waybar/style.css` |
| Wallpapers | `~/Pictures/wallpapers/` |

Only `user.lua` and `Settings.qml` are preserved automatically. Keep a backup
or use your own fork for changes to the other installed files.

## Hyprland examples

```lua
hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
hl.config({ input = { kb_layout = "us" } })
hl.unbind("SUPER + T")
hl.bind("SUPER + T", hl.dsp.exec_cmd("foot"))
```

Unbind a bundled shortcut before assigning a replacement to the same keys.

## Wallpapers

Place JPG, PNG, or WebP images in `~/Pictures/wallpapers/`, then press
`SUPER + P`. The installer can copy the bundled wallpapers into that folder for
you.

See the [configuration map](../config/README.md) when you are unsure which file
controls a feature.
