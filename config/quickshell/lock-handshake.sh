#!/usr/bin/env bash
# Write one authenticated lifecycle marker for the supervised lock launcher.
set -euo pipefail
umask 077

if [[ "$#" -ne 2 ]]; then
    printf 'Usage: %s HANDSHAKE_DIR {secure|release-authorized|release-requested}\n' "$0" >&2
    exit 2
fi

handshake_dir="$1"
event="$2"

case "$event" in
    secure|release-authorized|release-requested) ;;
    *)
        printf 'Tsugumori: invalid lock handshake event: %s\n' "$event" >&2
        exit 2
        ;;
esac

if [[ ! -d "$handshake_dir" || -L "$handshake_dir" || ! -O "$handshake_dir" ]]; then
    printf 'Tsugumori: invalid lock handshake directory.\n' >&2
    exit 1
fi

directory_mode=$(stat -c '%a' -- "$handshake_dir")
if [[ "$directory_mode" != "700" ]]; then
    printf 'Tsugumori: lock handshake directory must have mode 700.\n' >&2
    exit 1
fi

# Serialize lifecycle transitions with duplicate launcher requests. In
# particular, this makes release authorization and duplicate classification a
# single ordered operation: a duplicate is either harmlessly before the
# authorization marker or reliably records a relock request after it.
protocol_lock="$handshake_dir/.protocol.lock"
if [[ ! -f "$protocol_lock" || -L "$protocol_lock" || ! -O "$protocol_lock" ]]; then
    printf 'Tsugumori: invalid lock handshake protocol file.\n' >&2
    exit 1
fi
protocol_mode=$(stat -c '%a' -- "$protocol_lock")
if [[ "$protocol_mode" != "600" ]]; then
    printf 'Tsugumori: lock handshake protocol file must have mode 600.\n' >&2
    exit 1
fi
if ! command -v flock >/dev/null 2>&1; then
    printf 'Tsugumori: flock is required for the lock handshake.\n' >&2
    exit 1
fi
exec 9>>"$protocol_lock"
if ! flock --exclusive --wait 3 9; then
    printf 'Tsugumori: timed out acquiring the lock handshake protocol.\n' >&2
    exit 1
fi

# Recheck the objects after taking the lock so a replaced protocol path cannot
# be used to publish an apparently authenticated state transition.
if [[ ! -d "$handshake_dir" || -L "$handshake_dir" || ! -O "$handshake_dir" \
        || ! -f "$protocol_lock" || -L "$protocol_lock" || ! -O "$protocol_lock" ]]; then
    printf 'Tsugumori: lock handshake state changed while acquiring the protocol.\n' >&2
    exit 1
fi
directory_mode=$(stat -c '%a' -- "$handshake_dir")
protocol_mode=$(stat -c '%a' -- "$protocol_lock")
if [[ "$directory_mode" != "700" || "$protocol_mode" != "600" ]]; then
    printf 'Tsugumori: lock handshake permissions changed while acquiring the protocol.\n' >&2
    exit 1
fi

marker="$handshake_dir/$event"
temporary=$(mktemp "$handshake_dir/.${event}.XXXXXXXXXX")
cleanup() {
    rm -f -- "$temporary" 2>/dev/null || true
}
trap cleanup EXIT

printf '%s\n' "$event" >"$temporary"
chmod 600 "$temporary"
mv -T -- "$temporary" "$marker"
trap - EXIT
