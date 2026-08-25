#!/usr/bin/env python3
"""
qshare — PC <-> phone file sharing over HTTP + QR code

CLI usage:
    qshare send <file|directory...> [--tunnel] [-k]
    qshare recv [-o DIR] [--tunnel] [-k]

Internal usage (from Quickshell):
    qshare ... --qr-out "$XDG_RUNTIME_DIR/tsugumori/qshare-qr-RUN.png" \
        --event-file "$XDG_RUNTIME_DIR/tsugumori/qshare-events-RUN"
"""
from __future__ import annotations

import argparse
import atexit
from email.message import Message
from http import HTTPStatus
import math
import os
import queue
import re
import secrets
import signal
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlsplit

try:
    import qrcode
    from qrcode.image.pil import PilImage
except ImportError:
    sys.exit("Missing dependency: pacman -S python-qrcode  (or pip install qrcode[pil])")


_CHILD_PROCESSES: set[subprocess.Popen] = set()


def _terminate_children() -> None:
    for proc in tuple(_CHILD_PROCESSES):
        if proc.poll() is None:
            proc.terminate()


def _handle_termination(_signum, _frame) -> None:
    _terminate_children()
    raise KeyboardInterrupt


atexit.register(_terminate_children)
signal.signal(signal.SIGTERM, _handle_termination)
signal.signal(signal.SIGINT, _handle_termination)


TSUGUMORI_BG, TSUGUMORI_FG, TSUGUMORI_ACCENT, TSUGUMORI_DIM = "#1c1a17", "#a89a7e", "#d4c8a8", "#6b6453"
ANSI_FG = "\033[38;2;168;154;126m"
ANSI_DIM = "\033[38;2;107;100;83m"
ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"

DEFAULT_MAX_UPLOAD_BYTES = 1024 * 1024 * 1024
DEFAULT_MAX_SESSION_BYTES = 4 * 1024 * 1024 * 1024
DEFAULT_MAX_FILES_PER_REQUEST = 32
DEFAULT_MAX_FILES_PER_SESSION = 128
DEFAULT_UPLOAD_TIMEOUT = 300.0
DEFAULT_HEADER_TIMEOUT = 15.0
MAX_UPLOAD_TIMEOUT = min(24 * 60 * 60.0, threading.TIMEOUT_MAX)
DEFAULT_TRANSFER_TIMEOUT = 300.0
CLOUDFLARED_STARTUP_TIMEOUT = 30.0
DEFAULT_MAX_CONNECTIONS = 16
_UPLOAD_CHUNK_SIZE = 64 * 1024
_DOWNLOAD_CHUNK_SIZE = 64 * 1024
_MAX_MULTIPART_HEADER_LINE = 64 * 1024


class UploadRejected(Exception):
    """A client upload that must be rejected with a specific HTTP status."""

    def __init__(self, status: HTTPStatus, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


class _DeadlineReader:
    """Read exactly one bounded request body without exceeding its deadline."""

    def __init__(self, rfile, connection, length: int, deadline: float):
        self.rfile = rfile
        self.connection = connection
        self.remaining = length
        self.deadline = deadline
        self.buffer = bytearray()

    def _fill(self) -> None:
        if self.remaining <= 0:
            raise UploadRejected(HTTPStatus.BAD_REQUEST, "Truncated multipart body")

        timeout = self.deadline - time.monotonic()
        if timeout <= 0:
            raise UploadRejected(HTTPStatus.REQUEST_TIMEOUT, "Upload deadline exceeded")
        self.connection.settimeout(timeout)

        read = getattr(self.rfile, "read1", self.rfile.read)
        try:
            chunk = read(min(_UPLOAD_CHUNK_SIZE, self.remaining))
        except (TimeoutError, socket.timeout) as exc:
            raise UploadRejected(
                HTTPStatus.REQUEST_TIMEOUT, "Upload deadline exceeded"
            ) from exc
        if not chunk:
            raise UploadRejected(HTTPStatus.BAD_REQUEST, "Truncated multipart body")
        self.remaining -= len(chunk)
        self.buffer.extend(chunk)

    def readline(self, limit: int = _MAX_MULTIPART_HEADER_LINE) -> bytes:
        while True:
            newline = self.buffer.find(b"\n")
            if newline >= 0:
                end = newline + 1
                if end > limit:
                    raise UploadRejected(
                        HTTPStatus.BAD_REQUEST, "Multipart header too long"
                    )
                line = bytes(self.buffer[:end])
                del self.buffer[:end]
                return line
            if len(self.buffer) >= limit:
                raise UploadRejected(
                    HTTPStatus.BAD_REQUEST, "Multipart header too long"
                )
            if self.remaining <= 0:
                if not self.buffer:
                    return b""
                line = bytes(self.buffer)
                self.buffer.clear()
                return line
            self._fill()

    def copy_part(self, out, marker: bytes, max_bytes: int) -> tuple[bool, int]:
        """Copy through the next boundary and return (is_final, bytes_written)."""
        written = 0
        suffix_size = 2
        keep = len(marker) + suffix_size - 1

        def write(data: bytes) -> None:
            nonlocal written
            if written + len(data) > max_bytes:
                raise UploadRejected(
                    HTTPStatus.CONTENT_TOO_LARGE, "Size limit exceeded"
                )
            if out is not None:
                out.write(data)
            written += len(data)

        while True:
            marker_at = self.buffer.find(marker)
            if marker_at >= 0:
                marker_end = marker_at + len(marker)
                while len(self.buffer) < marker_end + suffix_size:
                    if self.remaining <= 0:
                        raise UploadRejected(
                            HTTPStatus.BAD_REQUEST, "Invalid multipart ending"
                        )
                    self._fill()
                suffix = bytes(self.buffer[marker_end:marker_end + suffix_size])
                if suffix in (b"\r\n", b"--"):
                    write(bytes(self.buffer[:marker_at]))
                    del self.buffer[:marker_end + suffix_size]
                    return suffix == b"--", written

                # A boundary-looking byte sequence inside file data is not a
                # delimiter unless it has a valid multipart suffix.
                write(bytes(self.buffer[:marker_at + 1]))
                del self.buffer[:marker_at + 1]
                continue

            safe = len(self.buffer) - keep
            if safe > 0:
                write(bytes(self.buffer[:safe]))
                del self.buffer[:safe]
            if self.remaining <= 0:
                raise UploadRejected(HTTPStatus.BAD_REQUEST, "Fin multipart absente")
            self._fill()

    def drain(self) -> None:
        """Consume the declared epilogue so a short body cannot be accepted."""
        self.buffer.clear()
        while self.remaining > 0:
            self._fill()
            self.buffer.clear()


# ─── Network ──────────────────────────────────────────────────────────────────
def get_local_ip(iface: str | None = None) -> str:
    if iface:
        try:
            import fcntl, struct
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                packed = struct.pack("256s", iface.encode()[:15])
                return socket.inet_ntoa(fcntl.ioctl(s.fileno(), 0x8915, packed)[20:24])
        except OSError as e:
            sys.exit(f"Could not read the IP address for {iface}: {e}")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("", 0))
        return s.getsockname()[1]


