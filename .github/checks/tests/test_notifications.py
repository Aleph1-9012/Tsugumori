"""Notification history and menu power action tests."""
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
    "record", "popupTimeout", "entryIndex", "removeEntry",
    "dismiss", "activate", "clearAll")

NOTIFICATION_OBSERVERS = re.search(
    r"^    Instantiator \{.*?^    }$", NOTIFICATIONS_QML.read_text(),
    flags=re.MULTILINE | re.DOTALL)[0]

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
import QtQml.Models
TestCase {
    id: root
    name: "NotificationHistory"
    property var history: []
    property var tracked: []
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
""" + FAKES + NOTIFICATION_METHODS + NOTIFICATION_OBSERVERS + tests + """
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
        record(a); record(b)
        tracked = [a, b]
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
        record(n); tracked = [n]
        n.hints = {category: "email"}
        compare(history[0].category, "email")
    }
""")

    def test_dismissed_entry_is_not_resurrected_by_updates(self) -> None:
        self.run_case("""
    function test_no_resurrect() {
        var n = liveNotification.createObject(root, {id: 1, summary: "a"})
        record(n); tracked = [n]
        dismiss(1)
        compare(history.length, 0)
        n.summary = "late update"
        compare(history.length, 0)
    }
""")

    def test_update_connections_end_with_their_owner_or_tracked_entry(self) -> None:
        self.run_case("""
    Component {
        id: observerOwner
        Item {
            id: owner
            property var tracked: []
            property int updates: 0
            function entryIndex(id) { return 0 }
            function record(notification) { updates++ }
""" + NOTIFICATION_OBSERVERS.replace("root.", "owner.") + """
        }
    }
    function test_observer_lifetime() {
        failOnWarning(/.*/)
        var n = liveNotification.createObject(root, {id: 1})
        var owner = observerOwner.createObject(root, {tracked: [n]})
        n.summary = "first"
        compare(owner.updates, 1)
        owner.tracked = []
        n.summary = "untracked"
        compare(owner.updates, 1)
        owner.tracked = [n]
        owner.destroy()
        wait(0)
        n.summary = "after reload"
        wait(0)
    }
""")

    def test_action_can_destroy_its_popup_without_accessing_it_afterward(self) -> None:
        source = NOTIFICATIONS_QML.read_text()
        click = re.search(r"id: actMouse.*?onClicked: \{(.*?)\n\s*}", source, re.DOTALL)[1]
        result = run_qml_case('''import QtQuick
import QtTest
TestCase {
    id: test
    name: "NotificationActionLifetime"
    width: 100; height: 100
    visible: true
    when: windowShown
    property int invocations: 0
    QtObject {
        id: action
        function invoke() {
            test.compare(popups.itemAt(0).state, "closing")
            test.invocations++
            popups.model = 0
        }
    }
    Repeater {
        id: popups
        model: []
        delegate: Item {
            id: notif
            width: 100; height: 100
            required property var modelData
            MouseArea {
                anchors.fill: parent
                objectName: "notificationAction"
                onClicked: {''' + click + '''
                }
            }
        }
    }
    function test_invoke() {
        failOnWarning(/.*/)
        popups.model = [action]
        mouseClick(findChild(test, "notificationAction"), 10, 10)
        compare(invocations, 1)
        compare(popups.count, 0)
    }
}
''', "NotificationActionLifetime")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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


if __name__ == "__main__":
    unittest.main()
