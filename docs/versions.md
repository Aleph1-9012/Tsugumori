# Tested versions

This config was last tested with the following versions of its main
dependencies on 2026-08-15. The tested set is a record, not a promise that
the current Arch repositories still provide these versions.

## Main components

| Component         | Version              |
|-------------------|----------------------|
| Hyprland          | 0.56.2-1             |
| Hyprlock          | 0.9.6-2              |
| Hypridle          | 0.1.8-1              |
| Waybar            | 0.15.0-2             |
| Kitty             | 0.48.2-1             |
| Quickshell (official) | 0.3.0-2          |
| awww (official)   | 0.12.1-1             |
| Linux kernel      | 7.1.8-arch1-3         |
| Arch Linux        | clean rolling install |

On 2026-08-15, Tsugumori was installed from scratch in a fresh Arch VM with
`install.sh --vm` and official repository packages. The installer validated both
the bundled and effective candidate Lua configurations before deployment. After
the final hardening changes, the feature-complete candidate was validated again
in that same official-package VM: all 48 tests, ShellCheck, Hyprland config
verification, and QML lint/import checks across all 17 QML files passed. The
release tree is additionally covered by the same required Arch checks in GitHub
Actions.

The minimum supported Hyprland version, 0.55.2-1, was also checked separately
with the native Lua parser and a Quickshell 0.3 development build. The VM run was
headless validation of installation, configuration, and integration behavior;
it did not replace an interactive GPU/PAM acceptance test on physical hardware.

## Updating this list

After verifying the config works, the maintainer regenerates pinned
versions with:

```bash
./maintenance/update-pins.sh
```

This updates `packages/pinned-pacman.txt`, recording each package's version and
architecture as `package=version=architecture`. The generated file must be
reviewed and committed before `--pinned` can be offered to users.

## How to install pinned versions

Pinned manifests are not currently committed to this branch, so `--pinned`
intentionally exits with a clear error instead of silently installing latest
packages. Once reviewed manifests are published, the command will be:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh) --pinned
```

The installer verifies that a pinned manifest includes Hyprland, then asks the
installed Hyprland binary to parse both the bundled configuration and the
candidate configuration containing preserved `user.lua` overrides before
deploying it. Tsugumori's default package set uses official repository packages
only; bundled Share Tech Mono assets replace the former optional font path.

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

- **Hyprland 0.55.2 and newer:** Tsugumori now uses Hyprland's native Lua
  configuration and no longer ships a legacy `hyprland.conf`. The installer
  validates the bundled Lua config and the candidate config containing preserved
  `user.lua` overrides before replacing user files. Because the Lua interface is
  newer than Hyprlang, future Hyprland releases may still require config updates.
