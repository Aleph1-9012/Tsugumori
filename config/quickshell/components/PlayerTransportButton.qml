pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"

Button {
    id: root
    property string glyph: ""
    property real uiScale: 1
    property bool primary: false
    property bool stacked: false
    property bool reducedMotion: false
    readonly property bool interactionActive: enabled && (hovered || down || activeFocus)
    property real underlineProgress: primary || interactionActive ? 1 : 0
    implicitHeight: (stacked ? 52 : 44) * uiScale
    implicitWidth: 110 * uiScale
    padding: (stacked ? 6 : 8) * uiScale
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    opacity: enabled ? 1 : 0.38

    Behavior on underlineProgress {
        NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
    }
    HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

    background: Item {
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: Math.max(1, root.uiScale)
            color: root.primary ? Theme.a1 : "#655448"
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width * root.underlineProgress; height: 3 * root.uiScale
            color: Theme.a1
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: 3 * root.uiScale
            visible: root.activeFocus; color: "transparent"
            border.width: 1; border.color: Theme.fg
        }
    }
    contentItem: Item {
        GridLayout {
            anchors.centerIn: parent
            columns: root.stacked ? 1 : 2
            columnSpacing: 8 * root.uiScale; rowSpacing: 4 * root.uiScale
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.glyph; textFormat: Text.PlainText
                font.family: Theme.mono; font.pixelSize: 18 * root.uiScale
                color: root.interactionActive ? "#ef7664" : Theme.fg
                Behavior on color { ColorAnimation { duration: root.reducedMotion ? 0 : 220 } }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.text; textFormat: Text.PlainText
                font.family: Theme.mono; font.pixelSize: 11 * root.uiScale
                font.weight: Font.Medium; font.letterSpacing: root.uiScale
                color: root.interactionActive ? "#ef7664" : Theme.fg
                Behavior on color { ColorAnimation { duration: root.reducedMotion ? 0 : 220 } }
            }
        }
    }
}
