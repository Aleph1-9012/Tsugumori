from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest


REPO_ROOT = Path(__file__).parents[1]
STATUS_SCRIPT = REPO_ROOT / "config/waybar/scripts/pomodoro.sh"
TOGGLE_SCRIPT = REPO_ROOT / "config/waybar/scripts/pomodoro_toggle.sh"


class PomodoroStateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-pomodoro-test-")
        self.root = Path(self.tempdir.name)
        self.runtime_dir = self.root / "runtime"
        self.runtime_dir.mkdir(mode=0o700)
        self.state_dir = self.runtime_dir / "tsugumori"
        self.state_file = self.state_dir / "pomodoro_state"
        self.env = os.environ.copy()
        self.env["XDG_RUNTIME_DIR"] = str(self.runtime_dir)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_script(self, script: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(script)],
            env=self.env,
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_toggle_uses_private_runtime_state_and_stops_cleanly(self) -> None:
        self.assertEqual(self.run_script(STATUS_SCRIPT).stdout, "POMO --:--\n")

        started = self.run_script(TOGGLE_SCRIPT)
        self.assertEqual(started.returncode, 0, started.stderr)
        self.assertEqual(stat.S_IMODE(self.state_dir.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.state_file.stat().st_mode), 0o600)
        state = self.state_file.read_text(encoding="utf-8")
        self.assertIn("RUNNING=true\n", state)
        self.assertIn("DURATION=1500\n", state)
        self.assertRegex(self.run_script(STATUS_SCRIPT).stdout, r"^POMO (25:00|24:59)\n$")

        stopped = self.run_script(TOGGLE_SCRIPT)
        self.assertEqual(stopped.returncode, 0, stopped.stderr)
        self.assertEqual(self.state_file.read_text(encoding="utf-8"), "RUNNING=false\n")
        self.assertEqual(stat.S_IMODE(self.state_file.stat().st_mode), 0o600)
        self.assertEqual(self.run_script(STATUS_SCRIPT).stdout, "POMO --:--\n")

    def test_state_values_are_parsed_as_data_and_never_executed(self) -> None:
        self.state_dir.mkdir(mode=0o700)
        marker = self.root / "state-was-executed"
        self.state_file.write_text(
            "RUNNING=true\n"
            f"START_TIME=$(touch {marker})\n"
            "DURATION=1500\n",
            encoding="utf-8",
        )
        self.state_file.chmod(0o600)

        status = self.run_script(STATUS_SCRIPT)

        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertEqual(status.stdout, "POMO --:--\n")
        self.assertFalse(marker.exists())

    def test_reader_rejects_state_without_private_mode(self) -> None:
        self.state_dir.mkdir(mode=0o700)
        self.state_file.write_text(
            f"RUNNING=true\nSTART_TIME={int(time.time())}\nDURATION=1500\n",
            encoding="utf-8",
        )
        self.state_file.chmod(0o644)

        status = self.run_script(STATUS_SCRIPT)

        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertEqual(status.stdout, "POMO --:--\n")


if __name__ == "__main__":
    unittest.main()
