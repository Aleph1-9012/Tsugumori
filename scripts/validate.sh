#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

mapfile -d '' SHELL_FILES < <(rg --files -0 -g '*.sh')
for file in "${SHELL_FILES[@]}"; do
    bash -n "$file"
done
printf 'Bash syntax: OK (%d files)\n' "${#SHELL_FILES[@]}"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --severity=error -- "${SHELL_FILES[@]}"
    printf 'ShellCheck errors: none\n'
else
    printf 'ShellCheck: skipped (not installed)\n'
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

python3 -m unittest discover -s tests -p 'test_*.py'
printf 'Python unit tests: OK\n'

if rg -n 'curl[^[:cntrl:]]*\[[[:space:]]*https?://' README.md; then
    printf 'README contains Markdown link syntax inside a curl command.\n' >&2
    exit 1
fi

if rg -n 'playerctl|nier-arrow\.png|/tmp/(qs-menu|qs-toggle|qs-front|mpv-tsugumori\.sock|qshare-(events|qr\.png)|yzi-out)|LOCKPWD|pamtester[[:space:]]+qs-lock' config packages; then
    printf 'Deprecated runtime path, asset, or credential transport found.\n' >&2
    exit 1
fi

if rg -n 'pkill[[:space:]]+(-[^[:space:]]+[[:space:]]+)*qs([[:space:]]|$)' config; then
    printf 'An unscoped Quickshell kill would also terminate the secure lock client.\n' >&2
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

for launcher in config/quickshell/lock.sh config/quickshell/restart.sh; do
    [[ -x "$launcher" ]] || { printf '%s must be executable.\n' "$launcher" >&2; exit 1; }
done

for token in 'fallback_lock' 'exec hyprlock' 'exec qs --no-duplicate'; do
    if ! rg -Fq "$token" config/quickshell/lock.sh; then
        printf 'Lock launcher contract is missing token: %s\n' "$token" >&2
        exit 1
    fi
done

[[ ! -e config/system/pam.d/qs-lock ]] || {
    printf 'The obsolete custom qs-lock PAM service must remain removed.\n' >&2
    exit 1
}

python3 - <<'PY'
import hashlib
import struct
from pathlib import Path

expected = {
    Path("config/quickshell/videos/wave_reveal.mp4"): "27aa916ecf517f9ae8fd81b01cd2d98540bd871f0157ea8638401ce6f3ed2ac0",
    Path("config/quickshell/videos/wave_hide.mp4"): "2de71962d6617f1610e1da422a97b31316826cc76d56f2246b013130dc089f09",
    Path("config/quickshell/videos/wave_last_frame.png"): "b2da90aa03b3600887732977cab6b918ede7e3af58b24bc3e91150f6a9fea3f1",
}

for path, wanted_hash in expected.items():
    data = path.read_bytes()
    if not data:
        raise SystemExit(f"{path}: lock asset is empty")
    actual_hash = hashlib.sha256(data).hexdigest()
    if actual_hash != wanted_hash:
        raise SystemExit(f"{path}: unexpected SHA-256 {actual_hash}")

    if path.suffix == ".mp4" and (len(data) < 12 or data[4:8] != b"ftyp"):
        raise SystemExit(f"{path}: invalid ISO BMFF/MP4 signature")
    if path.suffix == ".png":
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"{path}: invalid PNG signature")
        width, height = struct.unpack(">II", data[16:24])
        if (width, height) != (2560, 1600):
            raise SystemExit(f"{path}: unexpected dimensions {width}x{height}")

print("Secure lock assets: OK")
PY

python3 - <<'PY'
from pathlib import Path

manifest_packages = {}
for manifest in (Path("packages/pacman.txt"), Path("packages/aur.txt")):
    packages = [
        line.strip()
        for line in manifest.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    manifest_packages[manifest.name] = set(packages)
    duplicates = sorted({package for package in packages if packages.count(package) > 1})
    if duplicates:
        raise SystemExit(f"{manifest}: duplicate packages: {', '.join(duplicates)}")

required_pacman = {"quickshell", "qt6-multimedia-ffmpeg", "hyprlock", "hypridle"}
missing = sorted(required_pacman - manifest_packages["pacman.txt"])
if missing:
    raise SystemExit(f"packages/pacman.txt: missing secure-lock runtime: {', '.join(missing)}")

if "quickshell-git" in manifest_packages["aur.txt"]:
    raise SystemExit("packages/aur.txt: Quickshell must not be optional or conflict with the required official package")

print("Package manifests: OK")
PY

if command -v Hyprland >/dev/null 2>&1; then
    Hyprland --verify-config --config config/hypr/hyprland.conf >/dev/null
    printf 'Hyprland configuration: OK\n'
else
    printf 'Hyprland configuration: skipped (Hyprland not installed)\n'
fi

QMLLINT_BIN=""
if [[ -x /usr/lib/qt6/bin/qmllint ]]; then
    QMLLINT_BIN=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1 && qmllint --version 2>&1 | rg -q '^qmllint 6\.'; then
    QMLLINT_BIN=$(command -v qmllint)
fi

if [[ -n "$QMLLINT_BIN" ]]; then
    "$QMLLINT_BIN" -I config/quickshell \
        config/quickshell/shell.qml \
        config/quickshell/services/ShellIpc.qml \
        config/quickshell/services/WifiService.qml \
        config/quickshell/widgets/Player.qml \
        config/quickshell/widgets/lockscreen.qml
    printf 'QML entry points: OK\n'
else
    printf 'QML entry points: skipped (Qt 6 qmllint not installed)\n'
fi

printf 'Repository validation: OK\n'
