#!/usr/bin/env python3
"""Waybar keyboard layout indicator that hides itself with a single layout.

Prints one JSON line per change, driven by Hyprland's event socket.
"""

from __future__ import annotations

import json
import os
import socket
import sys
import xml.etree.ElementTree as ET


XKB_RULES = "/usr/share/X11/xkb/rules/evdev.xml"
REFRESH_EVENTS = {"activelayout", "configreloaded"}


def hypr_dir() -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return os.path.join(runtime, "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"])


def hypr_request(command: str) -> str:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(os.path.join(hypr_dir(), ".socket.sock"))
        sock.sendall(command.encode())
        chunks = []
        while chunk := sock.recv(65536):
            chunks.append(chunk)
    return b"".join(chunks).decode()


def short_descriptions() -> dict[str, str]:
    """Map XKB layout codes to their short language labels (us -> en)."""
    try:
        root = ET.parse(XKB_RULES).getroot()
    except (OSError, ET.ParseError):
        return {}
    labels = {}
    for item in root.iterfind("./layoutList/layout/configItem"):
        name = item.findtext("name")
        short = item.findtext("shortDescription")
        if name and short:
            labels[name] = short
    return labels


def render(labels: dict[str, str]) -> dict[str, str]:
    keyboards = json.loads(hypr_request("j/devices")).get("keyboards", [])
    keyboard = next((k for k in keyboards if k.get("main")), None)
    if keyboard is None:
        return {"text": ""}
    layouts = [code.strip() for code in keyboard.get("layout", "").split(",") if code.strip()]
    if len(layouts) < 2:
        return {"text": ""}
    index = keyboard.get("active_layout_index", 0)
    code = layouts[index] if 0 <= index < len(layouts) else layouts[0]
    label = labels.get(code, code).upper()
    return {
        "text": f"<span foreground='#c8c8c4'>KB</span> <span weight='medium'>{label}</span>",
        "tooltip": keyboard.get("active_keymap", code),
    }


def emit(labels: dict[str, str], last: str | None) -> str:
    line = json.dumps(render(labels))
    if line != last:
        print(line, flush=True)
    return line


def main() -> int:
    labels = short_descriptions()
    last = emit(labels, None)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as events:
        events.connect(os.path.join(hypr_dir(), ".socket2.sock"))
        for raw in events.makefile("r", encoding="utf-8", errors="replace"):
            if raw.split(">>", 1)[0] in REFRESH_EVENTS:
                last = emit(labels, last)
    return 0


if __name__ == "__main__":
    sys.exit(main())
