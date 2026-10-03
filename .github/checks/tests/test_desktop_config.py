"""Parse desktop configuration without starting a desktop session."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).parents[3]


class DesktopConfigTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("lua"), "Lua is not installed")
    def test_hyprland_preserves_inherited_path_and_adds_local_bin_once(self) -> None:
        source = (REPO / "config/hypr/hyprland.lua").read_text()
        # Evaluate the real environment setup, stopping before compositor settings.
        setup = source.split('hl.env("XCURSOR_SIZE"', 1)[0]
        lua = '''
package.preload.tsugumori_options = function() return {} end
hl = {
    monitor = function() end,
    env = function(name, value)
        if name == "PATH" then io.write(value) end
    end,
}
''' + setup
        local_bin = "/tmp/tsugumori-test-home/.local/bin"
        for original in (
            "/opt/custom/bin:/usr/bin",
            local_bin + ":/opt/custom/bin:/usr/bin",
            "/opt/custom/bin:" + local_bin + ":/usr/bin",
            "/tmp/tsugumori-test-home/.local/bin-extra:/usr/bin",
            "",
        ):
            with self.subTest(path=original):
                result = subprocess.run([shutil.which("lua"), "-"], input=lua,
                                        env={**os.environ, "HOME": "/tmp/tsugumori-test-home",
                                             "PATH": original},
                                        text=True, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                entries = result.stdout.split(":")
                self.assertEqual(entries.count(local_bin), 1)
                inherited = original.split(":") if original else [
                    "/usr/local/sbin", "/usr/local/bin", "/usr/bin", "/usr/sbin", "/bin", "/sbin",
                ]
                expected = inherited if local_bin in inherited else [local_bin, *inherited]
                self.assertEqual(entries, expected)

    @unittest.skipUnless(shutil.which("kitty"), "Kitty is not installed")
    def test_kitty_configuration_has_no_ignored_options(self) -> None:
        config = REPO / "config/kitty/kitty.conf"
        result = subprocess.run([
            "kitty", "+runpy",
            f"from kitty.config import load_config; load_config({str(config)!r})",
        ], text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Ignoring unknown config key", result.stderr)
        self.assertNotIn("Ignoring invalid config", result.stderr)


if __name__ == "__main__":
    unittest.main()
