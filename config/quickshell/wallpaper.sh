#!/bin/bash
pgrep -f "WallpaperPicker.qml" && exit 0
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
qs -p "$config_home/quickshell/widgets/WallpaperPicker.qml"
