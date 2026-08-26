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

## Lock-screen fallback

If the Quickshell lock cannot start safely, Tsugumori starts Hyprlock instead.
An unused `/etc/pam.d/qs-lock` file can remain after upgrading from an older
version. Remove it only after confirming that no local service uses it.

Check the [tested versions](versions.md) if a rolling Arch update introduces a
new compatibility problem.
