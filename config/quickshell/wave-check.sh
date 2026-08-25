#!/usr/bin/env bash
# Verify the committed lock-animation assets at session startup.
set -uo pipefail

readonly config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
readonly videos_dir="$config_home/quickshell/videos"
readonly log_dir="$cache_home/quickshell"
readonly log_file="$log_dir/wave-check.log"
readonly assets=(
    "$videos_dir/wave_reveal.mp4"
    "$videos_dir/wave_hide.mp4"
    "$videos_dir/wave_last_frame.png"
)

mkdir -p -- "$log_dir"

missing=()
for asset in "${assets[@]}"; do
    [[ -s "$asset" ]] || missing+=("${asset##*/}")
done

if (( ${#missing[@]} > 0 )); then
    printf '[%s] ERROR: missing or empty lock-animation asset(s): %s\n' \
        "$(date --iso-8601=seconds)" "${missing[*]}" >> "$log_file"
    exit 1
fi

printf '[%s] Lock-animation assets verified.\n' \
    "$(date --iso-8601=seconds)" >> "$log_file"
