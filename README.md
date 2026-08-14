**Sidonia/Tsugumori** by Aleph1-9012 — Knights of Sidonia inspired palette.

> [!WARNING]
> **Hyprland configuration migration** — This branch still uses Hyprlang. Hyprland deprecated that format in 0.55 in favor of Lua, but 0.55.2 still parses this configuration. The installer validates the bundled config with the installed Hyprland binary before replacing user files; a Lua port is still required before legacy support is removed upstream.

# Tsugumori

Hyprland + Quickshell + Waybar rice for Arch Linux, with a Knights of Sidonia aesthetic.



# SHOW OFF



https://github.com/user-attachments/assets/5b950538-f5c5-4334-abc7-b451dc3d63a0


Better quality showcase :https://youtu.be/VwLABphh-E0?si=obrjjakcOhFq8bV5

## Installation

Requirements: Arch Linux and a non-root user with `sudo`. Review the installer before running it.

### Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh)
```

To inspect all options without installing:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh) --help
```

`--latest` is the default. After package installation, the installer asks Hyprland to parse the bundled configuration and stops before deploying it if validation fails. `--pinned` also fails closed unless the repository contains complete pinned manifests; this branch does not currently publish them.

Quickshell 0.3 is a required official package. On upgrades, an already-installed
compatible provider such as `quickshell-git` is retained to avoid a package
conflict; fresh installations use Arch's `quickshell` package.
 
## What's included

- **Window manager**: Hyprland with custom keybinds (QWERTY layout)
- **Shell/widgets**: Quickshell with custom QML widgets (menu, wallpaper picker, notifications, player)
- **Session lock**: Quickshell `ext-session-lock-v1` surfaces with PAM authentication and the original animated NieR reveal/hide design
- **Idle/suspend safety**: Hypridle locks after five idle minutes, locks before sleep, and restores displays after resume
- **Bar**: Waybar
- **Terminal**: Kitty
- **Theme**: Knights of Sidonia with custom video transitions

## Control Center

A NieR:Automata-style radial menu with Knights of Sidonia theme accessible via `SUPER + Tab`. The interface is built around a cross of four sub-menus orbiting a central node, with full keyboard navigation.

> [!NOTE]
> The Control Center is embedded in the main Quickshell instance and exposes an IPC target named `ctrl`. It can be toggled from anywhere via `qs ipc call ctrl toggle`.


### Features

- **Connexion** — Wi-Fi & Bluetooth
  - Toggle radio on/off
  - Scan and connect to Wi-Fi networks with an inline password prompt (no external GUI)
  - List paired Bluetooth devices with connect/disconnect, pair, unpair, and live scan for new devices
- **Audio** — Output & Volume
  - Switch between PipeWire/PulseAudio sinks on the fly
  - Interactive volume slider (click to set, scroll to adjust, right-click to mute)
- **Quickshare** — Send & Receive over HTTP/QR
  - Pick files via a floating Yazi instance and share them over the local network
  - Scan a tokenized QR code from a phone to send or receive files
  - Optionally expose a temporary HTTPS Cloudflare tunnel for remote transfers
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
```ini
monitor = DP-1, 2560x1440@144, 0x0, 1
input { kb_layout = us }
bind = SUPER, B, exec, firefox
```

## Keybinds

| Key | Action |
|-----|--------|
| `SUPER` (tap) | Open app menu |
| `SUPER + L` | Lockscreen |
| `SUPER + T` | Terminal (kitty) |
| `SUPER + Return` | Toggle Quickshell player |
| `SUPER + R` | Restart only the main Quickshell desktop shell |
| `SUPER + P` | Wallpaper picker |
| `SUPER + Q` | Close window |
| `SUPER + F` | Fullscreen |
| `ALT + Tab` | Cycle windows |
| `ALT + 1/2/3/...` | Switch workspace (QWERTY) |
| `Print` | Screenshot |
| `ALT SHIFT + S` | Region screenshot |

## Troubleshooting

If installation stops because Hyprland cannot parse the bundled configuration,
do not force the installer past that check. Use a compatible Tsugumori branch or
wait for the Lua configuration port. Downgrading Hyprland by itself on a rolling
Arch system may leave its companion libraries out of sync. Restore your previous
configuration from the timestamped `~/.config-backup-*` directory if a later
step is interrupted.

Upgrades from the former Quickshell/pamtester lock may leave an unused
`/etc/pam.d/qs-lock` file. The installer warns instead of deleting a system PAM
file automatically; remove it only after confirming no local service uses it.

The animated lock is a real compositor session lock: if its dedicated
Quickshell process crashes while locked, Hyprland intentionally remains locked
instead of exposing the desktop. Hyprlock remains installed as the PAM service
provider and administrator fallback; its configuration is
`~/.config/hypr/hyprlock.conf`. Recovering an abandoned compositor lock still
requires an explicit TTY recovery procedure (or terminating the graphical
session); another lock client cannot silently take it over. `SUPER + R` targets
only the desktop-shell instance and never kills the independent lock process.
If a missing runtime or asset is detected before Quickshell starts, the launcher
uses Hyprlock immediately so a lock request does not fail open.

## Credits

Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell).

Inspired by https://github.com/flickowoa/dotfiles.git 

Inspired by https://github.com/samyns/Unit-3


## License

MIT
