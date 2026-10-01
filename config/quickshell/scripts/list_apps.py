#!/usr/bin/env python3
"""Read launcher entries without starting a subprocess for every desktop file."""

from __future__ import annotations

import os
from pathlib import Path
import re


def application_dirs() -> list[Path]:
    user = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    system = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    return [Path(base) / "applications" for base in [user, *system.split(":")] if base]


def desktop_entry(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    in_entry = False
    try:
        with path.open(encoding="utf-8", errors="replace") as stream:
            for raw in stream:
                line = raw.strip()
                if line.startswith("["):
                    in_entry = line == "[Desktop Entry]"
                elif in_entry and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    fields.setdefault(key, value)
    except OSError:
        pass
    return fields


def list_apps(directories: list[Path]) -> list[str]:
    seen: set[str] = set()
    rows: list[str] = []
    for directory in directories:
        for path in sorted(directory.rglob("*.desktop")):
            desktop_id = "-".join(path.relative_to(directory).parts)
            if desktop_id in seen:
                continue
            # A hidden user override must also suppress the system entry.
            seen.add(desktop_id)
            fields = desktop_entry(path)
            if fields.get("Hidden") == "true" or fields.get("NoDisplay") == "true":
                continue
            if fields.get("Type", "Application") != "Application":
                continue
            name, command = fields.get("Name", ""), fields.get("Exec", "")
            if not name or not command:
                continue
            command = re.sub(r" %[A-Za-z]", "", command)
            values = (name, desktop_id.removesuffix(".desktop"), fields.get("Categories", ""))
            # Keep the launcher's existing one-line, pipe-delimited protocol.
            # Exec is the final field and can itself contain shell pipelines.
            rows.append("|".join(value.replace("|", " ") for value in values) + "|" + command)
    return sorted(set(rows))


if __name__ == "__main__":
    for row in list_apps(application_dirs()):
        print(row)
