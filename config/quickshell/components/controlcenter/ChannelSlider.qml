pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    property string label: ""
    property real value: 0
    property real minimum: 0
    property bool muted: false
    property real wheelRemainder: 0
    signal moved(real value)
    signal muteRequested()
    implicitHeight: 66
    color: "#111111"; border.width: 1; border.color: "#333333"
    opacity: enabled ? 1 : 0.4
    Text {
        x: 13; y: 3; height: 16
        text: root.label
        font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 0.7
        color: "#e8e8e8"
        verticalAlignment: Text.AlignVCenter
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 13; y: 3; height: 16
        text: Math.round(slider.value) + "%"
        font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#e8e8e8"
        verticalAlignment: Text.AlignVCenter
    }
    Slider {
        id: slider
        objectName: root.label.toLowerCase() + "Slider"
        x: 3; y: 21; width: parent.width - 6; height: 44
        padding: 0
        from: root.minimum; to: 100; stepSize: 1; value: root.value
        focusPolicy: Qt.StrongFocus
        wheelEnabled: false
        Accessible.name: root.label
        onMoved: root.moved(value)
        background: Item {
            x: slider.leftPadding + slider.handle.width / 2
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: Math.max(0, slider.availableWidth - slider.handle.width)
            height: 12
            clip: true
            Image {
                anchors.fill: parent
                source: root.muted ? "assets/weave-muted.svg" : "assets/weave.svg"
                sourceSize.width: 5; sourceSize.height: 5
                fillMode: Image.Tile
                horizontalAlignment: Image.AlignLeft
                verticalAlignment: Image.AlignTop
            }
            Rectangle {
                x: slider.mirrored ? parent.width - width : 0
                width: slider.position * parent.width; height: parent.height
                color: root.muted ? "#777777" : "#cc1515"
            }
        }
        handle: Item {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding
            width: 20; height: slider.availableHeight
            Rectangle {
                anchors.centerIn: parent
                width: 7; height: 22; color: root.color
            }
            Rectangle {
                anchors.centerIn: parent
                width: 3; height: 18; color: "#e8e8e8"
            }
        }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.muteRequested() }
    }
    // The whole slider card accepts scrolling, including its label and value.
    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onActiveChanged: { if (!active) root.wheelRemainder = 0 }
        onWheel: event => {
            const delta = event.angleDelta.y !== 0
                ? event.angleDelta.y / 120 * 5 : event.pixelDelta.y / 8
            if (delta === 0) { event.accepted = false; return }
            root.wheelRemainder += delta
            const change = Math.trunc(root.wheelRemainder)
            root.wheelRemainder -= change
            const next = Math.max(root.minimum, Math.min(100, slider.value + change))
            if (next !== slider.value) root.moved(next)
            event.accepted = true
        }
    }
}
