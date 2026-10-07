"""Notification history, menu power confirmation, and audio parsing tests."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO_ROOT = Path(__file__).parents[3]
QUICKSHELL = REPO_ROOT / "config/quickshell"
NOTIFICATIONS_QML = QUICKSHELL / "widgets/Notifications.qml"
MENU_QML = QUICKSHELL / "widgets/Menu.qml"
CONTROLCENTER_QML = QUICKSHELL / "widgets/ControlCenter.qml"
QML_TEST_RUNNER = "/usr/lib/qt6/bin/qmltestrunner"

QML_ENV = {**os.environ, "QT_QPA_PLATFORM": "offscreen",
           "QT_QUICK_BACKEND": "software"}


def extract_functions(source: str, *names: str) -> str:
    methods = []
    for name in names:
        match = re.search(r"^    function " + name + r"\(.*?^    }$", source,
                          flags=re.MULTILINE | re.DOTALL)
        assert match is not None, f"missing function {name}"
        methods.append(match[0])
    return "\n".join(methods)


def run_qml_case(body: str, name: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory(prefix="tsugumori-qml-test-") as temp:
        test_file = Path(temp) / f"tst_{name}.qml"
        test_file.write_text(body, encoding="utf-8")
        return subprocess.run(
            [QML_TEST_RUNNER, "-input", str(test_file)],
            env=QML_ENV, capture_output=True, text=True, timeout=15)


NOTIFICATION_METHODS = extract_functions(
    NOTIFICATIONS_QML.read_text(encoding="utf-8"),
    "record", "watchUpdates", "popupTimeout", "entryIndex", "removeEntry",
    "dismiss", "activate", "clearAll")

FAKES = """
    function fakeNotification(properties) {
        var n = {
            id: 0, tracked: true, resident: false,
            summary: "", body: "", appName: "", appIcon: "",
            urgency: 1, expireTimeout: -1, desktopEntry: "",
            hints: ({}), image: "", actions: [],
            invoked: [], dismissed: false, expired: false
        }
        for (var key in properties) n[key] = properties[key]
        n.actions = (n.actions || []).map(function(action) {
            var identifier = action.identifier || ""
            var captured = n
            return {
                identifier: identifier,
                text: action.text || identifier,
                invoke: function() {
                    captured.invoked.push(identifier)
                    if (!captured.resident) captured.tracked = false
                }
            }
        })
        n.dismiss = function() { n.tracked = false; n.dismissed = true }
        n.expire = function() { n.tracked = false; n.expired = true }
        return n
    }
"""


def notification_case(tests: str) -> str:
    return """import QtQuick
import QtTest
TestCase {
    id: root
    name: "NotificationHistory"
    property var history: []
    readonly property int defaultTimeout: 5000
    readonly property int criticalTimeout: 10000

    Component {
        id: liveNotification
        QtObject {
            property int id: 0
            property bool tracked: true
            property bool resident: false
            property string summary: ""
            property string body: ""
            property string appName: ""
            property string appIcon: ""
            property int urgency: 1
            property int expireTimeout: -1
            property string desktopEntry: ""
            property var hints: ({})
            property string image: ""
            property var actions: []
            property var invoked: []
            property bool dismissed: false
            property bool expired: false
            function dismiss() { tracked = false; dismissed = true }
            function expire() { tracked = false; expired = true }
        }
    }
""" + FAKES + NOTIFICATION_METHODS + tests + """
}
"""


@unittest.skipUnless(Path(QML_TEST_RUNNER).is_file(),
                     "qmltestrunner is not installed")
class NotificationHistoryTests(unittest.TestCase):
    def run_case(self, tests: str) -> str:
        result = run_qml_case(notification_case(tests), "NotificationHistory")
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        return output

    def test_dismiss_removes_only_that_id_and_never_invokes(self) -> None:
        self.run_case("""
    function test_dismiss() {
        var first = fakeNotification({id: 1, actions: [{identifier: "default"}]})
        var second = fakeNotification({id: 2})
        record(first); record(second)
        dismiss(1)
        compare(history.length, 1)
        compare(history[0].id, 2)
        compare(first.invoked, [])
        verify(first.dismissed)
        verify(!second.dismissed)
        dismiss(999)
        compare(history.length, 1)
    }
""")

    def test_dismiss_hits_the_right_entry_after_a_newer_record(self) -> None:
        self.run_case("""
    function test_dismiss_older() {
        var old = fakeNotification({id: 1})
        var fresh = fakeNotification({id: 2})
        record(old); record(fresh)
        dismiss(1)
        verify(old.dismissed)
        compare(history.length, 1)
        compare(history[0].id, 2)
    }
""")

    def test_activate_invokes_only_the_default_action(self) -> None:
        self.run_case("""
    function test_activate_default() {
        var n = fakeNotification({id: 5, actions: [
            {identifier: "other"}, {identifier: "default"}, {identifier: "third"}]})
        record(n)
        activate(5)
        compare(n.invoked, ["default"])
        compare(history.length, 0)
        verify(!n.dismissed)  // non-resident invoke already untracked it
    }
