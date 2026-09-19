import QtQuick
import QtTest

// Visual-only tests. No real wallpaper selection, process execution, or layers.
Item {
    id: scene
    width: 1280; height: 800
    property var visuals
    readonly property var motion: visuals ? visuals.motion : null
    readonly property var field: visuals ? visuals.field : null
    readonly property var corners: visuals ? visuals.corners : null
    readonly property var registration: visuals ? visuals.registration : null
    TestCase {
        id: tests
        name: "PickerPhaseTransition"
        when: windowShown
        SignalSpy { id: closed; target: motion; signalName: "closed" }
        SignalSpy { id: progressSteps; target: motion; signalName: "progressChanged" }
        SignalSpy { id: fieldPaints; target: field; signalName: "paintCountChanged" }
        function initTestCase() {
            // Test the actual inline visuals without loading Quickshell's shell,
            // monitor lookup, wallpaper process, or exclusive keyboard layer.
            var widgets = Qt.resolvedUrl("../../../../config/quickshell/widgets/").toString();
            var request = new XMLHttpRequest();
            request.open("GET", widgets + "WallpaperPicker.qml", false);
            request.send();
            var source = request.responseText;
            var start = source.indexOf("    component PickerMotion:");
            verify(start >= 0, "Picker inline components must exist in WallpaperPicker.qml");
            var definitions = source.slice(start, source.lastIndexOf("\n}"));
            var imports = 'pragma ComponentBehavior: Bound\nimport QtQuick\nimport QtQuick.Window\n'
                + 'import QtQuick.Controls\nimport QtQuick.Layouts\n'
                + 'import "' + widgets + 'lockscreen"\n'
                + 'import "' + widgets + 'lockscreen/PhaseArt.js" as Art\n';
            scene.visuals = Qt.createQmlObject(imports + `Item {
                anchors.fill: parent
                property alias motion: timeline
                property alias field: backdrop
                property alias corners: decorations
                property alias registration: ticks
                PickerMotion { id: timeline }
                PickerBackdrop {
                    id: backdrop; anchors.fill: parent; progress: timeline.progress
                    vertexShaderUrl: "${widgets}lockscreen/shaders/lines.vert.qsb"
                    fragmentShaderUrl: "${widgets}lockscreen/shaders/lines.frag.qsb"
                }
                PickerCorners {
                    id: decorations; anchors.fill: parent
                    progress: timeline.progress; live: timeline.inputReady; hiding: timeline.closing
                    clockText: "18:24:09"; monitorName: "DP-1"
                }
                Rectangle {
                    anchors.centerIn: parent; width: 800; height: 500
                    color: "#0f0d0a"; border.color: "#e8e8e8"; border.width: 2
                    opacity: Art.ramp(timeline.progress, .22, .73)
                    Text { anchors.centerIn: parent; text: "WALLPAPER PREVIEW"; color: "#e8e8e8"; font.family: "JetBrains Mono" }
                }
                PickerRegistration {
                    id: ticks; anchors.centerIn: parent; width: 800; height: 500
                    progress: timeline.progress
                }
                ${definitions}
            }`, scene, "PickerVisualTest.qml");
            verify(scene.visuals !== null);
        }
        function init() {
            motion.close(); tryCompare(motion, "finished", true, 1600);
            motion.started = false; motion.opening = false; motion.closing = false; motion.finished = false; motion.progress = 0;
            scene.width = 1280; scene.height = 800;
            closed.clear(); wait(120);
        }
        function test_open_close_and_no_background_repaint() {
            verify(!motion.inputReady);
            scene.width = 2560; scene.height = 1600; wait(200);
            fieldPaints.clear(); progressSteps.clear();
            motion.open(); motion.open();
            verify(motion.opening);
            tryCompare(motion, "inputReady", true, 2400);
            compare(motion.progress, 1); verify(!motion.opening);
            // Keep timing diagnostics, but do not use runner load as an FPS test.
            verify(progressSteps.count > 1, "The transition must visit intermediate states");
            console.log("1450ms native timeline updates:", progressSteps.count);
            compare(fieldPaints.count, 0);
            verify(!registration.visible);
            var count = progressSteps.count;
            wait(180); compare(progressSteps.count, count); compare(fieldPaints.count, 0);
            motion.close(); motion.close();
            verify(motion.closing); verify(!motion.inputReady);
            tryCompare(motion, "finished", true, 1600);
            compare(motion.progress, 0); compare(closed.count, 1); compare(fieldPaints.count, 0);
            motion.open(); wait(80); compare(motion.progress, 0);
        }
        function test_escape_during_entrance_reverses_current_progress() {
            motion.open(); wait(400);
            verify(motion.progress > 0 && motion.progress < 1);
            var before = motion.progress;
            motion.close();
            verify(!motion.opening); verify(motion.closing); verify(!motion.inputReady);
            fuzzyCompare(motion.progress, before, .025);
            tryCompare(motion, "finished", true, 1200);
            compare(closed.count, 1); compare(motion.progress, 0);
        }
        function test_close_before_open_is_safe() {
            motion.close(); motion.open();
            tryCompare(motion, "finished", true, 400);
            compare(motion.progress, 0); compare(closed.count, 1); verify(!motion.inputReady);
        }
        function test_shader_urls_are_real_files() {
            verify(field.vertexShaderUrl.toString().startsWith("file:///"));
            verify(field.fragmentShaderUrl.toString().startsWith("file:///"));
            verify(field.vertexShaderUrl.toString().endsWith("/lockscreen/shaders/lines.vert.qsb"));
            verify(field.fragmentShaderUrl.toString().endsWith("/lockscreen/shaders/lines.frag.qsb"));
        }
        function test_live_corners_follow_picker_lifecycle() {
            motion.open(); tryCompare(motion, "inputReady", true, 2400);
            var items = [];
            for (var i = 0; i < 4; i++) {
                var item = findChild(corners, "pickerCorner" + i);
                verify(item !== null); verify(item.animating); items.push(item);
            }
            compare(items[3].label, "SELECT");
            tryVerify(function() { return items.every(function(c) { return c.travel > 0; }); }, 2000);
            corners.visible = false;
            items.forEach(function(c) { verify(!c.animating); });
            corners.visible = true;
            items.forEach(function(c) { verify(c.animating); });
            motion.close();
            items.forEach(function(c) { verify(!c.animating); compare(c.travel, 0); });
            compare(items[3].label, "CLOSING");
            tryCompare(motion, "finished", true, 1600);
        }
        function test_registration_and_render() {
            motion.progress = .4;
            verify(registration.visible); verify(registration.opacity > .5);
            wait(100); var entering = grabImage(scene);
            motion.progress = 1;
            verify(!registration.visible);
            wait(100); var open = grabImage(scene);
            verify(!entering.equals(open), "The completed panel must differ from its entrance");
            motion.progress = .15;
            wait(100); var leaving = grabImage(scene);
            verify(!leaving.equals(open), "The closing panel must change");
            motion.progress = 0;
            wait(100);
            var frame = grabImage(scene);
            verify(!frame.equals(open), "The closed panel must disappear");
            compare(frame.red(100, 100), 8); compare(frame.green(100, 100), 8); compare(frame.blue(100, 100), 8);
        }
    }
}
