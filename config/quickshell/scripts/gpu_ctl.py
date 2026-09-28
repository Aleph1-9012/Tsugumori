#!/usr/bin/env python3
"""Choose Hyprland's next-login renderer, without touching the running session.

Only `save` writes anything, and only an owned block in uwsm/env-hyprland.
`devices` resolves the saved PCI address at login so card numbers may change.
No driver, MUX, power-management, logout, or privileged operations are used.
"""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tempfile


DRM = Path("/sys/class/drm")
DEVICES = Path("/dev/dri")
PCI = re.compile(r"[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]\Z")
BEGIN = "# BEGIN TSUGUMORI GPU PREFERENCE\n"
END = "# END TSUGUMORI GPU PREFERENCE\n"
SESSION_KEY = "TSUGUMORI_GPU_PREFERENCE"
VENDORS = {"0x8086": "Intel", "0x1002": "AMD", "0x10de": "NVIDIA"}
MAX_SESSION_LOG = 8 * 1024 * 1024


def text(path):
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def command(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=3,
                                check=False, env={**os.environ, "LC_ALL": "C"})
        return result.stdout if result.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def discover(with_names=True):
    names = {}
    if with_names:
        for line in command(["lspci", "-Dmm"]).splitlines():
            try:
                fields = shlex.split(line)
                if len(fields) >= 4 and PCI.fullmatch(fields[0]):
                    names[fields[0]] = fields[3]
            except ValueError:
                continue
    cards = []
    for card in sorted(DRM.glob("card[0-9]*")):
        if not re.fullmatch(r"card[0-9]+", card.name):
            continue
        device = (card / "device").resolve()
        if not PCI.fullmatch(device.name) or not text(device / "class").startswith("0x03"):
            continue
        node = DEVICES / card.name
        if not node.exists():
            continue
        vendor = VENDORS.get(text(device / "vendor"), "GPU")
        outputs = [output.name[len(card.name) + 1:]
                   for output in sorted(DRM.glob(card.name + "-*"))
                   if text(output / "status") == "connected"]
        cards.append({"id": device.name, "name": names.get(device.name, vendor + " " + text(device / "device")),
                      "vendor": vendor, "node": str(node),
                      "driver": (device / "driver").resolve().name if (device / "driver").exists() else "unknown",
                      "outputs": outputs})
    return sorted(cards, key=lambda card: card["id"])


