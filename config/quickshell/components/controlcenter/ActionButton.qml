pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Button {
    id: root
    property bool primary: false
    property bool rowStyle: false
    property bool selected: false
    property bool navigationFocus: false
    property bool reducedMotion: false
    property bool diamond: !rowStyle
    property string metadata: ""
    property int signalBars: -1
    property bool secured: false
    property real fill: selected || hovered || visualFocus || navigationFocus ? 1 : 0
    property real underline: hovered || visualFocus || navigationFocus ? 1 : 0
    readonly property bool interactionActive: hovered || visualFocus || navigationFocus
    signal hoverEntered()
    implicitWidth: 240
    implicitHeight: rowStyle ? 40 : 36
    leftPadding: diamond || selected ? 26 : 12
    rightPadding: 12
    topPadding: 8; bottomPadding: 8
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text + (metadata ? " " + metadata : "")
    opacity: enabled ? 1 : 0.4
    onHoveredChanged: {
        if (hovered && !down && !selected) label.startRoll()
        else label.stopRoll()
        if (hovered) hoverEntered()
    }
    onPressed: label.stopRoll()
    onClicked: label.stopRoll()
    onCanceled: label.stopRoll()
    background: Rectangle {
        color: root.primary ? "#e8e8e8" : "#111111"
        border.width: 1
        border.color: root.selected ? "#cc1515" : root.primary ? "#e8e8e8" : "#858585"
        Rectangle {
            visible: root.rowStyle
            x: 1; y: 1; height: parent.height - 2; width: (parent.width - 2) * root.fill
            color: "#cc1515"
        }
        Rectangle {
            visible: !root.rowStyle
            anchors.bottom: parent.bottom
            width: parent.width * root.underline; height: 3
            color: "#cc1515"
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: 3
            color: "transparent"; border.color: "#e8e8e8"; border.width: 1
            visible: root.visualFocus
        }
        Rectangle {
            visible: root.diamond || root.selected
            x: root.selected ? 10 : 12
            anchors.verticalCenter: parent.verticalCenter
            width: root.selected ? 4 : 6; height: width; rotation: 45
            color: root.primary || root.selected ? "#080808" : "#e8e8e8"
        }
    }
    contentItem: Item {
        Row {
            id: indicators
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Row {
                visible: root.signalBars >= 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Repeater {
                    model: root.signalBars >= 0 ? 3 : 0
                    Rectangle {
                        required property int index
                        width: 7; height: 4
                        color: index < root.signalBars ? "#e8e8e8" : "transparent"
                        border.width: index < root.signalBars ? 0 : 1
                        border.color: "#e8e8e8"
                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.4, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                    }
                }
            }
            Text {
                visible: root.secured; text: "⚿"
                font.family: "JetBrains Mono"; font.pixelSize: 12; color: "#e8e8e8"
            }
            Text {
                visible: root.metadata !== ""; text: root.metadata
                font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#a2a2a2"
            }
        }
        RollingLabel {
            id: label
            anchors.left: parent.left; anchors.right: parent.right
            anchors.rightMargin: indicators.width > 0 ? indicators.width + 12 : 0
            height: parent.height
            text: root.text
            alignment: root.rowStyle ? Text.AlignHCenter : Text.AlignLeft
            pixelSize: 12; letterSpacing: 0.45
            color: root.rowStyle ? "#e8e8e8" : root.primary ? (root.interactionActive ? "#a81010" : "#080808") : (root.interactionActive ? "#ef7664" : "#e8e8e8")
            reducedMotion: root.reducedMotion
        }
    }
    Behavior on fill {
        enabled: !root.selected
        NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1] }
    }
    Behavior on underline { NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic } }
}
