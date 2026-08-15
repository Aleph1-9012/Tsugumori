# Tsugumori v0.1.0

Tsugumori `v0.1.0` is the first credible beta of the Knights of
Sidonia-inspired Arch Linux desktop. It focuses on safe installation, a native
Hyprland Lua configuration, and closing the security gaps found during the
pre-release audit.

## Highlights

- Migrated the complete Hyprland configuration to native Lua. Tsugumori supports
  Hyprland 0.55.2 or newer, and personal overrides live in a preserved
  `user.lua` module.
- Reworked the installer to validate both the bundled config and the exact
  candidate config—including preserved overrides and managed VM options—before
  deployment. Active legacy `user.conf` overrides fail closed when no native
  `user.lua` exists; when both exist, both files are preserved and the installer
  warns that `user.conf` remains dormant.
- Replaced the lock overlay with real `ext-session-lock-v1` surfaces and PAM
  authentication. A supervised startup handshake falls back to Hyprlock on an
  import error, early exit, readiness timeout, or post-acquisition crash.
  Duplicate lock requests are serialized across authenticated release, so a
  suspend-time request cannot disappear during the hide animation.
- Removed shell evaluation from wallpaper selection, made `awww` an official
  dependency, and started `awww-daemon` with the session.
- Moved Pomodoro state to a private XDG runtime directory, writing it with mode
  `600` and parsing state values without sourcing executable shell code.
- Added bounded Quickshare receiving: 1 GiB per request, 4 GiB per session, 32
  files per request, 128 files per session, at most 16 active connections, a
  request-header deadline capped at 15 seconds, and a five-minute overall upload
  deadline by default. Partial uploads are cleaned up transactionally.
- Made Arch-target integration validation mandatory in CI: ShellCheck, Python,
  48 unit tests, Hyprland Lua parsing, and lint/import checks for all 17 QML
  files.

## Installation and migration

Tsugumori supports Arch Linux with Hyprland 0.55.2 or newer and Quickshell 0.3.
The installer creates timestamped backups by default. Existing `user.lua` and
Quickshell settings are preserved. A legacy `user.conf` is retained as a dormant
backup, but it is not loaded by the native Lua configuration; migrate any active
machine-specific settings before upgrading.

`--pinned` intentionally exits with an error until complete, reviewed pinned
manifests are published. A fresh default `--latest` installation uses official
Arch packages, including Quickshell and `awww`; an already-installed compatible
Quickshell provider is retained during upgrades.

## Installing this release

Pin both the downloaded installer and the revision it clones:

```bash
TSUGUMORI_BRANCH=v0.1.0 bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/v0.1.0/install.sh)
```

The quick-install command in the README intentionally follows rolling `main`;
the command above installs the immutable `v0.1.0` tree.

## Validation record

An installation candidate was installed from scratch in an Arch VM on
2026-08-15 with Hyprland 0.56.2-1, official Quickshell 0.3.0-2, and official
`awww` 0.12.1-1. Both pre-deployment Lua checks passed and the installed
configuration parsed. After final hardening, the feature-complete candidate was
validated again in that same official-package VM: all 48 tests, ShellCheck,
Hyprland parsing, and all 17 QML checks passed. The release tree passed those
same required checks in Arch CI. Hyprland 0.55.2-1 was separately verified as
the supported minimum.

## Known limitations

- This is a beta release for rolling Arch Linux, not a distribution-independent
  or stable desktop product.
- The clean-VM acceptance run was headless. It validates the installer, package
  set, configs, fallback logic, and imports, but not every animation, GPU driver,
  display topology, or physical PAM interaction.
- The QML shell remains a large, tightly coupled architecture. Every file passes
  mandatory lint/import validation, but reducing its warning count and splitting
  major widgets are post-`v0.1.0` maintenance work.
- Reproducible `--pinned` installation is unavailable until reviewed manifests
  are committed; the option fails closed instead of silently installing latest.
- Quickshare's direct LAN transport is plaintext HTTP; use it only on a trusted
  network or choose the temporary HTTPS tunnel mode. Access is bearer-token
  based, so anyone who obtains a live LAN or tunnel URL can upload within the
  configured limits until that receive session ends.
