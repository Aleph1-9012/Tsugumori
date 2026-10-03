#!/usr/bin/env python3
"""Read launcher entries without starting a subprocess for every desktop file."""

from __future__ import annotations

import os
from pathlib import Path
import json

import gi

gi.require_version("GioUnix", "2.0")
from gi.repository import GioUnix


def application_dirs() -> list[Path]:
    user = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    system = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    return [Path(base) / "applications" for base in [user, *system.split(":")] if base]


def list_apps(directories: list[Path]) -> list[dict[str, str]]:
    seen: set[str] = set()
    rows: list[dict[str, str]] = []
    for directory in directories:
        for path in sorted(directory.rglob("*.desktop")):
            desktop_id = "-".join(path.relative_to(directory).parts)
            if desktop_id in seen:
                continue
            # A hidden user override must also suppress the system entry.
            seen.add(desktop_id)
            try:
                app = GioUnix.DesktopAppInfo.new_from_filename(str(path.absolute()))
            except TypeError:
                # PyGObject reports GIO's rejected entry as a NULL constructor.
                continue
            if app is None or app.get_is_hidden() or not app.should_show():
                continue
            if not app.get_executable() and not app.get_boolean("DBusActivatable"):
                continue

            rows.append({"name": app.get_name(), "desktopId": desktop_id.removesuffix(".desktop"),
                         "categories": app.get_categories() or "", "desktopFile": str(path.absolute())})
    return sorted(rows, key=lambda row: (row["name"], row["desktopId"]))


if __name__ == "__main__":
    print(json.dumps(list_apps(application_dirs()), ensure_ascii=True))
