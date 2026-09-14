pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../theme"

Button {
    id: root

    property bool reducedMotion: false
    readonly property bool interactionActive: enabled && (hovered || down || activeFocus)
    readonly property color labelColor: interactionActive ? Theme.bg : "#b0aba6"
    property real fillProgress: interactionActive ? 1 : 0

    implicitWidth: Math.max(88, contentItem.implicitWidth + 24)
    implicitHeight: 32
    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text

    Behavior on fillProgress {
        NumberAnimation {
            duration: root.reducedMotion ? 0 : 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
        }
    }
    HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

    background: Item {
        Rectangle {
            x: 2; y: 2
            width: Math.max(0, parent.width - 4) * root.fillProgress
            height: Math.max(0, parent.height - 4)
            color: Theme.a1
        }
        Repeater {
            model: 4
            Item {
                id: corner
                required property int index
                readonly property bool rightEdge: index % 2 === 1
                readonly property bool bottomEdge: index >= 2
                width: 6; height: 6
                x: rightEdge ? parent.width - width : 0
                y: bottomEdge ? parent.height - height : 0
                opacity: root.interactionActive ? 1 : 0.6
                Rectangle {
                    width: parent.width; height: 1
                    y: corner.bottomEdge ? parent.height - height : 0
                    color: Theme.a1
                }
                Rectangle {
                    width: 1; height: parent.height
                    x: corner.rightEdge ? parent.width - width : 0
                    color: Theme.a1
                }
            }
        }
    }

    contentItem: Text {
        text: root.text
        textFormat: Text.PlainText
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 1.3
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.labelColor
        Behavior on color { ColorAnimation { duration: root.reducedMotion ? 0 : 120 } }
    }
}
