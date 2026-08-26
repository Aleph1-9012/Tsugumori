# Tsugumori v0.1.2

Tsugumori `v0.1.2` is a narrow safety hotfix for the public beta. It preserves
the `v0.1.1` feature set while closing two remaining release blockers.

## Changes

- Installer preservation now rejects a preserved symlink when either its
  lexical destination or resolved target depends on an installer-managed
  directory. The check runs before deployment mutates configuration; regular
  preserved files and symlinks whose complete dependency path is external
  continue to behave as before.
- `qshare send` now derives `Content-Length` from the opened source file and
  sends exactly that many bytes. Early EOF fails the attempt without reporting
  completion or ending the one-shot session, while file growth cannot append
  bytes beyond the advertised length; a failed attempt remains retryable.

## Installing this release

Pin both the downloaded installer and the revision it clones:

```bash
TSUGUMORI_BRANCH=v0.1.2 bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/v0.1.2/install.sh)
```

The quick-install command in the README intentionally follows rolling `main`;
the command above installs the immutable `v0.1.2` tree. The historical
`v0.1.1` notes remain available from that tag and its GitHub release.

## Validation

This hotfix requires focused local installer and Quickshare unit suites,
followed by the protected Arch `Validate` workflow on the pull request, the
exact merged `main` commit, and the exact `v0.1.2` tag. No additional VM, PAM,
GPU, or multi-monitor acceptance cycle was run for this patch release.

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