# ─── Cloudflare Tunnel ────────────────────────────────────────────────────────
def start_cloudflared(local_port: int) -> tuple[subprocess.Popen, str]:
    if not shutil.which("cloudflared"):
        sys.exit("cloudflared not found. Install it with: pacman -S cloudflared")

    cmd = [
        "cloudflared", "tunnel",
        "--url", f"http://localhost:{local_port}",
        "--protocol", "http2",
        "--edge-ip-version", "4",
        "--no-autoupdate",
    ]
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    _CHILD_PROCESSES.add(proc)

    url_pattern = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")
    public_url: str | None = None
    registered = False
    deadline = time.monotonic() + CLOUDFLARED_STARTUP_TIMEOUT
    startup_lines: queue.Queue[str | None] = queue.Queue()
    startup_complete = threading.Event()

    def _read_output() -> None:
        # This remains the process's sole stdout reader after startup, when it
        # switches from forwarding lines to simply draining the pipe.
        for line in iter(proc.stdout.readline, ""):
            if not startup_complete.is_set():
                startup_lines.put(line)
        if not startup_complete.is_set():
            startup_lines.put(None)

    threading.Thread(target=_read_output, daemon=True).start()

    print(f"{ANSI_DIM}Starting Cloudflare tunnel…{ANSI_RESET}")
    failure = "Could not establish the Cloudflare tunnel (timeout)."
    while not (public_url and registered):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            line = startup_lines.get(timeout=remaining)
        except queue.Empty:
            break
        if line is None:
            failure = "cloudflared stopped before establishing the tunnel."
            break
        if not public_url:
            m = url_pattern.search(line)
            if m:
                public_url = m.group(0)
        if "Registered tunnel connection" in line:
            registered = True

    if not (public_url and registered):
        startup_complete.set()
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        _CHILD_PROCESSES.discard(proc)
        sys.exit(failure)

    startup_complete.set()
    return proc, public_url


# ─── QR ───────────────────────────────────────────────────────────────────────
def print_qr(url: str) -> None:
    qr = qrcode.QRCode(border=1, error_correction=qrcode.constants.ERROR_CORRECT_L)
    qr.add_data(url)
    qr.make(fit=True)
    qr.print_ascii(invert=True)


