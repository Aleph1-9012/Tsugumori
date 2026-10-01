from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


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
        self.entry(self.system, "editor.desktop", "Name=Editor\nExec=editor %F\nCategories=Development;\n"
                   "[Desktop Action Private]\nName=Private\nExec=editor --private\nHidden=true\n")
        self.assertEqual(apps.list_apps([self.system]), ["Editor|editor|Development;|editor"])

    def test_user_overrides_and_hidden_entries(self) -> None:
        for directory, name in ((self.system, "System"), (self.user, "Personal")):
            self.entry(directory, "editor.desktop", f"Name={name}\nExec=editor\n")
        self.entry(self.system, "hidden.desktop", "Name=Hidden\nExec=hidden\n")
        self.entry(self.user, "hidden.desktop", "Hidden=true\n")
        self.entry(self.system, "nodisplay.desktop", "Name=Helper\nExec=helper\nNoDisplay=true\n")
        self.entry(self.system, "empty.desktop", "Name=Missing command\n")
        self.assertEqual(apps.list_apps([self.user, self.system]), ["Personal|editor||editor"])

    def test_wrapper_uses_xdg_paths_and_nested_desktop_ids(self) -> None:
        self.entry(self.user, "tools/editor.desktop", "Name=Editor\nExec=editor --new\n")
        self.entry(self.system, "browser.desktop", "Name=Browser\nExec=browser %U\nCategories=Network;\n")
        env = {**os.environ, "XDG_DATA_HOME": str(self.user.parent),
               "XDG_DATA_DIRS": str(self.system.parent)}
        result = subprocess.run(["bash", str(SHELL / "list-apps.sh")], env=env,
                                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.splitlines(), ["Browser|browser|Network;|browser",
                                                     "Editor|tools-editor||editor --new"])

    def test_missing_roots_and_default_xdg_paths(self) -> None:
        self.assertEqual(apps.list_apps([self.root / "missing"]), [])
        with patch.dict(os.environ, {"HOME": str(self.root), "XDG_DATA_HOME": "", "XDG_DATA_DIRS": ""}):
            self.assertEqual(apps.application_dirs(), [self.root / ".local/share/applications",
                                                      Path("/usr/local/share/applications"),
                                                      Path("/usr/share/applications")])

    def test_preserves_pipelines_in_command(self) -> None:
        command = 'sh -c "printf hello | cat"'
        self.entry(self.system, "pipeline.desktop", f"Name=Pipeline\nExec={command}\n")
        self.assertEqual(apps.list_apps([self.system]), ["Pipeline|pipeline||" + command])
