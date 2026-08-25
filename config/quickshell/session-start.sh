#!/usr/bin/env bash
# Wait for usable monitor geometry before starting output-dependent desktop UI.
# Hyprland 0.56 can occasionally expose a connected output as 0x0 during boot;
# in that state a current-syntax DPMS cycle is the least invasive reprobe.
set -uo pipefail

readonly config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly state_dir="$state_home/tsugumori"
readonly log_file="$state_dir/session-start.log"
readonly restore_wallpaper="${1:-}"

mkdir -p -- "$state_dir"
: > "$log_file"
exec >>"$log_file" 2>&1

printf '[%s] session startup guard began\n' "$(date --iso-8601=seconds)"

INVALID_OUTPUTS=()

scan_monitors() {
    local monitor_json invalid

    monitor_json=$(hyprctl -j monitors all 2>/dev/null) || return 1
    invalid=$(python3 -c '
import json
import sys

try:
    monitors = json.load(sys.stdin)
except (TypeError, ValueError):
    raise SystemExit(1)

for monitor in monitors:
    if monitor.get("disabled", False):
        continue
    width = monitor.get("width", 0)
    height = monitor.get("height", 0)
    if not isinstance(width, (int, float)) or not isinstance(height, (int, float)):
        continue
    if width <= 0 or height <= 0:
        name = monitor.get("name", "")
        if name and all(character.isalnum() or character in "._:-" for character in name):
            print(name)
' <<<"$monitor_json") || return 1

    INVALID_OUTPUTS=()
    while IFS= read -r output; do
        [[ -n "$output" ]] && INVALID_OUTPUTS+=("$output")
    done <<<"$invalid"
    return 0
}

wait_for_valid_monitors() {
    local stable_samples=0
    local _

    for _ in {1..12}; do
        if scan_monitors && (( ${#INVALID_OUTPUTS[@]} == 0 )); then
            ((stable_samples += 1))
            (( stable_samples >= 4 )) && return 0
        else
            stable_samples=0
        fi
        sleep 0.5
    done

    scan_monitors && (( ${#INVALID_OUTPUTS[@]} == 0 ))
}

cycle_invalid_outputs() {
    local output
    local -a targets=("${INVALID_OUTPUTS[@]}")

    (( ${#targets[@]} > 0 )) || return 0
    printf '[%s] invalid monitor geometry: %s\n' \
        "$(date --iso-8601=seconds)" "${targets[*]}"

    for output in "${targets[@]}"; do
        hyprctl dispatch \
            "hl.dsp.dpms({ action = \"disable\", monitor = \"$output\" })" || true
    done
    sleep 2
    for output in "${targets[@]}"; do
        hyprctl dispatch \
            "hl.dsp.dpms({ action = \"enable\", monitor = \"$output\" })" || true
    done
}

if ! wait_for_valid_monitors; then
    cycle_invalid_outputs
    if ! wait_for_valid_monitors; then
        printf '[%s] DPMS recovery did not settle; forcing renderer reload\n' \
            "$(date --iso-8601=seconds)"
        hyprctl dispatch 'hl.dsp.force_renderer_reload()' || true
        wait_for_valid_monitors || true
    fi
fi

if scan_monitors && (( ${#INVALID_OUTPUTS[@]} == 0 )); then
    printf '[%s] monitor geometry is valid\n' "$(date --iso-8601=seconds)"
else
    printf '[%s] continuing with invalid outputs: %s\n' \
        "$(date --iso-8601=seconds)" "${INVALID_OUTPUTS[*]:-unknown}"
fi

# Start output-dependent processes only after the monitor check. The guard is
# fail-open so the working display still gets a bar if recovery is unsuccessful.
if ! pgrep -u "$UID" -x waybar >/dev/null 2>&1; then
    /usr/bin/waybar &
fi

if ! pgrep -u "$UID" -x awww-daemon >/dev/null 2>&1; then
    /usr/bin/awww-daemon &
fi

wallpaper=""
selection_file="$config_home/quickshell/current_wallpaper.txt"
if [[ -r "$selection_file" ]]; then
    IFS= read -r wallpaper < "$selection_file" || true
    [[ -f "$wallpaper" ]] || wallpaper=""
fi

if [[ -z "$wallpaper" && "$restore_wallpaper" == "--restore-wallpaper" ]]; then
    while IFS= read -r -d '' candidate; do
        wallpaper="$candidate"
        break
    done < <(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -print0 2>/dev/null | sort -z)
fi

if [[ -n "$wallpaper" ]]; then
    for _ in {1..30}; do
        awww query >/dev/null 2>&1 && break
        sleep 0.2
    done
    awww img --transition-type none -- "$wallpaper" || true
fi

printf '[%s] session startup guard finished\n' "$(date --iso-8601=seconds)"
