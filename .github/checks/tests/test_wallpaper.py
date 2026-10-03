from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).parents[3]
SET_WALLPAPER = REPO_ROOT / "config/quickshell/setwallpaper.sh"
PICKER_QML = REPO_ROOT / "config/quickshell/widgets/WallpaperPicker.qml"
QML_TEST_RUNNER = "/usr/lib/qt6/bin/qmltestrunner"


class WallpaperCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-wallpaper-test-")
        self.root = Path(self.tempdir.name)
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.capture = self.root / "awww-argv.json"
        fake_awww = self.bin_dir / "awww"
        fake_awww.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, pathlib, sys\n"
            "pathlib.Path(os.environ['AWWW_CAPTURE']).write_text("
            "json.dumps(sys.argv[1:]), encoding='utf-8')\n",
            encoding="utf-8",
        )
        fake_awww.chmod(0o755)

        self.config_home = self.root / "config"
        self.env = os.environ.copy()
        self.env["PATH"] = str(self.bin_dir) + os.pathsep + self.env["PATH"]
        self.env["AWWW_CAPTURE"] = str(self.capture)
        self.env["XDG_CONFIG_HOME"] = str(self.config_home)
        self.env["HOME"] = str(self.root / "home")

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def test_metacharacters_remain_literal_arguments(self) -> None:
        wallpaper = self.root / "night'$(touch injected)`touch backtick`.jpg"
        wallpaper.touch()
        target = "DP-1; touch monitor-injected"

        completed = subprocess.run(
            [str(SET_WALLPAPER), str(wallpaper), target],
            cwd=self.root,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertFalse((self.root / "injected").exists())
        self.assertFalse((self.root / "backtick").exists())
        self.assertFalse((self.root / "monitor-injected").exists())
        self.assertEqual(
            json.loads(self.capture.read_text(encoding="utf-8")),
            [
                "img",
                "--transition-type",
                "fade",
                "--transition-duration",
                "0.6",
                "--transition-fps",
                "60",
                "--outputs",
                target,
                str(wallpaper),
            ],
        )
        selection = self.config_home / "quickshell/current_wallpaper.txt"
        self.assertEqual(selection.read_text(encoding="utf-8"), f"{wallpaper}\n")
        self.assertEqual(selection.stat().st_mode & 0o777, 0o600)

    @unittest.skipUnless(Path(QML_TEST_RUNNER).is_file(), "qmltestrunner is not installed")
    def test_picker_passes_filename_and_monitor_as_literal_arguments(self) -> None:
        source = PICKER_QML.read_text(encoding="utf-8")
        method = re.search(r"^    function applyWallpaper\(.*?^    }$", source,
                           flags=re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(method)
        filename = "night'$(touch injected)`touch backtick`.jpg"
        monitor = "DP-1'; $(touch monitor-injected)"
        qml = '''import QtQuick
import QtTest
TestCase {
    id: root
    name: "WallpaperArguments"
    property string xdgConfigHome: __CONFIG__
    property string wallpaperDir: __DIRECTORY__
    property var wallpapers: __FILES__

    QtObject {
        id: applyProc
        property var command: []
        property bool running: false
    }

    __METHOD__

    function test_literal_arguments() {
        applyWallpaper(0, __MONITOR__)
        compare(applyProc.command, __EXPECTED__)
        verify(applyProc.running)
    }
}
'''.replace("__CONFIG__", json.dumps(str(self.config_home))) \
   .replace("__DIRECTORY__", json.dumps(str(self.root))) \
   .replace("__FILES__", json.dumps([filename])) \
   .replace("__METHOD__", method[0]) \
   .replace("__MONITOR__", json.dumps(monitor)) \
   .replace("__EXPECTED__", json.dumps([
       str(self.config_home / "quickshell/setwallpaper.sh"),
       str(self.root / filename), monitor,
   ]))
        test_file = self.root / "tst_WallpaperArguments.qml"
        test_file.write_text(qml, encoding="utf-8")
        result = subprocess.run([QML_TEST_RUNNER, "-input", str(test_file)],
                                env={**self.env, "QT_QPA_PLATFORM": "offscreen",
                                     "QT_QUICK_BACKEND": "software"},
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
