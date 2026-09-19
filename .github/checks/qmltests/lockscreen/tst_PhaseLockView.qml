import QtQuick
import QtTest
import "../../../../config/quickshell/widgets/lockscreen"
import "../../../../config/quickshell/widgets/lockscreen/PhaseArt.js" as Art

// Run with QT_QPA_PLATFORM=offscreen. This never loads WlSessionLock or PAM.
Item {
    width: 1280; height: 800
    PhaseLockView {
        id: view
        anchors.fill: parent
        progress: 1
        userName: "testPilot"
        now: new Date(2026, 8, 14, 0, 14)
        onPasswordEdited: value => password = value
        onCleared: password = ""
    }
    TestCase {
        id: testCase
        name: "PhaseLockVisuals"
        when: windowShown
        SignalSpy { id: submitted; target: view; signalName: "submitted" }
        SignalSpy { id: fieldPaints; target: testCase.findChild(view, "phaseField"); signalName: "paintCountChanged" }
        SignalSpy { id: progressSteps; target: view; signalName: "progressChanged" }
        NumberAnimation { id: entry; target: view; property: "progress"; from: 0; to: 1; duration: 1450 }
        function init() {
            view.parent.width = 1280; view.parent.height = 800;
            view.progress = 1; view.password = ""; view.inputReady = true;
            view.pending = false; view.error = false; view.hiding = false;
            submitted.clear(); wait(180);
        }
        function test_center_and_square() {
            var panel = findChild(view, "loginPanel"), glyph = findChild(view, "compoundGlyph");
            compare(panel.width, 408);
            fuzzyCompare(panel.scale, 1.3225, .0001);
            fuzzyCompare(panel.width * panel.scale, 539.58, .001);
            verify(Math.abs(panel.x * 2 + panel.width - view.width) <= 1);
            verify(Math.abs(panel.y * 2 + panel.height - view.height) <= 1);
            compare(glyph.width, 162); compare(glyph.height, glyph.width);
            fuzzyCompare(glyph.width * panel.scale, 214.245, .001);
            var glyphOrigin = glyph.mapToItem(view, 0, 0);
            fuzzyCompare(glyph.renderOrigin.x, glyphOrigin.x, .001);
            fuzzyCompare(glyph.renderOrigin.y, glyphOrigin.y, .001);
            var registration = findChild(view, "panelRegistration");
            compare(registration.scale, panel.scale);
            compare(registration.mapToItem(view, 0, 0), panel.mapToItem(view, 0, 0));
            compare(findChild(view, "userLabel").text, "TESTPILOT");
            // The compact power controls add a footer beneath the password field.
            verify(panel.height < 540 && panel.height > 420);
        }
        function test_typing_backspace_and_focus() {
            var input = findChild(view, "passwordInput"), row = findChild(view, "passwordRow");
            input.forceActiveFocus();
            keyClick(Qt.Key_A); keyClick(Qt.Key_B); keyClick(Qt.Key_C);
            compare(view.password, "abc");
            tryCompare(view, "glyphPhase", 3, 1000);
            keyClick(Qt.Key_Backspace); tryCompare(view, "glyphPhase", 2, 1000);
            compare(view.password, "ab"); compare(view.glyphPhase, 2);
            mouseClick(input, 8, 10);
            compare(row.border.color.toString(), "#55504a");
            compare(input.echoMode, TextInput.Password);
            compare(input.passwordMaskDelay, 0);
            keyClick(Qt.Key_Return); compare(submitted.count, 1);
            keyClick(Qt.Key_Escape); compare(view.password, "");
        }
        function test_pending_disables_submit() {
            view.pending = true;
            verify(!findChild(view, "passwordInput").enabled);
            verify(!findChild(view, "unlockButton").enabled);
            compare(findChild(view, "authStatus").text, "AUTHENTICATING…");
            view.pending = false; view.error = true;
            compare(findChild(view, "authStatus").text, "AUTHENTICATION FAILED");
        }
        function test_password_is_not_limited_to_glyph_range() {
            view.password = new Array(81).join("x"); wait(800);
            compare(findChild(view, "passwordInput").text.length, 80);
            compare(view.glyphPhase, 64);
            view.password = "x"; wait(800); compare(view.glyphPhase, 1);
        }
        function test_idle_has_no_field_repaint() {
            wait(300); fieldPaints.clear(); wait(400); compare(fieldPaints.count, 0);
            view.password = "xxxx"; wait(300); compare(fieldPaints.count, 0);
        }
        function test_corner_animation_lifecycle() {
            // Headless font fallback can make the panel taller than on desktop.
            // Leave room for the corners before checking their animation state.
            view.parent.height = Math.ceil(view.panelHeight * view.panelScale + 160);
            var corners = [];
            for (var i = 0; i < 4; i++) {
                corners.push(findChild(view, "formationCorner" + i));
                verify(corners[i].animating);
            }
            tryVerify(function() { return corners.every(function(c) { return c.travel > 0; }); }, 2000);
            view.hiding = true;
            corners.forEach(function(c) { verify(!c.animating); compare(c.travel, 0); compare(c.signalOpacity, 0); });
            compare(corners[2].activeStation, 3);
            view.hiding = false; view.progress = .5;
            corners.forEach(function(c) { verify(!c.animating); });
            view.progress = 1;
            corners.forEach(function(c) { verify(c.animating); });
            view.parent.height = 500;
            corners.forEach(function(c) { verify(!c.visible); verify(!c.animating); });
        }
        function test_narrow_screen() {
            view.parent.width = 320; view.parent.height = 736; wait(150);
            var panel = findChild(view, "loginPanel"), glyph = findChild(view, "compoundGlyph");
            var topLeft = panel.mapToItem(view, 0, 0), bottomRight = panel.mapToItem(view, panel.width, panel.height);
            verify(topLeft.x >= 0 && bottomRight.x <= view.width);
            verify(topLeft.y >= 0 && bottomRight.y <= view.height);
            compare(glyph.width, glyph.height);
            verify(findChild(view, "passwordInput").width > 90);
        }
        function test_phase_endpoints() {
            var off = Art.componentState(0), on = Art.componentState(1);
            for (var key in off) { compare(off[key], 0); compare(on[key], 1); }
            for (var n = 0; n <= 64; n++) {
                var a = Art.glyphMarks(n), b = Art.glyphMarks(n);
                verify(a.length > 0); compare(JSON.stringify(a), JSON.stringify(b));
            }
        }
        function test_render() {
            view.password = "xxxx"; wait(350);
            var locked = grabImage(view);
            view.progress = .45; wait(150);
            var appearing = grabImage(view);
            verify(!locked.equals(appearing), "The transition must change the rendered panel");
            view.progress = 0; wait(100);
            var cleared = grabImage(view);
            verify(!locked.equals(cleared), "The closed panel must disappear");
            compare(cleared.red(100, 100), 8);
            compare(cleared.green(100, 100), 8);
            compare(cleared.blue(100, 100), 8);
        }
        function test_full_resolution_transition() {
            view.parent.width = 2560; view.parent.height = 1600;
            view.inputReady = false; view.progress = 0; wait(100);
            fieldPaints.clear(); progressSteps.clear(); entry.start();
            tryCompare(view, "progress", 1, 3000);
            // Shared CI runners cannot provide an FPS guarantee.
            verify(progressSteps.count > 1, "The transition must visit intermediate states");
            console.log("1450ms timeline updates:", progressSteps.count);
            compare(fieldPaints.count, 0);
            wait(200); fieldPaints.clear(); wait(200);
            compare(fieldPaints.count, 0);
        }
    }
}
