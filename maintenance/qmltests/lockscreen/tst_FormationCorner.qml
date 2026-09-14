import QtQuick
import QtTest
import "../../../config/quickshell/widgets/lockscreen"

Item {
    width: 300; height: 160
    Component {
        id: cornerComponent
        FormationCorner { width: 254; height: 50; compact: false; label: "LOCKED" }
    }
    TestCase {
        id: tests
        name: "FormationCornerMotion"
        when: windowShown
        SignalSpy { id: pathChanges; signalName: "pathsChanged" }
        SignalSpy { id: segmentChanges; signalName: "segmentsChanged" }
        SignalSpy { id: labelChanges; signalName: "labelsChanged" }
        function makeCorner(index) {
            var corner = createTemporaryObject(cornerComponent, tests.parent, {index:index});
            verify(corner !== null);
            return corner;
        }
        function test_routes_follow_existing_art() {
            var circuit = makeCorner(0);
            compare(circuit.routeLength, 76);
            compare(circuit.signalPosition, Qt.point(26,5));
            circuit.travel = 23; compare(circuit.signalPosition, Qt.point(26,28));
            circuit.travel = 39; compare(circuit.signalPosition, Qt.point(10,28));
            circuit.travel = 51; compare(circuit.signalPosition, Qt.point(10,16));
            circuit.travel = 76; compare(circuit.signalPosition, Qt.point(35,16));
            var track = makeCorner(2);
            for (var i = 0; i < 4; i++) {
                track.travel = i * track.stationSpacing;
                fuzzyCompare(track.signalPosition.x, 9 + i * (track.span - 18) / 3, .001);
                fuzzyCompare(track.signalPosition.y, 10 + (i % 2 ? 8 : 0), .001);
            }
            track.span = 123;
            compare(track.routeLength, 129);
            track.travel = track.routeLength;
            compare(track.signalPosition, Qt.point(114,18));
            var sidonia = makeCorner(1), status = makeCorner(3);
            for (var span of [244, 123]) {
                sidonia.span = span; sidonia.travel = 0;
                compare(sidonia.routeLength, span - 38);
                compare(sidonia.signalPosition, Qt.point(0,32));
                sidonia.travel = span - 56;
                compare(sidonia.signalPosition, Qt.point(span - 56,32));
                sidonia.travel += 10;
                compare(sidonia.signalPosition, Qt.point(span - 56,22));
                sidonia.travel = sidonia.routeLength;
                compare(sidonia.signalPosition, Qt.point(span - 48,22));
                status.span = span; status.travel = 0;
                compare(status.routeLength, span + 20);
                compare(status.signalPosition, Qt.point(0,9));
                status.travel = 24;
                compare(status.signalPosition, Qt.point(0,33));
                status.travel = status.routeLength - 10;
                compare(status.signalPosition, Qt.point(span - 14,33));
                status.travel = status.routeLength;
                compare(status.signalPosition, Qt.point(span - 14,43));
            }
        }
        function test_loop_does_not_rebuild_paths_or_labels() {
            var track = makeCorner(2);
            pathChanges.target = track; pathChanges.clear();
            segmentChanges.target = track; segmentChanges.clear();
            labelChanges.target = track; labelChanges.clear();
            track.live = true;
            compare(track.activeStation, 0);
            tryCompare(track, "activeStation", 1, 1800);
            tryCompare(track, "activeStation", 2, 1800);
            tryCompare(track, "activeStation", 3, 1800);
            tryCompare(track, "activeStation", 0, 2200);
            compare(pathChanges.count, 0); compare(segmentChanges.count, 0); compare(labelChanges.count, 0);
            track.live = false;
            compare(track.travel, 0); compare(track.signalOpacity, 0); compare(track.activeStation, 3);
            wait(100); compare(track.travel, 0);
        }
        function test_right_corner_loops_data() {
            return [{tag:"SID0NIA", index:1}, {tag:"LOCKED", index:3}];
        }
        function test_right_corner_loops(data) {
            var corner = makeCorner(data.index);
            pathChanges.target = corner; pathChanges.clear();
            segmentChanges.target = corner; segmentChanges.clear();
            labelChanges.target = corner; labelChanges.clear();
            corner.live = true;
            verify(corner.animating);
            compare(corner.segments.length, 3);
            tryVerify(function() { return corner.travel > 0; }, 1800);
            tryCompare(corner, "travel", corner.routeLength, 3600);
            tryCompare(corner, "travel", 0, 2200);
            compare(pathChanges.count, 0); compare(segmentChanges.count, 0); compare(labelChanges.count, 0);
            corner.visible = false;
            verify(!corner.animating); compare(corner.signalOpacity, 0);
            corner.visible = true; verify(corner.animating);
            corner.live = false;
            verify(!corner.animating); compare(corner.travel, 0); compare(corner.signalOpacity, 0);
            wait(100); compare(corner.travel, 0);
        }
    }
}
