#!/usr/bin/env python3
"""Launch the qshare Yazi picker using a private per-user chooser file."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


def runtime_dir() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR")
    if base:
        path = Path(base) / "tsugumori"
    else:
        path = Path.home() / ".cache" / "tsugumori" / "runtime"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.chmod(0o700)
    return path


def main() -> int:
    chooser = runtime_dir() / "yazi-chooser"
    if len(sys.argv) == 2 and sys.argv[1] == "--read-choice":
        try:
            sys.stdout.write(chooser.read_text())
        except FileNotFoundError:
            pass
        return 0

    chooser.unlink(missing_ok=True)

    terminals = (
        ("foot", ["foot", "--app-id", "qs-yazi-picker", "yazi", f"--chooser-file={chooser}"]),
        ("alacritty", ["alacritty", "--class", "qs-yazi-picker", "-e", "yazi", f"--chooser-file={chooser}"]),
        ("kitty", ["kitty", "--class", "qs-yazi-picker", "yazi", f"--chooser-file={chooser}"]),
        ("wezterm", ["wezterm", "start", "--class", "qs-yazi-picker", "--", "yazi", f"--chooser-file={chooser}"]),
    )
    for executable, command in terminals:
        if shutil.which(executable):
            time.sleep(0.35)
            subprocess.Popen(command, start_new_session=True)
            time.sleep(0.45)
            subprocess.run(
                ["hyprctl", "dispatch", "focuswindow", "^(qs-yazi-picker)$"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return 0


    subprocess.run(
        ["notify-send", "qshare", "No supported terminal found (foot/alacritty/kitty/wezterm)"],
        check=False,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
