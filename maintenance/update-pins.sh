#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#   Tsugumori — regenerate pinned package versions
#
#   Run this from the repo root after verifying the current config
#   works on your system. It records the exact installed versions of
#   every package listed in packages/pacman.txt so `install.sh --pinned`
#   can reproduce a known-good setup later.
#
#   Usage: ./maintenance/update-pins.sh
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

cd "$(dirname "$0")/.."   # repo root, regardless of where this is invoked from

mkdir -p packages

generate_pins() {
    local src="$1" dest="$2" label="$3"
    local tmp failed=0
    tmp=$(mktemp "${dest}.tmp.XXXXXX")

    if {
        echo "# Pinned ${label} versions — generated $(date +%Y-%m-%d)"
        echo "# These exact versions are known to work together."
        echo "# The installer can use these via the --pinned flag."
        echo ""
        while IFS= read -r pkg; do
            # skip comments and blank lines
            [[ "$pkg" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${pkg// }" ]] && continue
            local version architecture
            local installed_name
            installed_name=$(pacman -Qq "$pkg" 2>/dev/null || true)
            if [[ "$label" == "pacman" && "$installed_name" != "$pkg" ]]; then
                printf 'Pinned official package %s is provided by %s; install the exact manifest package before generating archive pins.\n' "$pkg" "${installed_name:-nothing}" >&2
                failed=1
                break
            fi
            version=$(pacman -Qi "$pkg" 2>/dev/null | awk '/^Version/{print $3}')
            architecture=$(pacman -Qi "$pkg" 2>/dev/null | awk '/^Architecture/{print $3}')
            if [[ -z "$version" || -z "$architecture" ]]; then
                printf 'Required package is not installed locally: %s\n' "$pkg" >&2
                failed=1
                break
            fi
            echo "$pkg=$version=$architecture"
        done < "$src"
        (( failed == 0 ))
    } > "$tmp"; then
        mv "$tmp" "$dest"
    else
        rm -f "$tmp"
        return 1
    fi
}

generate_pins "packages/pacman.txt" "packages/pinned-pacman.txt" "pacman"

echo "── packages/pinned-pacman.txt ──"
cat packages/pinned-pacman.txt
