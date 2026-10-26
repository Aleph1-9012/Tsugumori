#!/usr/bin/env python3
"""Read launcher entries without starting a subprocess for every desktop file."""

from __future__ import annotations

import os
from pathlib import Path
import json
import sys

import gi

gi.require_version("GioUnix", "2.0")
from gi.repository import Gio, GioUnix, GLib


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


class CatalogWatcher:
    """Keep one catalog for the shell; invalidate it through GIO notifications."""

    def __init__(self) -> None:
        self.directories = application_dirs()
        self.dirty = True
        self.entries = None
        self.pending = b""
        self.loop = GLib.MainLoop()
        self.monitor = Gio.AppInfoMonitor.get()
        self.monitor.connect("changed", self.changed)

    @staticmethod
    def emit(message: dict) -> None:
        print(json.dumps(message, ensure_ascii=True), flush=True)

    def changed(self, _monitor) -> None:
        if not self.dirty:
            self.dirty = True
            self.emit({"type": "changed"})

    def refresh(self) -> None:
        if not self.dirty:
            return
        self.dirty = False
        # Re-arm GIO even when there are no desktop entries to read.
        Gio.AppInfo.get_all()
        entries = list_apps(self.directories)
        if entries != self.entries:
            self.entries = entries
            self.emit({"type": "entries", "entries": entries})

    def read_requests(self, _fd, condition) -> bool:
        if condition & (GLib.IO_HUP | GLib.IO_ERR):
            self.loop.quit()
            return False
        block = os.read(sys.stdin.fileno(), 4096)
        if not block:
            self.loop.quit()
            return False
        self.pending += block
        while b"\n" in self.pending:
            line, self.pending = self.pending.split(b"\n", 1)
            if line == b"refresh":
                self.refresh()
        return True

    def run(self) -> None:
        GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.read_requests)
        self.loop.run()


if __name__ == "__main__":
    if sys.argv[1:] == ["--watch"]:
        CatalogWatcher().run()
    else:
        print(json.dumps(list_apps(application_dirs()), ensure_ascii=True))
