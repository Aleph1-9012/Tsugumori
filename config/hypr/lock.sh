#!/usr/bin/env bash
# Compatibility wrapper for older callers. The Quickshell-side launcher owns
# duplicate suppression, config validation, and immediate secure lock startup.
set -u

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
exec "$config_home/quickshell/lock.sh" "$@"
