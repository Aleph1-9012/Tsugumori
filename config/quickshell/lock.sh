#!/usr/bin/env bash
# Tsugumori animated secure lock launcher.
#
# Quickshell owns ext-session-lock-v1 and authenticates through PamContext;
# the original NieR reveal/hide presentation remains intact.
set -eu
umask 077

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
lockscreen="$config_home/quickshell/widgets/lockscreen.qml"
handshake_helper="$config_home/quickshell/lock-handshake.sh"
video_dir="$config_home/quickshell/videos"
hyprlock_config="$config_home/hypr/hyprlock.conf"
export XDG_CONFIG_HOME="$config_home"

handshake_dir=""
state_dir=""
protocol_lock=""
protocol_fd_open=0
protocol_locked=0
qs_pid=""

private_directory_is_valid() {
    local directory="$1"
    local directory_mode

    [[ -d "$directory" && ! -L "$directory" && -O "$directory" ]] || return 1
    directory_mode=$(stat -c '%a' -- "$directory") || return 1
    [[ "$directory_mode" == "700" ]]
}

protocol_file_is_valid() {
    local path="$1"
    local file_mode

    [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
    file_mode=$(stat -c '%a' -- "$path") || return 1
    [[ "$file_mode" == "600" ]]
}

marker_is_valid_in() {
    local directory="$1"
    local event="$2"
    local marker="$directory/$event"
    local marker_mode marker_value

    [[ -f "$marker" && ! -L "$marker" && -O "$marker" ]] || return 1
    marker_mode=$(stat -c '%a' -- "$marker") || return 1
    [[ "$marker_mode" == "600" ]] || return 1
    marker_value=$(<"$marker") || return 1
    [[ "$marker_value" == "$event" ]]
}

marker_is_valid() {
    local event="$1"

    [[ -n "$handshake_dir" ]] || return 1
    marker_is_valid_in "$handshake_dir" "$event"
}

write_marker() {
    local directory="$1"
    local event="$2"
    local temporary

    case "$event" in
        relock-requested|closing) ;;
        *) return 2 ;;
    esac
    private_directory_is_valid "$directory" || return 1
    temporary=$(mktemp "$directory/.${event}.XXXXXXXXXX") || return 1
    if ! printf '%s\n' "$event" >"$temporary" \
            || ! chmod 600 "$temporary" \
            || ! mv -T -- "$temporary" "$directory/$event"; then
        rm -f -- "$temporary" 2>/dev/null || true
        return 1
    fi
}

clear_lifecycle_markers() {
    local directory="$1"

    private_directory_is_valid "$directory" || return 1
    # Remove `closing` last. A duplicate that lands in the tiny cleanup window
    # will see either that marker or the absence of `secure`, and wait to take
    # over the launch guard instead of treating the request as a stable no-op.
    rm -f -- "$directory/secure" "$directory/release-authorized" \
        "$directory/release-requested" "$directory/relock-requested" 2>/dev/null || true
    rm -f -- "$directory/closing" 2>/dev/null || true
}

cleanup_handshake() {
    if [[ -n "$handshake_dir" ]]; then
        clear_lifecycle_markers "$handshake_dir" || true
    fi
    handshake_dir=""
}

lock_protocol() {
    [[ "$protocol_fd_open" -eq 1 ]] || return 1
    if [[ "$protocol_locked" -eq 1 ]]; then
        return 0
    fi
    if flock --exclusive --wait 3 8; then
        protocol_locked=1
        return 0
    fi
    return 1
}

release_protocol() {
    if [[ "$protocol_fd_open" -eq 1 && "$protocol_locked" -eq 1 ]]; then
        flock --unlock 8 2>/dev/null || true
    fi
    protocol_locked=0
}

close_protocol() {
    release_protocol
    if [[ "$protocol_fd_open" -eq 1 ]]; then
        exec 8>&-
    fi
    protocol_fd_open=0
}

stop_quickshell() {
    local pid="${qs_pid:-}"
    local attempt

    qs_pid=""
    [[ -n "$pid" ]] || return 0

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        for ((attempt = 0; attempt < 20; attempt++)); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.05
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
    wait "$pid" 2>/dev/null || true
}

