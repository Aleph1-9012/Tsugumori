from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).parents[3]
SHELL = REPO / "config/quickshell"


class NativeIntegrationTests(unittest.TestCase):
    def test_registered_types_and_singleton_members_exist(self) -> None:
        for qmldir in SHELL.rglob("qmldir"):
            for line in qmldir.read_text().splitlines():
                fields = line.split()
                if fields and fields[-1].endswith(".qml"):
                    self.assertTrue((qmldir.parent / fields[-1]).is_file(), line)
        sources = list(SHELL.rglob("*.qml")) + list(SHELL.rglob("*.js"))
        for name, folder in (("Settings", "settings"), ("Theme", "theme")):
            text = (SHELL / folder / (name + ".qml")).read_text()
            members = set(re.findall(r"property\s+\w+\s+(\w+)\s*:", text))
            members.update(re.findall(r"function\s+(\w+)\s*\(", text))
            for path in sources:
                refs = set(re.findall(r"\b" + name + r"\.(\w+)", path.read_text()))
                self.assertFalse(refs - members, (path, refs - members))

    def test_startup_check_accepts_native_files_without_videos(self) -> None:
        with tempfile.TemporaryDirectory(prefix="tsugumori-native-check-") as temp:
            env = {**os.environ, "XDG_CONFIG_HOME": str(REPO / "config"), "XDG_CACHE_HOME": temp}
            result = subprocess.run(["bash", str(SHELL / "wave-check.sh")], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((SHELL / "videos").exists())
            self.assertIn("Native lockscreen and picker assets verified",
                          (Path(temp) / "quickshell/wave-check.log").read_text())

    def test_startup_check_rejects_missing_or_empty_native_assets(self) -> None:
        assets = (
            "lockscreen.qml", "lockscreen/PhaseLockView.qml", "lockscreen/PhaseArt.js",
            "lockscreen/PhaseLines.qml", "lockscreen/PhaseCpuFallback.qml",
            "lockscreen/FormationCorner.qml", "lockscreen/shaders/lines.vert.qsb",
            "lockscreen/shaders/lines.frag.qsb", "WallpaperPicker.qml",
            "wallpaper/PickerMotion.qml", "wallpaper/PickerBackdrop.qml",
            "wallpaper/PickerRegistration.qml", "wallpaper/PickerCorners.qml",
        )
        for asset in assets:
            for empty in (False, True):
                with self.subTest(asset=asset, empty=empty), tempfile.TemporaryDirectory(
                    prefix="tsugumori-native-assets-"
                ) as temp:
                    root = Path(temp)
                    widgets = root / "config/quickshell/widgets"
                    shutil.copytree(SHELL / "widgets", widgets)
                    if empty:
                        (widgets / asset).write_bytes(b"")
                    else:
                        (widgets / asset).unlink()
                    env = {**os.environ, "XDG_CONFIG_HOME": str(root / "config"),
                           "XDG_CACHE_HOME": str(root / "cache")}
                    result = subprocess.run(["bash", str(SHELL / "wave-check.sh")], env=env,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn("widgets/" + asset,
                                  (root / "cache/quickshell/wave-check.log").read_text())

    def test_clipboard_keeps_keyboard_routing_and_live_bounds(self) -> None:
        source = (SHELL / "widgets/Clipboard.qml").read_text()
        self.assertIn("keyNavigationEnabled: false", source)
        self.assertIn("root.store.moveSelection(event.key", source)
        self.assertIn("CurtainSurface {", source)
        service = (SHELL / "services/ClipboardService.qml").read_text()
        self.assertIn("Math.max(0, Math.min(entriesModel.count - 1, selectedIndex + step))", service)

    def test_notes_copy_feedback_and_same_size_button_remain(self) -> None:
        source = (SHELL / "widgets/QuickNotes.qml").read_text()
        self.assertIn("Quickshell.clipboardText = copyText", source)
        self.assertIn("Layout.preferredWidth: newButton.implicitWidth", source)
        self.assertIn("onCopyTextChanged: resetCopyFeedback()", source)

    def test_terminal_noninteractive_use_is_silent(self) -> None:
        for name in ("tsugumori-welcome.sh", "tsugumori-prompt.sh"):
            result = subprocess.run(["bash", str(SHELL / name)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")

    def test_deployed_code_has_no_machine_paths_or_video_players(self) -> None:
        for path in SHELL.rglob("*"):
            if path.suffix not in (".qml", ".js", ".sh", ".py"):
                continue
            text = path.read_text()
            self.assertNotRegex(text, r"/home/[^/\s]+/", str(path))
            self.assertNotIn("import QtMultimedia", text, str(path))
            self.assertNotIn("MediaPlayer {", text, str(path))


if __name__ == "__main__":
    unittest.main()
