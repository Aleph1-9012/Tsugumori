#!/bin/bash
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
exec qs --no-duplicate --path "$config_home/quickshell/widgets/WallpaperPicker.qml"
