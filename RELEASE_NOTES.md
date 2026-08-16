# Tsugumori v0.1.1

Tsugumori `v0.1.1` is a focused safety hotfix for the public beta. It preserves
the `v0.1.0` feature set while hardening upgrades and Quickshare connections.

## Changes

- Installer preservation now handles `user.lua`, dormant `user.conf`, and
  `Settings.qml` symlinks lexically. Relative link text survives an upgrade
  unchanged; dangling or non-file preserved links fail closed before the
  installed configuration is replaced.
- `qshare send` now applies a fixed 15-second absolute request-header deadline
  and a five-minute absolute download deadline by default. The new
  `--transfer-timeout SECONDS` option adjusts the latter, up to the existing
  24-hour safety maximum. A stalled or disconnected client no longer completes
  a one-shot send, so another client can retry.
- Cloudflare tunnel startup now reads output in the background instead of
  blocking on `readline()`. Its existing 30-second startup limit remains in
  force, and failed tunnel processes are terminated and reaped.

## Installing this release

Pin both the downloaded installer and the revision it clones:

```bash
TSUGUMORI_BRANCH=v0.1.1 bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/v0.1.1/install.sh)
```

The quick-install command in the README intentionally follows rolling `main`;
the command above installs the immutable `v0.1.1` tree. The historical
`v0.1.0` notes remain available from that tag and its GitHub release.

## Validation

This hotfix uses focused local installer and Quickshare unit suites, followed by
the protected Arch `Validate` workflow as the full release gate. No additional
VM, PAM, GPU, or multi-monitor acceptance cycle was run for this patch release.

## Known limitations

- Preserving the complete tracked `Settings.qml` still makes future settings
  migrations fragile; a narrower user-override format is deferred.
- The README gallery still uses its original full-width source images; layout
  and asset-size optimization are deferred.
- Reproducible `--pinned` installation remains unavailable until reviewed
  manifests are committed; the option continues to fail closed.
- Live PAM, GPU, and multi-monitor acceptance remains outstanding. This is an
  Arch Linux beta, not a stable or distribution-independent desktop release.
- Quickshare's direct LAN transport remains plaintext HTTP and should be used
  only on trusted networks; tunnel mode provides HTTPS but still uses bearer
  URLs for access.
- The QML shell remains large and tightly coupled. Splitting major widgets and
  reducing non-fatal lint warnings remain post-beta maintenance work.
