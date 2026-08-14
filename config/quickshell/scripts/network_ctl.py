#!/usr/bin/env python3
"""Run NetworkManager actions without passing network data through a shell."""

from __future__ import annotations

import argparse
import subprocess
import sys


def run(
    *args: str,
    check: bool = True,
    input_text: str | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["nmcli", *args],
        check=check,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def disconnect(ssid: str) -> int:
    result = run("connection", "down", "id", ssid, check=False)
    if result.returncode == 0:
        sys.stdout.write(result.stdout)
        return 0

    devices = run("-t", "-f", "DEVICE,TYPE", "device", "status", check=False)
    for line in devices.stdout.splitlines():
        device, separator, device_type = line.partition(":")
        if separator and device_type == "wifi" and device:
            fallback = run("device", "disconnect", device, check=False)
            sys.stdout.write(fallback.stdout)
            return fallback.returncode

    sys.stdout.write(result.stdout)
    return result.returncode


def connect(ssid: str, password: str | None) -> int:
    args = ["device", "wifi", "connect", ssid]
    input_text = None
    if password is not None:
        # --ask accepts the secret on stdin, keeping it out of both the helper's
        # and nmcli's argv (and therefore out of process listings).
        args.insert(0, "--ask")
        input_text = password + "\n"
    result = run(*args, check=False, input_text=input_text)
    sys.stdout.write(result.stdout)
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="action", required=True)

    disconnect_parser = subparsers.add_parser("disconnect")
    disconnect_parser.add_argument("--ssid", required=True)

    connect_parser = subparsers.add_parser("connect")
    connect_parser.add_argument("--ssid", required=True)
    connect_parser.add_argument("--password-stdin", action="store_true")

    args = parser.parse_args()
    if args.action == "disconnect":
        return disconnect(args.ssid)
    password = sys.stdin.readline().rstrip("\r\n") if args.password_stdin else None
    return connect(args.ssid, password)


if __name__ == "__main__":
    raise SystemExit(main())
