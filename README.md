**Sidonia/Tsugumori** by Aleph1-9012 — Knights of Sidonia inspired palette.

> [!WARNING]

> **Hyprland v0.55+ Lua migration** — This config uses legacy hyprlang syntax (supported until ~v0.57). Pin to v0.54 or wait for the Lua port. 

# Tsugumori

Hyprland + Quickshell + Waybar rice for Arch Linux, with a Knights of Sidonia aesthetic.



# SHOW OFF


https://github.com/user-attachments/assets/af51b507-1511-4ae2-ab97-889a92a6597f




### Quick install

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh](https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh))
```
 OR 
 ```
curl -fsSL [https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh](https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh) | bash
 ```
 
## What's included

- **Window manager**: Hyprland with custom keybinds (QWERTY layout)
- **Shell/widgets**: Quickshell with custom QML widgets (menu, lockscreen, wallpaper picker, notifications, player)
- **Bar**: Waybar
- **Terminal**: Kitty
- **Theme**: Knights of Sidonia with custom video transitions

## Control Center

A NieR:Automata-style radial menu with Knights of Sidonia theme accessible via `SUPER + Tab`. The interface is built around a cross of four sub-menus orbiting a central node, with full keyboard navigation.

> [!NOTE]
> The Control Center runs as a separate Quickshell instance and exposes an IPC target named `ctrl`. It can also be toggled from anywhere via `qs ipc call ctrl toggle`.


### Features

- **Connexion** — Wi-Fi & Bluetooth
  - Toggle radio on/off
  - Scan and connect to Wi-Fi networks with an inline password prompt (no external GUI)
  - List paired Bluetooth devices with connect/disconnect, pair, unpair, and live scan for new devices
- **Audio** — Output & Volume
  - Switch between PipeWire/PulseAudio sinks on the fly
  - Interactive volume slider (click to set, scroll to adjust, right-click to mute)
- **Quickshare** — Send & Receive (KDE Connect)
  - Pick files via a floating Yazi instance and send to paired devices
  - Pair/unpair devices directly from the panel, with a refresh button for discovery
  - Falls back to a clear "Install KDE Connect" prompt if missing
- **Notifications** — History & DND
  - Live history fed by the Quickshell notification daemon (no `mako`/`dunst` needed)
  - Click a notification once to expand (body, urgency, category, app, actions), click again to invoke the source app
  - Do Not Disturb toggle silences popups while preserving history
  - Pinned "Clear All" button

### Navigation

The menu uses three focus levels:

- **L1 — Overview**: navigate between the four slots and the center node
- **L3 — Settings**: focus inside a sub-menu (sub-item + first action are focused simultaneously)

| Key | Action |
|---|---|
| `W` / `↑` | Move up (or scroll up in lists) |
| `A` / `←` | Move left (or scroll left in actions) |
| `S` / `↓` | Move down (or scroll down in lists) |
| `D` / `→` | Move right (or scroll right in actions) |
| `Enter` / `Space` | Activate focused action (or expand a notification) |
| `Esc` | Back to center (or close menu) |

**From the center node**, pressing any direction enters the corresponding sub-menu directly (no double-press). **From a slot**, pressing the same direction enters its settings; pressing the opposite direction returns to center.

When you focus a sub-menu, the whole cross slides ("pulls the tablecloth") to bring the focused panel closer to the center, while the other slots dim but stay visible.


## Customization

Personal overrides go in `~/.config/hypr/user.conf` — this file is **never** overwritten by updates.

Example:
monitor = DP-1, 2560x1440@144, 0x0, 1
input { kb_layout = us }
bind = SUPER, B, exec, firefox

## Keybinds

| Key | Action |
|-----|--------|
| `SUPER` (tap) | Open app menu |
| `SUPER + L` | Lockscreen |
| `SUPER + T` | Terminal (kitty) |
| `SUPER + Return` | Toggle Quickshell player |
| `SUPER + P` | Wallpaper picker |
| `SUPER + Q` | Close window |
| `SUPER + F` | Fullscreen |
| `ALT + Tab` | Cycle windows |
| `ALT + 1/2/3/...` | Switch workspace (QWERTY) |
| `Print` | Screenshot |
| `ALT SHIFT + S` | Region screenshot |

## Credits

Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell).

Inspired by https://github.com/flickowoa/dotfiles.git 

Inspired by https://github.com/samyns/Unit-3

## License

MIT
EOF
