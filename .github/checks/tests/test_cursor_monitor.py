"""Tests for the cursor-position-to-monitor helper."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

REPO_ROOT = Path(__file__).parents[3]
SCRIPT = REPO_ROOT / "config/quickshell/scripts/cursor_monitor.py"
CONTROLCENTER_QML = REPO_ROOT / "config/quickshell/widgets/ControlCenter.qml"
PICKER_QML = REPO_ROOT / "config/quickshell/widgets/WallpaperPicker.qml"

sys.path.insert(0, str(SCRIPT.parent))
import cursor_monitor  # noqa: E402


class MonitorAtTests(unittest.TestCase):
    def test_scaled_and_unscaled_monitor(self) -> None:
        monitors = [
            {"name": "DP-1", "x": 0, "y": 0, "width": 3840, "height": 2160,
             "scale": 1.5, "transform": 0},
            {"name": "HDMI-A-1", "x": 2560, "y": 0, "width": 1920, "height": 1080,
             "scale": 1, "transform": 0},
        ]
        self.assertEqual(cursor_monitor.monitor_at(2600, 100, monitors), "HDMI-A-1")
        self.assertEqual(cursor_monitor.monitor_at(100, 100, monitors), "DP-1")
        self.assertEqual(cursor_monitor.monitor_at(2559, 100, monitors), "DP-1")

    def test_rotated_monitor_swaps_logical_size(self) -> None:
        monitors = [
            {"name": "DP-2", "x": 0, "y": 0, "width": 1920, "height": 1080,
             "scale": 1, "transform": 1},
        ]
        self.assertEqual(cursor_monitor.monitor_at(1000, 100, monitors), "DP-2")
        self.assertIsNone(cursor_monitor.monitor_at(1100, 100, monitors))
        self.assertIsNone(cursor_monitor.monitor_at(500, 2000, monitors))

    def test_outside_every_monitor_returns_none(self) -> None:
        monitors = [
            {"name": "DP-1", "x": 0, "y": 0, "width": 1920, "height": 1080,
             "scale": 1, "transform": 0},
        ]
        self.assertIsNone(cursor_monitor.monitor_at(-1, 0, monitors))
        self.assertIsNone(cursor_monitor.monitor_at(1920, 0, monitors))
        self.assertIsNone(cursor_monitor.monitor_at(0, 1080, monitors))


class CursorMonitorMainTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-cursor-test-")
        self.root = Path(self.tempdir.name)
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_fake_hyprctl(self, cursor: dict, monitors: list) -> None:
        script = self.bin_dir / "hyprctl"
        script.write_text(textwrap.dedent(f"""\
            #!/usr/bin/env python3
            import json, sys
            if sys.argv[1] == "cursorpos":
                print(json.dumps({cursor!r}).replace("'", '"'))
            elif sys.argv[1] == "monitors":
                print(json.dumps({monitors!r}).replace("'", '"'))
            else:
                sys.exit(1)
            """), encoding="utf-8")
        script.chmod(0o755)

    def test_main_prints_the_monitor_under_the_cursor(self) -> None:
        monitors = [
            {"name": "DP-1", "x": 0, "y": 0, "width": 3840, "height": 2160,
             "scale": 1.5, "transform": 0},
            {"name": "HDMI-A-1", "x": 2560, "y": 0, "width": 1920, "height": 1080,
             "scale": 1, "transform": 0},
        ]
        self.write_fake_hyprctl({"x": 2600, "y": 100}, monitors)
        env = {**os.environ, "PATH": f"{self.bin_dir}{os.pathsep}{os.environ['PATH']}"}
        result = subprocess.run(
            [sys.executable, str(SCRIPT)], env=env,
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "HDMI-A-1")

    def test_main_fails_when_hyprctl_fails(self) -> None:
        script = self.bin_dir / "hyprctl"
        script.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        script.chmod(0o755)
        env = {**os.environ, "PATH": f"{self.bin_dir}{os.pathsep}{os.environ['PATH']}"}
        result = subprocess.run(
            [sys.executable, str(SCRIPT)], env=env,
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)


class CursorMonitorStaticTests(unittest.TestCase):
    def test_qml_uses_the_helper_script(self) -> None:
        for path in (CONTROLCENTER_QML, PICKER_QML):
            source = path.read_text(encoding="utf-8")
            self.assertNotIn("hyprctl cursorpos", source, str(path))
            self.assertIn("cursor_monitor.py", source, str(path))


if __name__ == "__main__":
    unittest.main()
