#!/usr/bin/env python3
"""Print the name of the Hyprland monitor under the cursor.

Queries `hyprctl cursorpos -j` and `hyprctl monitors -j`, then maps the
cursor position into logical (post-scale, post-rotation) monitor bounds.
Exits nonzero when the position cannot be resolved.
"""

import json
import subprocess
import sys

_HYPRCTL_TIMEOUT = 5


def logical_bounds(monitor: dict) -> tuple[float, float, float, float]:
    """Return (x, y, width, height) in compositor logical coordinates."""
    scale = float(monitor.get("scale") or 1)
    width = monitor["width"] / scale
    height = monitor["height"] / scale
    if int(monitor.get("transform", 0)) % 2:
        width, height = height, width
    return monitor["x"], monitor["y"], width, height


def monitor_at(x: int, y: int, monitors: list) -> str | None:
    for monitor in monitors:
        mx, my, width, height = logical_bounds(monitor)
        if mx <= x < mx + width and my <= y < my + height:
            return monitor["name"]
    return None


def _hyprctl(*args: str):
    return json.loads(
        subprocess.check_output(["hyprctl", *args], timeout=_HYPRCTL_TIMEOUT)
    )


def main() -> int:
    try:
        position = _hyprctl("cursorpos", "-j")
        monitors = _hyprctl("monitors", "-j")
        name = monitor_at(position["x"], position["y"], monitors)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError,
            KeyError, TypeError, ValueError):
        return 1
    if name is None:
        return 1
    print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