def active_renderer(cards):
    """Read only this session's primary DRM device; never infer it from a preference."""
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", signature) or not runtime.is_absolute():
        return None, "The current Hyprland session could not be identified."
    directory = runtime / "hypr" / signature
    try:
        if not (directory / ".socket.sock").is_socket():
            return None, "The current Hyprland session socket is unavailable."
        # Nonblocking and bounded: missing, rotated, or unsuitable logs mean UNKNOWN.
        flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW
        with os.fdopen(os.open(directory / "hyprland.log", flags), "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                return None, "The session log is not a regular, user-owned file."
            if info.st_size > MAX_SESSION_LOG:
                return None, "The session log is too large to verify the active GPU."
            content = stream.read(MAX_SESSION_LOG + 1)
        if len(content) > MAX_SESSION_LOG:
            return None, "The session log is too large to verify the active GPU."
    except OSError:
        return None, "The current session log is unavailable; the active GPU cannot be verified."
    # Renderer names also appear for secondary GPUs. Only the primary marker counts.
    primary = re.findall(rb"drm: gpu (/dev/dri/card[0-9]+) becomes primary drm\b", content)
    if not primary:
        return None, "The current session log does not identify a primary GPU."
    node = primary[-1].decode("ascii")
    matches = [card for card in cards if card["node"] == node]
    if len(matches) != 1:
        return None, "The logged primary GPU is no longer available or cannot be identified."
    return matches[0]["id"], ""


def config_path():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    if not config.is_absolute():
        raise ValueError("XDG_CONFIG_HOME must be an absolute path.")
    return config / "uwsm" / "env-hyprland"


def read_config(path):
    if path.is_symlink():
        raise ValueError("env-hyprland is a symlink. Manage its GPU setting in your dotfiles instead.")
    try:
        info = path.stat()
    except FileNotFoundError:
        return "", 0o600
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 1024 * 1024:
        raise ValueError("env-hyprland is not a regular, user-owned configuration file.")
    return path.read_text(encoding="utf-8"), stat.S_IMODE(info.st_mode)


def split_config(content):
    if BEGIN not in content and END not in content:
        return content, "auto"
    if content.count(BEGIN) != 1 or content.count(END) != 1:
        raise ValueError("The saved GPU block is malformed. No configuration was changed.")
    start = content.index(BEGIN)
    finish = content.index(END) + len(END)
    if finish <= start:
        raise ValueError("The saved GPU block is malformed. No configuration was changed.")
    block = content[start:finish]
    match = re.search(r"^# preferred=([0-9a-f:.]+)$", block, re.MULTILINE)
    if not match or not PCI.fullmatch(match[1]):
        raise ValueError("The saved GPU selection is invalid. No configuration was changed.")
    return content[:start] + content[finish:], match[1]


def uwsm_active():
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return False
    units = command(["systemctl", "--user", "list-units", "--type=service", "--state=active",
                     "--plain", "--no-legend", "--no-pager", "wayland-wm@*.service"])
    return any(line.split()[0].startswith("wayland-wm@") and "hyprland" in line.split()[0].lower()
               for line in units.splitlines() if line.split())


def block_reason(remainder, saved):
    # Do not replace hand-written GPU priorities or inherit an unknown override.
    uncommented = "\n".join(line for line in remainder.splitlines() if not line.lstrip().startswith("#"))
    if re.search(r"\bAQ_DRM_DEVICES\b", uncommented):
        return "A custom AQ_DRM_DEVICES setting exists in env-hyprland. Manage it there first."
    if os.environ.get("AQ_DRM_DEVICES") and not os.environ.get(SESSION_KEY) and saved == "auto":
        return "This session has a custom GPU override. Remove it from your startup configuration first."
    if not uwsm_active():
        return "GPU selection requires a Hyprland session started with UWSM. Nothing will be changed."
    return ""


def status():
    cards = discover()
    saved = "auto"
    reason = ""
    try:
        remainder, saved = split_config(read_config(config_path())[0])
        reason = block_reason(remainder, saved)
    except (OSError, ValueError) as error:
        reason = str(error)
    session = os.environ.get(SESSION_KEY, "auto")
    if session != "auto" and not PCI.fullmatch(session):
        session = "auto"
    active, active_reason = active_renderer(cards)
    pending = saved != session or (saved != "auto" and active is not None and saved != active)
    return {"ok": True, "gpus": cards, "saved": saved, "session": session,
            "active": active, "active_reason": active_reason,
            "supported": not reason, "reason": reason,
            "pending": pending,
            "missing": saved != "auto" and not any(card["id"] == saved for card in cards)}


def make_block(preferred):
    helper = shlex.quote(str(Path(__file__).resolve()))
    python = shlex.quote(sys.executable)
    return (BEGIN + f"# preferred={preferred}\n"
            "# Resolve PCI identity on every login; retain other GPUs for their displays.\n"
            f"if _tsugumori_gpu_devices=$({python} {helper} devices {shlex.quote(preferred)}); then\n"
            '    if [ -n "$_tsugumori_gpu_devices" ]; then\n'
            '        export AQ_DRM_DEVICES="$_tsugumori_gpu_devices"\n'
            f"        export {SESSION_KEY}={shlex.quote(preferred)}\n"
            "    fi\n"
            "fi\n"
            "unset _tsugumori_gpu_devices\n" + END)


def save(preferred):
    if preferred != "auto" and not PCI.fullmatch(preferred):
        raise ValueError("Invalid GPU selection.")
    cards = discover(with_names=False)
    if preferred != "auto" and (len(cards) < 2 or not any(card["id"] == preferred for card in cards)):
        raise ValueError("The selected GPU is no longer available. Refresh and try again.")
    path = config_path()
    initial, _ = read_config(path)
    remainder, saved = split_config(initial)
    if preferred == "auto" and saved == "auto":
        return
    # Restoring Automatic only removes our block, even if UWSM is no longer active.
    if preferred != "auto":
        reason = block_reason(remainder, saved)
        if reason:
            raise ValueError(reason)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Lock the directory so simultaneous menu instances cannot race each other.
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    temporary = None
    try:
        fcntl.flock(directory_fd, fcntl.LOCK_EX)
        current, mode = read_config(path)
        if current != initial:
            raise ValueError("The startup file changed while saving. Refresh and try again.")
        updated = remainder if preferred == "auto" else make_block(preferred) + remainder
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".tsugumori-gpu-", delete=False) as stream:
            temporary = Path(stream.name)
            os.fchmod(stream.fileno(), mode)
            stream.write(updated)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        temporary = None
        os.fsync(directory_fd)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        os.close(directory_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "save", "devices"))
    parser.add_argument("preferred", nargs="?")
    args = parser.parse_args()
    if args.action in ("save", "devices") and not args.preferred:
        parser.error("this action requires a GPU PCI address or auto")
    try:
        if args.action == "devices":
            # Called before Hyprland starts. Missing/unplugged hardware falls back
            # to the normal renderer selection without breaking login.
            cards = discover(with_names=False)
            chosen = next((card for card in cards if card["id"] == args.preferred), None)
            if chosen:
                print(":".join([chosen["node"]] + [card["node"] for card in cards if card != chosen]))
            return 0
        if args.action == "save":
            save(args.preferred)
        result = status()
        if args.action == "save":
            result["message"] = "Saved for next login. Log out and back in when ready; no restart was triggered."
        print(json.dumps(result))
        return 0
    except (OSError, ValueError) as error:
        if args.action != "devices":
            print(json.dumps({"ok": False, "error": str(error)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
