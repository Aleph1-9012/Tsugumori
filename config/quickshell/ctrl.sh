#!/usr/bin/env bash
# Compatibility entry point for existing shortcuts and preserved user configs.
# New defaults use IPC directly; keep this path usable during upgrades.
set -eu

action="${1:-toggle}"
case "$action" in
    toggle) ;;
    open) action="show" ;;
    close) action="hide" ;;
    *) printf 'Usage: %s [toggle|open|close]\n' "$0" >&2; exit 2 ;;
esac

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
exec qs ipc --path "$config_home/quickshell/shell.qml" call -- ctrl "$action"
