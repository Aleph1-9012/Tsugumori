#!/usr/bin/env python3
"""Launch a desktop file with GIO, using Kitty for terminal applications."""

import os
from pathlib import Path
import sys

import gi

gi.require_version("GioUnix", "2.0")
from gi.repository import GioUnix, GLib


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: launch_desktop.py DESKTOP_FILE", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    try:
        app = GioUnix.DesktopAppInfo.new_from_filename(str(path.absolute()))
    except TypeError:
        # The entry may have been removed or become invalid since the last scan.
        print("Application is unavailable.", file=sys.stderr)
        return 1
    if app is None or app.get_is_hidden() or not app.should_show():
        print("Application is unavailable.", file=sys.stderr)
        return 1

    # GIO expands Exec field codes, applies Path and handles DBus activation.
    # Its terminal launcher receives the resulting argv without shell parsing.
    # Scope the adapter to this process and its children, never the login PATH.
    if app.get_boolean("Terminal"):
        adapter = Path(__file__).resolve().parent / "terminal"
        os.environ["PATH"] = str(adapter) + os.pathsep + os.environ.get("PATH", os.defpath)

    try:
        # Applications outlive this short helper. Give their standard streams
        # independent descriptors so closing the launcher's pipes cannot EPIPE.
        with open(os.devnull, "r+b", buffering=0) as streams:
            launched = app.launch_uris_as_manager_with_fds(
                [], None, GLib.SpawnFlags.SEARCH_PATH, None, None, None, None,
                streams.fileno(), streams.fileno(), streams.fileno())
        return 0 if launched else 1
    except GLib.Error as error:
        print(f"Cannot launch application: {error.message}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
