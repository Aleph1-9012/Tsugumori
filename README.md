# Tsugumori

Knights of Sidonia-inspired Hyprland desktop for Arch Linux.

![Project status: beta](https://img.shields.io/badge/status-beta-c8b89a)
![Hyprland: 0.55.2+](https://img.shields.io/badge/Hyprland-0.55.2%2B-58e1ff)
![License: MIT](https://img.shields.io/badge/license-MIT-7a7358)

<p align="center">
  <img src="https://i.ytimg.com/vi/VwLABphh-E0/maxresdefault.jpg" width="900" alt="Tsugumori desktop showcase">
  <br>
  <a href="https://youtu.be/VwLABphh-E0">Watch the showcase in higher quality on YouTube</a>
</p>

## Screenshots

<p align="center">
  <img width="49%" alt="Tsugumori desktop screenshot 1" src="https://github.com/user-attachments/assets/ae03e598-540b-41f6-8d92-43b77bc7bd2d">
  <img width="49%" alt="Tsugumori desktop screenshot 2" src="https://github.com/user-attachments/assets/6e290d5f-8628-471e-99d9-90cb58182626">
</p>
<p align="center">
  <img width="49%" alt="Tsugumori desktop screenshot 3" src="https://github.com/user-attachments/assets/b63348dc-3717-4faa-b303-193b1c46cb0a">
  <img width="49%" alt="Tsugumori desktop screenshot 4" src="https://github.com/user-attachments/assets/93c8a56c-46c9-4371-bdd5-331aff5ace7d">
</p>

> [!NOTE]
> Tsugumori is currently a beta. The installer checks the configuration before
> replacing anything and keeps timestamped backups by default.

## Install

You need Arch Linux, Hyprland 0.55.2 or newer, a normal user account, and
`sudo` access.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh)
```

To see the available installer options without changing your system:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh) --help
```

Tsugumori uses official Arch packages. Share Tech Mono and its license are
included in the repository, so the installer does not need an AUR helper.

## What you get

- Hyprland with a native Lua configuration and custom keybindings
- A NieR:Automata-style Control Center with a Knights of Sidonia theme
- Quickshell launcher, lock screen, notifications, player, and wallpaper picker
- Wi-Fi, Bluetooth, audio, and Quickshare controls
- Waybar and Kitty configurations
- Animated transitions and bundled wallpapers

## Change the basics

| What you want to change | Where to look |
|---|---|
| Keybindings, monitors, or keyboard layout | [`config/hypr/user.lua`](config/hypr/user.lua) |
| Colors, fonts, or spacing | [`config/quickshell/theme/Theme.qml`](config/quickshell/theme/Theme.qml) |
| Quickshell options | [`config/quickshell/settings/Settings.qml`](config/quickshell/settings/Settings.qml) |
| Terminal appearance | [`config/kitty/kitty.conf`](config/kitty/kitty.conf) |
| Waybar | [`config/waybar/`](config/waybar) |
| Installed applications | [`packages/pacman.txt`](packages/pacman.txt) |
| Wallpapers | [`assets/wallpapers/`](assets/wallpapers) |

The installer preserves `~/.config/hypr/user.lua` and Quickshell's
`Settings.qml` during upgrades. See the [customization guide](docs/customize.md)
and the [configuration map](config/README.md) before editing other installed
files.

## Everyday shortcuts

| Shortcut | Action |
|---|---|
| `SUPER` | Open the application menu |
| `SUPER + Tab` | Open the Control Center |
| `SUPER + L` | Lock the session |
| `SUPER + T` | Open Kitty |
| `SUPER + P` | Open the wallpaper picker |
| `SUPER + R` | Restart the desktop shell |
| `SUPER + Q` | Close the active window |
| `ALT + Tab` | Cycle through windows |
| `ALT + SHIFT + S` | Select an area for a screenshot |

See [controls and keybindings](docs/controls.md) for the complete guide.

## Help and project information

- [Common problems and recovery](docs/help.md)
- [Tested software versions](docs/versions.md)
- [v0.1.2 release notes](docs/releases/v0.1.2.md)
- [Files used to maintain the project](maintenance/README.md)

## Folder guide

| Folder | Purpose |
|---|---|
| `config/` | Desktop configuration installed into `~/.config` |
| `assets/` | Wallpapers and the bundled font |
| `packages/` | Applications installed by `install.sh` |
| `docs/` | Customization, controls, help, and release information |
| `maintenance/` | Tests and project utilities that normal users can ignore |

## Credits

Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell),
[flickowoa/dotfiles](https://github.com/flickowoa/dotfiles), and
[samyns/Unit-3](https://github.com/samyns/Unit-3).

## License

MIT