fallback_lock() {
    local reason="$1"

    trap - EXIT HUP INT TERM
    stop_quickshell
    if [[ "$protocol_fd_open" -eq 0 ]] || lock_protocol; then
        cleanup_handshake
    else
        # Do not mutate state concurrently with a lifecycle transition.
        handshake_dir=""
    fi
    close_protocol
    printf 'Tsugumori: %s; starting the Hyprlock fallback.\n' "$reason" >&2
    if ! command -v hyprlock >/dev/null 2>&1; then
        printf 'Tsugumori: Hyprlock is unavailable; the session was not locked.\n' >&2
        exit 127
    fi
    if [[ ! -r "$hyprlock_config" ]]; then
        printf 'Tsugumori: missing readable fallback config: %s\n' "$hyprlock_config" >&2
        exit 1
    fi
    exec hyprlock --config "$hyprlock_config" --grace 0 --immediate-render
}

cleanup_on_exit() {
    if [[ "$protocol_fd_open" -eq 0 ]] || lock_protocol; then
        cleanup_handshake
    fi
    close_protocol
}

trap cleanup_on_exit EXIT
trap 'fallback_lock "the supervised Quickshell launcher was interrupted"' HUP INT TERM

case "${1:-}" in
    "") fast_mode=0 ;;
    --fast) fast_mode=1 ;;
    *) printf 'Usage: %s [--fast]\n' "$0" >&2; exit 2 ;;
esac

if ! command -v flock >/dev/null 2>&1; then
    fallback_lock "flock is unavailable"
fi

if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    lock_runtime="$XDG_RUNTIME_DIR/tsugumori"
else
    lock_runtime="$HOME/.cache/tsugumori/runtime"
fi
session_key="${HYPRLAND_INSTANCE_SIGNATURE:-${WAYLAND_DISPLAY:-default}}"
session_key="${session_key//[^[:alnum:]._-]/_}"
state_dir="$lock_runtime/lock-handshake-$session_key"
if ! install -d -m 700 "$lock_runtime"; then
    fallback_lock "the private lock runtime could not be created"
fi
if ! { exec 9>"$lock_runtime/quickshell-lock-$session_key.lock"; }; then
    fallback_lock "the lock-launch guard could not be opened"
fi
if flock --nonblocking --conflict-exit-code 75 9; then
    :
else
    flock_status=$?
    if [[ "$flock_status" -eq 75 ]]; then
        duplicate_request=1
    else
        fallback_lock "the lock-launch guard failed (status $flock_status)"
    fi
fi

wait_for_guard_takeover() {
    local attempt status

    close_protocol
    for ((attempt = 0; attempt < 60; attempt++)); do
        if flock --nonblocking --conflict-exit-code 75 9; then
            return 0
        fi
        status=$?
        if [[ "$status" -ne 75 ]]; then
            fallback_lock "the lock-launch guard failed during relock (status $status)"
        fi
        sleep 0.05
    done
    return 1
}

handle_duplicate_request() {
    # A valid secure state with no release authorization is deliberately a
    # no-op: the existing client is already the compositor security boundary.
    # Authorization and this classification share the protocol flock, so a
    # request cannot disappear between the two states.
    if private_directory_is_valid "$state_dir"; then
        protocol_lock="$state_dir/.protocol.lock"
        if protocol_file_is_valid "$protocol_lock" && { exec 8>>"$protocol_lock"; }; then
            protocol_fd_open=1
            if lock_protocol \
                    && private_directory_is_valid "$state_dir" \
                    && protocol_file_is_valid "$protocol_lock"; then
                if marker_is_valid_in "$state_dir" release-authorized \
                        && ! marker_is_valid_in "$state_dir" closing; then
                    if write_marker "$state_dir" relock-requested; then
                        close_protocol
                        exit 0
                    fi
                    # The authenticated release marker exists, so losing the
                    # relock request is unsafe. Wait for the guard and relaunch.
                    release_protocol
                elif marker_is_valid_in "$state_dir" secure \
                        && ! marker_is_valid_in "$state_dir" closing; then
                    close_protocol
                    exit 0
                else
                    release_protocol
                fi
            fi
        fi
    fi

    # Missing/closing state is transitional. If the first supervisor exits,
    # take over and launch a fresh client; if it retains the guard, either its
    # secure client or its Hyprlock fallback still owns the lock lifecycle.
    if wait_for_guard_takeover; then
        return 0
    fi
    exit 0
}

if [[ "${duplicate_request:-0}" -eq 1 ]]; then
    handle_duplicate_request
fi

