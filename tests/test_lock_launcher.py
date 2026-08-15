from __future__ import annotations

import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import textwrap
import time
import unittest


REPO_ROOT = Path(__file__).parents[1]
LAUNCHER = REPO_ROOT / "config/quickshell/lock.sh"
HANDSHAKE_HELPER = REPO_ROOT / "config/quickshell/lock-handshake.sh"
LOCK_QML = REPO_ROOT / "config/quickshell/widgets/lockscreen.qml"
HYPRLAND_LUA = REPO_ROOT / "config/hypr/hyprland.lua"


class LockHandshakeHelperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-lock-handshake-")
        self.handshake_dir = Path(self.tempdir.name) / "private"
        self.handshake_dir.mkdir(mode=0o700)
        (self.handshake_dir / ".protocol.lock").touch(mode=0o600)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_helper(self, event: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(HANDSHAKE_HELPER), str(self.handshake_dir), event],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_writes_exact_private_marker(self) -> None:
        result = self.run_helper("secure")

        self.assertEqual(result.returncode, 0, result.stderr)
        marker = self.handshake_dir / "secure"
        self.assertEqual(marker.read_text(encoding="utf-8"), "secure\n")
        self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)

    def test_writes_release_authorization_marker(self) -> None:
        result = self.run_helper("release-authorized")

        self.assertEqual(result.returncode, 0, result.stderr)
        marker = self.handshake_dir / "release-authorized"
        self.assertEqual(marker.read_text(encoding="utf-8"), "release-authorized\n")
        self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)

    def test_rejects_unknown_event(self) -> None:
        result = self.run_helper("anything-else")

        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.handshake_dir / "anything-else").exists())

    def test_rejects_non_private_directory(self) -> None:
        self.handshake_dir.chmod(0o755)

        result = self.run_helper("secure")

        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.handshake_dir / "secure").exists())


class SupervisedLockLauncherTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-lock-launcher-")
        self.root = Path(self.tempdir.name)
        self.config_home = self.root / "config"
        self.runtime_dir = self.root / "runtime"
        self.fake_bin = self.root / "bin"
        self.hyprlock_log = self.root / "hyprlock.log"
        self.qs_log = self.root / "qs.log"
        self.pam_service = self.root / "pam-hyprlock"
        self.release_trigger = self.root / "release.trigger"
        self.state_dir = self.runtime_dir / "tsugumori/lock-handshake-wayland-test"
        self.processes: list[subprocess.Popen[str]] = []

        quickshell = self.config_home / "quickshell"
        (quickshell / "widgets").mkdir(parents=True)
        (quickshell / "videos").mkdir()
        (self.config_home / "hypr").mkdir()
        self.runtime_dir.mkdir()
        self.fake_bin.mkdir()

        shutil.copy2(LOCK_QML, quickshell / "widgets/lockscreen.qml")
        shutil.copy2(HANDSHAKE_HELPER, quickshell / "lock-handshake.sh")
        (quickshell / "lock-handshake.sh").chmod(0o755)
        (quickshell / "videos/wave_hide.mp4").write_bytes(b"hide")
        (quickshell / "videos/wave_reveal.mp4").write_bytes(b"reveal")
        (quickshell / "videos/wave_last_frame.png").write_bytes(b"frame")
        (self.config_home / "hypr/hyprlock.conf").write_text(
            "general { immediate_render = true }\n", encoding="utf-8"
        )
        self.pam_service.write_text("auth required pam_unix.so\n", encoding="utf-8")

        self.write_executable(
            "ffmpeg",
            """
            #!/bin/sh
            exit 0
            """,
        )
        self.write_executable(
            "hyprlock",
            """
            #!/bin/sh
            printf '%s\n' "$*" >"$FAKE_HYPRLOCK_LOG"
            exit 0
            """,
        )
        self.write_executable(
            "qs",
            """
            #!/usr/bin/env bash
            set -eu
            printf '%s\n' "$*" >>"$FAKE_QS_LOG"
            helper="$XDG_CONFIG_HOME/quickshell/lock-handshake.sh"
            case "$FAKE_QS_MODE" in
                early-exit)
                    exit 23
                    ;;
                secure-release)
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" secure
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" release-authorized
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" release-requested
                    exit 0
                    ;;
                secure-await-relock)
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" secure
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" release-authorized
                    for ((attempt = 0; attempt < 500; attempt++)); do
                        [[ -f "$TSUGUMORI_LOCK_HANDSHAKE_DIR/relock-requested" ]] && break
                        sleep 0.01
                    done
                    [[ -f "$TSUGUMORI_LOCK_HANDSHAKE_DIR/relock-requested" ]] || exit 65
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" release-requested
                    exit 0
                    ;;
                stable-secure)
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" secure
                    for ((attempt = 0; attempt < 500; attempt++)); do
                        [[ -f "$FAKE_RELEASE_TRIGGER" ]] && break
                        sleep 0.01
                    done
                    [[ -f "$FAKE_RELEASE_TRIGGER" ]] || exit 66
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" release-authorized
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" release-requested
                    exit 0
                    ;;
                secure-crash)
                    "$helper" "$TSUGUMORI_LOCK_HANDSHAKE_DIR" secure
                    exit 24
                    ;;
                hang)
                    exec sleep 30
                    ;;
                insecure-marker)
                    printf 'secure\n' >"$TSUGUMORI_LOCK_HANDSHAKE_DIR/secure"
                    chmod 644 "$TSUGUMORI_LOCK_HANDSHAKE_DIR/secure"
                    exit 0
                    ;;
                *)
                    exit 64
                    ;;
            esac
            """,
        )

    def tearDown(self) -> None:
        for process in self.processes:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=2)
        self.tempdir.cleanup()

    def write_executable(self, name: str, source: str) -> None:
        path = self.fake_bin / name
        path.write_text(textwrap.dedent(source).lstrip(), encoding="utf-8")
        path.chmod(0o755)

    def launcher_env(self, mode: str) -> dict[str, str]:
        env = os.environ.copy()
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        env.update(
            {
                "HOME": str(self.root / "home"),
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_RUNTIME_DIR": str(self.runtime_dir),
                "WAYLAND_DISPLAY": "wayland-test",
                "PATH": f"{self.fake_bin}{os.pathsep}{env.get('PATH', os.defpath)}",
                "FAKE_QS_MODE": mode,
                "FAKE_QS_LOG": str(self.qs_log),
                "FAKE_HYPRLOCK_LOG": str(self.hyprlock_log),
                "FAKE_RELEASE_TRIGGER": str(self.release_trigger),
                "TSUGUMORI_LOCK_TESTING": "1",
                "TSUGUMORI_LOCK_TEST_PAM_SERVICE": str(self.pam_service),
            }
        )
        return env

    def run_launcher(self, mode: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(LAUNCHER)],
            env=self.launcher_env(mode),
            text=True,
            capture_output=True,
            check=False,
            timeout=8,
        )

    def start_launcher(self, mode: str) -> subprocess.Popen[str]:
        process = subprocess.Popen(
            [str(LAUNCHER)],
            env=self.launcher_env(mode),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.processes.append(process)
        return process

    def wait_for_path(self, path: Path, timeout: float = 5.0) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if path.exists():
                return
            time.sleep(0.01)
        self.fail(f"timed out waiting for {path}")

    def assert_fallback_started(self) -> None:
        self.assertTrue(self.hyprlock_log.exists())
        self.assertEqual(
            self.hyprlock_log.read_text(encoding="utf-8").strip(),
            f"--config {self.config_home}/hypr/hyprlock.conf --grace 0 --immediate-render",
        )

    def assert_handshake_cleaned(self) -> None:
        self.assertTrue(self.state_dir.is_dir())
        leftovers = {path.name for path in self.state_dir.iterdir()}
        self.assertEqual(leftovers, {".protocol.lock"})
        self.assertEqual(stat.S_IMODE(self.state_dir.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.state_dir / ".protocol.lock").stat().st_mode), 0o600)

    def test_qml_or_import_exit_before_secure_falls_back(self) -> None:
        result = self.run_launcher("early-exit")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("exited before confirming a secure session lock", result.stderr)
        self.assert_fallback_started()
        self.assert_handshake_cleaned()

    def test_authenticated_release_request_does_not_fallback(self) -> None:
        result = self.run_launcher("secure-release")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.hyprlock_log.exists())
        self.assertIn("--no-duplicate --path", self.qs_log.read_text(encoding="utf-8"))
        self.assert_handshake_cleaned()

    def test_duplicate_during_authenticated_release_forces_relock_fallback(self) -> None:
        first = self.start_launcher("secure-await-relock")
        self.wait_for_path(self.state_dir / "release-authorized")

        duplicate = self.run_launcher("secure-await-relock")
        first_stdout, first_stderr = first.communicate(timeout=8)

        self.assertEqual(duplicate.returncode, 0, duplicate.stderr)
        self.assertEqual(first.returncode, 0, first_stdout + first_stderr)
        self.assertIn(
            "another lock request arrived during the authenticated release",
            first_stderr,
        )
        self.assert_fallback_started()
        self.assertEqual(len(self.qs_log.read_text(encoding="utf-8").splitlines()), 1)
        self.assert_handshake_cleaned()

    def test_duplicate_while_stably_secure_is_a_noop(self) -> None:
        first = self.start_launcher("stable-secure")
        self.wait_for_path(self.state_dir / "secure")

        duplicate = self.run_launcher("stable-secure")

        self.assertEqual(duplicate.returncode, 0, duplicate.stderr)
        self.assertFalse((self.state_dir / "relock-requested").exists())
        self.assertEqual(len(self.qs_log.read_text(encoding="utf-8").splitlines()), 1)
        self.release_trigger.touch()
        first_stdout, first_stderr = first.communicate(timeout=8)
        self.assertEqual(first.returncode, 0, first_stdout + first_stderr)
        self.assertFalse(self.hyprlock_log.exists())
        self.assert_handshake_cleaned()

    def test_qml_commits_release_authorization_before_hide_animation(self) -> None:
        source = LOCK_QML.read_text(encoding="utf-8")
        do_hide = source[source.index("function doHide()") : source.index("function beginHide()")]
        begin_hide = source[
            source.index("function beginHide()") : source.index("function requestSessionRelease()")
        ]

        self.assertIn(
            'command: [root.handshakeHelper, root.handshakeDir, "release-authorized"]',
            source,
        )
        self.assertIn("root.releaseAuthorized = true\n                root.beginHide()", source)
        self.assertIn("releaseAuthorizeProc.running = true", do_hide)
        self.assertNotIn("root.hiding = true", do_hide)
        self.assertIn("root.hiding = true", begin_hide)
        self.assertIn("unlockAnimationTimer.restart()", begin_hide)

    def test_exit_after_secure_without_release_falls_back(self) -> None:
        result = self.run_launcher("secure-crash")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("without an authenticated release request", result.stderr)
        self.assert_fallback_started()
        self.assert_handshake_cleaned()

    def test_live_client_without_secure_marker_times_out_and_falls_back(self) -> None:
        result = self.run_launcher("hang")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("did not confirm a secure session lock within 3 seconds", result.stderr)
        self.assert_fallback_started()
        self.assert_handshake_cleaned()

    def test_missing_pam_service_still_attempts_hyprlock_fallback(self) -> None:
        self.pam_service.unlink()

        result = self.run_launcher("early-exit")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("required PAM service is unavailable", result.stderr)
        self.assert_fallback_started()
        self.assertFalse(self.qs_log.exists())

    def test_hyprland_allows_fallback_to_restore_a_crashed_lock(self) -> None:
        source = HYPRLAND_LUA.read_text(encoding="utf-8")

        self.assertIn("allow_session_lock_restore = true", source)

    def test_marker_with_wrong_permissions_is_not_accepted(self) -> None:
        result = self.run_launcher("insecure-marker")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("exited before confirming a secure session lock", result.stderr)
        self.assert_fallback_started()


if __name__ == "__main__":
    unittest.main()
