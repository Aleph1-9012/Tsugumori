<h1><samp>TSUGUMORI // 継衛</samp></h1>

<p><samp>KNIGHTS OF SIDONIA-INSPIRED HYPRLAND DESKTOP // ARCH LINUX</samp></p>

![Type-17: Sidonia / 704](https://img.shields.io/badge/TYPE--17-SIDONIA%20%2F%20704-cc1515?style=flat-square&labelColor=2a2a2a)
![Hyprland: 0.55.2+](https://img.shields.io/badge/HYPRLAND-0.55.2%2B-cc1515?style=flat-square&labelColor=2a2a2a)
![License: MIT](https://img.shields.io/badge/LICENSE-MIT-cc1515?style=flat-square&labelColor=2a2a2a)

https://github.com/user-attachments/assets/0f27254b-d3ef-4ce7-a7c8-903179d5269e
<p align="center">
  <a href="https://youtu.be/nO3lfZ2hsdM">Watch the showcase in higher quality on YouTube</a>
</p>

## Screenshots

<p align="center">
  <img width="49%" alt="Tsugumori desktop screenshot 1" src="https://github.com/user-attachments/assets/46133f0e-0af4-4d45-a132-355acf489372">
  <img width="49%" alt="Tsugumori desktop screenshot 2" src="https://github.com/user-attachments/assets/40c3157f-0e7d-4941-b7ad-318cbc3b7a3e">  
</p>
<p align="center">
  <img width="49%" alt="Tsugumori desktop screenshot 3" src="https://github.com/user-attachments/assets/ad4b8e28-9891-4ba5-a0c5-714d9ceb9823">
  <img width="49%" alt="Tsugumori desktop screenshot 4" src="https://github.com/user-attachments/assets/19deb533-1a98-40b5-b9c5-4b80b84335a3">
</p>

> [!NOTE]
> The installer checks the configuration before replacing anything and keeps
> timestamped backups by default.

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

Tsugumori uses official Arch packages. IBM Plex Mono and Share Tech Mono ship
with their licenses, so the installer does not need an AUR helper.

## What you get

- Hyprland with a native Lua configuration and custom keybindings
- A NieR:Automata-style Control Center with a Knights of Sidonia theme
- Quickshell launcher, lock screen, notifications, player, and wallpaper picker
- Wi-Fi, Bluetooth, audio, per-monitor brightness, and Quickshare controls
- Standalone quick notes drawer on `SUPER + N`, with local autosave and deletion Undo
- Clipboard history on `SUPER + C`, with search, image previews, pins, and deletion Undo
- Compact music player with an artwork glyph matrix, hover colour reveal, and local track drawer
- Waybar and Kitty configurations, plus themed Fastfetch and btop
- Native Phase lock and wallpaper-picker transitions, shared red curtains, and bundled wallpapers

See [desktop design and runtime notes](docs/native-desktop.md) for the terminal,
widgets, fonts, and native animation details.

## Change the basics

| What you want to change | Where to look |
|---|---|
| Keybindings, monitors, or keyboard layout | [`config/hypr/user.lua`](config/hypr/user.lua) |
| Colors, fonts, or spacing | [`config/quickshell/theme/Theme.qml`](config/quickshell/theme/Theme.qml) |
| Quickshell options | [`config/quickshell/settings/Settings.qml`](config/quickshell/settings/Settings.qml) |
| Terminal appearance | [`config/kitty/kitty.conf`](config/kitty/kitty.conf) |
| Fastfetch layout | [`config/kitty/fastfetch.jsonc`](config/kitty/fastfetch.jsonc) |
| btop colors and layout | [`config/kitty/btop.conf`](config/kitty/btop.conf) and [`tsugumori-btop.theme`](config/kitty/tsugumori-btop.theme) |
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
| `SUPER + N` | Open or close Quick Notes on the focused monitor |
| `SUPER + C` | Open or close clipboard history on the focused monitor |
| `SUPER + Enter` | Show or hide the music player |
| `SUPER + L` | Lock the session |
| `SUPER + T` | Open Kitty |
| `SUPER + P` | Open the wallpaper picker |
| `SUPER + R` | Restart the desktop shell |
| `SUPER + Q` | Close the active window |
| `ALT + Tab` | Cycle through windows |
| `ALT + SHIFT + S` | Select an area for a screenshot |

See [controls and keybindings](docs/controls.md) for the complete guide.

Quick Notes is a standalone drawer, separate from the Control Center. Press
`SUPER + N` again to close it, or use the shortcut on another monitor to move
the same drawer there. Notes autosave locally, and deleted notes can be
restored with Undo during the current shell session.

## Help and project information

- [Common problems and recovery](docs/help.md)
- [Tested software versions](docs/versions.md)

## Folder guide

| Folder | Purpose |
|---|---|
| `config/` | Desktop configuration installed into `~/.config` |
| `assets/` | Wallpapers and the bundled font |
| `packages/` | Applications installed by `install.sh` |
| `docs/` | Customization, controls, help, and software requirements |
| `.github/` | GitHub checks and issue templates; not installed on the desktop |

## Credits

Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell),
[flickowoa/dotfiles](https://github.com/flickowoa/dotfiles), and
[samyns/Unit-3](https://github.com/samyns/Unit-3).

## License

MIT
