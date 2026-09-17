#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
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

mapfile -d '' SHELL_FILES < <(rg --files --hidden -0 -g '!.git/**' -g '*.sh')
for file in "${SHELL_FILES[@]}"; do
    bash -n "$file"
done
bash -n config/bash/.bashrc
printf 'Bash syntax: OK (%d files)\n' "$(( ${#SHELL_FILES[@]} + 1 ))"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --severity=error -- "${SHELL_FILES[@]}"
    shellcheck --severity=error --shell=bash -- config/bash/.bashrc
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

if ! command -v mpv >/dev/null 2>&1; then
    missing_optional_tool "mpv playback tests"
fi
python3 -B -m unittest discover -s .github/checks/tests -p 'test_*.py'
printf 'Python unit tests: OK\n'

if rg -n 'curl[^[:cntrl:]]*\[[[:space:]]*https?://' README.md; then
    printf 'README contains Markdown link syntax inside a curl command.\n' >&2
    exit 1
fi

# Macrons in the approved Shōi/SHŌI terminal title are intentional.
if rg -nP '[\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{024F}]' \
    README.md docs install.sh config | sed -e 's/Shōi/Shoi/g' -e 's/SHŌI/SHOI/g' \
    | rg -P '[\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{024F}]'; then
    printf 'User-facing files contain accented Latin presentation text.\n' >&2
    exit 1
fi

if rg -ni "\\b(p[o]lice|tr[a]it (horizontal|vertical)|optimis[a]tion vectorielle|r[e]ndu|s[o]rtie|l[a]ncement|ab[a]ndon|l[e]cture [.]desktop|compos[a]nts?|l['’]im[a]ge|t[e]xte|c[o]nteneur|volume act[u]el|s[i]non|indicat[i]on mute|c[a]rrousel|art[i]ste|scale gl[o]bal|c[o]uleurs|b[o]utons|transm[e]ttre|f[i]n multipart abs[e]nte)\\b" \
    README.md docs install.sh config; then
    printf 'User-facing files contain legacy French or mixed-French presentation text.\n' >&2
    exit 1
fi

if rg -n 'ttf-[g]oogle|INSTALL_A[U]R|bootstrap_aur_[h]elper|pinned-[a]ur|base-[d]evel' \
    install.sh packages README.md; then
    printf 'Legacy AUR or build-tool bootstrap logic remains.\n' >&2
    exit 1
fi

if rg -n 'session-[s]tart|session_start_[c]ommand|force_renderer_[r]eload|hl[.]dsp[.]d[p]ms' \
    config .github/checks; then
    printf 'Monitor-recovery feature code remains mixed into the cleanup branch.\n' >&2
    exit 1
fi

for retired in config/quickshell/videos maintenance \
    config/waybar/scripts/pomodoro.sh config/waybar/scripts/pomodoro_toggle.sh \
    config/quickshell/components/WipeCurtain.qml config/quickshell/components/Scanlines.qml \
    config/quickshell/components/CornerDeco.qml config/quickshell/components/TsugumoriButton.qml; do
    [[ ! -e "$retired" ]] || { printf 'Retired file remains: %s\n' "$retired" >&2; exit 1; }
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

    if wanted_dimensions is not None:
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"{path}: invalid PNG signature")
        width, height = struct.unpack(">II", data[16:24])
        if (width, height) != wanted_dimensions:
            raise SystemExit(f"{path}: unexpected dimensions {width}x{height}")

print("Fallback lock wallpaper: OK")
PY

python3 - <<'PY'
import hashlib
from pathlib import Path

font_assets = {
    Path("assets/fonts/share-tech-mono/ShareTechMono-Regular.ttf"):
        "9ceab1f87414829af259c0f537573ae03ef7dd3147c0b27a36a1a0beb6732677",
    Path("assets/fonts/share-tech-mono/OFL.txt"):
        "9d96f445b6e9c701428811d0177f894874f8d6f07ecc30d568c506542368f3ff",
    Path("config/quickshell/assets/fonts/ibm-plex-mono/IBMPlexMono-Regular.ttf"):
        "6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46",
    Path("config/quickshell/assets/fonts/ibm-plex-mono/IBMPlexMono-Medium.ttf"):
        "a9b4c49bb299e05b5f6c481e7fb5e78943d2793249a0c8874ab574a2d1ea6755",
    Path("config/quickshell/assets/fonts/ibm-plex-mono/OFL.txt"):
        "7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da",
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

required_pacman = {
    "awww", "quickshell", "hyprlock", "hypridle",
    "ttf-jetbrains-mono-nerd",
}
missing = sorted(required_pacman - package_set)
if missing:
    raise SystemExit(f"packages/pacman.txt: missing required runtime: {', '.join(missing)}")

removed_packages = {
    "qt6-multimedia-ffmpeg",
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

if [[ -x /usr/lib/qt6/bin/qsb ]]; then
    SHADER_VERIFY_DIR=$(mktemp -d)
    for stage in vert frag; do
        shader="config/quickshell/widgets/lockscreen/shaders/lines.$stage"
        if ! /usr/lib/qt6/bin/qsb --dump "$shader.qsb" >/dev/null \
            || ! /usr/lib/qt6/bin/qsb --glsl '300 es,330' --hlsl 50 --msl 12 \
                -o "$SHADER_VERIFY_DIR/lines.$stage.qsb" "$shader"; then
            rm -rf -- "$SHADER_VERIFY_DIR"
            exit 1
        fi
    done
    rm -rf -- "$SHADER_VERIFY_DIR"
    printf 'Native shader packages and source compilation: OK\n'
else
    missing_optional_tool "Native shader packages"
fi

if [[ -x /usr/lib/qt6/bin/qmltestrunner ]]; then
    for suite in lockscreen wallpaper; do
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_SCALE_FACTOR=1.25 \
            /usr/lib/qt6/bin/qmltestrunner -input ".github/checks/qmltests/$suite" -o -,txt
    done
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_SCALE_FACTOR=1.25 \
        /usr/lib/qt6/bin/qmltestrunner -import .github/checks/qmltests/player/stubs \
            -input .github/checks/qmltests/player/tst_PlayerClose.qml -o -,txt
else
    missing_optional_tool "Qt presentation tests"
fi

printf 'Repository validation: OK\n'