""")

    def test_activate_dismisses_resident_notifications(self) -> None:
        self.run_case("""
    function test_activate_resident() {
        var n = fakeNotification({id: 6, resident: true,
            actions: [{identifier: "default"}]})
        record(n)
        activate(6)
        compare(n.invoked, ["default"])
        verify(n.dismissed)
    }
""")

    def test_activate_without_default_action_just_dismisses(self) -> None:
        self.run_case("""
    function test_activate_no_default() {
        var n = fakeNotification({id: 7, actions: [{identifier: "reply"}]})
        record(n)
        activate(7)
        compare(n.invoked, [])
        verify(n.dismissed)
        compare(history.length, 0)
    }
""")

    def test_untracked_ref_gets_no_calls(self) -> None:
        self.run_case("""
    function test_untracked() {
        var n = fakeNotification({id: 8, tracked: false,
            actions: [{identifier: "default"}]})
        record(n)
        dismiss(8)
        verify(!n.dismissed)
        record(n)
        activate(8)
        compare(n.invoked, [])
        verify(!n.dismissed)
    }
""")

    def test_record_reads_hints_category_and_dedupes_and_caps(self) -> None:
        self.run_case("""
    function test_record() {
        var n = fakeNotification({id: 1, hints: {category: "email"}, image: "file:///x.png"})
        record(n)
        compare(history[0].category, "email")
        compare(history[0].hasImage, true)
        for (var i = 2; i <= 60; i++) record(fakeNotification({id: i}))
        compare(history.length, 50)
        compare(history[0].id, 60)
    }
""")

    def test_watched_updates_move_the_entry_to_the_front(self) -> None:
        self.run_case("""
    function test_watched_update() {
        var a = liveNotification.createObject(root, {id: 1, summary: "a"})
        var b = liveNotification.createObject(root, {id: 2})
        record(a); watchUpdates(a)
        record(b); watchUpdates(b)
        a.summary = "a2"
        a.body = "body2"
        compare(history.length, 2)
        compare(history[0].id, 1)
        compare(history[0].summary, "a2")
        compare(history[0].body, "body2")
    }
""")

    def test_watched_update_reads_new_hints(self) -> None:
        self.run_case("""
    function test_watched_hints() {
        var n = liveNotification.createObject(root, {id: 1})
        record(n); watchUpdates(n)
        n.hints = {category: "email"}
        compare(history[0].category, "email")
    }
""")

    def test_dismissed_entry_is_not_resurrected_by_updates(self) -> None:
        self.run_case("""
    function test_no_resurrect() {
        var n = liveNotification.createObject(root, {id: 1, summary: "a"})
        record(n); watchUpdates(n)
        dismiss(1)
        compare(history.length, 0)
        n.summary = "late update"
        compare(history.length, 0)
    }
""")

    def test_popup_timeout_never_expires_on_zero(self) -> None:
        self.run_case("""
    function test_popup_timeout() {
        compare(popupTimeout(fakeNotification({expireTimeout: 0})), -1)
        compare(popupTimeout(fakeNotification({expireTimeout: -1})), 5000)
        compare(popupTimeout(fakeNotification({expireTimeout: -1, urgency: 2})), 10000)
        compare(popupTimeout(fakeNotification({expireTimeout: 3000})), 3000)
        compare(popupTimeout(null), 5000)
    }
""")

    def test_clear_all_dismisses_only_tracked_refs(self) -> None:
        self.run_case("""
    function test_clear_all() {
        var tracked = fakeNotification({id: 1})
        var untracked = fakeNotification({id: 2, tracked: false})
        record(tracked); record(untracked)
        clearAll()
        compare(history.length, 0)
        verify(tracked.dismissed)
        verify(!untracked.dismissed)
    }
""")


class NotificationStaticTests(unittest.TestCase):
    def test_server_declares_markup_without_images(self) -> None:
        source = NOTIFICATIONS_QML.read_text(encoding="utf-8")
        self.assertIn("bodyMarkupSupported: true", source)
        self.assertIn("bodyImagesSupported: false", source)
        self.assertNotIn("dismissAt", source)
        self.assertNotRegex(source, r"\bn\.(category|hasImage)\b")

    def test_control_center_has_no_ipc_polling(self) -> None:
        source = CONTROLCENTER_QML.read_text(encoding="utf-8")
        self.assertNotIn("qs ipc call notifs", source)
        self.assertNotIn("expandedNotifIdx", source)

    def test_every_notification_text_declares_a_format(self) -> None:
        source = NOTIFICATIONS_QML.read_text(encoding="utf-8")
        for match in re.finditer(r"Text\s*{", source):
            depth, end = 0, match.end() - 1
            while end < len(source):
                if source[end] == "{":
                    depth += 1
                elif source[end] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                end += 1
            block = source[match.start():end]
            if re.search(r"text:\s*[^\n]*\b(notif\.notification|modelData)\b", block):
                self.assertIn("textFormat", block,
                              "Text block without textFormat: " + block[:120])


MENU_CHOOSE_POWER = extract_functions(
    MENU_QML.read_text(encoding="utf-8"), "choosePower")


@unittest.skipUnless(Path(QML_TEST_RUNNER).is_file(),
                     "qmltestrunner is not installed")
class MenuPowerTests(unittest.TestCase):
    def run_case(self, tests: str) -> str:
        body = """import QtQuick