def write_qr_png(url: str, path: Path) -> None:
    """Write a QR PNG using the Sidonia palette (dark background, light modules)."""
    qr = qrcode.QRCode(
        border=2,
        box_size=12,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
    )
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(
        image_factory=PilImage,
        fill_color=TSUGUMORI_FG,
        back_color=TSUGUMORI_BG,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


# ─── Event file (IPC to Quickshell) ───────────────────────────────────────────
class EventLog:
    def __init__(self, path: str | None):
        self.path = Path(path) if path else None
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text("")  # reset
        self._lock = threading.Lock()

    def emit(self, line: str) -> None:
        if not self.path:
            return
        with self._lock:
            with self.path.open("a") as f:
                f.write(line.rstrip("\n") + "\n")


# ─── Prepare the SEND payload ─────────────────────────────────────────────────
def build_payload(paths: list[Path]) -> tuple[Path, str, bool]:
    for p in paths:
        if not p.exists():
            sys.exit(f"Not found: {p}")

    if len(paths) == 1 and paths[0].is_file():
        return paths[0], paths[0].name, False

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".zip")
    tmp.close()
    zip_path = Path(tmp.name)

    if len(paths) == 1 and paths[0].is_dir():
        archive_name = paths[0].name + ".zip"
        root = paths[0]
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for f in root.rglob("*"):
                if f.is_file():
                    zf.write(f, f.relative_to(root.parent))
    else:
        archive_name = "qshare_bundle.zip"
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for p in paths:
                if p.is_file():
                    zf.write(p, p.name)
                else:
                    for f in p.rglob("*"):
                        if f.is_file():
                            zf.write(f, f.relative_to(p.parent))
    return zip_path, archive_name, True


# ─── Upload HTML page (Sidonia style) ────────────────────────────────────────
UPLOAD_HTML = """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>qshare</title>
<style>
  :root {{ --bg:{bg}; --fg:{fg}; --accent:{accent}; --dim:{dim}; }}
  * {{ box-sizing: border-box; }}
  html, body {{ margin:0; padding:0; background:var(--bg); color:var(--fg);
    font-family:'Iosevka',ui-monospace,monospace; min-height:100vh; }}
  main {{ max-width:540px; margin:0 auto; padding:2.5rem 1.5rem; }}
  h1 {{ font-weight:400; letter-spacing:0.4em; text-transform:uppercase;
    border-bottom:1px solid var(--dim); padding-bottom:0.6rem; font-size:1.1rem; }}
  .frame {{ border:1px solid var(--dim); padding:1.5rem; margin-top:1.5rem; position:relative; }}
  .frame::before, .frame::after {{ content:""; position:absolute; width:8px; height:8px;
    border:1px solid var(--accent); background:var(--bg); }}
  .frame::before {{ top:-4px; left:-4px; }}
  .frame::after {{ bottom:-4px; right:-4px; }}
  input[type=file] {{ display:block; width:100%; color:var(--fg); margin-bottom:1.2rem; }}
  button {{ width:100%; background:transparent; color:var(--accent); border:1px solid var(--accent);
    padding:0.7rem; font-family:inherit; letter-spacing:0.3em; text-transform:uppercase;
    cursor:pointer; transition:all 0.2s; }}
  button:hover:not(:disabled) {{ background:var(--accent); color:var(--bg); }}
  button:disabled {{ opacity:0.4; cursor:wait; }}
  .progress {{ margin-top:1rem; height:4px; background:var(--dim); display:none; overflow:hidden; }}
  .progress > div {{ height:100%; width:0%; background:var(--accent); transition:width 0.1s linear; }}
  .status {{ margin-top:1rem; min-height:1.4em; font-size:0.9rem; }}
  .ok {{ color:var(--accent); }}
  .err {{ color:#c97a6f; }}
</style>
</head><body>
<main>
  <h1>qshare // upload</h1>
  <div class="frame">
    <input type="file" id="files" multiple>
    <button id="send">Transmettre</button>
    <div class="progress"><div id="bar"></div></div>
    <div class="status" id="status"></div>
  </div>
</main>
<script>
const TOKEN = "{token}";
const filesInput = document.getElementById("files");
const btn = document.getElementById("send");
const bar = document.getElementById("bar");
const progress = document.querySelector(".progress");
const status = document.getElementById("status");
btn.addEventListener("click", () => {{
  const files = filesInput.files;
  if (!files.length) {{ status.textContent = "No file selected."; return; }}
  const fd = new FormData();
  for (const f of files) fd.append("files", f, f.name);
  const xhr = new XMLHttpRequest();
  xhr.open("POST", "/upload?t=" + TOKEN);
  xhr.upload.onprogress = e => {{
    if (e.lengthComputable) {{
      progress.style.display = "block";
      bar.style.width = (e.loaded / e.total * 100).toFixed(1) + "%";
    }}
  }};
  xhr.onload = () => {{
    btn.disabled = false;
    if (xhr.status === 200) {{ status.textContent = "✓ Transfer complete."; status.className = "status ok"; }}
    else {{ status.textContent = "✗ Error " + xhr.status; status.className = "status err"; }}
  }};
  xhr.onerror = () => {{ btn.disabled = false; status.textContent = "✗ Network error."; status.className = "status err"; }};
  btn.disabled = true;
  status.textContent = "Sending…";
  status.className = "status";
  xhr.send(fd);
}});
</script>
</body></html>
"""


