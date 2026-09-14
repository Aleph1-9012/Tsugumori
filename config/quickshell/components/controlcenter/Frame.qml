pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property string number: "00"
    property string title: ""
    property bool active: false
    property bool cornersActive: active
    property bool reducedMotion: false
    property int headerHeight: 28
    property real titleRightPadding: 12
    property real titleLetterSpacing: 0.25
    property real highlight: active ? 1 : 0
    function startRoll() { heading.startRoll() }
    function stopRoll() { heading.stopRoll() }

    Rectangle {
        anchors.fill: parent
        color: "#111111"
        border.width: 1
        border.color: root.active ? "#e8e8e8" : "#858585"
    }
    Rectangle {
        x: -1; y: 8; width: 3; height: root.headerHeight
        color: "#cc1515"; opacity: root.highlight
    }
    Item {
        x: 8; y: 8; width: parent.width - 16; height: root.headerHeight
        Rectangle { width: parent.width * root.highlight; height: parent.height; color: "#cc1515" }
        Text {
            width: 32; height: parent.height
            text: root.number
            font.family: "JetBrains Mono"; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            color: root.active ? "#080808" : "#e8e8e8"
        }
        Rectangle {
            x: 32; width: 1; height: parent.height
            color: root.active ? "#55080808" : "#26e8e8e8"
        }
        RollingLabel {
            id: heading
            x: 44; width: parent.width - x - root.titleRightPadding; height: parent.height
            text: root.title.toUpperCase(); pixelSize: 13; letterSpacing: root.titleLetterSpacing
            color: root.active ? "#080808" : "#e8e8e8"
            reducedMotion: root.reducedMotion
        }
    }
    Rectangle {
        x: 8; y: 8 + root.headerHeight + 8
        width: parent.width - 16; height: 1
        color: "#858585"; opacity: 0.55
    }
    Repeater {
        model: 4
        Item {
            required property int index
            readonly property bool leftSide: index % 2 === 0
            readonly property bool topSide: index < 2
            x: (leftSide ? 5 : root.width - 7) + (root.cornersActive ? (leftSide ? -3 : 3) : 0)
            y: (topSide ? -3 : root.height - 5) + (root.cornersActive ? (topSide ? -3 : 3) : 0)
            width: 8; height: 8
            opacity: root.cornersActive ? 1 : 0.65
            Rectangle { x: parent.leftSide ? 0 : 6; width: 2; height: 8; color: "#e8e8e8" }
            Rectangle { y: parent.topSide ? 0 : 6; width: 8; height: 2; color: "#e8e8e8" }
            Behavior on x { NumberAnimation { duration: root.reducedMotion ? 0 : 340; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: root.reducedMotion ? 0 : 340; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 220 } }
        }
    }
    Behavior on highlight {
        NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1] }
    }
}
