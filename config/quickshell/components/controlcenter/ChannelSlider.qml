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
    implicitHeight: 74
    color: "#111111"; border.width: 1; border.color: "#858585"
    opacity: enabled ? 1 : 0.4
    Text {
        x: 12; y: 10
        text: root.label
        font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 0.7
        color: "#e8e8e8"
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 12; y: 9
        text: Math.round(slider.value) + "%"
        font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#e8e8e8"
    }
    Slider {
        id: slider
        objectName: root.label.toLowerCase() + "Slider"
        x: 12; y: 32; width: parent.width - 24; height: 34
        from: root.minimum; to: 100; stepSize: 1; value: root.value
        focusPolicy: Qt.StrongFocus
        wheelEnabled: false
        Accessible.name: root.label
        onMoved: root.moved(value)
        background: Rectangle {
            x: slider.leftPadding; y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth; height: 4; color: "#33e8e8e8"
            Rectangle { width: slider.position * parent.width; height: 4; color: root.muted ? "#777777" : "#cc1515" }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 4; height: 18; color: "#e8e8e8"
        }
        Rectangle {
            anchors.fill: parent; color: "transparent"; border.width: 1; border.color: "#e8e8e8"
            visible: slider.activeFocus
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