# ─── Handlers HTTP ────────────────────────────────────────────────────────────
class SendHandler(BaseHTTPRequestHandler):
    file_path: Path = None  # type: ignore[assignment]
    file_name: str = ""
    token: str = ""
    keep_alive: bool = False
    done_event: threading.Event = None  # type: ignore[assignment]
    events: EventLog = None  # type: ignore[assignment]
    transfer_timeout: float = DEFAULT_TRANSFER_TIMEOUT
    header_timeout: float = DEFAULT_HEADER_TIMEOUT

    def setup(self) -> None:
        # Bound both the HTTP header phase and the complete download from the
        # instant this request starts.
        self.timeout = min(self.header_timeout, self.transfer_timeout)
        self._header_timer_lock = threading.Lock()
        self._header_timer: threading.Timer | None = None
        self._reading_headers = False
        self._request_deadline = time.monotonic() + self.transfer_timeout
        super().setup()

    def handle_one_request(self) -> None:
        self._start_header_deadline()
        try:
            super().handle_one_request()
        finally:
            self._finish_header_deadline()

    def parse_request(self) -> bool:
        try:
            return super().parse_request()
        finally:
            self._finish_header_deadline()

    def _start_header_deadline(self) -> None:
        header_timeout = min(self.header_timeout, self.transfer_timeout)
        self.connection.settimeout(header_timeout)
        self._request_deadline = time.monotonic() + self.transfer_timeout
        timer = threading.Timer(header_timeout, self._expire_header_read)
        timer.daemon = True
        with self._header_timer_lock:
            self._reading_headers = True
            self._header_timer = timer
        timer.start()

    def _finish_header_deadline(self) -> None:
        with self._header_timer_lock:
            self._reading_headers = False
            timer = self._header_timer
            self._header_timer = None
        if timer is not None:
            timer.cancel()

    def _expire_header_read(self) -> None:
        with self._header_timer_lock:
            if not self._reading_headers:
                return
            self._reading_headers = False
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def log_message(self, fmt, *args):
        print(f"{ANSI_DIM}[{self.address_string()}] {fmt % args}{ANSI_RESET}")

    def do_GET(self):  # noqa: N802
        if f"/{self.token}/" not in self.path:
            self.send_error(404); return
        try:
            with open(self.file_path, "rb", buffering=0) as source:
                size = os.fstat(source.fileno()).st_size
                remaining = size
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(size))
                self.send_header("Content-Disposition", f'attachment; filename="{quote(self.file_name)}"')
                self.end_headers()
                while remaining > 0:
                    chunk = source.read(min(_DOWNLOAD_CHUNK_SIZE, remaining))
                    if not chunk:
                        raise OSError("source ended before advertised length")
                    timeout = self._request_deadline - time.monotonic()
                    if timeout <= 0:
                        raise TimeoutError("download deadline exceeded")
                    self.connection.settimeout(timeout)
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
                    if time.monotonic() > self._request_deadline:
                        raise TimeoutError("download deadline exceeded")
        except OSError:
            # A failed client must not complete a one-shot session. Closing
            # only this connection leaves the server available for a retry.
            self.close_connection = True
            return
        print(f"{ANSI_FG}{ANSI_BOLD}✓ {self.file_name} sent{ANSI_RESET}")
        if self.events:
            self.events.emit(f"TICK {self.file_name}")
        if not self.keep_alive:
            if self.events:
                self.events.emit("DONE")
            self.done_event.set()


class RecvHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    out_dir: Path = None  # type: ignore[assignment]
    token: str = ""
    keep_alive: bool = False
    done_event: threading.Event = None  # type: ignore[assignment]
    events: EventLog = None  # type: ignore[assignment]
    max_upload_bytes: int = DEFAULT_MAX_UPLOAD_BYTES
    max_session_bytes: int = DEFAULT_MAX_SESSION_BYTES
    max_files_per_request: int = DEFAULT_MAX_FILES_PER_REQUEST
    max_files_per_session: int = DEFAULT_MAX_FILES_PER_SESSION
    upload_timeout: float = DEFAULT_UPLOAD_TIMEOUT
    header_timeout: float = DEFAULT_HEADER_TIMEOUT
    upload_lock = threading.Lock()
    session_upload_count: int = 0
    session_upload_bytes: int = 0

    def setup(self) -> None:
        # Bound the request line and HTTP headers before BaseHTTPRequestHandler
        # starts parsing them. The deadline timer also prevents a peer from
        # evading an idle socket timeout by slowly dripping header bytes.
        self.timeout = min(self.header_timeout, self.upload_timeout)
        self._header_timer_lock = threading.Lock()
        self._header_timer: threading.Timer | None = None
        self._reading_headers = False
        self._request_deadline = time.monotonic() + self.upload_timeout
        super().setup()

    def handle_one_request(self) -> None:
        self._start_header_deadline()
        try:
            super().handle_one_request()
        finally:
            self._finish_header_deadline()

    def parse_request(self) -> bool:
        try:
            parsed = super().parse_request()
        finally:
            # At this point the request line and all HTTP headers have either
            # arrived or failed validation. Body reads retain the same absolute
            # request deadline through _DeadlineReader.
            self._finish_header_deadline()
        if not parsed:
            return False

        expectation = self.headers.get("Expect")
        if expectation and (
            expectation.lower() != "100-continue"
            or self.request_version < "HTTP/1.1"
        ):
            self.send_error(HTTPStatus.EXPECTATION_FAILED, "Expect header not supported")
            return False
        return True

    def _start_header_deadline(self) -> None:
        header_timeout = min(self.header_timeout, self.upload_timeout)
        self.connection.settimeout(header_timeout)
        self._request_deadline = time.monotonic() + self.upload_timeout
        timer = threading.Timer(header_timeout, self._expire_header_read)
        timer.daemon = True
        with self._header_timer_lock:
            self._reading_headers = True
            self._header_timer = timer
        timer.start()

    def _finish_header_deadline(self) -> None:
        with self._header_timer_lock:
            self._reading_headers = False
            timer = self._header_timer
            self._header_timer = None
        if timer is not None:
            timer.cancel()

    def _expire_header_read(self) -> None:
        with self._header_timer_lock:
            if not self._reading_headers:
                return
            self._reading_headers = False
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def log_message(self, fmt, *args):
        print(f"{ANSI_DIM}[{self.address_string()}] {fmt % args}{ANSI_RESET}")

    def do_GET(self):  # noqa: N802
        if self.path != f"/{self.token}":
            self.send_error(404); return
        html = UPLOAD_HTML.format(
            bg=TSUGUMORI_BG, fg=TSUGUMORI_FG, accent=TSUGUMORI_ACCENT, dim=TSUGUMORI_DIM, token=self.token
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)

    def handle_expect_100(self) -> bool:
        # Validate the complete upload preflight before asking a streaming
        # client (curl, mobile HTTP stacks) to transmit a potentially large body.
        try:
            self._validate_upload_request()
        except UploadRejected as exc:
            self._send_upload_error(exc.status, exc.message)
            return False
        self.send_response_only(HTTPStatus.CONTINUE)
        self.end_headers()
        return True

    def _validate_upload_request(self) -> tuple[bytes, int]:
        target = urlsplit(self.path)
        if target.path != "/upload":
            raise UploadRejected(HTTPStatus.NOT_FOUND, "Resource not found")
        if parse_qs(target.query, keep_blank_values=True).get("t") != [self.token]:
            raise UploadRejected(HTTPStatus.FORBIDDEN, "Invalid token")

        if self.headers.get_content_type() != "multipart/form-data":
            raise UploadRejected(
                HTTPStatus.BAD_REQUEST, "multipart/form-data required"
            )
        boundary_text = self.headers.get_param("boundary", header="content-type")
        if not boundary_text:
            raise UploadRejected(HTTPStatus.BAD_REQUEST, "Missing multipart boundary")
        try:
            boundary = boundary_text.encode("ascii")
        except UnicodeEncodeError as exc:
            raise UploadRejected(
                HTTPStatus.BAD_REQUEST, "Invalid multipart boundary"
            ) from exc
        if not 1 <= len(boundary) <= 70 or b"\r" in boundary or b"\n" in boundary:
            raise UploadRejected(HTTPStatus.BAD_REQUEST, "Invalid multipart boundary")

        if self.headers.get("Transfer-Encoding"):
            raise UploadRejected(HTTPStatus.LENGTH_REQUIRED, "Content-Length required")
        raw_lengths = self.headers.get_all("Content-Length", [])
        if not raw_lengths:
            raise UploadRejected(HTTPStatus.LENGTH_REQUIRED, "Content-Length required")
        if len(raw_lengths) != 1:
            raise UploadRejected(HTTPStatus.BAD_REQUEST, "Ambiguous Content-Length")
        try:
            length = int(raw_lengths[0])
        except ValueError as exc:
            raise UploadRejected(
                HTTPStatus.BAD_REQUEST, "Invalid Content-Length"
            ) from exc
        if length <= 0:
            raise UploadRejected(HTTPStatus.BAD_REQUEST, "Empty upload body")
        if length > self.max_upload_bytes:
            raise UploadRejected(
                HTTPStatus.CONTENT_TOO_LARGE,
                f"Upload limited to {self.max_upload_bytes} bytes",
            )
        return boundary, length

    def do_POST(self):  # noqa: N802
        try:
            boundary, length = self._validate_upload_request()
        except UploadRejected as exc:
            self._send_upload_error(exc.status, exc.message)
            return

        deadline = getattr(
            self, "_request_deadline", time.monotonic() + self.upload_timeout
        )
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            self._send_upload_error(HTTPStatus.REQUEST_TIMEOUT, "Upload deadline exceeded")
            return
        acquired = self.upload_lock.acquire(timeout=remaining)
        if not acquired:
            self._send_upload_error(HTTPStatus.REQUEST_TIMEOUT, "Upload deadline exceeded")
            return

        error: UploadRejected | None = None
        try:
            state = type(self)
            if state.session_upload_count >= self.max_files_per_session:
                raise UploadRejected(
                    HTTPStatus.TOO_MANY_REQUESTS,
                    "Session file limit reached",
                )
            saved = self._parse_multipart(boundary, length, deadline)
        except UploadRejected as exc:
            error = exc
            saved = []
        except OSError:
            error = UploadRejected(
                HTTPStatus.INSUFFICIENT_STORAGE,
                "Could not save the upload",
            )
            saved = []
        finally:
            self.upload_lock.release()

        if error:
            self._send_upload_error(error.status, error.message)
            return

        try:
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
        except OSError:
            # The upload is already committed. A peer disappearing before the
            # acknowledgement must not strand a one-shot receiver forever.
            self.close_connection = True

        one_shot_complete = bool(saved) and not self.keep_alive
        try:
            for name in saved:
                try:
                    print(f"{ANSI_FG}{ANSI_BOLD}✓ received: {name}{ANSI_RESET}")
                except OSError:
                    pass
                self._emit_event_safely(f"TICK {name}")
            if one_shot_complete:
                self._emit_event_safely("DONE")
        finally:
            if one_shot_complete:
                self.done_event.set()

    def _emit_event_safely(self, line: str) -> None:
        if not self.events:
            return
        try:
            self.events.emit(line)
        except OSError as exc:
            try:
                print(
                    f"qshare: could not write event {line!r}: {exc}",
                    file=sys.stderr,
                )
            except OSError:
                pass

    def _send_upload_error(self, status: HTTPStatus, message: str) -> None:
        # Rejected bodies are intentionally not drained. Closing prevents their
        # remaining bytes from being interpreted as another HTTP request.
        self.close_connection = True
        try:
            self.connection.settimeout(1.0)
            self.send_error(status, message)
        except (BrokenPipeError, ConnectionError, TimeoutError, socket.timeout):
            pass

    def _parse_multipart(
        self, boundary: bytes, length: int, deadline: float
    ) -> list[str]:
        delim = b"--" + boundary
        marker = b"\r\n" + delim
        reader = _DeadlineReader(self.rfile, self.connection, length, deadline)
        pending: list[tuple[Path, str, int]] = []
        committed: list[Path] = []
        complete = False

        try:
            opening = reader.readline()
            if opening.rstrip(b"\r\n") == delim + b"--":
                reader.drain()
                complete = True
                return []
            if opening.rstrip(b"\r\n") != delim:
                raise UploadRejected(
                    HTTPStatus.BAD_REQUEST, "Invalid multipart start"
                )

            final_boundary = False
            request_file_bytes = 0
            while not final_boundary:
                headers: dict[str, str] = {}
                for _ in range(100):
                    line = reader.readline()
                    if line == b"\r\n":
                        break
                    if not line or b":" not in line:
                        raise UploadRejected(
                            HTTPStatus.BAD_REQUEST, "Invalid multipart header"
                        )
                    key, value = line.decode("utf-8", "replace").split(":", 1)
                    headers[key.strip().lower()] = value.strip()
                else:
                    raise UploadRejected(
                        HTTPStatus.BAD_REQUEST, "Too many multipart headers"
                    )

                disposition = Message()
                disposition["Content-Disposition"] = headers.get(
                    "content-disposition", ""
                )
                filename = disposition.get_filename()
                if filename is None:
                    final_boundary, _ = reader.copy_part(
                        None, marker, self.max_upload_bytes
                    )
                    continue

                safe_name = Path(filename.replace("\\", "/").replace("\x00", "")).name
                if safe_name in ("", ".", ".."):
                    raise UploadRejected(HTTPStatus.BAD_REQUEST, "Invalid file name")

                request_count = len(pending) + 1
                state = type(self)
                if request_count > self.max_files_per_request:
                    raise UploadRejected(
                        HTTPStatus.CONTENT_TOO_LARGE,
                        "Too many files in this upload",
                    )
                if state.session_upload_count + request_count > self.max_files_per_session:
                    raise UploadRejected(
                        HTTPStatus.TOO_MANY_REQUESTS,
                        "Session file limit reached",
                    )

                session_remaining = (
                    self.max_session_bytes
                    - state.session_upload_bytes
                    - request_file_bytes
                )
                if session_remaining < 0:
                    raise UploadRejected(
                        HTTPStatus.CONTENT_TOO_LARGE,
                        "Session size limit reached",
                    )

                fd, tmp_name = tempfile.mkstemp(prefix=".qshare-", dir=self.out_dir)
                tmp_path = Path(tmp_name)
                try:
                    with os.fdopen(fd, "wb") as out:
                        final_boundary, file_bytes = reader.copy_part(
                            out,
                            marker,
                            min(self.max_upload_bytes, session_remaining),
                        )
                except BaseException:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                    tmp_path.unlink(missing_ok=True)
                    raise
                pending.append((tmp_path, safe_name, file_bytes))
                request_file_bytes += file_bytes

            reader.drain()

            saved: list[str] = []
            for tmp_path, safe_name, _ in pending:
                dest = _unique_path(self.out_dir / safe_name)
                tmp_path.replace(dest)
                committed.append(dest)
                saved.append(dest.name)

            state = type(self)
            state.session_upload_count += len(saved)
            state.session_upload_bytes += request_file_bytes
            complete = True
            return saved
        finally:
            for tmp_path, _, _ in pending:
                tmp_path.unlink(missing_ok=True)
            if not complete:
                for dest in committed:
                    dest.unlink(missing_ok=True)


