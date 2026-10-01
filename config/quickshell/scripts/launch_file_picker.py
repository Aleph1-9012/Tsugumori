#!/usr/bin/env python3
"""Choose a local file for qshare using a GTK file chooser."""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path


def choice_path() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR")
    directory = Path(base) / "tsugumori" if base else Path.home() / ".cache/tsugumori/runtime"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory.chmod(0o700)
    return directory / "file-chooser"


def main() -> int:
    choice = choice_path()
    if sys.argv[1:] == ["--read-choice"]:
        try:
            sys.stdout.write(choice.read_text())
        except FileNotFoundError:
            pass
        return 0

    choice.unlink(missing_ok=True)
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk

    time.sleep(0.35)
    dialog = Gtk.FileChooserDialog(title="Choose a file to share", action=Gtk.FileChooserAction.OPEN)
    dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Select", Gtk.ResponseType.ACCEPT)
    dialog.set_default_response(Gtk.ResponseType.ACCEPT)
    dialog.set_default_size(900, 600)
    dialog.set_local_only(True)
    dialog.set_select_multiple(False)
    try:
        response = dialog.run()
        filename = dialog.get_filename()
        if response == Gtk.ResponseType.ACCEPT and filename and Path(filename).is_file():
            choice.write_text(filename + "\n")
            choice.chmod(0o600)
            return 0
        return 1
    finally:
        dialog.destroy()


if __name__ == "__main__":
    sys.exit(main())
