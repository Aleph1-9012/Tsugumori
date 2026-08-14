#!/usr/bin/env bash
# Restart only the desktop-shell Quickshell instance.
# Never signal every `qs` process: the secure lockscreen is a separate instance.
set -eu

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
shell_qml="$config_home/quickshell/shell.qml"

if ! command -v qs >/dev/null 2>&1; then
    printf 'Tsugumori: Quickshell is required.\n' >&2
    exit 127
fi

if [[ ! -r "$shell_qml" ]]; then
    printf 'Tsugumori: missing readable shell: %s\n' "$shell_qml" >&2
    exit 1
fi

# Quickshell selects by exact config path, so this cannot terminate the
# independent widgets/lockscreen.qml instance. Wait for the old PID to exit so
# --no-duplicate cannot race it and leave the desktop shell stopped.
shell_pid="$(qs list --json --path "$shell_qml" 2>/dev/null \
    | sed -n 's/^[[:space:]]*"pid": \([0-9][0-9]*\),*$/\1/p' \
    | head -n 1)"

if [[ -n "$shell_pid" ]]; then
    qs kill --pid "$shell_pid" >/dev/null
    for _ in {1..50}; do
        [[ ! -d "/proc/$shell_pid" ]] && break
        sleep 0.05
    done
    if [[ -d "/proc/$shell_pid" ]]; then
        printf 'Tsugumori: desktop shell PID %s did not exit; restart aborted.\n' "$shell_pid" >&2
        exit 1
    fi
fi

exec qs --no-duplicate --path "$shell_qml"
