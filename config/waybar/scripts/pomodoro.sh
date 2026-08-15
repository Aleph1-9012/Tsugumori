#!/usr/bin/env bash
set -u

readonly IDLE_LABEL="POMO --:--"

print_idle() {
    printf '%s\n' "$IDLE_LABEL"
}

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    print_idle
    exit 0
fi

readonly STATE_DIR="$XDG_RUNTIME_DIR/tsugumori"
readonly STATE_FILE="$STATE_DIR/pomodoro_state"

# Never follow a state-file symlink. The toggle script creates STATE_DIR with
# mode 700 and atomically replaces STATE_FILE with a mode-600 regular file.
if [[ ! -f "$STATE_FILE" || -L "$STATE_FILE" ]]; then
    print_idle
    exit 0
fi

state_mode=$(stat -c '%a' -- "$STATE_FILE" 2>/dev/null) || {
    print_idle
    exit 0
}
if [[ ! -O "$STATE_FILE" || "$state_mode" != "600" ]]; then
    print_idle
    exit 0
fi

running=""
start_time=""
duration=""
seen_running=false
seen_start_time=false
seen_duration=false
valid=true

# This is deliberately a data parser, not `source`: only the three expected
# keys and narrowly validated values can enter arithmetic below.
while IFS='=' read -r key value; do
    case "$key" in
        RUNNING)
            if $seen_running || [[ "$value" != "true" && "$value" != "false" ]]; then
                valid=false
                break
            fi
            seen_running=true
            running="$value"
            ;;
        START_TIME)
            if $seen_start_time || [[ ! "$value" =~ ^[0-9]{1,12}$ ]]; then
                valid=false
                break
            fi
            seen_start_time=true
            start_time=$((10#$value))
            ;;
        DURATION)
            if $seen_duration || [[ ! "$value" =~ ^[0-9]{1,6}$ ]]; then
                valid=false
                break
            fi
            seen_duration=true
            duration=$((10#$value))
            if (( duration < 1 || duration > 86400 )); then
                valid=false
                break
            fi
            ;;
        *)
            valid=false
            break
            ;;
    esac
done < "$STATE_FILE"

if ! $valid || ! $seen_running || [[ "$running" != "true" ]]; then
    print_idle
    exit 0
fi

if ! $seen_start_time || ! $seen_duration; then
    print_idle
    exit 0
fi

now=$(date +%s)
elapsed=$((now - start_time))
remaining=$((duration - elapsed))

if (( remaining <= 0 )); then
    printf 'POMO 00:00\n'
    exit 0
fi

minutes=$((remaining / 60))
seconds=$((remaining % 60))
printf 'POMO %02d:%02d\n' "$minutes" "$seconds"
