"""Control Center refresh batching and native service presentation contracts."""
from pathlib import Path
import unittest

from test_notifications import extract_functions, run_qml_case, QML_TEST_RUNNER

SHELL = Path(__file__).parents[3] / "config/quickshell"


@unittest.skipUnless(Path(QML_TEST_RUNNER).is_file(), "qmltestrunner is not installed")
class ControlCenterTests(unittest.TestCase):
    def check(self, qml: str) -> None:
        result = run_qml_case(qml, "ControlCenter")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_refreshes_are_batched_relevant_and_preserve_unchanged_rows(self) -> None:
        methods = extract_functions((SHELL / "components/controlcenter/ControlCenterView.qml").read_text(),
                                    "requestRefresh", "flushRefresh", "refresh")
        self.check('''import QtQuick
import QtTest
TestCase {
    id: view
    name: "ControlCenterRefresh"
    property bool active: true
    property bool expanded: true
    property bool refreshPending: false
    property string displaySlot: ""
    property string displaySub: ""
    property string detailTitle: ""
    property string detailStatus: ""
    property bool detailOn: false
    QtObject {
        id: controller
        property string slot: "right"
        property string sub: "history"
        property int calls: 0
        property var entries: [{key:"notif:1", label:"First"}, {key:"notif:2", label:"Second"}]
        function actList() { calls++; return entries }
        function detailH3() { return "History" }
        function detailStatus() { return "2 notifications" }
        function detailOn() { return true }
    }
    ListModel { id: actionModel; dynamicRoles: true }
    SignalSpy { id: changed; target: actionModel; signalName: "dataChanged" }
''' + methods + '''
    function test_updates() {
        for (var i = 0; i < 30; ++i) requestRefresh("right", "history")
        compare(controller.calls, 0)
        tryCompare(controller, "calls", 1)
        compare(actionModel.count, 2)
        changed.clear()
        controller.entries = [{key:"notif:1", label:"First"}, {key:"notif:2", label:"Second"}]
        requestRefresh("right", "history")
        tryCompare(controller, "calls", 2)
        compare(changed.count, 0)

        requestRefresh("bottom", "volume")
        wait(20)
        compare(controller.calls, 2)
        active = false
        requestRefresh()
        wait(20)
        compare(controller.calls, 2)

        controller.entries = [{key:"notif:2", label:"Updated"}]
        active = true
        requestRefresh()
        tryCompare(controller, "calls", 3)
        compare(actionModel.count, 1)
        compare(actionModel.get(0).entry.key, "notif:2")
        compare(actionModel.get(0).entry.label, "Updated")
    }
}
''')

    def test_native_rows_and_latest_queued_volume(self) -> None:
        methods = extract_functions((SHELL / "widgets/ControlCenter.qml").read_text(),
                                    "audioRows", "bluetoothRows", "setAudioPercent", "flushVolume")
        self.check('''import QtQuick
import QtTest
TestCase {
    id: root
    name: "NativeControlState"
    property bool audioReady: true
    property int pendingAudioPercent: -1
    property var defaultAudioNode: ({audio:{volume:0.5}})
    QtObject { id: volumeWriteTimer; property bool running: false; function start() { running = true } }
''' + methods + '''
    function test_audio() {
        var rows = audioRows([
            {name:"speakers", description:"Speakers", isSink:true, isStream:false, audio:{}},
            {name:"headphones", description:"", isSink:true, isStream:false, audio:{}},
            {name:"app", isSink:true, isStream:true, audio:{}},
            {name:"microphone", isSink:false, isStream:false, audio:{}},
            {name:"video", isSink:true, isStream:false, audio:null}
        ], "headphones")
        compare(rows, [{name:"speakers", description:"Speakers", isDefault:false},
                       {name:"headphones", description:"headphones", isDefault:true}])
        setAudioPercent(30)
        setAudioPercent(73)
        compare(defaultAudioNode.audio.volume, 0.5)
        flushVolume()
        compare(defaultAudioNode.audio.volume, 0.73)
        compare(pendingAudioPercent, -1)
        setAudioPercent(999)
        flushVolume()
        compare(defaultAudioNode.audio.volume, 1)
        audioReady = false
        setAudioPercent(0)
        compare(pendingAudioPercent, -1)
    }
    function test_bluetooth() {
        var rows = bluetoothRows([
            {address:"3", name:"Discovered", connected:false, paired:false, trusted:false},
            {address:"2", name:"Paired", connected:false, paired:true, trusted:true},
            {address:"1", name:"Speaker | O'Brien", connected:true, paired:true, trusted:true}
        ])
        compare(rows.map(function(row) { return row.mac }), ["1", "2", "3"])
        compare(rows[0].name, "Speaker | O'Brien")
    }
}
''')

    def test_panel_keeps_a_monitor_when_cursor_lookup_is_unavailable(self) -> None:
        source = (SHELL / "widgets/ControlCenter.qml").read_text()
        selection = source.split("    // ── Active screen detection ──", 1)[1].split(
            "    onActiveMonitorChanged:", 1)[0].replace("Quickshell.screens", "screens")
        self.check('''import QtQuick
import QtTest
TestCase {
    id: root
    name: "ControlCenterMonitor"
    property var screens: [{name:"eDP-1"}, {name:"DP-1"}]
''' + selection + '''
    function test_lookup_and_hotplug() {
        compare(activeMonitor, "eDP-1")
        requestedMonitor = "DP-1"
        compare(activeMonitor, "DP-1")
        requestedMonitor = "missing-output"
        compare(activeMonitor, "eDP-1")
        requestedMonitor = "DP-1"
        screens = [{name:"eDP-1"}]
        compare(activeMonitor, "eDP-1")
        screens = []
        compare(activeMonitor, "")
        screens = [{name:"HDMI-A-1"}]
        compare(activeMonitor, "HDMI-A-1")
    }
}
''')


class ControlCenterStaticTests(unittest.TestCase):
    def test_dispatch_uses_argv_not_a_shell_string(self) -> None:
        source = (SHELL / "widgets/ControlCenter.qml").read_text(encoding="utf-8")
        self.assertNotIn('cmd = "', source)
