#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s <path> <monitor_name|both>\n' "${0##*/}" >&2
}

if (( $# != 2 )); then
    usage
    exit 2
fi

readonly wallpaper="$1"
readonly target="$2"

if [[ ! -f "$wallpaper" ]]; then
    printf 'Wallpaper is not a regular file: %s\n' "$wallpaper" >&2
    exit 1
fi
if [[ -z "$target" ]]; then
    usage
    exit 2
fi

awww_args=(
    awww img
    --transition-type fade
    --transition-duration 0.6
    --transition-fps 60
)
if [[ "$target" != "both" ]]; then
    awww_args+=(--outputs "$target")
fi
awww_args+=("$wallpaper")

# Keep filenames and monitor names as argv elements all the way to awww. In
# particular, no part of either value is reparsed by a shell.
"${awww_args[@]}"

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
selection_dir="$config_home/quickshell"
selection_file="$selection_dir/current_wallpaper.txt"
mkdir -p -- "$selection_dir"

umask 077
temporary=$(mktemp -- "$selection_dir/.current_wallpaper.XXXXXX")
cleanup() {
    rm -f -- "$temporary"
}
trap cleanup EXIT
printf '%s\n' "$wallpaper" > "$temporary"
chmod 600 -- "$temporary"
mv -fT -- "$temporary" "$selection_file"
trap - EXIT
