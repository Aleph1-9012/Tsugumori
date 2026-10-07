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

    def run_hyprland(self, user_chunk: str) -> dict:
        source = (REPO / "config/hypr/hyprland.lua").read_text()
        lua = '''
local envs, binds, execs, ons = {}, {}, {}, {}
local function any()
    return setmetatable({}, {
        __call = function(_, ...) return any() end,
        __index = function(_, _) return any() end,
    })
end
local dsp = setmetatable({}, {__index = function(_, key)
    if key == "exec_cmd" then
        return function(command) return {exec = command} end
    end
    return any()
end})
hl = setmetatable({}, {__index = function(_, key)
    if key == "env" then return function(name, value) envs[name] = value end
    elseif key == "bind" then
        return function(shortcut, target) binds[shortcut] = target end
    elseif key == "on" then
        return function(event, handler) ons[event] = handler end
    elseif key == "exec_cmd" then
        return function(command) table.insert(execs, command) end
    elseif key == "dsp" then return dsp
    end
    return function(...) return any() end
end})
package.preload.tsugumori_options = function() return {} end
package.preload.user = function()
__USER__
end
''' + source + '''
if ons["hyprland.start"] then ons["hyprland.start"]() end
'''
        lua += '''
local function emit()
    io.write("ENVS\\n")
    for k, v in pairs(envs) do io.write(k .. "=" .. tostring(v) .. "\\n") end
    io.write("BINDS\\n")
    for k, v in pairs(binds) do
        io.write(k .. "=" .. (type(v) == "table" and type(v.exec) == "string"
            and v.exec or tostring(v)) .. "\\n")
    end
    io.write("EXECS\\n")
    for _, c in ipairs(execs) do io.write(c .. "\\n") end
end
emit()
'''
        result = subprocess.run(
            [shutil.which("lua"), "-"],
            input=lua.replace("__USER__", user_chunk),
            env={**os.environ, "HOME": "/tmp/tsugumori-test-home",
                 "PATH": "/usr/bin"},
            text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        sections: dict[str, dict[str, str] | list[str]] = {}
        current = ""
        for line in result.stdout.splitlines():
            if line in ("ENVS", "BINDS"):
                sections[line.lower()] = {}
                current = line.lower()
            elif line == "EXECS":
                sections["execs"] = []
                current = "execs"
            elif "=" in line and current in ("envs", "binds"):
                key, value = line.split("=", 1)
                sections[current][key] = value
            elif line:
                sections["execs"].append(line)
        return sections

    @unittest.skipUnless(shutil.which("lua"), "Lua is not installed")
    def test_startup_locks_by_default(self) -> None:
        sections = self.run_hyprland("")
        self.assertTrue(
            any("lock.sh" in command for command in sections["execs"]),
            sections["execs"])
        self.assertTrue(
            any("qs" in command for command in sections["execs"]),
            sections["execs"])

    @unittest.skipUnless(shutil.which("lua"), "Lua is not installed")
    def test_lock_at_login_opt_out_keeps_other_autostart(self) -> None:
        sections = self.run_hyprland(
            "tsugumori.lock_at_login = false")
        self.assertFalse(
            any("lock.sh" in command for command in sections["execs"]),
            sections["execs"])
        self.assertTrue(any("hypridle" in c for c in sections["execs"]))
        self.assertTrue(any("qs" in c for c in sections["execs"]))

    @unittest.skipUnless(shutil.which("lua"), "Lua is not installed")
    def test_super_tab_opens_control_center_and_qt_prefers_wayland(self) -> None:
        sections = self.run_hyprland("")
        self.assertEqual(sections["binds"].get("SUPER + Tab"),
                         "qs ipc call ctrl toggle")
        self.assertEqual(sections["envs"].get("QT_QPA_PLATFORM"), "wayland;xcb")

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
