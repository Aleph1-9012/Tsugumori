#!/usr/bin/env bash
# Tsugumori animated secure lock launcher.
#
# Quickshell owns ext-session-lock-v1 and authenticates through PamContext;
# the original NieR reveal/hide presentation remains intact.
set -eu
umask 077

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
lockscreen="$config_home/quickshell/widgets/lockscreen.qml"
video_dir="$config_home/quickshell/videos"
hyprlock_config="$config_home/hypr/hyprlock.conf"
export XDG_CONFIG_HOME="$config_home"

fallback_lock() {
    reason="$1"
    printf 'Tsugumori: %s; starting the Hyprlock fallback.\n' "$reason" >&2
    if ! command -v hyprlock >/dev/null 2>&1; then
        printf 'Tsugumori: Hyprlock is unavailable; the session was not locked.\n' >&2
        exit 127
    fi
    if [[ ! -r "$hyprlock_config" ]]; then
        printf 'Tsugumori: missing readable fallback config: %s\n' "$hyprlock_config" >&2
        exit 1
    fi
    exec hyprlock --config "$hyprlock_config" --grace 0 --immediate-render
}

case "${1:-}" in
    "") fast_mode=0 ;;
    --fast) fast_mode=1 ;;
    *) printf 'Usage: %s [--fast]\n' "$0" >&2; exit 2 ;;
esac

if ! command -v qs >/dev/null 2>&1; then
    fallback_lock "Quickshell is unavailable"
fi

if ! command -v flock >/dev/null 2>&1; then
    fallback_lock "flock is unavailable"
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    fallback_lock "ffmpeg is unavailable"
fi

if [[ ! -r "$lockscreen" ]]; then
    fallback_lock "the secure Quickshell lockscreen is unreadable"
fi

required_assets=("$video_dir/wave_hide.mp4")
if [[ "$fast_mode" -eq 1 ]]; then
    required_assets+=("$video_dir/wave_last_frame.png")
else
    required_assets+=("$video_dir/wave_reveal.mp4")
fi
for asset in "${required_assets[@]}"; do
    if [[ ! -s "$asset" || ! -r "$asset" ]]; then
        fallback_lock "a required animated-lock asset is missing or empty ($asset)"
    fi
done

if [[ ! -r /etc/pam.d/hyprlock ]]; then
    printf 'Tsugumori: missing PAM service /etc/pam.d/hyprlock; the session was not locked.\n' >&2
    exit 1
fi

if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    lock_runtime="$XDG_RUNTIME_DIR/tsugumori"
else
    lock_runtime="$HOME/.cache/tsugumori/runtime"
fi
session_key="${HYPRLAND_INSTANCE_SIGNATURE:-${WAYLAND_DISPLAY:-default}}"
session_key="${session_key//[^[:alnum:]._-]/_}"
install -d -m 700 "$lock_runtime"
exec 9>"$lock_runtime/quickshell-lock-$session_key.lock"
if flock --nonblocking --conflict-exit-code 75 9; then
    :
else
    flock_status=$?
    if [[ "$flock_status" -eq 75 ]]; then
        exit 0
    fi
    printf 'Tsugumori: failed to acquire the lock-launch guard (status %s).\n' "$flock_status" >&2
    exit "$flock_status"
fi

export QT_MEDIA_BACKEND=ffmpeg
if [[ "$fast_mode" -eq 1 ]]; then
    export UNIT3_LOCK_FAST=1
else
    unset UNIT3_LOCK_FAST
fi

exec qs --no-duplicate --path "$lockscreen"
