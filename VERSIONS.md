# Tested versions

This config was last tested with the following versions of its main
dependencies on 2026-08-13. The tested set is a record, not a promise that
the current Arch repositories still provide these versions.

## Main components

| Component         | Version              |
|-------------------|----------------------|
| Hyprland          | 0.55.2-1             |
| Hyprlock          | 0.9.5-4              |
| Hypridle          | 0.1.7-9              |
| Waybar            | 0.15.0-2             |
| Kitty             | 0.46.2-1             |
| Quickshell (tested git build) | 0.3.0.r9.g68c2c85-1 |
| awww (AUR)        | 0.12.0-1             |
| Arch Linux        | rolling              |

The secure animated lock, suspend/idle path, and legacy Hyprlang configuration
were exercised with Hyprland 0.55.2 and Quickshell 0.3.0.r9 on 2026-08-13.
Hyprlang is deprecated from 0.55 onward and the repository still needs a Lua
migration before that compatibility layer is removed.

## Updating this list

After verifying the config works, the maintainer regenerates pinned
versions with:

```bash
./scripts/update-pins.sh
```

This updates `packages/pinned-pacman.txt` and `packages/pinned-aur.txt`, recording
each package's version and architecture as `package=version=architecture`.
Those generated files must be reviewed and committed before `--pinned` can
be offered to users.

## How to install pinned versions

Pinned manifests are not currently committed to this branch, so `--pinned`
intentionally exits with a clear error instead of silently installing latest
packages. Once reviewed manifests are published, the command will be:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh) --pinned
```

The installer verifies that a pinned manifest includes Hyprland, then asks the
installed Hyprland binary to parse the bundled configuration before deploying
it. AUR helpers install the package names recorded in `pinned-aur.txt` at their
currently available AUR versions; the AUR cannot reliably reproduce historical
build versions.

## Manually pinning a single package

The archive URL pattern for a historical package is:

```bash
sudo pacman -U https://archive.archlinux.org/packages/h/hyprland/hyprland-0.54.3-2-x86_64.pkg.tar.zst
```

Do not treat this as a supported one-package downgrade recipe. Hyprland and its
companion libraries must remain compatible, and mixing an old compositor with a
current rolling Arch stack can break the session. Use a complete, reviewed
pinned manifest or an Arch Linux Archive snapshot instead. Browse available
versions at <https://archive.archlinux.org/packages/>.

## Known issues with newer versions

- **Hyprland 0.55 and newer:** Hyprlang is deprecated in favor of Lua. Version
  0.55.2 still parses this repository's legacy configuration, but future
  releases may remove that compatibility. The installer validates the config
  with the installed binary before replacing user files.
