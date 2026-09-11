#!/usr/bin/env python3
"""Local clipboard history. JSON-lines UI protocol; wl-paste capture on stdin.

Clipboard bytes never appear in command arguments or diagnostic output. Images
are decoded only to a bounded preview; restoring an entry uses its original bytes.
"""

import base64
import ctypes
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import selectors
import signal
import sqlite3
import stat
import subprocess
import sys
import time
import warnings

MAX_ENTRY = 8 * 1024 * 1024
MAX_TEXT = 1024 * 1024
MAX_RECENT = 100
MAX_PINS = 40
MAX_RECENT_BYTES = 64 * 1024 * 1024
UNDO_SECONDS = 30


class StoreError(Exception):
    pass


def private_directory():
    base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    if not base.is_absolute():
        raise StoreError("path")
    directory = base / "tsugumori" / "clipboard"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise StoreError("unsafe")
    directory.chmod(0o700)
    return directory


def private_file(path):
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        os.close(fd)
        raise StoreError("unsafe")
    os.fchmod(fd, 0o600)
    return fd


def connect(directory):
    path = directory / "history.sqlite3"
    os.close(private_file(path))
    db = sqlite3.connect(path, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=DELETE")
    db.execute("PRAGMA secure_delete=ON")
    version = db.execute("PRAGMA user_version").fetchone()[0]
    if version not in (0, 1):
        raise StoreError("version")
    db.execute("""CREATE TABLE IF NOT EXISTS clips (
        id TEXT PRIMARY KEY, mime TEXT NOT NULL, kind TEXT NOT NULL,
        title TEXT NOT NULL, body TEXT NOT NULL, search TEXT NOT NULL,
        preview TEXT NOT NULL, data BLOB NOT NULL, size INTEGER NOT NULL,
        copied REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0,
        deleted REAL NOT NULL DEFAULT 0)""")
    db.execute("PRAGMA user_version=1")
    db.commit()
    return db


def prune(db):
    db.execute("DELETE FROM clips WHERE deleted > 0 AND deleted <= ?", (time.time(),))
    rows = db.execute("SELECT id,size FROM clips WHERE pinned=0 AND deleted=0 ORDER BY copied DESC,id").fetchall()
    total = 0
    for index, row in enumerate(rows):
        total += row["size"]
        if index >= MAX_RECENT or total > MAX_RECENT_BYTES:
            db.execute("DELETE FROM clips WHERE id=?", (row["id"],))


def prepare(data, category):
    if not data or len(data) > MAX_ENTRY:
        return None
    if category == "image":
        from PIL import Image, ImageOps
        Image.MAX_IMAGE_PIXELS = 20_000_000
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(data)) as image:
                    mime = {"PNG": "image/png", "JPEG": "image/jpeg", "WEBP": "image/webp",
                            "GIF": "image/gif", "BMP": "image/bmp"}.get(image.format)
                    if not mime:
                        return None
                    title = f"Image · {image.width} × {image.height}"
                    image = ImageOps.exif_transpose(image)
                    image.thumbnail((480, 320))
                    image = image.convert("RGBA")
                    output = io.BytesIO()
                    image.save(output, format="PNG")
            preview = "data:image/png;base64," + base64.b64encode(output.getvalue()).decode("ascii")
            return mime, "IMAGE", title, "", preview
        except (OSError, ValueError, SyntaxError, Image.DecompressionBombError, Image.DecompressionBombWarning):
            return None
    if category != "text" or len(data) > MAX_TEXT or b"\0" in data:
        return None
    try:
        body = data.decode("utf-8")
    except UnicodeError:
        return None
    if not body.strip():
        return None
    # Plain text only, never HTML interpretation or automatic URL fetching.
    title = re.sub(r"\s+", " ", body.strip())[:160]
    kind = "LINK" if re.fullmatch(r"https?://\S+", body.strip(), re.I) else "TEXT"
    return "text/plain;charset=utf-8", kind, title, body, ""


