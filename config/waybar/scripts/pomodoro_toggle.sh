#!/usr/bin/env bash
set -u

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    printf 'XDG_RUNTIME_DIR is not set; cannot store Pomodoro state safely.\n' >&2
    exit 1
fi

readonly STATE_DIR="$XDG_RUNTIME_DIR/tsugumori"
readonly STATE_FILE="$STATE_DIR/pomodoro_state"
readonly DEFAULT_DURATION=1500

umask 077

if [[ -L "$STATE_DIR" ]]; then
    printf 'Refusing symlinked Pomodoro state directory: %s\n' "$STATE_DIR" >&2
    exit 1
fi
mkdir -p -- "$STATE_DIR"
chmod 700 -- "$STATE_DIR"

write_state() {
    local running="$1"
    local temporary

    temporary=$(mktemp -- "$STATE_DIR/.pomodoro_state.XXXXXX") || return 1
    if [[ "$running" == "true" ]]; then
        if ! printf 'RUNNING=true\nSTART_TIME=%s\nDURATION=%s\n' \
            "$(date +%s)" "$DEFAULT_DURATION" > "$temporary"; then
            rm -f -- "$temporary"
            return 1
        fi
    elif ! printf 'RUNNING=false\n' > "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi

    chmod 600 -- "$temporary"
    if ! mv -fT -- "$temporary" "$STATE_FILE"; then
        rm -f -- "$temporary"
        return 1
    fi
}

running=""
seen_running=false
valid=true

# Read only the whitelisted RUNNING value. START_TIME and DURATION are ignored
# here because a stopped timer is always restarted with a fresh interval.
if [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]]; then
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
            START_TIME|DURATION)
                ;;
            *)
                valid=false
                break
                ;;
        esac
    done < "$STATE_FILE"
fi

if $valid && $seen_running && [[ "$running" == "true" ]]; then
    write_state false
else
    write_state true
fi
