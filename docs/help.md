# Help and recovery

## The installer reports a Hyprland Lua error

Do not force the installer past the configuration check. Fix the reported
problem in `~/.config/hypr/user.lua`, then run the installer again. If an
installation was interrupted, restore your previous configuration from the
timestamped `~/.config-backup-*` directory.

An old `~/.config/hypr/user.conf` is preserved, but native Lua configurations
do not load it. Move any settings you still need into `user.lua`.

## Notifications do not appear

Only one notification service can run at a time. If dunst, mako, swaync, or
another notification daemon is already running, it will receive notifications
instead of Tsugumori. Disable that daemon through its own service or autostart
configuration if you want to use Tsugumori's notification panel.

## The desktop shell needs restarting

Press `SUPER + R`. This restarts the desktop shell without terminating the
separate secure lock process.

## The wallpaper picker is empty

Place JPG, PNG, or WebP files in `~/Pictures/wallpapers/`, then open the picker
with `SUPER + P`.

## Quickshare does not connect

Both devices must be able to reach each other for a local transfer. Use a
trusted local network or enable tunnel mode. See the
[Quickshare guide](quickshare.md) for transfer limits and security information.

## Quick notes cannot save or load

The drawer keeps unsaved edits in memory after a storage failure. Use Retry
after resolving the permission or disk-space issue. Do not restart while it
says `SAVE FAILED`; copy any draft you need to keep first.

If another process changed the file, the revision guard refuses to overwrite
it. Copy your pending draft, then restart the desktop shell to load the disk
version. Personal notes are plain text, not encrypted. The data directory is
private to your user, with mode 0700, and its files use mode 0600.

If the notes file is unreadable and a valid previous backup exists, choose
`RECOVER BACKUP`, then `CONFIRM RECOVERY`. This loads `notes.json.bak` and keeps
the damaged file under a unique `notes.json.damaged-*` name. Recovery is only
available before editing begins. If no valid backup exists, the drawer leaves
the original file untouched for manual recovery.

The data directory is `$XDG_DATA_HOME/tsugumori`, falling back to
`~/.local/share/tsugumori`. Keep it when reinstalling or removing the widget.
The previous-file backup is not unlimited history, and deletion Undo only
lasts for the current shell session.

## Lock-screen fallback

If the Quickshell lock cannot start safely, Tsugumori starts Hyprlock instead.
An unused `/etc/pam.d/qs-lock` file can remain after upgrading from an older
version. Remove it only after confirming that no local service uses it.

Check the [tested versions](versions.md) if a rolling Arch update introduces a
new compatibility problem.
