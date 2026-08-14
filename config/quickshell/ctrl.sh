#!/usr/bin/env bash
# ── Unit-3 ControlCenter toggle ──
# Usage:
#   ctrl.sh         → toggle the ControlCenter (open if closed, close if open)
#   ctrl.sh open    → force open
#   ctrl.sh close   → force close
#
# The ControlCenter must already be loaded by the main Quickshell instance.
# This script sends an IPC command — it does NOT spawn a new qs process.

action="${1:-toggle}"
case "$action" in
    toggle|open|close) ;;
    *) printf 'Usage: %s [toggle|open|close]\n' "$0" >&2; exit 2 ;;
esac

printf "This wrapper is deprecated; use 'qs ipc call ctrl %s'.\n" "$action" >&2
case "$action" in
    open)  action="show" ;;
    close) action="hide" ;;
esac
exec qs ipc call ctrl "$action"
