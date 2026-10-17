from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

try:
    import gi
    gi.require_version("GioUnix", "2.0")
except (ImportError, ValueError) as error:
    raise unittest.SkipTest("GIO desktop application tests require python-gobject") from error


SHELL = Path(__file__).parents[3] / "config/quickshell"
SPEC = importlib.util.spec_from_file_location("list_apps", SHELL / "scripts/list_apps.py")
apps = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(apps)


class AppCatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory(prefix="tsugumori-apps-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.user = self.root / "user/applications"
        self.system = self.root / "system/applications"

    def entry(self, directory: Path, name: str, content: str) -> None:
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("[Desktop Entry]\nType=Application\n" + content, encoding="utf-8")

    def test_reads_main_section_without_desktop_actions(self) -> None:
        self.entry(self.system, "editor.desktop", "Name=Editor\nExec=/usr/bin/true %F\nCategories=Development;\n"
                   "[Desktop Action Private]\nName=Private\nExec=editor --private\nHidden=true\n")
        self.assertEqual(apps.list_apps([self.system]), [{"name": "Editor", "desktopId": "editor",
            "categories": "Development;", "desktopFile": str(self.system / "editor.desktop")}])

    def test_user_overrides_and_hidden_entries(self) -> None:
        for directory, name in ((self.system, "System"), (self.user, "Personal")):
            self.entry(directory, "editor.desktop", f"Name={name}\nExec=/usr/bin/true\n")
        self.entry(self.system, "hidden.desktop", "Name=Hidden\nExec=/usr/bin/true\n")
        self.entry(self.user, "hidden.desktop", "Hidden=true\n")
        self.entry(self.system, "nodisplay.desktop", "Name=Helper\nExec=/usr/bin/true\nNoDisplay=true\n")
        self.entry(self.system, "empty.desktop", "Name=Missing command\n")
        self.assertEqual([row["name"] for row in apps.list_apps([self.user, self.system])], ["Personal"])

    def test_wrapper_uses_xdg_paths_and_nested_desktop_ids(self) -> None:
        self.entry(self.user, "tools/editor.desktop", "Name=Editor\nExec=/usr/bin/true --new\n")
        self.entry(self.system, "browser.desktop", "Name=Browser\nExec=/usr/bin/true %U\nCategories=Network;\n")
        env = {**os.environ, "XDG_DATA_HOME": str(self.user.parent),
               "XDG_DATA_DIRS": str(self.system.parent)}
        result = subprocess.run(["bash", str(SHELL / "list-apps.sh")], env=env,
                                capture_output=True, text=True, check=True)
        rows = json.loads(result.stdout)
        self.assertEqual([(row["name"], row["desktopId"]) for row in rows],
                         [("Browser", "browser"), ("Editor", "tools-editor")])

    def test_missing_roots_and_default_xdg_paths(self) -> None:
        self.assertEqual(apps.list_apps([self.root / "missing"]), [])
        with patch.dict(os.environ, {"HOME": str(self.root), "XDG_DATA_HOME": "", "XDG_DATA_DIRS": ""}):
            self.assertEqual(apps.application_dirs(), [self.root / ".local/share/applications",
                                                      Path("/usr/local/share/applications"),
                                                      Path("/usr/share/applications")])

    def test_transports_desktop_path_without_rewriting_command(self) -> None:
        command = 'sh -c "printf hello | cat"'
        self.entry(self.system, "pipeline.desktop", f"Name=Pipeline\nExec={command}\n")
        self.assertEqual(apps.list_apps([self.system])[0]["desktopFile"], str(self.system / "pipeline.desktop"))

    def test_show_in_and_try_exec_filters(self) -> None:
        for name, settings in {
            "visible": "OnlyShowIn=Hyprland;\n",
            "other": "OnlyShowIn=GNOME;\n",
            "excluded": "NotShowIn=Hyprland;\n",
            "missing": "TryExec=/nonexistent/tsugumori-test-app\n",
        }.items():
            self.entry(self.system, name + ".desktop", f"Name={name}\nExec=/usr/bin/true\n{settings}")
        result = subprocess.run([sys.executable, str(SHELL / "scripts/list_apps.py")],
            env={**os.environ, "XDG_DATA_HOME": str(self.user.parent),
                 "XDG_DATA_DIRS": str(self.system.parent), "XDG_CURRENT_DESKTOP": "Hyprland"},
            capture_output=True, text=True, check=True)
        self.assertEqual([row["name"] for row in json.loads(result.stdout)], ["visible"])

    def test_catalog_observes_install_remove_and_hidden_override(self) -> None:
        self.entry(self.system, "first.desktop", "Name=First\nExec=/usr/bin/true\n")
        self.assertEqual(len(apps.list_apps([self.user, self.system])), 1)
        self.entry(self.system, "second.desktop", "Name=Second\nExec=/usr/bin/true\n")
        self.assertEqual(len(apps.list_apps([self.user, self.system])), 2)
        (self.system / "first.desktop").unlink()
        self.entry(self.user, "second.desktop", "Hidden=true\n")
        self.assertEqual(apps.list_apps([self.user, self.system]), [])

    @unittest.skipUnless(Path("/usr/lib/qt6/bin/qmltestrunner").exists(), "qmltestrunner is unavailable")
    def test_menu_requests_catalog_again_on_reopen(self) -> None:
        source = (SHELL / "widgets/Menu.qml").read_text()
        method = source.split("    function openMenu() {", 1)[1].split("\n    function closeMenu", 1)[0]
        qml = '''import QtQuick
import QtTest
TestCase {
    id: root
    name: "MenuCatalogRefresh"
    property bool menuOpen: false
    property bool appsLoaded: false
    property string searchQuery: ""
    property int focusIdx: -1
    property string currentCat: "all"
    QtObject { id: desktopReader; property bool running: false }
    QtObject { id: searchInput; property string text: "" }
    QtObject { id: wipeHide; function stop() {} }
    QtObject { id: wipeReveal; function start() {} }
    function openMenu() {__METHOD__
    function test_reopen_refreshes_loaded_catalog() {
        openMenu()
        compare(desktopReader.running, true)
        desktopReader.running = false
        appsLoaded = true
        menuOpen = false
        openMenu()
        compare(desktopReader.running, true)
    }
}
'''.replace("__METHOD__", method)
        path = self.root / "tst_MenuCatalog.qml"
        path.write_text(qml)
        result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(path)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
            capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class DesktopLaunchTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="tsugumori-launch-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.record = self.root / "record.json"
        self.app = self.root / "record-app"
        self.app.write_text(f'''#!{sys.executable}
import json, os, pathlib, sys, time
time.sleep(0.1)
os.write(1, b"application output\\n")
os.write(2, b"application error output\\n")
pathlib.Path(os.environ["TSUGUMORI_TEST_RECORD"]).write_text(json.dumps({{"argv": sys.argv[1:], "cwd": os.getcwd()}}))
''')
        self.app.chmod(0o755)
        self.desktop = self.root / "sample.desktop"
        self.environment = {**os.environ, "TSUGUMORI_TEST_RECORD": str(self.record),
                            "PATH": str(self.root) + os.pathsep + os.environ["PATH"]}

    def launch(self, settings: str) -> dict:
        self.desktop.write_text("[Desktop Entry]\nType=Application\nName=Test | App\n" + settings)
        result = subprocess.run([sys.executable, str(SHELL / "scripts/launch_desktop.py"), str(self.desktop)],
            env=self.environment, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")
        deadline = time.monotonic() + 3
        while not self.record.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(self.record.exists(), "Launched application did not finish after helper exit")
        return json.loads(self.record.read_text())

    def test_field_codes_path_and_literal_arguments(self) -> None:
        result = self.launch(f'Exec={self.app} %c %k %i %f %F %u %U %% "literal;$(printf unwanted)"\n'
                             f'Icon=test-icon\nPath={self.root}\n')
        self.assertEqual(result, {"argv": ["Test | App", str(self.desktop), "--icon", "test-icon", "%",
                                           "literal;$(printf unwanted)"], "cwd": str(self.root)})

    def test_terminal_launch_uses_kitty_and_executes_expanded_command(self) -> None:
        terminal_record = self.root / "terminal.json"
        kitty = self.root / "kitty"
        kitty.write_text(f'''#!{sys.executable}
import json, os, pathlib, sys
pathlib.Path({str(terminal_record)!r}).write_text(json.dumps(sys.argv[1:]))
os.execv(sys.argv[3], sys.argv[3:])
''')
        kitty.chmod(0o755)
        result = self.launch(f'Exec={self.app} "two words" %k\nTerminal=true\nPath={self.root}\n')
        self.assertEqual(json.loads(terminal_record.read_text()),
            ["--single-instance", "--", str(self.app), "two words", str(self.desktop)])
        self.assertEqual(result, {"argv": ["two words", str(self.desktop)], "cwd": str(self.root)})
