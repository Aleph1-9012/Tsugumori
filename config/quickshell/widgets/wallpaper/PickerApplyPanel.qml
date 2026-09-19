pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: panel
    property string monitorName: ""
    property string fileName: ""
    signal applyRequested(string target)

    implicitWidth: 420
    implicitHeight: content.implicitHeight + 36
    color: "#0a0a0a"
    border.width: 1
    border.color: "#4e4944"

    Rectangle { x: 0; y: 0; width: 36; height: 2; color: "#cc1515" }
    Rectangle { x: 0; y: 0; width: 2; height: 20; color: "#cc1515" }
    Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 36; height: 2; color: "#cc1515" }

    // Match the menu controls without importing the separate desktop shell.
    component ApplyButton: Button {
        id: control
        readonly property bool interactionActive: enabled && (hovered || down || activeFocus)
        property real fillProgress: interactionActive ? 1 : 0
        implicitWidth: 162
        implicitHeight: 40
        padding: 0
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: text
        Behavior on fillProgress { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        HoverHandler { cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Item {
            Rectangle {
                x: 2; y: 2
                width: Math.max(0, parent.width - 4) * control.fillProgress
                height: Math.max(0, parent.height - 4)
                color: "#cc1515"
            }
            Repeater {
                model: 4
                Item {
                    id: corner
                    required property int index
                    width: 6; height: 6
                    x: index % 2 ? parent.width - width : 0
                    y: index >= 2 ? parent.height - height : 0
                    opacity: control.interactionActive ? 1 : .6
                    Rectangle { width: parent.width; height: 1; y: corner.index >= 2 ? parent.height - height : 0; color: "#cc1515" }
                    Rectangle { width: 1; height: parent.height; x: corner.index % 2 ? parent.width - width : 0; color: "#cc1515" }
                }
            }
        }
        contentItem: Text {
            text: control.text
            textFormat: Text.PlainText
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; letterSpacing: 1.3 }
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: control.interactionActive ? "#0a0a0a" : "#b0aba6"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "APPLY WALLPAPER"
                color: "#e8e8e8"
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; letterSpacing: 1.4 }
                Layout.fillWidth: true
            }
            Text {
                text: "//"
                color: "#cc1515"
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#373331" }
        Text {
            Layout.fillWidth: true
            text: panel.monitorName ? "TARGET / " + panel.monitorName : "TARGET / CURRENT SCREEN"
            textFormat: Text.PlainText
            color: "#92908d"
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; letterSpacing: .6 }
            elide: Text.ElideRight
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ApplyButton {
                objectName: "applyCurrentScreen"
                text: "THIS SCREEN"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                enabled: panel.fileName.length > 0
                onClicked: panel.applyRequested(panel.monitorName)
            }
            ApplyButton {
                objectName: "applyAllScreens"
                text: "ALL SCREENS"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                enabled: panel.fileName.length > 0
                onClicked: panel.applyRequested("both")
            }
        }
    }
}
