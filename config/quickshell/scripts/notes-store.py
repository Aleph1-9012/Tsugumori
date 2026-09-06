#!/usr/bin/env python3
"""Private, revision-checked notes storage. One JSON request on stdin."""

import fcntl
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import uuid


class StoreError(Exception):
    def __init__(self, code):
        self.code = code


def empty_store():
    return {"schema": 1, "revision": 0, "activeId": "", "notes": []}


def validate(doc):
    if not isinstance(doc, dict) or type(doc.get("schema")) is not int or doc["schema"] != 1:
        raise StoreError("invalid")
    if type(doc.get("revision")) is not int or doc["revision"] < 0:
        raise StoreError("invalid")
    if not isinstance(doc.get("notes"), list) or not isinstance(doc.get("activeId"), str):
        raise StoreError("invalid")
    ids = set()
    for note in doc["notes"]:
        if not isinstance(note, dict):
            raise StoreError("invalid")
        if any(not isinstance(note.get(key), str) for key in ("id", "title", "body", "createdAt", "updatedAt")):
            raise StoreError("invalid")
        if not note["id"] or note["id"] in ids:
            raise StoreError("invalid")
        ids.add(note["id"])
    if (ids and doc["activeId"] not in ids) or (not ids and doc["activeId"] != ""):
        raise StoreError("invalid")
    return doc


def private_open(path, flags):
    fd = os.open(path, flags | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise StoreError("unsafe")
        os.fchmod(fd, 0o600)
        return fd
    except BaseException:
        os.close(fd)
        raise


def read_doc(path, missing_ok=False):
    try:
        fd = private_open(path, os.O_RDONLY)
    except FileNotFoundError:
        if missing_ok:
            return empty_store()
        raise StoreError("missing") from None
    try:
        with os.fdopen(fd, "r", encoding="utf-8") as source:
            return validate(json.load(source))
    except (ValueError, UnicodeError, RecursionError):
        raise StoreError("invalid") from None


def sync_directory(directory):
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_write(path, doc):
    fd, name = tempfile.mkstemp(prefix=".notes-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            os.fchmod(output.fileno(), 0o600)
            json.dump(doc, output, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, path)
        sync_directory(path.parent)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def can_recover(backup):
    try:
        read_doc(backup)
        return True
    except (StoreError, OSError):
        return False


def run(request):
    data_root = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    if not os.path.isabs(data_root):
        raise StoreError("path")
    directory = Path(data_root) / "tsugumori"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise StoreError("unsafe")
    directory.chmod(0o700)
    path, backup = directory / "notes.json", directory / "notes.json.bak"
    lock_fd = private_open(directory / "notes.lock", os.O_RDWR | os.O_CREAT)
    with os.fdopen(lock_fd, "r+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise StoreError("busy") from None
        operation = request.get("operation")
        if operation == "recover":
            # Recovery is explicit and only replaces an unreadable store.
            try:
                read_doc(path)
            except StoreError as error:
                if error.code not in ("invalid", "missing"):
                    raise
            else:
                raise StoreError("conflict")
            doc = read_doc(backup)
            if path.exists():
                os.replace(path, directory / ("notes.json.damaged-" + uuid.uuid4().hex))
                sync_directory(directory)
            atomic_write(path, doc)
            return {"ok": True, "document": doc}
        try:
            current = read_doc(path, missing_ok=True)
        except StoreError as error:
            return {"ok": False, "error": error.code, "canRecover": can_recover(backup)}
        if operation == "read":
            return {"ok": True, "document": current}
        if operation != "write":
            raise StoreError("request")
        doc = validate(request.get("document"))
        expected = request.get("expectedRevision")
        if type(expected) is not int or expected != current["revision"] or doc["revision"] != expected + 1:
            raise StoreError("conflict")
        if path.exists():
            atomic_write(backup, current)
        atomic_write(path, doc)
        return {"ok": True, "revision": doc["revision"]}


def main():
    os.umask(0o077)
    try:
        request = json.loads(sys.stdin.readline())
        if not isinstance(request, dict):
            raise StoreError("request")
        result = run(request)
    except StoreError as error:
        result = {"ok": False, "error": error.code}
    except (OSError, ValueError, UnicodeError, RecursionError):
        # Never print exceptions that could include the user's note content.
        result = {"ok": False, "error": "io"}
    print(json.dumps(result, ensure_ascii=True), flush=True)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
