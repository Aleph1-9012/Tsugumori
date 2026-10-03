# Tested versions

The following versions were tested together on 2026-08-15.
The tested set is a historical record, not a promise that
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

## Validation on 2026-10-03

The October fixes were checked on an existing Arch installation with these
versions. This is separate from the August clean-install VM record above.

| Component | Version |
|---|---|
| Hyprland | 0.56.2-2 |
| Quickshell | quickshell-git 0.3.0.r20.g28771c7-3 |
| Kitty | 0.48.2-1 |
| Fish | 4.9.2-1 |
| Qt Declarative | 6.11.2-1 |
| Python | 3.14.7-1 |
| PyGObject | 3.56.3-1 |
| mpv | 0.41.0-6 |
| Lua | 5.5.1-1 |
| ShellCheck | 0.11.0 |

The initial strict validation of commit `8babbb8` passed 104 Python tests,
Bash/Fish/Lua syntax checks, ShellCheck, Hyprland configuration verification,
and QML lint/import checks across 31 files. The standalone Qt suites passed
33 behavior cases and skipped one shader-render case because the software
backend cannot run it. Their reported 47 passes also included 14 setup and cleanup entries.
Shader source compilation and bundled shader checks passed separately.

New regressions cover installer recovery and destination conflicts, optional
Fish preservation, pinned-mode ordering, desktop launches and catalog refresh,
escaped Wi-Fi names, MPRIS position ownership, lock-launch contention, PATH
preservation, Kitty options, and Quickshare listener/token routing.
Installation tests used temporary homes and fault-injection fixtures. This pass
did not redeploy the desktop or repeat the August clean-install VM exercise.

The follow-up test cleanup removed three brittle UI/source-text tests and one
Qt case that only rechecked its own fixture. It also trimmed historical
assertions and focused the upload-page and wallpaper-command checks on token
wiring and literal arguments. The suite now contains 101 Python test methods and 33 standalone Qt
cases. Qt case counts exclude setup and cleanup entries.

## How to install pinned versions

Pinned manifests are not currently committed to this branch, so `--pinned`
intentionally exits with a clear error before package installation or config
deployment. The installer checks the cloned manifest before invoking Pacman.
Git must already be installed for this mode; it will not be installed as a
side effect of a failed pinned request. Once reviewed manifests are published,
the command will be:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh) --pinned
```

The installer verifies that a pinned manifest includes Hyprland, then asks the
installed Hyprland binary to parse both the bundled configuration and the
candidate configuration containing preserved `user.lua` overrides before
deploying it. Tsugumori's default package set uses official repository packages
only; bundled Share Tech Mono assets replace the former optional font path.

The default `--latest` mode expects a fully updated Arch installation and
uses its existing package databases. Complete a full system update separately
before installing or updating the rice. The installer does not run
`pacman -Syu` or refresh package databases on its own.

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