def capture(data, category, state="data", directory=None):
    if state != "data":
        return False
    item = prepare(data, category)
    if item is None:
        return False
    mime, kind, title, body, preview = item
    identity = hashlib.sha256(mime.encode() + b"\0" + data).hexdigest()
    db = connect(directory or private_directory())
    try:
        with db:
            # Recopying updates recency without losing the pin or creating duplicates.
            db.execute("""INSERT INTO clips(id,mime,kind,title,body,search,preview,data,size,copied)
                VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET copied=excluded.copied,deleted=0""",
                (identity, mime, kind, title, body, (title + "\n" + body).casefold(),
                 preview, data, len(data), time.time()))
            prune(db)
    finally:
        db.close()
    return True


def snapshot(db, view, watcher_error=""):
    query = str(view.get("query", ""))[:512].casefold()
    pinned = bool(view.get("pinnedOnly", False))
    rows = db.execute("""SELECT id,kind,title,size,copied,pinned FROM clips
        WHERE deleted=0 AND (?=0 OR pinned=1) AND instr(search,?)>0
        ORDER BY copied DESC,id""", (pinned, query)).fetchall()
    entries = [{"clipId": r["id"], "kind": r["kind"], "title": r["title"],
                "byteSize": r["size"], "copiedAt": r["copied"], "pinned": bool(r["pinned"])} for r in rows]
    ids = [r["id"] for r in rows]
    selected = view.get("selected", "")
    if selected not in ids:
        selected = ids[0] if ids else ""
    view["selected"] = selected
    detail = {"clipId": "", "body": "", "preview": "", "truncated": False}
    if selected:
        row = db.execute("SELECT body,preview FROM clips WHERE id=?", (selected,)).fetchone()
        detail = {"clipId": selected, "body": row["body"][:16000], "preview": row["preview"],
                  "truncated": len(row["body"]) > 16000}
    undo = db.execute("SELECT count(*) FROM clips WHERE deleted>?", (time.time(),)).fetchone()[0] > 0
    counts = db.execute("""SELECT count(*) AS total,
        count(CASE WHEN pinned=0 THEN 1 END) AS clearable FROM clips WHERE deleted=0""").fetchone()
    return {"ok": True, "event": "snapshot", "requestId": view.get("requestId", 0),
            "entries": entries, "selected": selected, "detail": detail, "total": counts["total"],
            "clearableCount": counts["clearable"],
            "canUndo": undo, "watcherError": watcher_error}


