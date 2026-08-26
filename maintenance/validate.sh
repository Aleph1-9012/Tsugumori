#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

REQUIRE_INTEGRATION=${TSUGUMORI_REQUIRE_INTEGRATION:-0}

missing_optional_tool() {
    local label="$1"
    if [[ "$REQUIRE_INTEGRATION" == "1" ]]; then
        printf '%s is required for integration validation.\n' "$label" >&2
        exit 1
    fi
    printf '%s: skipped (not installed)\n' "$label"
}

mapfile -d '' SHELL_FILES < <(rg --files -0 -g '*.sh')
for file in "${SHELL_FILES[@]}"; do
    bash -n "$file"
done
printf 'Bash syntax: OK (%d files)\n' "${#SHELL_FILES[@]}"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --severity=error -- "${SHELL_FILES[@]}"
    printf 'ShellCheck errors: none\n'
else
    missing_optional_tool "ShellCheck"
fi

mapfile -d '' LUA_FILES < <(rg --files -0 -g '*.lua')
if command -v luac >/dev/null 2>&1; then
    for file in "${LUA_FILES[@]}"; do
        luac -p "$file"
    done
    printf 'Lua syntax: OK (%d files)\n' "${#LUA_FILES[@]}"
else
    missing_optional_tool "Lua syntax"
fi

python3 - <<'PY'
import ast
from pathlib import Path

paths = sorted(Path(".").rglob("*.py"))

count = 0
for path in paths:
    if ".git" in path.parts or "__pycache__" in path.parts:
        continue
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    count += 1

print(f"Python syntax: OK ({count} files)")
PY

python3 -m unittest discover -s maintenance/tests -p 'test_*.py'
printf 'Python unit tests: OK\n'

if rg -n 'curl[^[:cntrl:]]*\[[[:space:]]*https?://' README.md; then
    printf 'README contains Markdown link syntax inside a curl command.\n' >&2
    exit 1
fi

if rg -nP '[\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{024F}]' \
    README.md docs install.sh config; then
    printf 'User-facing files contain accented Latin presentation text.\n' >&2
    exit 1
fi

if rg -ni "\\b(p[o]lice|tr[a]it (horizontal|vertical)|optimis[a]tion vectorielle|r[e]ndu|s[o]rtie|l[a]ncement|ab[a]ndon|l[e]cture [.]desktop|compos[a]nts?|l['’]im[a]ge|t[e]xte|c[o]nteneur|volume act[u]el|s[i]non|indicat[i]on mute|c[a]rrousel|art[i]ste|scale gl[o]bal|c[o]uleurs|b[o]utons|transm[e]ttre|f[i]n multipart abs[e]nte)\\b" \
    README.md docs install.sh config; then
    printf 'User-facing files contain legacy French or mixed-French presentation text.\n' >&2
    exit 1
fi

if rg -n 'ttf-[g]oogle|INSTALL_A[U]R|bootstrap_aur_[h]elper|pinned-[a]ur|base-[d]evel' \
    install.sh packages maintenance/update-pins.sh README.md; then
    printf 'Legacy AUR or build-tool bootstrap logic remains.\n' >&2
    exit 1
fi

if rg -n 'session-[s]tart|session_start_[c]ommand|force_renderer_[r]eload|hl[.]dsp[.]d[p]ms' \
    config maintenance; then
    printf 'Monitor-recovery feature code remains mixed into the cleanup branch.\n' >&2
    exit 1
fi

for generator in \
    config/quickshell/pixel_wave.py \
    config/quickshell/pixel-wave-close-video.py \
    config/quickshell/ext_last_fr.py; do
    [[ ! -e "$generator" ]] || { printf 'Maintainer generator remains deployed: %s\n' "$generator" >&2; exit 1; }
done
for generator in \
    maintenance/wave-assets/pixel_wave.py \
    maintenance/wave-assets/pixel-wave-close-video.py \
    maintenance/wave-assets/extract_last_frame.py; do
    [[ -f "$generator" ]] || { printf 'Maintainer generator is missing: %s\n' "$generator" >&2; exit 1; }
done
if rg -n '\bpython(3)?\b|pixel[_-]wave|ext_last|generat(e|ing|or)' config/quickshell/wave-check.sh; then
    printf 'Login-time wave verification still invokes asset generation.\n' >&2
    exit 1
fi

if rg -n 'playerctl|n[i]er-arrow\.png|/tmp/(pomodoro_state|qs-menu|qs-toggle|qs-front|mpv-tsugumori\.sock|qshare-(events|qr\.png)|yzi-out)|LOCKPWD|pamtester[[:space:]]+qs-lock' config packages; then
    printf 'Deprecated runtime path, asset, or credential transport found.\n' >&2
    exit 1
