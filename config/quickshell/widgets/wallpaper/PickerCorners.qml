pragma ComponentBehavior: Bound
import QtQuick
import "../lockscreen"
import "../lockscreen/PhaseArt.js" as Art

Item {
    id: corners
    required property real progress
    property bool live: false
    property bool hiding: false
    property string clockText: ""
    property string monitorName: ""
    readonly property bool compact: width < 540
    readonly property real inset: compact ? 14 : 20
    readonly property real span: Math.min(244, (width - inset * 2 - 20) / 2)
    enabled: false

    Repeater {
        model: 4
        FormationCorner {
            objectName: "pickerCorner" + index
            compact: corners.compact
            span: corners.span
            label: corners.hiding ? "CLOSING" : corners.progress < 1 ? "REGISTER" : "SELECT"
            live: corners.live && corners.progress === 1 && !corners.hiding
            x: index % 2 ? corners.width - corners.inset - span - 5 : corners.inset - 5
            y: index < 2 ? 11 : corners.height - 61
            width: span + 10; height: 50
            opacity: Art.ramp(corners.progress, .28, .74)
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: corners.height - 26
        width: Math.max(0, corners.width - 2 * (corners.span + corners.inset + 20))
        visible: width >= 300
        opacity: Art.ramp(corners.progress, .28, .74)
        text: corners.clockText + "  //  " + corners.monitorName + "  //  ↑↓ / SCROLL · ESC QUIT"
        textFormat: Text.PlainText
        color: "#aaa59b"
        font { family: "JetBrains Mono"; pixelSize: 9; letterSpacing: .3 }
        renderType: Text.CurveRendering
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
}
