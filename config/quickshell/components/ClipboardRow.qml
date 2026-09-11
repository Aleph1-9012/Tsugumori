import QtQuick
import QtQuick.Controls

Button {
    id: root
    property string title: ""
    property string kind: "TEXT"
    property string age: ""
    property bool pinned: false
    property int number: 1
    property bool selected: false
    property bool reducedMotion: false
    property real uiScale: 1
    property color ink: "#252424"
    property color muted: "#62605a"
    property color line: "#c3bcb2"
    property color accent: "#d4161c"
    property real fillProgress: 0
    readonly property bool rowHighlighted: selected || hovered
    implicitHeight: 71 * uiScale
    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: number.toString().padStart(2, "0") + "// " + title + (pinned ? ", pinned" : "")
    Accessible.description: selected ? "Selected clipboard entry" : "Preview clipboard entry"

    function updateFill() {
        wipe.stop()
        if (selected || reducedMotion) fillProgress = rowHighlighted ? 1 : 0
        else { wipe.from = fillProgress; wipe.to = rowHighlighted ? 1 : 0; wipe.start() }
    }
    onRowHighlightedChanged: updateFill()
    onSelectedChanged: updateFill()
    onReducedMotionChanged: updateFill()
    Component.onCompleted: updateFill()
    NumberAnimation {
        id: wipe
        target: root; property: "fillProgress"
        duration: 280
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.2, 0.7, 0.2, 1, 1, 1]
    }
    background: Item {
        Rectangle { width: parent.width * root.fillProgress; height: parent.height; color: root.accent }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.line }
        Rectangle {
            anchors.fill: parent; anchors.margins: 3 * root.uiScale
            visible: root.activeFocus; color: "transparent"
            border.color: root.rowHighlighted ? "#090909" : root.muted
        }
    }
    contentItem: Item {
        Text {
            x: 21 * root.uiScale; y: 16 * root.uiScale
            text: root.number.toString().padStart(2, "0") + "//"
            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 * root.uiScale
            color: root.rowHighlighted ? "#090909" : root.muted
        }
        Column {
            x: 63 * root.uiScale; y: 13 * root.uiScale
            width: Math.max(1, parent.width - x - 36 * root.uiScale)
            spacing: 7 * root.uiScale
            Text {
                width: parent.width
                text: root.title; textFormat: Text.PlainText; elide: Text.ElideRight
                font.family: "Inter"; font.pixelSize: 14 * root.uiScale; font.letterSpacing: 0.35 * root.uiScale
                color: root.rowHighlighted ? "#090909" : root.ink
            }
            Text {
                width: parent.width
                text: (root.kind === "IMAGE" ? "IMG" : root.kind === "LINK" ? "URL" : "TXT")
                      + "  " + root.age + (root.pinned ? "  / PIN" : "")
                elide: Text.ElideRight
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 * root.uiScale
                color: root.rowHighlighted ? "#090909" : root.muted
            }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 19 * root.uiScale; verticalCenter: parent.verticalCenter }
            width: 6 * root.uiScale; height: width; rotation: 45
            visible: root.selected; color: "#090909"
        }
    }
}