fi

if rg -n 'pkill[[:space:]]+(-[^[:space:]]+[[:space:]]+)*qs([[:space:]]|$)' config; then
    printf 'An unscoped Quickshell kill would also terminate the secure lock client.\n' >&2
    exit 1
fi

if rg -n '\b(pkill|killall)\b.*\b(dunst|mako|swaync)\b' config; then
    printf 'Tsugumori must not terminate user-managed notification daemons.\n' >&2
    exit 1
fi

LOCK_QML=config/quickshell/widgets/lockscreen.qml
for token in 'WlSessionLock {' 'locked: true' 'WlSessionLockSurface {' 'PamContext {' 'config: "hyprlock"' '!sessionLock.secure' 'Quickshell.watchFiles = false'; do
    if ! rg -Fq "$token" "$LOCK_QML"; then
        printf 'Secure lock contract is missing token: %s\n' "$token" >&2
        exit 1
    fi
done

if rg -n 'PanelWindow|WlrLayershell|WlrLayer|LOCKPWD|pamtester|environment[[:space:]]*:' "$LOCK_QML"; then
    printf 'The lockscreen contains a layer-shell overlay or deprecated credential transport.\n' >&2
    exit 1
fi

for launcher in config/quickshell/lock.sh config/quickshell/lock-handshake.sh config/quickshell/restart.sh; do
    [[ -x "$launcher" ]] || { printf '%s must be executable.\n' "$launcher" >&2; exit 1; }
done

for token in 'fallback_lock' 'exec hyprlock' 'qs --no-duplicate --path "$lockscreen" &' 'marker_is_valid secure' 'marker_is_valid release-requested'; do
    if ! rg -Fq "$token" config/quickshell/lock.sh; then
        printf 'Lock launcher contract is missing token: %s\n' "$token" >&2
        exit 1
    fi
done

if rg -ni 'n[i]er|mot de p[a]sse|authent[i]fication|tent[a]tive|Noto Sans JP' \
    config/hypr/hyprlock.conf; then
    printf 'The Hyprlock fallback still contains legacy branding or French presentation text.\n' >&2
    exit 1
fi

for token in 'allow_session_lock_restore = true' 'hl.exec_cmd("awww-daemon")'; do
    if ! rg -Fq "$token" config/hypr/hyprland.lua; then
        printf 'Hyprland Lua contract is missing token: %s\n' "$token" >&2
        exit 1
    fi
done

if [[ -e config/hypr/hyprland.conf ]]; then
    printf 'The retired Hyprlang configuration must not ship beside hyprland.lua.\n' >&2
    exit 1
fi

[[ ! -e config/system/pam.d/qs-lock ]] || {
    printf 'The obsolete custom qs-lock PAM service must remain removed.\n' >&2
    exit 1
}

python3 - <<'PY'
import hashlib
import struct
from pathlib import Path

expected = {
    Path("config/quickshell/videos/wave_reveal.mp4"): (
        "27aa916ecf517f9ae8fd81b01cd2d98540bd871f0157ea8638401ce6f3ed2ac0",
        None,
    ),
    Path("config/quickshell/videos/wave_hide.mp4"): (
        "2de71962d6617f1610e1da422a97b31316826cc76d56f2246b013130dc089f09",
        None,
    ),
    Path("config/quickshell/videos/wave_last_frame.png"): (
        "b2da90aa03b3600887732977cab6b918ede7e3af58b24bc3e91150f6a9fea3f1",
        (2560, 1600),
    ),
    Path("assets/wallpapers/Aleph1.png"): (
        "c4219b4d669751aa3ab7f8d621dc7a40d82b5e1daebf52ca2aaa575bc9bace87",
        (8000, 4500),
    ),
}

for path, (wanted_hash, wanted_dimensions) in expected.items():
    data = path.read_bytes()
    if not data:
        raise SystemExit(f"{path}: lock asset is empty")
    actual_hash = hashlib.sha256(data).hexdigest()
    if actual_hash != wanted_hash:
        raise SystemExit(f"{path}: unexpected SHA-256 {actual_hash}")

    if path.suffix == ".mp4" and (len(data) < 12 or data[4:8] != b"ftyp"):
        raise SystemExit(f"{path}: invalid ISO BMFF/MP4 signature")
    if wanted_dimensions is not None:
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"{path}: invalid PNG signature")
        width, height = struct.unpack(">II", data[16:24])
        if (width, height) != wanted_dimensions:
            raise SystemExit(f"{path}: unexpected dimensions {width}x{height}")

print("Secure lock assets: OK")
PY

