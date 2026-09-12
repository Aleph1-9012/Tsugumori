pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"

Button {
    id: root
    property string trackTitle: ""
    property string subtitle: "LOCAL FILE"
    property string durationText: ""
    property int number: 1
    property bool selected: false
    property real uiScale: 1
    property bool reducedMotion: false
    readonly property bool fillActive: selected || hovered || activeFocus
    property real fillProgress: 0
    implicitHeight: 58 * uiScale
    implicitWidth: 500 * uiScale
    leftPadding: 24 * uiScale; rightPadding: 12 * uiScale
    topPadding: 10 * uiScale; bottomPadding: 10 * uiScale
    focusPolicy: Qt.StrongFocus
    Accessible.name: number.toString().padStart(2, "0") + " // " + trackTitle

    function updateFill() {
        wipe.stop()
        if (selected || reducedMotion) fillProgress = fillActive ? 1 : 0
        else { wipe.from = fillProgress; wipe.to = fillActive ? 1 : 0; wipe.start() }
    }
    onFillActiveChanged: updateFill()
    onSelectedChanged: updateFill()
    onReducedMotionChanged: updateFill()
    Component.onCompleted: updateFill()
    NumberAnimation {
        id: wipe; target: root; property: "fillProgress"
        duration: 220; easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    background: Item {
        Rectangle { anchors.fill: parent; color: Theme.bg }
        Rectangle { width: parent.width * root.fillProgress; height: parent.height; color: Theme.a1 }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2c2622" }
        Rectangle {
            x: 9 * root.uiScale
            anchors.verticalCenter: parent.verticalCenter
            width: 6 * root.uiScale; height: width
            rotation: 45; visible: root.selected; color: Theme.bg
        }
    }
    contentItem: RowLayout {
        spacing: 9 * root.uiScale
        Text {
            Layout.preferredWidth: 42 * root.uiScale
            text: root.number.toString().padStart(2, "0") + " //"
            font.family: Theme.mono; font.pixelSize: 11 * root.uiScale
            color: root.fillActive ? Theme.fg : Theme.a1
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 4 * root.uiScale
            Text {
                Layout.fillWidth: true; text: root.trackTitle; textFormat: Text.PlainText
                font.family: Theme.mono; font.pixelSize: 12 * root.uiScale
                elide: Text.ElideRight; maximumLineCount: 1; color: Theme.fg
            }
            Text {
                Layout.fillWidth: true; text: root.subtitle; textFormat: Text.PlainText
                font.family: Theme.mono; font.pixelSize: 11 * root.uiScale
                elide: Text.ElideRight; color: root.fillActive ? Theme.fg : "#aaa29c"
            }
        }
        Text {
            visible: root.durationText.length > 0; text: root.durationText
            font.family: Theme.mono; font.pixelSize: 11 * root.uiScale
            color: root.fillActive ? Theme.fg : "#aaa29c"
        }
    }
}
