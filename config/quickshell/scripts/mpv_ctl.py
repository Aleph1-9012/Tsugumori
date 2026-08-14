#!/usr/bin/env python3
"""Persistent, line-oriented bridge between QML and mpv's JSON IPC socket."""

from __future__ import annotations

import json
import os
import selectors
import socket
import sys
import time
from typing import Any


OBSERVED_PROPERTIES = (
    "pause",
    "time-pos",
    "duration",
    "eof-reached",
    "idle-active",
)


def emit(message: dict[str, Any]) -> None:
    print(json.dumps(message, separators=(",", ":")), flush=True)


def connect(socket_path: str) -> socket.socket | None:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(0.25)
    try:
        sock.connect(socket_path)
    except OSError:
        sock.close()
        return None
    sock.setblocking(False)
    return sock


def encode_command(command: list[Any], request_id: int | None = None) -> bytes:
    payload: dict[str, Any] = {"command": command}
    if request_id is not None:
        payload["request_id"] = request_id
    return (json.dumps(payload, separators=(",", ":")) + "\n").encode()


def send(sock: socket.socket, command: list[Any], request_id: int | None = None) -> None:
    sock.sendall(encode_command(command, request_id))


def publish_state(state: dict[str, Any]) -> None:
    emit(
        {
            "type": "state",
            "pause": bool(state.get("pause", True)),
            "position": state.get("time-pos") or 0,
            "duration": state.get("duration") or 0,
            "eofReached": bool(state.get("eof-reached", False)),
            "idleActive": bool(state.get("idle-active", True)),
        }
    )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: mpv_ctl.py <socket_path>", file=sys.stderr)
        return 2

    socket_path = sys.argv[1]
    selector = selectors.DefaultSelector()
    stdin_fd = sys.stdin.fileno()
    os.set_blocking(stdin_fd, False)
    selector.register(stdin_fd, selectors.EVENT_READ, "stdin")
    stdin_buffer = b""
    sock: socket.socket | None = None
    socket_buffer = b""
    pending_commands: list[list[Any]] = []
    state: dict[str, Any] = {
        "pause": True,
        "time-pos": 0,
        "duration": 0,
        "eof-reached": False,
        "idle-active": True,
    }
    next_connect_at = 0.0

    def disconnect() -> None:
        nonlocal sock, socket_buffer, next_connect_at
        if sock is not None:
            try:
                selector.unregister(sock)
            except (KeyError, ValueError):
                pass
            sock.close()
        sock = None
        socket_buffer = b""
        state.update(
            {
                "pause": True,
                "time-pos": 0,
                "duration": 0,
                "eof-reached": False,
                "idle-active": True,
            }
        )
        emit({"type": "disconnected"})
        next_connect_at = time.monotonic() + 0.1

    while True:
        now = time.monotonic()
        if sock is None and now >= next_connect_at:
            sock = connect(socket_path)
            if sock is None:
                next_connect_at = now + 0.1
            else:
                selector.register(sock, selectors.EVENT_READ, "mpv")
                socket_buffer = b""
                sent = 0
                try:
                    for index, name in enumerate(OBSERVED_PROPERTIES, start=1):
                        send(sock, ["observe_property", index, name])
                    while sent < len(pending_commands):
                        send(sock, pending_commands[sent])
                        sent += 1
                    if sent:
                        del pending_commands[:sent]
                    emit({"type": "ready"})
                except OSError:
                    if sent:
                        del pending_commands[:sent]
                    disconnect()
        timeout = 0.1 if sock is None else 0.5
        for key, _ in selector.select(timeout):
            if key.data == "stdin":
                try:
                    chunk = os.read(stdin_fd, 65536)
                except BlockingIOError:
                    chunk = None
                if chunk is None:
                    continue
                if chunk == b"":
                    # A final unterminated frame is invalid by protocol; every valid
                    # newline-delimited frame has already been drained below.
                    return 0
                stdin_buffer += chunk
                while b"\n" in stdin_buffer:
                    raw, stdin_buffer = stdin_buffer.split(b"\n", 1)
                    if not raw:
                        continue
                    try:
                        message = json.loads(raw)
                        command = message.get("command")
                        if message.get("type") == "command" and isinstance(command, list):
                            if sock is None:
                                pending_commands.append(command)
                            else:
                                try:
                                    send(sock, command)
                                except OSError:
                                    pending_commands.append(command)
                                    disconnect()
                    except (json.JSONDecodeError, TypeError):
                        continue
            elif key.data == "mpv" and sock is not None:
                try:
                    chunk = sock.recv(65536)
                    if not chunk:
                        raise ConnectionError("mpv closed its IPC socket")
                    socket_buffer += chunk
                    while b"\n" in socket_buffer:
                        raw, socket_buffer = socket_buffer.split(b"\n", 1)
                        if not raw:
                            continue
                        message = json.loads(raw)
                        name = message.get("name")
                        if message.get("event") == "property-change" and name in state:
                            state[name] = message.get("data")
                            publish_state(state)
                except (ConnectionError, json.JSONDecodeError, OSError):
                    disconnect()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
