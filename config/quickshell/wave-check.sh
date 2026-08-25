#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# wave-check.sh
# Check at Hyprland startup that the pixel-wave videos
# (reveal + hide) exist. Generate them synchronously if needed.
#
# Usage:
#   - Run manually: ./wave-check.sh
#   - At startup: called by the hyprland.start callback in hyprland.lua.
# ═════════════════════════════════════════════════════════════════════

set -e

# ── Generic paths (respect XDG) ──
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

QS_DIR="$CONFIG_HOME/quickshell"
VIDEOS_DIR="$QS_DIR/videos"
LOG_DIR="$CACHE_HOME/quickshell"
LOG_FILE="$LOG_DIR/wave-check.log"

# Expected files (names used by lockscreen.qml and WallpaperPicker.qml).
REVEAL_VIDEO="$VIDEOS_DIR/wave_reveal.mp4"
HIDE_VIDEO="$VIDEOS_DIR/wave_hide.mp4"
LAST_FRAME="$VIDEOS_DIR/wave_last_frame.png"

# Generator scripts.
REVEAL_SCRIPT="$QS_DIR/pixel_wave.py"
HIDE_SCRIPT="$QS_DIR/pixel-wave-close-video.py"
LAST_FRAME_SCRIPT="$QS_DIR/ext_last_fr.py"

# ── Setup ──
mkdir -p "$VIDEOS_DIR" "$LOG_DIR"

# Redirect stdout and stderr to the log (with a timestamp).
exec > >(while IFS= read -r line; do printf '[%s] %s\n' "$(date +%H:%M:%S)" "$line"; done >> "$LOG_FILE") 2>&1

echo "═══════════════════════════════════════════════════════════"
echo "wave-check.sh — starting"
echo "  videos dir : $VIDEOS_DIR"
echo "═══════════════════════════════════════════════════════════"

# ── Verify generator scripts ──
missing_scripts=()
[[ -f "$REVEAL_SCRIPT" ]] || missing_scripts+=("$REVEAL_SCRIPT")
[[ -f "$HIDE_SCRIPT"   ]] || missing_scripts+=("$HIDE_SCRIPT")
[[ -f "$LAST_FRAME_SCRIPT" ]] || missing_scripts+=("$LAST_FRAME_SCRIPT")
if (( ${#missing_scripts[@]} > 0 )); then
    echo "❌ Missing generator script(s):"
    printf '   - %s\n' "${missing_scripts[@]}"
    echo "Abandon."
    exit 1
fi

# ── Verify and generate reveal ──
if [[ -f "$REVEAL_VIDEO" ]]; then
    echo "✓ wave_reveal.mp4 present"
else
    echo "⚠ wave_reveal.mp4 missing — generating…"
    python "$REVEAL_SCRIPT" -o "$REVEAL_VIDEO"
    if [[ -f "$REVEAL_VIDEO" ]]; then
        echo "✓ wave_reveal.mp4 generated"
    else
        echo "❌ wave_reveal.mp4 generation failed"
        exit 2
    fi
fi

# ── Verify and generate hide ──
if [[ -f "$HIDE_VIDEO" ]]; then
    echo "✓ wave_hide.mp4 present"
else
    echo "⚠ wave_hide.mp4 missing — generating…"
    python "$HIDE_SCRIPT" -o "$HIDE_VIDEO"
    if [[ -f "$HIDE_VIDEO" ]]; then
        echo "✓ wave_hide.mp4 generated"
    else
        echo "❌ wave_hide.mp4 generation failed"
        exit 3
    fi
fi

if [[ -f "$LAST_FRAME" ]]; then
    echo "✓ wave_last_frame.png present"
else
    echo "⚠ wave_last_frame.png missing — generating…"
    python "$LAST_FRAME_SCRIPT" "$REVEAL_VIDEO"
    if [[ -f "$LAST_FRAME" ]]; then
        echo "✓ wave_last_frame.png generated"
    else
        echo "❌ wave_last_frame.png generation failed"
        exit 4
    fi
fi

echo "═══════════════════════════════════════════════════════════"
echo "wave-check.sh — finished"
echo "═══════════════════════════════════════════════════════════"
