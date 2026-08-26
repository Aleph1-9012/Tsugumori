from __future__ import annotations

import json
from pathlib import Path
import queue
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest


HELPER = Path(__file__).parents[2] / "config/quickshell/scripts/mpv_ctl.py"
OBSERVE_COMMAND = "observe_property"


class FakeMpvServer:
    """Small mpv JSON-IPC stand-in backed by a real Unix socket."""

    def __init__(self, socket_path: Path):
        self.socket_path = socket_path
        self.connection: socket.socket | None = None
        self.buffer = b""
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(str(socket_path))
        self.listener.listen(1)

    def accept(self, timeout: float = 2.0) -> None:
        self.listener.settimeout(timeout)
        self.connection, _ = self.listener.accept()

    def receive_forwarded_commands(
        self, count: int, timeout: float = 2.0
    ) -> list[list[object]]:
        if self.connection is None:
            self.accept(timeout)
        assert self.connection is not None

        commands: list[list[object]] = []
        deadline = time.monotonic() + timeout
        while len(commands) < count:
            while b"\n" in self.buffer:
                raw, self.buffer = self.buffer.split(b"\n", 1)
                if not raw:
                    continue
                message = json.loads(raw)
                command = message.get("command")
                if (
                    isinstance(command, list)
                    and command
                    and command[0] != OBSERVE_COMMAND
                ):
                    commands.append(command)
                    if len(commands) == count:
                        return commands

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self.fail_timeout(count, commands)
            self.connection.settimeout(remaining)
            try:
                chunk = self.connection.recv(65536)
            except TimeoutError:
                self.fail_timeout(count, commands)
            if not chunk:
                raise AssertionError(
                    f"bridge disconnected after forwarding {commands!r}"
                )
            self.buffer += chunk

        return commands

    @staticmethod
    def fail_timeout(count: int, commands: list[list[object]]) -> None:
        raise AssertionError(
            f"timed out waiting for {count} forwarded commands; got {commands!r}"
        )

    def close(self) -> None:
        if self.connection is not None:
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.connection.close()
            self.connection = None
        self.listener.close()
        self.socket_path.unlink(missing_ok=True)


class BridgeProcess:
    def __init__(self, socket_path: Path):
        self.process = subprocess.Popen(
            [sys.executable, str(HELPER), str(socket_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        self.messages: queue.Queue[dict[str, object]] = queue.Queue()
        self.output_thread = threading.Thread(target=self._read_output, daemon=True)
        self.output_thread.start()

    def _read_output(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            try:
                self.messages.put(json.loads(line))
            except json.JSONDecodeError:
                self.messages.put({"type": "invalid-output", "line": line})

    def send_batch(self, commands: list[list[object]]) -> None:
        """Write every command in one flush, matching QML's NDJSON protocol."""
        assert self.process.stdin is not None
        frames = "".join(
            json.dumps({"type": "command", "command": command}) + "\n"
            for command in commands
        )
        self.process.stdin.write(frames)
        self.process.stdin.flush()

    def wait_for(self, message_type: str, timeout: float = 2.0) -> dict[str, object]:
        deadline = time.monotonic() + timeout
        seen: list[dict[str, object]] = []
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(
                    f"timed out waiting for bridge message {message_type!r}; "
                    f"saw {seen!r}, returncode={self.process.poll()!r}"
                )
            try:
                message = self.messages.get(timeout=remaining)
            except queue.Empty:
                continue
            seen.append(message)
            if message.get("type") == message_type:
                return message

    def close(self) -> None:
        if self.process.poll() is None:
            assert self.process.stdin is not None
            try:
                self.process.stdin.close()
            except BrokenPipeError:
                pass
            try:
                self.process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=2.0)
        self.output_thread.join(timeout=1.0)
        if self.process.stdout is not None:
            self.process.stdout.close()
        if self.process.stderr is not None:
            self.process.stderr.close()


class MpvCtlBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-mpv-test-")
        self.socket_path = Path(self.tempdir.name) / "mpv.sock"
        self.resources: list[FakeMpvServer | BridgeProcess] = []

    def tearDown(self) -> None:
        for resource in reversed(self.resources):
            resource.close()
        self.tempdir.cleanup()

    def server(self) -> FakeMpvServer:
        server = FakeMpvServer(self.socket_path)
        self.resources.append(server)
        return server

    def bridge(self) -> BridgeProcess:
        bridge = BridgeProcess(self.socket_path)
        self.resources.append(bridge)
        return bridge

    def test_batched_commands_are_all_forwarded_in_order(self) -> None:
        server = self.server()
        bridge = self.bridge()
        server.accept()
        bridge.wait_for("ready")
        commands: list[list[object]] = [
            ["cycle", "pause"],
            ["set_property", "time-pos", 17.25],
            ["loadfile", "/music/three.flac", "replace"],
        ]

        bridge.send_batch(commands)

        self.assertEqual(server.receive_forwarded_commands(len(commands)), commands)

    def test_commands_queued_before_socket_exists_forward_after_connect(self) -> None:
        self.assertFalse(self.socket_path.exists())
        bridge = self.bridge()
        commands: list[list[object]] = [
            ["set_property", "pause", False],
            ["set_property", "time-pos", 42],
        ]

        bridge.send_batch(commands)
        # The bridge retries every 100 ms. Keeping the path absent for two retry
        # periods proves these frames entered its disconnected queue first.
        time.sleep(0.25)
        self.assertFalse(self.socket_path.exists())
        server = self.server()
        server.accept()
        bridge.wait_for("ready")

        self.assertEqual(server.receive_forwarded_commands(len(commands)), commands)

    def test_reconnect_retains_commands_queued_while_disconnected(self) -> None:
        first_server = self.server()
        bridge = self.bridge()
        first_server.accept()
        bridge.wait_for("ready")

        first_server.close()
        self.resources.remove(first_server)
        bridge.wait_for("disconnected")
        self.assertFalse(self.socket_path.exists())
        commands: list[list[object]] = [
            ["set_property", "time-pos", 73],
            ["cycle", "pause"],
            ["set_property", "pause", True],
        ]
        bridge.send_batch(commands)
        time.sleep(0.15)

        second_server = self.server()
        second_server.accept()
        bridge.wait_for("ready")

        self.assertEqual(
            second_server.receive_forwarded_commands(len(commands)), commands
        )


if __name__ == "__main__":
    unittest.main()