def _unique_path(p: Path) -> Path:
    if not p.exists():
        return p
    stem, suf = p.stem, p.suffix
    i = 1
    while True:
        cand = p.with_name(f"{stem} ({i}){suf}")
        if not cand.exists():
            return cand
        i += 1


# ─── Commands ─────────────────────────────────────────────────────────────────
class BoundedThreadingHTTPServer(ThreadingHTTPServer):
    """Threading HTTP server with a hard cap applied before thread creation."""

    def __init__(
        self,
        server_address,
        handler_cls,
        bind_and_activate: bool = True,
        *,
        max_connections: int = DEFAULT_MAX_CONNECTIONS,
    ):
        self._connection_slots = threading.BoundedSemaphore(max_connections)
        super().__init__(server_address, handler_cls, bind_and_activate)

    def process_request(self, request, client_address) -> None:
        if not self._connection_slots.acquire(blocking=False):
            self._reject_saturated(request)
            return
        try:
            self._start_request_thread(request, client_address)
        except BaseException:
            self._connection_slots.release()
            raise

    def _start_request_thread(self, request, client_address) -> None:
        super().process_request(request, client_address)

    def process_request_thread(self, request, client_address) -> None:
        try:
            self._run_request_thread(request, client_address)
        finally:
            self._connection_slots.release()

    def _run_request_thread(self, request, client_address) -> None:
        super().process_request_thread(request, client_address)

    def _reject_saturated(self, request) -> None:
        try:
            request.settimeout(1.0)
            request.sendall(
                b"HTTP/1.1 503 Service Unavailable\r\n"
                b"Connection: close\r\n"
                b"Content-Length: 0\r\n"
                b"Retry-After: 1\r\n\r\n"
            )
        except OSError:
            pass
        finally:
            self.shutdown_request(request)