def operate(db, request, view):
    operation = request.get("operation", "sync")
    if operation not in ("sync", "pin", "delete", "clear", "undo", "use"):
        raise StoreError("request")
    for key in ("query", "pinnedOnly", "selected", "requestId"):
        if key in request:
            view[key] = request[key]
    identity = str(request.get("selected", ""))
    with db:
        prune(db)
        if operation in ("pin", "delete", "use"):
            row = db.execute("SELECT * FROM clips WHERE id=? AND deleted=0", (identity,)).fetchone()
            if not row:
                raise StoreError("missing")
            if operation == "pin":
                count = db.execute("SELECT count(*) FROM clips WHERE pinned=1").fetchone()[0]
                if not row["pinned"] and count >= MAX_PINS:
                    raise StoreError("pin-limit")
                db.execute("UPDATE clips SET pinned=? WHERE id=?", (not row["pinned"], identity))
                prune(db)
            elif operation == "delete":
                # One-level undo, expires after 30 seconds. Older deletions are removed.
                db.execute("DELETE FROM clips WHERE deleted>0")
                db.execute("UPDATE clips SET deleted=? WHERE id=?", (time.time() + UNDO_SECONDS, identity))
            else:
                try:
                    subprocess.run(["wl-copy", "--type", row["mime"]], input=row["data"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=4, check=True)
                except (OSError, subprocess.SubprocessError):
                    raise StoreError("restore") from None
        elif operation == "clear":
            # Clear all unpinned history, regardless of the current search/filter.
            # The latest deletion, whether one entry or a batch, can be undone.
            if db.execute("SELECT 1 FROM clips WHERE pinned=0 AND deleted=0 LIMIT 1").fetchone():
                db.execute("DELETE FROM clips WHERE deleted>0")
                db.execute("UPDATE clips SET deleted=? WHERE pinned=0 AND deleted=0",
                           (time.time() + UNDO_SECONDS,))
        elif operation == "undo":
            now = time.time()
            row = db.execute("SELECT id FROM clips WHERE deleted>? ORDER BY copied DESC,id LIMIT 1", (now,)).fetchone()
            if row:
                view["selected"] = row["id"]
                db.execute("UPDATE clips SET deleted=0 WHERE deleted>?", (now,))
                prune(db)
    return operation == "use"


def emit(message):
    print(json.dumps(message, ensure_ascii=True, separators=(",", ":")), flush=True)


def serve(watch=True):
    directory = private_directory()
    lock = private_file(directory / "watcher.lock")
    # A shell reload may briefly overlap the old worker's shutdown.
    deadline = time.monotonic() + 3
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if time.monotonic() >= deadline:
                os.close(lock)
                raise StoreError("already-running")
            time.sleep(0.05)
    db = connect(directory)
    watchers = []
    selector = selectors.DefaultSelector()
    view = {"selected": "", "query": "", "pinnedOnly": False, "requestId": 0}
    watcher_error = ""
    running = True
    owner_pid = os.getpid()

    def bind_watcher_lifetime():
        # Quickshell can SIGKILL workers during a reload, bypassing finally.
        # Linux must also terminate each wl-paste child when its owner dies.
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "prctl")
        if os.getppid() != owner_pid:
            os._exit(0)

    def stop(_signum, _frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        if watch:
            for kind in ("text", "image"):
                watchers.append(subprocess.Popen(
                    ["wl-paste", "--no-newline", "--type", kind, "--watch", sys.executable,
                     str(Path(__file__).resolve()), "capture", kind], stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
                    preexec_fn=bind_watcher_lifetime))
        selector.register(sys.stdin, selectors.EVENT_READ)
        with db:
            prune(db)
        emit(snapshot(db, view))
        version = db.execute("PRAGMA data_version").fetchone()[0]
        pending = b""
        while running:
            events = selector.select(timeout=1)
            for _key, _mask in events:
                block = os.read(sys.stdin.fileno(), 65536)
                if not block:
                    running = False
                    break
                pending += block
                if len(pending) > 65536:
                    raise StoreError("request")
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    try:
                        request = json.loads(line)
                        if not isinstance(request, dict):
                            raise StoreError("request")
                        restored = operate(db, request, view)
                        response = snapshot(db, view, watcher_error)
                        response["restored"] = restored
                        emit(response)
                    except (ValueError, TypeError, StoreError) as error:
                        emit({"ok": False, "error": str(error) if isinstance(error, StoreError) else "request",
                              "requestId": view.get("requestId", 0)})
            if not running:
                break
            changed = False
            if any(p.poll() is not None for p in watchers) and not watcher_error:
                watcher_error = "watcher"
                changed = True
            expired = db.execute("SELECT count(*) FROM clips WHERE deleted>0 AND deleted<=?", (time.time(),)).fetchone()[0]
            if expired:
                with db:
                    prune(db)
                changed = True
            current = db.execute("PRAGMA data_version").fetchone()[0]
            if current != version or changed:
                version = current
                emit(snapshot(db, view, watcher_error))
    finally:
        selector.close()
        for process in watchers:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for process in watchers:
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        db.close()
        os.close(lock)


def main():
    os.umask(0o077)
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "capture":
            state = os.environ.get("CLIPBOARD_STATE", "data")
            if state == "data":
                capture(sys.stdin.buffer.read(MAX_ENTRY + 1), sys.argv[2], state)
        elif sys.argv[1:] in (["serve"], ["serve", "--no-watch"]):
            serve(watch="--no-watch" not in sys.argv)
        else:
            return 2
    except BrokenPipeError:
        return 0
    except (OSError, sqlite3.Error, StoreError, ImportError) as error:
        # Never include clipboard contents, paths, or exception strings in logs.
        if "serve" in sys.argv:
            emit({"ok": False, "error": str(error) if isinstance(error, StoreError) else "storage"})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
