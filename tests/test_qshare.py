from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
from pathlib import Path
import socket
import tempfile
import threading
import time
import types
import unittest
from unittest import mock


QSHARE_PATH = (
    Path(__file__).parents[1] / "config/quickshell/scripts/qshare.py"
)


def load_qshare():
    spec = importlib.util.spec_from_file_location("qshare_under_test", QSHARE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


qshare = load_qshare()


def multipart(
    boundary: bytes, files: list[tuple[str, bytes]], *, close: bool = True
) -> bytes:
    body = bytearray()
    for filename, payload in files:
        body.extend(b"--" + boundary + b"\r\n")
        body.extend(
            b'Content-Disposition: form-data; name="files"; filename="'
            + filename.encode("utf-8")
            + b'"\r\nContent-Type: application/octet-stream\r\n\r\n'
        )
        body.extend(payload)
        body.extend(b"\r\n")
    if close:
        body.extend(b"--" + boundary + b"--\r\n")
    return bytes(body)


def request_bytes(
    body: bytes,
    boundary: bytes,
    *,
    token: str = "test-token",
    extra_headers: tuple[bytes, ...] = (),
) -> bytes:
    headers = [
        b"POST /upload?t=" + token.encode("ascii") + b" HTTP/1.1",
        b"Host: qshare.test",
        b"Connection: close",
        b"Content-Type: multipart/form-data; boundary=\"" + boundary + b"\"",
        b"Content-Length: " + str(len(body)).encode("ascii"),
        *extra_headers,
    ]
    return b"\r\n".join(headers) + b"\r\n\r\n" + body


def response_status(response: bytes) -> int:
    first_line = response.split(b"\r\n", 1)[0]
    return int(first_line.split(b" ", 2)[1])


class TimeoutInput(io.BytesIO):
    """A complete header stream whose request body stalls at EOF."""

    def read1(self, size: int = -1) -> bytes:
        data = super().read(size)
        if data:
            return data
        raise socket.timeout("simulated stalled upload")


class BlockingInput:
    """An incomplete HTTP header stream released only by socket shutdown."""

    def __init__(self):
        self.released = threading.Event()
        self.closed = False

    def readline(self, _limit: int = -1) -> bytes:
        self.released.wait(2)
        return b""

    def close(self) -> None:
        self.closed = True
        self.released.set()


class MemoryConnection:
    """The socket surface StreamRequestHandler needs, without network access."""

    def __init__(
        self,
        request: bytes = b"",
        *,
        input_stream=None,
        fail_writes: bool = False,
    ):
        self.input = input_stream if input_stream is not None else io.BytesIO(request)
        self.output = bytearray()
        self.fail_writes = fail_writes
        self.timeouts: list[float] = []
        self.shutdown_calls = 0

    def makefile(self, mode: str, _buffering: int = -1):
        if mode != "rb":
            raise AssertionError(f"unexpected makefile mode: {mode}")
        return self.input

    def sendall(self, data: bytes) -> None:
        if self.fail_writes:
            raise BrokenPipeError("simulated disconnected uploader")
        self.output.extend(data)

    def settimeout(self, value: float) -> None:
        self.timeouts.append(value)

    def shutdown(self, _how: int) -> None:
        self.shutdown_calls += 1
        released = getattr(self.input, "released", None)
        if released is not None:
            released.set()


class DownloadConnection(MemoryConnection):
    """Record bounded response-body writes and optionally time them out."""

    def __init__(self, request: bytes, *, stall_body: bool = False):
        super().__init__(request)
        self.stall_body = stall_body
        self.headers_sent = False
        self.body_write_sizes: list[int] = []

    def sendall(self, data: bytes) -> None:
        if self.headers_sent:
            self.body_write_sizes.append(len(data))
            if self.stall_body:
                raise socket.timeout("simulated stalled download")
        super().sendall(data)
        if b"\r\n\r\n" in self.output:
            self.headers_sent = True


class RecordingEvents:
    def __init__(self):
        self.lines: list[str] = []

    def emit(self, line: str) -> None:
        self.lines.append(line)


def run_handler(
    handler_type,
    request: bytes = b"",
    *,
    input_stream=None,
    fail_writes: bool = False,
) -> tuple[bytes, MemoryConnection]:
    connection = MemoryConnection(
        request, input_stream=input_stream, fail_writes=fail_writes
    )
    handler_type(connection, ("memory", 0), types.SimpleNamespace())
    return bytes(connection.output), connection


class QuickshareReceiveTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-qshare-")
        self.root = Path(self.tempdir.name)
        self.output = self.root / "received"
        self.output.mkdir()

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def handler(
        self,
        *,
        max_upload_bytes: int = 64 * 1024,
        max_session_bytes: int = 64 * 1024,
        max_files_per_request: int = 8,
        max_files_per_session: int = 16,
        upload_timeout: float = 0.5,
        header_timeout: float = qshare.DEFAULT_HEADER_TIMEOUT,
        keep_alive: bool = True,
        events=None,
    ):
        output = self.output

        class Handler(qshare.RecvHandler):
            out_dir = output
            token = "test-token"
            done_event = threading.Event()
            upload_lock = threading.Lock()
            session_upload_count = 0
            session_upload_bytes = 0

            def log_message(self, _fmt, *_args):
                pass

        Handler.max_upload_bytes = max_upload_bytes
        Handler.max_session_bytes = max_session_bytes
        Handler.max_files_per_request = max_files_per_request
        Handler.max_files_per_session = max_files_per_session
        Handler.upload_timeout = upload_timeout
        Handler.header_timeout = header_timeout
        Handler.keep_alive = keep_alive
        Handler.events = events
        return Handler

    def upload(
        self,
        handler_type,
        files: list[tuple[str, bytes]],
        *,
        boundary: bytes = b"BrowserBoundary123",
    ) -> tuple[int, bytes]:
        body = multipart(boundary, files)
        response, _ = run_handler(handler_type, request_bytes(body, boundary))
        return response_status(response), response

    def assert_no_temporary_uploads(self) -> None:
        self.assertEqual(list(self.output.glob(".qshare-*")), [])

    def test_browser_multipart_preserves_binary_content(self) -> None:
        handler = self.handler()
        payload = b"a\x00b\r\n--BrowserBoundary123-not-a-delimiter\nlast"

        status, _ = self.upload(handler, [("sample.bin", payload)])

        self.assertEqual(status, 200)
        self.assertEqual((self.output / "sample.bin").read_bytes(), payload)
        self.assertEqual(handler.session_upload_count, 1)
        self.assertEqual(handler.session_upload_bytes, len(payload))

    def test_request_byte_and_file_limits_leave_no_files(self) -> None:
        boundary = b"LimitBoundary"
        two_files = multipart(boundary, [("a", b"1"), ("b", b"2")])

        size_handler = self.handler(max_upload_bytes=len(two_files) - 1)
        response, _ = run_handler(size_handler, request_bytes(two_files, boundary))
        self.assertEqual(response_status(response), 413)
        self.assertEqual(list(self.output.iterdir()), [])

        count_handler = self.handler(max_files_per_request=1)
        response, _ = run_handler(count_handler, request_bytes(two_files, boundary))
        self.assertEqual(response_status(response), 413)
        self.assertEqual(list(self.output.iterdir()), [])
        self.assert_no_temporary_uploads()

    def test_session_byte_and_file_limits_are_cumulative(self) -> None:
        byte_handler = self.handler(max_session_bytes=4)
        self.assertEqual(self.upload(byte_handler, [("first", b"1234")])[0], 200)
        self.assertEqual(self.upload(byte_handler, [("second", b"5")])[0], 413)
        self.assertEqual(byte_handler.session_upload_bytes, 4)
        self.assertFalse((self.output / "second").exists())

        for path in self.output.iterdir():
            path.unlink()

        count_handler = self.handler(max_files_per_session=1)
        self.assertEqual(self.upload(count_handler, [("first", b"1")])[0], 200)
        self.assertEqual(self.upload(count_handler, [("second", b"2")])[0], 429)
        self.assertEqual(count_handler.session_upload_count, 1)
        self.assertFalse((self.output / "second").exists())
        self.assert_no_temporary_uploads()

    def test_malformed_and_partial_bodies_are_rejected_and_cleaned(self) -> None:
        boundary = b"BrokenBoundary"
        handler = self.handler()
        truncated = multipart(boundary, [("partial.bin", b"partial")], close=False)

        response, _ = run_handler(handler, request_bytes(truncated, boundary))

        self.assertEqual(response_status(response), 400)
        self.assertEqual(list(self.output.iterdir()), [])
        self.assert_no_temporary_uploads()

    def test_stalled_body_hits_absolute_request_timeout_and_cleans_up(self) -> None:
        boundary = b"SlowBoundary"
        complete = multipart(boundary, [("slow.bin", b"abcdef")])
        handler = self.handler(upload_timeout=0.12)
        headers = request_bytes(complete, boundary)
        split = headers.index(b"\r\n\r\n") + 4
        partial = TimeoutInput(headers[: split + 8])
        response, _ = run_handler(handler, input_stream=partial)

        self.assertEqual(response_status(response), 408)
        self.assertEqual(list(self.output.iterdir()), [])
        self.assert_no_temporary_uploads()

    def test_partial_headers_are_closed_at_the_connection_deadline(self) -> None:
        handler = self.handler(upload_timeout=5, header_timeout=0.12)
        blocked = BlockingInput()
        connection = MemoryConnection(input_stream=blocked)
        started = time.monotonic()
        handler(connection, ("memory", 0), types.SimpleNamespace())
        elapsed = time.monotonic() - started

        self.assertLess(elapsed, 1.0)
        self.assertEqual(connection.shutdown_calls, 1)
        self.assertEqual(connection.timeouts, [0.12, 0.12])
        self.assertTrue(blocked.closed)

    def test_expect_100_continue_is_acknowledged_then_uploaded(self) -> None:
        boundary = b"ExpectBoundary"
        body = multipart(boundary, [("expect.bin", b"ok")])
        handler = self.handler()
        request = request_bytes(
            body, boundary, extra_headers=(b"Expect: 100-continue",)
        )
        response, _ = run_handler(handler, request)

        self.assertTrue(response.startswith(b"HTTP/1.1 100 Continue\r\n\r\n"))
        self.assertIn(b"HTTP/1.1 200 OK\r\n", response)
        self.assertEqual((self.output / "expect.bin").read_bytes(), b"ok")

    def test_traversal_is_sanitized_and_duplicate_names_are_unique(self) -> None:
        handler = self.handler()

        status, _ = self.upload(
            handler,
            [("../../same.txt", b"first"), ("same.txt", b"second")],
        )

        self.assertEqual(status, 200)
        self.assertEqual((self.output / "same.txt").read_bytes(), b"first")
        self.assertEqual((self.output / "same (1).txt").read_bytes(), b"second")
        self.assertFalse((self.root / "same.txt").exists())

    def test_concurrent_uploads_cannot_bypass_session_limit(self) -> None:
        handler = self.handler(max_session_bytes=5)
        barrier = threading.Barrier(3)
        statuses: list[int] = []
        failures: list[BaseException] = []

        def upload_one(index: int) -> None:
            try:
                boundary = f"Concurrent{index}".encode("ascii")
                body = multipart(boundary, [(f"{index}.bin", b"12345")])
                barrier.wait()
                response, _ = run_handler(handler, request_bytes(body, boundary))
                statuses.append(response_status(response))
            except BaseException as exc:
                failures.append(exc)

        threads = [threading.Thread(target=upload_one, args=(i,)) for i in range(2)]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join(2)

        self.assertEqual(failures, [])
        self.assertEqual(sorted(statuses), [200, 413])
        self.assertEqual(handler.session_upload_count, 1)
        self.assertEqual(handler.session_upload_bytes, 5)
        self.assertEqual(len(list(self.output.iterdir())), 1)
        self.assert_no_temporary_uploads()

    def test_one_shot_completion_survives_client_and_event_failures(self) -> None:
        class BrokenEvents:
            def emit(self, _line: str) -> None:
                raise OSError("event target disappeared")

        handler = self.handler(keep_alive=False, events=BrokenEvents())
        boundary = b"DisconnectBoundary"
        body = multipart(boundary, [("saved.bin", b"saved")])

        with redirect_stderr(io.StringIO()):
            run_handler(
                handler,
                request_bytes(body, boundary),
                fail_writes=True,
            )

        self.assertTrue(handler.done_event.is_set())
        self.assertEqual((self.output / "saved.bin").read_bytes(), b"saved")


class QuickshareSendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-qshare-send-")
        self.root = Path(self.tempdir.name)
        self.payload = self.root / "payload.bin"
        self.payload.write_bytes(b"x" * (qshare._DOWNLOAD_CHUNK_SIZE + 17))

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def handler(
        self,
        *,
        transfer_timeout: float = 0.5,
        header_timeout: float = qshare.DEFAULT_HEADER_TIMEOUT,
        events=None,
    ):
        payload = self.payload

        class Handler(qshare.SendHandler):
            file_path = payload
            file_name = payload.name
            token = "test-token"
            keep_alive = False
            done_event = threading.Event()

            def log_message(self, _fmt, *_args):
                pass

        Handler.transfer_timeout = transfer_timeout
        Handler.header_timeout = header_timeout
        Handler.events = events
        return Handler

    @staticmethod
    def request() -> bytes:
        return (
            b"GET /test-token/payload.bin HTTP/1.1\r\n"
            b"Host: qshare.test\r\nConnection: close\r\n\r\n"
        )

    def test_partial_headers_hit_absolute_deadline_without_completing(self) -> None:
        events = RecordingEvents()
        handler = self.handler(
            transfer_timeout=5, header_timeout=0.05, events=events
        )
        blocked = BlockingInput()
        connection = MemoryConnection(input_stream=blocked)

        started = time.monotonic()
        handler(connection, ("memory", 0), types.SimpleNamespace())
        elapsed = time.monotonic() - started

        self.assertLess(elapsed, 0.5)
        self.assertEqual(connection.shutdown_calls, 1)
        self.assertFalse(handler.done_event.is_set())
        self.assertEqual(events.lines, [])

    def test_stalled_download_can_retry_and_uses_bounded_chunks(self) -> None:
        events = RecordingEvents()
        handler = self.handler(events=events)
        stalled = DownloadConnection(self.request(), stall_body=True)

        handler(stalled, ("memory", 0), types.SimpleNamespace())

        self.assertFalse(handler.done_event.is_set())
        self.assertEqual(events.lines, [])
        self.assertEqual(stalled.body_write_sizes, [qshare._DOWNLOAD_CHUNK_SIZE])

        retry = DownloadConnection(self.request())
        handler(retry, ("memory", 0), types.SimpleNamespace())

        self.assertTrue(handler.done_event.is_set())
        self.assertEqual(
            events.lines,
            [f"TICK {self.payload.name}", "DONE"],
        )
        self.assertEqual(
            retry.body_write_sizes,
            [qshare._DOWNLOAD_CHUNK_SIZE, 17],
        )
        self.assertTrue(bytes(retry.output).endswith(self.payload.read_bytes()))


class QuickshareCliTests(unittest.TestCase):
    def test_upload_timeout_must_be_positive_and_finite(self) -> None:
        self.assertEqual(qshare._positive_float("0.5"), 0.5)
        for value in ("0", "-1", "nan", "inf", "-inf"):
            with self.subTest(value=value):
                with self.assertRaises(qshare.argparse.ArgumentTypeError):
                    qshare._positive_float(value)

    def test_upload_timeout_rejects_huge_finite_values(self) -> None:
        self.assertEqual(
            qshare._positive_float(str(qshare.MAX_UPLOAD_TIMEOUT)),
            qshare.MAX_UPLOAD_TIMEOUT,
        )
        for value in (str(qshare.MAX_UPLOAD_TIMEOUT + 1), "1e308"):
            with self.subTest(value=value):
                with self.assertRaises(qshare.argparse.ArgumentTypeError):
                    qshare._positive_float(value)


class QuickshareCloudflareTests(unittest.TestCase):
    def test_silent_startup_obeys_deadline_and_reaps_process(self) -> None:
        class SilentStdout:
            def __init__(self):
                self.released = threading.Event()

            def readline(self) -> str:
                self.released.wait(1)
                return ""

        class SilentProcess:
            def __init__(self):
                self.stdout = SilentStdout()
                self.terminated = False
                self.reaped = False

            def terminate(self) -> None:
                self.terminated = True
                self.stdout.released.set()

            def wait(self, timeout=None) -> int:
                self.reaped = True
                return -15

            def kill(self) -> None:
                self.stdout.released.set()

            def poll(self):
                return -15 if self.terminated else None

        proc = SilentProcess()
        started = time.monotonic()
        with (
            mock.patch.object(qshare.shutil, "which", return_value="/usr/bin/cloudflared"),
            mock.patch.object(qshare.subprocess, "Popen", return_value=proc),
            mock.patch.object(qshare, "CLOUDFLARED_STARTUP_TIMEOUT", 0.05),
            redirect_stdout(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            qshare.start_cloudflared(8080)
        elapsed = time.monotonic() - started

        self.assertLess(elapsed, 0.5)
        self.assertTrue(proc.terminated)
        self.assertTrue(proc.reaped)
        self.assertNotIn(proc, qshare._CHILD_PROCESSES)

    def test_success_uses_one_reader_that_continues_draining(self) -> None:
        class SequenceStdout:
            def __init__(self):
                self.lines = iter(
                    [
                        "https://example.trycloudflare.com\n",
                        "Registered tunnel connection\n",
                        "post-startup diagnostic\n",
                        "",
                    ]
                )
                self.calls = 0

            def readline(self) -> str:
                self.calls += 1
                return next(self.lines)

        class RunningProcess:
            def __init__(self):
                self.stdout = SequenceStdout()

            def poll(self):
                return None

            def terminate(self) -> None:
                pass

        proc = RunningProcess()
        created_threads = []
        real_thread = threading.Thread

        def recording_thread(*args, **kwargs):
            thread = real_thread(*args, **kwargs)
            created_threads.append(thread)
            return thread

        try:
            with (
                mock.patch.object(qshare.shutil, "which", return_value="/usr/bin/cloudflared"),
                mock.patch.object(qshare.subprocess, "Popen", return_value=proc),
                mock.patch.object(qshare.threading, "Thread", side_effect=recording_thread),
                redirect_stdout(io.StringIO()),
            ):
                returned, url = qshare.start_cloudflared(8080)

            created_threads[0].join(0.5)
            self.assertIs(returned, proc)
            self.assertEqual(url, "https://example.trycloudflare.com")
            self.assertEqual(len(created_threads), 1)
            self.assertEqual(proc.stdout.calls, 4)
        finally:
            qshare._CHILD_PROCESSES.discard(proc)


class QuickshareServerTests(unittest.TestCase):
    def test_saturation_rejects_without_thread_and_releases_capacity(self) -> None:
        class RecordingServer(qshare.BoundedThreadingHTTPServer):
            def __init__(self):
                self._connection_slots = threading.BoundedSemaphore(1)
                self.started = []
                self.completed = []
                self.closed = []

            def _start_request_thread(self, request, client_address) -> None:
                self.started.append((request, client_address))

            def _run_request_thread(self, request, client_address) -> None:
                self.completed.append((request, client_address))

            def shutdown_request(self, request) -> None:
                self.closed.append(request)

        server = RecordingServer()
        first = MemoryConnection()
        excess = MemoryConnection()
        after_release = MemoryConnection()

        server.process_request(first, ("first", 1))
        server.process_request(excess, ("excess", 2))

        self.assertEqual([request for request, _ in server.started], [first])
        self.assertTrue(excess.output.startswith(b"HTTP/1.1 503"))
        self.assertEqual(server.closed, [excess])

        server.process_request_thread(first, ("first", 1))
        server.process_request(after_release, ("after", 3))

        self.assertEqual(
            [request for request, _ in server.started],
            [first, after_release],
        )
        self.assertEqual([request for request, _ in server.completed], [first])
        server.process_request_thread(after_release, ("after", 3))


if __name__ == "__main__":
    unittest.main()