def _start_server_with_port(handler_cls, preferred_port: int):
    port = preferred_port if preferred_port else _free_port()
    try:
        return BoundedThreadingHTTPServer(("0.0.0.0", port), handler_cls), port
    except OSError:
        port = _free_port()
        return BoundedThreadingHTTPServer(("0.0.0.0", port), handler_cls), port


def _emit_ready(events: EventLog, url: str, qr_path: Path | None) -> None:
    events.emit(f"URL {url}")
    if qr_path:
        events.emit(f"QR {qr_path}")
    events.emit("READY")


def cmd_send(args: argparse.Namespace) -> None:
    paths = [Path(p).expanduser().resolve() for p in args.paths]
    served, name, is_tmp = build_payload(paths)
    token = secrets.token_urlsafe(8)
    events = EventLog(args.event_file)

    SendHandler.file_path = served
    SendHandler.file_name = name
    SendHandler.token = token
    SendHandler.keep_alive = args.keep_alive
    SendHandler.done_event = threading.Event()
    SendHandler.events = events
    SendHandler.transfer_timeout = args.transfer_timeout

    preferred = args.port or (8080 if args.tunnel else 0)
    server, port = _start_server_with_port(SendHandler, preferred)

    tunnel_proc = None
    if args.tunnel:
        tunnel_proc, public = start_cloudflared(port)
        url = f"{public}/{token}/{quote(name)}"
    else:
        ip = get_local_ip(args.iface)
        url = f"http://{ip}:{port}/{token}/{quote(name)}"

    qr_path = Path(args.qr_out).expanduser().resolve() if args.qr_out else None
    if qr_path:
        write_qr_png(url, qr_path)

    _print_banner("SEND", name, url, tunneled=args.tunnel)
    _emit_ready(events, url, qr_path)

    try:
        if args.keep_alive:
            server.serve_forever()
        else:
            t = threading.Thread(target=server.serve_forever, daemon=True)
            t.start()
            SendHandler.done_event.wait()
            server.shutdown()
    except KeyboardInterrupt:
        print(f"\n{ANSI_DIM}interrupted{ANSI_RESET}")
        events.emit("CANCELLED")
    finally:
        if is_tmp:
            try: served.unlink()
            except OSError: pass
        if tunnel_proc:
            tunnel_proc.terminate()
            _CHILD_PROCESSES.discard(tunnel_proc)