initialize_handshake() {
    if [[ -e "$state_dir" || -L "$state_dir" ]]; then
        private_directory_is_valid "$state_dir" || return 1
    elif ! install -d -m 700 "$state_dir"; then
        return 1
    fi

    handshake_dir="$state_dir"
    protocol_lock="$handshake_dir/.protocol.lock"
    if [[ -e "$protocol_lock" || -L "$protocol_lock" ]]; then
        protocol_file_is_valid "$protocol_lock" || return 1
    else
        if ! (set -o noclobber; : >"$protocol_lock") 2>/dev/null; then
            return 1
        fi
        chmod 600 "$protocol_lock" || return 1
    fi
    if ! { exec 8>>"$protocol_lock"; }; then
        return 1
    fi
    protocol_fd_open=1
    lock_protocol || return 1
    if ! private_directory_is_valid "$handshake_dir" \
            || ! protocol_file_is_valid "$protocol_lock" \
            || ! clear_lifecycle_markers "$handshake_dir"; then
        return 1
    fi
    export TSUGUMORI_LOCK_HANDSHAKE_DIR="$handshake_dir"
    release_protocol
}

if ! initialize_handshake; then
    fallback_lock "the private lock lifecycle state could not be initialized"
fi

# Resolve client dependencies only after the per-session guard. A normal
# duplicate stays harmless even if an optional animation dependency changes
# while the existing secure client is running.
if ! command -v qs >/dev/null 2>&1; then
    fallback_lock "Quickshell is unavailable"
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    fallback_lock "ffmpeg is unavailable"
fi

if [[ ! -r "$lockscreen" ]]; then
    fallback_lock "the secure Quickshell lockscreen is unreadable"
fi

if [[ ! -r "$handshake_helper" || ! -x "$handshake_helper" ]]; then
    fallback_lock "the secure lock handshake helper is unavailable"
fi

required_assets=("$video_dir/wave_hide.mp4")
if [[ "$fast_mode" -eq 1 ]]; then
    required_assets+=("$video_dir/wave_last_frame.png")
else
    required_assets+=("$video_dir/wave_reveal.mp4")
fi
for asset in "${required_assets[@]}"; do
    if [[ ! -s "$asset" || ! -r "$asset" ]]; then
        fallback_lock "a required animated-lock asset is missing or empty ($asset)"
    fi
done

pam_service=/etc/pam.d/hyprlock
if [[ "${TSUGUMORI_LOCK_TESTING:-0}" == "1" ]]; then
    pam_service="${TSUGUMORI_LOCK_TEST_PAM_SERVICE:-$pam_service}"
fi
if [[ ! -r "$pam_service" ]]; then
    fallback_lock "the required PAM service is unavailable ($pam_service)"
fi

export QT_MEDIA_BACKEND=ffmpeg
if [[ "$fast_mode" -eq 1 ]]; then
    export UNIT3_LOCK_FAST=1
else
    unset UNIT3_LOCK_FAST
fi

qs --no-duplicate --path "$lockscreen" &
qs_pid=$!

# QML/import/protocol failures normally exit quickly. A bounded wait also
# catches a client that starts but never reaches compositor-confirmed `secure`.
startup_confirmed=0
for ((attempt = 0; attempt < 60; attempt++)); do
    if marker_is_valid secure; then
        startup_confirmed=1
        break
    fi
    kill -0 "$qs_pid" 2>/dev/null || break
    sleep 0.05
done

if [[ "$startup_confirmed" -ne 1 ]]; then
    if kill -0 "$qs_pid" 2>/dev/null; then
        fallback_lock "Quickshell did not confirm a secure session lock within 3 seconds"
    fi

    qs_status=0
    if wait "$qs_pid"; then
        :
    else
        qs_status=$?
    fi
    qs_pid=""
    fallback_lock "Quickshell exited before confirming a secure session lock (status $qs_status)"
fi

# Keep the launch guard for the full lock lifetime. Final release and duplicate
# classification are serialized on the protocol lock: `closing` is committed
# before the relock decision, so a late duplicate either records its request
# first or waits to take over after this supervisor releases the guard.
qs_status=0
if wait "$qs_pid"; then
    :
else
    qs_status=$?
fi
qs_pid=""

if ! lock_protocol; then
    fallback_lock "the final lock lifecycle decision could not be serialized"
fi

if marker_is_valid release-authorized && marker_is_valid release-requested; then
    if ! write_marker "$handshake_dir" closing; then
        fallback_lock "the authenticated release could not be closed safely"
    fi
    if marker_is_valid relock-requested; then
        fallback_lock "another lock request arrived during the authenticated release"
    fi
    cleanup_handshake
    close_protocol
    exit 0
fi

fallback_lock "Quickshell exited without an authenticated release request (status $qs_status)"