python3 - <<'PY'
import hashlib
from pathlib import Path

font_assets = {
    Path("assets/fonts/share-tech-mono/ShareTechMono-Regular.ttf"):
        "9ceab1f87414829af259c0f537573ae03ef7dd3147c0b27a36a1a0beb6732677",
    Path("assets/fonts/share-tech-mono/OFL.txt"):
        "9d96f445b6e9c701428811d0177f894874f8d6f07ecc30d568c506542368f3ff",
}
for path, wanted_hash in font_assets.items():
    if not path.is_file():
        raise SystemExit(f"{path}: bundled font asset is missing")
    data = path.read_bytes()
    if not data:
        raise SystemExit(f"{path}: bundled font asset is empty")
    actual_hash = hashlib.sha256(data).hexdigest()
    if actual_hash != wanted_hash:
        raise SystemExit(f"{path}: unexpected SHA-256 {actual_hash}")

print("Bundled font assets: OK")
PY

python3 - <<'PY'
from pathlib import Path

manifest = Path("packages/pacman.txt")
packages = [
    line.strip()
    for line in manifest.read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]
package_set = set(packages)
duplicates = sorted({package for package in packages if packages.count(package) > 1})
if duplicates:
    raise SystemExit(f"{manifest}: duplicate packages: {', '.join(duplicates)}")
if len(packages) != 39:
    raise SystemExit(f"{manifest}: expected 39 direct packages, found {len(packages)}")
obsolete_manifests = [Path("packages/" "aur.txt"), Path("packages/pinned-" "aur.txt")]
present_obsolete = [str(path) for path in obsolete_manifests if path.exists()]
if present_obsolete:
    raise SystemExit(f"obsolete package manifests must remain removed: {', '.join(present_obsolete)}")

required_pacman = {"awww", "quickshell", "qt6-multimedia-ffmpeg", "hyprlock", "hypridle"}
missing = sorted(required_pacman - package_set)
if missing:
    raise SystemExit(f"packages/pacman.txt: missing required runtime: {', '.join(missing)}")

removed_packages = {
    "qt5-wayland", "gtk4-layer-shell", "figlet", "pavucontrol", "satty",
    "ttf-jetbrains-mono", "fish", "starship", "python-cairo", "python-numpy",
    "python-opencv", "qrencode",
}
reintroduced = sorted(removed_packages & package_set)
if reintroduced:
    raise SystemExit(f"packages/pacman.txt: removed packages reintroduced: {', '.join(reintroduced)}")

print("Package manifests: OK")
PY

if command -v Hyprland >/dev/null 2>&1; then
    VERIFY_RUNTIME=$(mktemp -d)
    chmod 700 "$VERIFY_RUNTIME"
    HYPRLAND_VERIFY_ARGS=(--verify-config --config config/hypr/hyprland.lua)
    if (( EUID == 0 )); then
        HYPRLAND_VERIFY_ARGS+=(--i-am-really-stupid)
    fi
    if ! XDG_RUNTIME_DIR="$VERIFY_RUNTIME" Hyprland "${HYPRLAND_VERIFY_ARGS[@]}" >/dev/null; then
        rm -rf -- "$VERIFY_RUNTIME"
        exit 1
    fi
    rm -rf -- "$VERIFY_RUNTIME"
    printf 'Hyprland configuration: OK\n'
else
    missing_optional_tool "Hyprland configuration"
fi

QMLLINT_BIN=""
if [[ -x /usr/lib/qt6/bin/qmllint ]]; then
    QMLLINT_BIN=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1 && qmllint --version 2>&1 | rg -q '^qmllint 6\.'; then
    QMLLINT_BIN=$(command -v qmllint)
fi

if [[ -n "$QMLLINT_BIN" ]]; then
    mapfile -d '' QML_FILES < <(rg --files -0 -g '*.qml' config/quickshell)
    (( ${#QML_FILES[@]} >= 16 )) || { printf 'Expected at least 16 QML files, found %d.\n' "${#QML_FILES[@]}" >&2; exit 1; }
    QMLLINT_LOG=$(mktemp)
    if ! "$QMLLINT_BIN" -I config/quickshell "${QML_FILES[@]}" >"$QMLLINT_LOG" 2>&1; then
        sed -n '1,500p' "$QMLLINT_LOG" >&2
        rm -f -- "$QMLLINT_LOG"
        exit 1
    fi
    rm -f -- "$QMLLINT_LOG"
    printf 'QML syntax and imports: OK (%d files)\n' "${#QML_FILES[@]}"
else
    missing_optional_tool "QML syntax and imports"
fi

printf 'Repository validation: OK\n'