def cmd_recv(args: argparse.Namespace) -> None:
    out = Path(args.output).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(8)
    events = EventLog(args.event_file)

    RecvHandler.out_dir = out
    RecvHandler.token = token
    RecvHandler.keep_alive = args.keep_alive
    RecvHandler.done_event = threading.Event()
    RecvHandler.events = events
    RecvHandler.max_upload_bytes = args.max_upload_bytes
    RecvHandler.max_session_bytes = args.max_session_bytes
    RecvHandler.max_files_per_request = args.max_files_per_request
    RecvHandler.max_files_per_session = args.max_files_per_session
    RecvHandler.upload_timeout = args.upload_timeout
    RecvHandler.upload_lock = threading.Lock()
    RecvHandler.session_upload_count = 0
    RecvHandler.session_upload_bytes = 0

    preferred = args.port or (8080 if args.tunnel else 0)
    server, port = _start_server_with_port(RecvHandler, preferred)

    tunnel_proc = None
    if args.tunnel:
        tunnel_proc, public = start_cloudflared(port)
        url = f"{public}/{token}"
    else:
        ip = get_local_ip(args.iface)
        url = f"http://{ip}:{port}/{token}"

    qr_path = Path(args.qr_out).expanduser().resolve() if args.qr_out else None
    if qr_path:
        write_qr_png(url, qr_path)

    _print_banner("RECV", str(out), url, tunneled=args.tunnel)
    _emit_ready(events, url, qr_path)

    try:
        if args.keep_alive:
            server.serve_forever()
        else:
            t = threading.Thread(target=server.serve_forever, daemon=True)
            t.start()
            RecvHandler.done_event.wait()
            server.shutdown()
    except KeyboardInterrupt:
        print(f"\n{ANSI_DIM}interrupted{ANSI_RESET}")
        events.emit("CANCELLED")
    finally:
        if tunnel_proc:
            tunnel_proc.terminate()
            _CHILD_PROCESSES.discard(tunnel_proc)


def _print_banner(mode: str, target: str, url: str, *, tunneled: bool) -> None:
    line = "─" * 48
    print(f"\n{ANSI_FG}{line}")
    mode_label = f"{mode} (TUNNEL)" if tunneled else mode
    print(f"  qshare // {mode_label}")
    print(f"  {ANSI_DIM}target: {ANSI_FG}{target}")
    print(f"  {ANSI_DIM}url   : {ANSI_FG}{url}")
    print(f"{line}{ANSI_RESET}\n")
    print_qr(url)
    hint = "Public QR, accessible from the Internet (4G OK)." if tunneled \
           else "LAN QR, same Wi-Fi required."
    print(f"\n{ANSI_DIM}{hint} Press Ctrl-C to stop.{ANSI_RESET}\n")


# ─── CLI ──────────────────────────────────────────────────────────────────────
def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def _positive_float(value: str) -> float:
    parsed = float(value)
    if (
        not math.isfinite(parsed)
        or parsed <= 0
        or parsed > MAX_UPLOAD_TIMEOUT
    ):
        raise argparse.ArgumentTypeError(
            f"must be between 0 and {MAX_UPLOAD_TIMEOUT:g} seconds"
        )
    return parsed


def main() -> None:
    p = argparse.ArgumentParser(prog="qshare",
        description="Share files PC <-> phone over HTTP + QR")
    sub = p.add_subparsers(dest="cmd", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("-p", "--port", type=int, default=0)
    common.add_argument("-i", "--iface")
    common.add_argument("-k", "--keep-alive", action="store_true")
    common.add_argument("-t", "--tunnel", action="store_true")
    common.add_argument("--qr-out", help="Write a QR PNG to this path (for Quickshell)")
    common.add_argument("--event-file", help="Event file for Quickshell IPC")

    sp_send = sub.add_parser("send", parents=[common])
    sp_send.add_argument("paths", nargs="+")
    sp_send.add_argument(
        "--transfer-timeout",
        type=_positive_float,
        default=DEFAULT_TRANSFER_TIMEOUT,
        help=(
            "Maximum download time in seconds "
            f"(default: {DEFAULT_TRANSFER_TIMEOUT:g}, maximum: {MAX_UPLOAD_TIMEOUT:g})"
        ),
    )
    sp_send.set_defaults(func=cmd_send)

    sp_recv = sub.add_parser("recv", parents=[common])
    sp_recv.add_argument("-o", "--output", default=os.getcwd())
    sp_recv.add_argument(
        "--max-upload-bytes",
        type=_positive_int,
        default=DEFAULT_MAX_UPLOAD_BYTES,
        help=f"Maximum request size (default: {DEFAULT_MAX_UPLOAD_BYTES})",
    )
    sp_recv.add_argument(
        "--max-session-bytes",
        type=_positive_int,
        default=DEFAULT_MAX_SESSION_BYTES,
        help=f"Maximum cumulative session size (default: {DEFAULT_MAX_SESSION_BYTES})",
    )
    sp_recv.add_argument(
        "--max-files-per-request",
        type=_positive_int,
        default=DEFAULT_MAX_FILES_PER_REQUEST,
        help=f"Maximum files per request (default: {DEFAULT_MAX_FILES_PER_REQUEST})",
    )
    sp_recv.add_argument(
        "--max-files-per-session",
        type=_positive_int,
        default=DEFAULT_MAX_FILES_PER_SESSION,
        help=f"Maximum files per session (default: {DEFAULT_MAX_FILES_PER_SESSION})",
    )
    sp_recv.add_argument(
        "--upload-timeout",
        type=_positive_float,
        default=DEFAULT_UPLOAD_TIMEOUT,
        help=(
            "Maximum request time in seconds "
            f"(default: {DEFAULT_UPLOAD_TIMEOUT:g}, maximum: {MAX_UPLOAD_TIMEOUT:g})"
        ),
    )
    sp_recv.set_defaults(func=cmd_recv)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
