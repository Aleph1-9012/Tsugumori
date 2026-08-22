# Tsugumori

Knights of Sidonia-inspired Hyprland, Quickshell, and Waybar for Arch Linux.

![Project status: beta](https://img.shields.io/badge/status-beta-c8b89a)
![Hyprland: 0.55.2+](https://img.shields.io/badge/Hyprland-0.55.2%2B-58e1ff)
![License: MIT](https://img.shields.io/badge/license-MIT-7a7358)

<p align="center">
  <a href="https://youtu.be/VwLABphh-E0">
    <img src="https://i.ytimg.com/vi/VwLABphh-E0/maxresdefault.jpg" width="900" alt="Watch the Tsugumori desktop showcase">
  </a>
</p>
<p align="center"><sub>Click the image to watch the full-quality showcase.</sub></p>


<img width="2563" height="1598" alt="2026-08-15-122553_hyprshot" src="https://github.com/user-attachments/assets/ae03e598-540b-41f6-8d92-43b77bc7bd2d" />
<img width="2560" height="1612" alt="2026-08-15-122143_hyprshot" src="https://github.com/user-attachments/assets/6e290d5f-8628-471e-99d9-90cb58182626" />
<img width="2560" height="1618" alt="2026-08-15-122252_hyprshot" src="https://github.com/user-attachments/assets/b63348dc-3717-4faa-b303-193b1c46cb0a" />
<img width="2560" height="1602" alt="2026-08-15-122232_hyprshot" src="https://github.com/user-attachments/assets/93c8a56c-46c9-4371-bdd5-331aff5ace7d" />




> [!NOTE]
> Tsugumori is a credible beta, not a stable release. The installer validates its Hyprland Lua configuration before replacing your existing desktop config and keeps timestamped backups by default.

## Installation

Requirements: Arch Linux, Hyprland 0.55.2 or newer, and a non-root user with
`sudo`. Review the installer before running it.

### Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh)
```

To inspect all options without installing:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh) --help
```

`--latest` is the default. After package installation, the installer asks
Hyprland to parse both the bundled Lua configuration and the candidate config
with preserved user overrides. It stops before deployment if either fails.
`--pinned` also fails closed unless the repository contains complete pinned
manifests; this branch does not currently publish them.

Quickshell 0.3 is a required official package. On upgrades, an already-installed
compatible provider such as `quickshell-git` is retained to avoid a package
conflict; fresh installations use Arch's `quickshell` package.

## What's included

- **Window manager**: Hyprland 0.55.2+ with a native Lua config and custom keybinds (QWERTY layout)
- **Shell/widgets**: Quickshell with custom QML widgets (menu, wallpaper picker, notifications, player)
- **Session lock**: Quickshell `ext-session-lock-v1` surfaces with PAM authentication, animated transitions, and a dedicated Tsugumori Hyprlock fallback
- **Idle/suspend safety**: Hypridle locks after five idle minutes, locks before sleep, and restores displays after resume
- **Bar**: Waybar
- **Terminal**: Kitty
- **Theme**: Knights of Sidonia with custom video transitions

## Release status

`v0.1.2` is a narrow safety hotfix for Tsugumori's public beta, not a stable
release. It makes the installer reject preserved symlinks that depend on paths
deployment will replace, and makes Quickshare sends deliver exactly the bytes
advertised from the opened source file before reporting success. The focused
installer and Quickshare test suites cover the blocker regressions locally,
while the complete release tree remains gated by the required Arch checks in
GitHub Actions. See the [`v0.1.2` release notes](RELEASE_NOTES.md) for known
limitations.

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
  - Send mode uses a fixed 15-second absolute request-header deadline and a
    five-minute absolute download deadline by default. Use
    `qshare send --transfer-timeout SECONDS` to adjust the download deadline.
  - Receive mode defaults to a 1 GiB request limit, 4 GiB cumulative session
    limit, 32 files per request, 128 files per session, at most 16 active
    connections, a request-header deadline capped at 15 seconds, and a
    five-minute overall upload deadline. The `qshare recv --help` flags adjust
    the byte/file quotas and overall upload deadline.
- **Notifications** — History & DND
  - Live history fed by the Quickshell notification daemon (no `mako`/`dunst` needed)
  - Click a notification once to expand (body, urgency, category, app, actions), click again to invoke the source app
  - Do Not Disturb toggle silences popups while preserving history
  - Pinned "Clear All" button

> [!NOTE]
> Tsugumori never stops dunst, mako, swaync, or any other third-party
> notification daemon. Only one process can own `org.freedesktop.Notifications`
> at a time, so if such a daemon is running it will keep receiving your
> notifications and Tsugumori's popups and history will stay empty. To use
> Tsugumori notifications, disable the competing daemon in its own user service
> or autostart configuration — see that daemon's documentation for how.

### Navigation

The menu uses two interaction levels (the internal names retain their original
L1/L3 numbering):

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

Personal overrides go in `~/.config/hypr/user.lua` — this file is **never**
overwritten by updates. It loads after Tsugumori's defaults, so later calls
override the base configuration. Unbind a bundled shortcut before replacing it.

Example:
```lua
hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
hl.config({ input = { kb_layout = "us" } })
hl.unbind("SUPER + T")
hl.bind("SUPER + T", hl.dsp.exec_cmd("foot"))
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
do not force the installer past that check. Fix the reported Lua error in a
preserved `user.lua`, or use a compatible Tsugumori revision. Downgrading
Hyprland by itself on a rolling Arch system may leave its companion libraries
out of sync. Restore your previous configuration from the timestamped
`~/.config-backup-*` directory if a later step is interrupted.

Upgrades preserve a legacy `~/.config/hypr/user.conf`, but Lua does not load
that file. Translate active machine-specific overrides to `user.lua` before
installing; the installer refuses to proceed when doing otherwise would
silently discard them.

Upgrades from the former Quickshell/pamtester lock may leave an unused
`/etc/pam.d/qs-lock` file. The installer warns instead of deleting a system PAM
file automatically; remove it only after confirming no local service uses it.

The animated lock is a real compositor session lock. Its launcher supervises
startup and requires an explicit readiness handshake; a QML/import failure,
timeout, or early exit starts Hyprlock instead. The installer deploys the same
English-language Tsugumori emergency screen for every user, using the bundled
`Aleph1.png` wallpaper rather than an image inherited from a pre-existing rice.
Hyprland's session-lock restore option also lets that fallback replace a lock
client which crashes after acquisition. `SUPER + R` targets only the
desktop-shell instance and never kills the independent lock process.

## Credits

Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell).

Inspired by [flickowoa/dotfiles](https://github.com/flickowoa/dotfiles).

Inspired by [samyns/Unit-3](https://github.com/samyns/Unit-3).


## License

MIT
