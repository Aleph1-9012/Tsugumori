#!/bin/bash
pgrep -f "WallpaperPicker.qml" && exit 0
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
QT_MEDIA_BACKEND=ffmpeg qs -p "$config_home/quickshell/widgets/WallpaperPicker.qml"
