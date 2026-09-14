pragma ComponentBehavior: Bound
import QtQuick
import "../settings"
import "../theme"

// A1 registration marks with a centered wordmark. Transitions stay in each widget.
Rectangle {
    id: root

    property real uiScale: 1
    readonly property color stencilInk: "#130707"

    color: Settings.curtainColor
    clip: true
    visible: width > 0 && height > 0

    Column {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 18 * root.uiScale
        anchors.rightMargin: 16 * root.uiScale
        spacing: 3 * root.uiScale

        Text {
            text: "継衛"
            height: 17 * root.uiScale
            font.family: Theme.mono
            font.pixelSize: Math.max(1, Math.round(11 * root.uiScale))
            font.letterSpacing: 2 * root.uiScale
            color: root.stencilInk
        }
        Text {
            text: "TYPE 17"
            height: 17 * root.uiScale
            font.family: Theme.mono
            font.pixelSize: Math.max(1, Math.round(11 * root.uiScale))
            font.letterSpacing: 2 * root.uiScale
            color: root.stencilInk
        }
    }

    Text {
        anchors.centerIn: parent
        text: "SID0NIA"
        font.family: Theme.mono
        font.weight: Font.Medium
        font.pixelSize: Math.max(1, Math.round(24 * root.uiScale))
        font.letterSpacing: 5 * root.uiScale
        color: root.stencilInk
    }

    Repeater {
        model: 4
        Item {
            id: corner
            required property int index
            readonly property bool rightEdge: index % 2 === 1
            readonly property bool bottomEdge: index >= 2
            readonly property real strokeWidth: Math.max(1, Math.round(2 * root.uiScale))
            width: 12 * root.uiScale
            height: width
            x: rightEdge ? root.width - 8 * root.uiScale - width : 8 * root.uiScale
            y: bottomEdge ? root.height - 8 * root.uiScale - height : 8 * root.uiScale
            opacity: 0.8

            Rectangle {
                width: corner.width
                height: corner.strokeWidth
                y: corner.bottomEdge ? corner.height - height : 0
                color: root.stencilInk
            }
            Rectangle {
                width: corner.strokeWidth
                height: corner.height
                x: corner.rightEdge ? corner.width - width : 0
                color: root.stencilInk
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 23 * root.uiScale
        anchors.bottomMargin: 20 * root.uiScale
        spacing: 7 * root.uiScale
        opacity: 0.8

        // Decorative barcode pattern from the A1 preview.
        Item {
            width: 72 * root.uiScale
            height: 12 * root.uiScale
            clip: true
            Repeater {
                model: 15
                Rectangle {
                    required property int index
                    x: (Math.floor(index / 4) * 19 + [0, 4, 9, 15][index % 4]) * root.uiScale
                    width: [1, 3, 1, 2][index % 4] * root.uiScale
                    height: 12 * root.uiScale
                    color: root.stencilInk
                }
            }
        }
        Text {
            text: "TS // 017"
            height: 17 * root.uiScale
            font.family: Theme.mono
            font.pixelSize: Math.max(1, Math.round(11 * root.uiScale))
            font.letterSpacing: root.uiScale
            color: root.stencilInk
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16 * root.uiScale
        anchors.bottomMargin: 17 * root.uiScale
        width: 46 * root.uiScale
        height: 3 * root.uiScale
        color: "#160707"
    }
}
