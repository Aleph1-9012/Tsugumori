#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#   Tsugumori — regenerate pinned package versions
#
#   Run this from the repo root after verifying the current config
#   works on your system. It records the exact installed versions of
#   every package listed in packages/pacman.txt and packages/aur.txt,
#   so `install.sh --pinned` can reproduce a known-good setup later.
#
#   Usage: ./scripts/update-pins.sh
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

cd "$(dirname "$0")/.."   # repo root, regardless of where this is invoked from

mkdir -p packages

generate_pins() {
    local src="$1" dest="$2" label="$3"

    {
        echo "# Pinned ${label} versions — generated $(date +%Y-%m-%d)"
        echo "# These exact versions are known to work together."
        echo "# The installer can use these via the --pinned flag."
        echo ""
        while IFS= read -r pkg; do
            # skip comments and blank lines
            [[ "$pkg" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${pkg// }" ]] && continue
            local version
            version=$(pacman -Qi "$pkg" 2>/dev/null | awk '/^Version/{print $3}')
            if [[ -n "$version" ]]; then
                echo "$pkg=$version"
            else
                echo "# $pkg (not installed locally)"
            fi
        done < "$src"
    } > "$dest"
}

generate_pins "packages/pacman.txt" "packages/pinned-pacman.txt" "pacman"
generate_pins "packages/aur.txt"    "packages/pinned-aur.txt"    "AUR"

echo "── packages/pinned-pacman.txt ──"
cat packages/pinned-pacman.txt
echo
echo "── packages/pinned-aur.txt ──"
cat packages/pinned-aur.txt