import QtTest
TestCase {
    id: root
    name: "MenuPower"
    property string powerConfirmation: ""
    property var launches: []
    function launch(cmd) { launches.push(cmd) }
""" + MENU_CHOOSE_POWER + tests + """
}
"""
        result = run_qml_case(body, "MenuPower")
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        return output

    def test_two_press_poweroff(self) -> None:
        self.run_case("""
    function test_poweroff() {
        choosePower("poweroff")
        compare(powerConfirmation, "poweroff")
        compare(launches, [])
        choosePower("poweroff")
        compare(powerConfirmation, "")
        compare(launches, ["systemctl poweroff"])
    }
""")

    def test_two_press_reboot(self) -> None:
        self.run_case("""
    function test_reboot() {
        choosePower("reboot"); choosePower("reboot")
        compare(launches, ["systemctl reboot"])
    }
""")

    def test_other_button_cancels(self) -> None:
        self.run_case("""
    function test_cancel() {
        choosePower("poweroff")
        choosePower("reboot")
        compare(powerConfirmation, "")
        compare(launches, [])
        choosePower("poweroff")
        compare(launches, [])
        choosePower("logout")
        compare(powerConfirmation, "poweroff")
    }
""")


AUDIO_PARSER = extract_functions(
    CONTROLCENTER_QML.read_text(encoding="utf-8"), "parseAudioState")


@unittest.skipUnless(Path(QML_TEST_RUNNER).is_file(),
                     "qmltestrunner is not installed")
class AudioParseTests(unittest.TestCase):
    def run_case(self, tests: str) -> str:
        body = """import QtQuick
import QtTest
TestCase {
    id: root
    name: "AudioParse"
""" + AUDIO_PARSER + tests + """
}
"""
        result = run_qml_case(body, "AudioParse")
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        return output

    def test_normal_two_sink_output(self) -> None:
        self.run_case("""
    function test_normal() {
        var state = parseAudioState(
            "DEFAULT:sink-b\\n" +
            '[{"name":"sink-a","description":"Speakers","mute":false,' +
            ' "volume":{"front-left":{"value_percent":"40%"}}},' +
            '{"name":"sink-b","description":"Headphones","mute":false,' +
            ' "volume":{"front-left":{"value_percent":"66%"},"front-right":{"value_percent":"66%"}}}]')
        compare(state.defaultSink, "sink-b")
        compare(state.volume, 66)
        compare(state.muted, false)
        compare(state.sinks, [
            {name: "sink-a", description: "Speakers", isDefault: false},
            {name: "sink-b", description: "Headphones", isDefault: true}])
    }
""")

    def test_muted_and_missing_description(self) -> None:
        self.run_case("""
    function test_muted() {
        var state = parseAudioState(
            "DEFAULT:sink-a\\n" +
            '[{"name":"sink-a","mute":true,"volume":{"front-left":{"value_percent":"10%"}}}]')
        compare(state.muted, true)
        compare(state.sinks[0].description, "sink-a")
    }
""")

    def test_null_channel_does_not_throw(self) -> None:
        self.run_case("""
    function test_null_channel() {
        var state = parseAudioState(
            "DEFAULT:sink-a\\n" +
            '[{"name":"sink-a","mute":false,' +
            ' "volume":{"front-left":null}}]')
        compare(state.volume, -1)
        compare(state.sinks.length, 1)
    }
""")

    def test_empty_and_malformed_output(self) -> None:
        self.run_case("""
    function test_malformed() {
        var empty = {defaultSink: "", volume: -1, muted: false, sinks: []}
        compare(parseAudioState(""), empty)
        compare(parseAudioState("DEFAULT:sink-a"), empty)
        compare(parseAudioState("no header\\n[]"), empty)
        compare(parseAudioState("DEFAULT:sink-a\\nnot json"), empty)
        compare(parseAudioState("DEFAULT:sink-a\\n[]"),
            {defaultSink: "sink-a", volume: -1, muted: false, sinks: []})
    }
""")


class AudioStaticTests(unittest.TestCase):
    def test_dispatch_uses_argv_not_a_shell_string(self) -> None:
        source = CONTROLCENTER_QML.read_text(encoding="utf-8")
        self.assertNotIn('cmd = "', source)
        self.assertNotIn("set-default-sink '", source)


if __name__ == "__main__":
    unittest.main()
