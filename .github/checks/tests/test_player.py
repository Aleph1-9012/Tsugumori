"""Player integration checks using private IPC, silent audio, and offscreen Qt."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import wave

from test_mpv_ctl import BridgeProcess

SHELL = Path(__file__).parents[3] / "config/quickshell"
QML_TEST_RUNNER = "/usr/lib/qt6/bin/qmltestrunner"


class PlayerTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory(prefix="tsugumori-player-test-")
        self.addCleanup(temp.cleanup)
        self.path = Path(temp.name)

    @unittest.skipUnless(shutil.which("mpv"), "mpv is not installed")
    def test_real_mpv_completion_and_manual_stop(self) -> None:
        socket_path = self.path / "mpv.sock"
        process = subprocess.Popen([
            "mpv", "--no-config", "--load-scripts=no", "--ao=null", "--no-video",
            "--no-terminal", "--idle=yes", "--keep-open=no",
            "--reset-on-next-file=pause", "--input-ipc-server=" + str(socket_path),
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def stop_mpv() -> None:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)

        self.addCleanup(stop_mpv)
        bridge = BridgeProcess(socket_path)
        self.addCleanup(bridge.close)
        bridge.wait_for("ready", timeout=4)

        def fixture(name: str, samples: int) -> str:
            path = self.path / name
            with wave.open(str(path), "wb") as wav:
                wav.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
                wav.writeframes(b"\0\0" * samples)
            return str(path)

        entries = []
        for i in range(2):
            path = fixture(f"track-{i}.wav", 2000)
            bridge.send_batch([["loadfile", path, "replace"], ["set_property", "pause", False]])
            result = bridge.wait_for("track-ended", timeout=4)
            self.assertEqual(result["reason"], "eof")
            self.assertEqual(result["path"], path)
            self.assertIsInstance(result["entryId"], int)
            entries.append(result["entryId"])
        self.assertNotEqual(*entries)

        path = fixture("manual-stop.wav", 16000)
        bridge.send_batch([["loadfile", path, "replace"], ["set_property", "pause", True]])
        deadline = time.monotonic() + 4
        while True:
            state = bridge.wait_for("state", timeout=max(.01, deadline - time.monotonic()))
            if state["metadataPath"] == path and state["pause"]:
                break
        bridge.send_batch([["stop"]])
        self.assertEqual(bridge.wait_for("track-ended")["reason"], "stop")

    @unittest.skipUnless(Path(QML_TEST_RUNNER).is_file(), "qmltestrunner is not installed")
    def test_shell_auto_next_policy(self) -> None:
        # Use the actual shell methods without starting desktop services.
        source = (SHELL / "shell.qml").read_text()

        def function(name: str) -> str:
            body = source.split("    function " + name + "(", 1)[1]
            return "function " + name + "(" + body.split("\n    function ", 1)[0]

        qml = '''import QtQuick
import QtTest
TestCase {
    id: root
    name: "LocalAutoNext"
    property bool localMode: true
    property bool mpvReady: false
    property var lastMpvEndEntry: -1
    property var localTracks: ["one", "two", "three"]
    property string localTrackPath: "one"
    property int localTrackIndex: 0
    property int plays: 0
    property real mpPosition: 0
    property real mpLength: 10
    property bool mpPlaying: true
    property string mpTitle: ""
    property string mpArtist: ""
    property string mpAlbum: ""
    function flushMpvCommands() {}
    function playLocalTrack(path) {
        plays++; localTrackPath = path; localTrackIndex = localTracks.indexOf(path)
    }
    __FUNCTIONS__
    function ended(path, reason, entry) {
        handleMpvMessage(JSON.stringify({type: "track-ended", path: path, reason: reason, entryId: entry}))
    }
    function init() {
        localMode = true; lastMpvEndEntry = -1; plays = 0
        localTracks = ["one", "two", "three"]; localTrackPath = "one"; localTrackIndex = 0
    }
    function test_eof_advances_and_wraps() {
        ended("one", "eof", 0); compare(localTrackPath, "two")
        ended("two", "eof", 1); compare(localTrackPath, "three")
        ended("three", "eof", 2); compare(localTrackPath, "one"); compare(plays, 3)
    }
    function test_other_reasons_and_invalid_events_ignored() {
        ["stop", "quit", "error", "redirect"].forEach(function(r) { ended("one", r, 0) })
        ended("old", "eof", 0); ended("", "eof", 0);
        [null, -1, "0", 0.5].forEach(function(id) { ended("one", "eof", id) })
        compare(plays, 0)
        handleMpvMessage("not json"); compare(plays, 0)
    }
    function test_external_playback_is_not_interrupted() {
        localMode = false; ended("one", "eof", 0); compare(plays, 0)
    }
    function test_single_track_and_duplicate_completion() {
        localTracks = ["one"]
        ended("one", "eof", 0); ended("one", "eof", 0); compare(plays, 1)
        ended("one", "eof", 1); compare(plays, 2)
    }
    function test_empty_library_is_safe() {
        localTracks = []; ended("one", "eof", 0); compare(plays, 0)
    }
    function test_idle_snapshots_do_not_advance() {
        handleMpvMessage(JSON.stringify({type: "state", path: "one", eofReached: true, idleActive: true}))
        compare(plays, 0)
    }
    function test_reconnect_resets_entry_ids() {
        lastMpvEndEntry = 0
        handleMpvMessage('{"type":"ready"}')
        ended("one", "eof", 0); compare(plays, 1)
    }
}'''.replace("__FUNCTIONS__", "\n".join(
            function(name) for name in ("handleMpvMessage", "nextLocalTrack", "localTag")))
        test_file = self.path / "tst_AutoNext.qml"
        test_file.write_text(qml)
        result = subprocess.run([QML_TEST_RUNNER, "-input", str(test_file)],
                                env={**os.environ, "QT_QPA_PLATFORM": "offscreen",
                                     "QT_QUICK_BACKEND": "software"},
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
