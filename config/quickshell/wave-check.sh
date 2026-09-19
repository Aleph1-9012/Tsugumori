#!/usr/bin/env bash
# Verify native lockscreen and picker assets at session startup.
# Keep this entry point for the existing Hyprland startup command.
set -uo pipefail

readonly config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
readonly shell_dir="$config_home/quickshell"
readonly log_dir="$cache_home/quickshell"
readonly log_file="$log_dir/wave-check.log"
readonly assets=(
    widgets/lockscreen.qml
    widgets/lockscreen/PhaseLockView.qml
    widgets/lockscreen/PhaseArt.js
    widgets/lockscreen/PhaseLines.qml
    widgets/lockscreen/PhaseCpuFallback.qml
    widgets/lockscreen/FormationCorner.qml
    widgets/lockscreen/shaders/lines.vert.qsb
    widgets/lockscreen/shaders/lines.frag.qsb
    widgets/WallpaperPicker.qml
    widgets/wallpaper/PickerMotion.qml
    widgets/wallpaper/PickerBackdrop.qml
    widgets/wallpaper/PickerRegistration.qml
    widgets/wallpaper/PickerCorners.qml
    widgets/wallpaper/PickerApplyPanel.qml
    widgets/wallpaper/PickerPreview.qml
)

mkdir -p -- "$log_dir" || exit 1

missing=()
for asset in "${assets[@]}"; do
    [[ -s "$shell_dir/$asset" ]] || missing+=("$asset")
done

if (( ${#missing[@]} > 0 )); then
    printf '[%s] ERROR: missing or empty native animation assets: %s\n' \
        "$(date --iso-8601=seconds)" "${missing[*]}" >> "$log_file"
    exit 1
fi

printf '[%s] Native lockscreen and picker assets verified.\n' \
    "$(date --iso-8601=seconds)" >> "$log_file"
