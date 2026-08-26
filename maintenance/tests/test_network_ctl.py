from __future__ import annotations

import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock


HELPER = Path(__file__).parents[2] / "config/quickshell/scripts/network_ctl.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("network_ctl", HELPER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class NetworkCtlTests(unittest.TestCase):
    def test_password_is_forwarded_only_over_stdin(self):
        module = load_helper()
        secret = "never-put-this-in-argv"
        helper_argv = [
            str(HELPER),
            "connect",
            "--ssid=Test Network",
            "--password-stdin",
        ]
        completed = subprocess.CompletedProcess([], 0, stdout="successfully activated\n")

        with (
            mock.patch.object(sys, "argv", helper_argv),
            mock.patch.object(sys, "stdin", io.StringIO(secret + "\n")),
            mock.patch.object(sys, "stdout", io.StringIO()),
            mock.patch.object(module.subprocess, "run", return_value=completed) as run,
        ):
            self.assertEqual(module.main(), 0)

        self.assertFalse(any(secret in arg for arg in helper_argv))
        nmcli_argv = run.call_args.args[0]
        self.assertFalse(any(secret in arg for arg in nmcli_argv))
        self.assertEqual(
            nmcli_argv,
            ["nmcli", "--ask", "device", "wifi", "connect", "Test Network"],
        )
        self.assertEqual(run.call_args.kwargs["input"], secret + "\n")


if __name__ == "__main__":
    unittest.main()
