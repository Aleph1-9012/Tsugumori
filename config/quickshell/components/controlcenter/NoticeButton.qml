pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Button {
    id: root
    required property var entry
    property bool expanded: false
    property bool navigationFocus: false
    property bool reducedMotion: false
    property real fill: hovered || visualFocus || navigationFocus || expanded ? 1 : 0
    signal dismissed()
    signal hoverEntered()
    implicitHeight: expanded ? 174 : 76
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    padding: 12; rightPadding: 42
    Accessible.name: (entry.app || "Notification") + ": " + entry.label
    onHoveredChanged: {
        if (hovered && !down && !expanded) summary.startRoll()
        else summary.stopRoll()
        if (hovered) hoverEntered()
    }
    onPressed: summary.stopRoll()
    background: Rectangle {
        color: "#111111"; border.width: 1; border.color: "#858585"
        Rectangle { x: 1; y: 1; width: (parent.width - 2) * root.fill; height: parent.height - 2; color: "#cc1515" }
        Rectangle { anchors.fill: parent; anchors.margins: 3; color: "transparent"; border.color: "#e8e8e8"; visible: root.visualFocus }
    }
    contentItem: Column {
        spacing: 5
        Text {
            width: parent.width
            text: (root.entry.app || "NOTIFICATION").toUpperCase(); textFormat: Text.PlainText
            font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#e8e8e8"
            elide: Text.ElideRight
        }
        RollingLabel { id: summary; width: parent.width; height: 21; text: root.entry.label; pixelSize: 13; reducedMotion: root.reducedMotion }
        Text {
            visible: root.expanded
            width: parent.width
            text: root.entry.body || ""; textFormat: Text.PlainText
            font.family: "JetBrains Mono"; font.pixelSize: 12; color: "#e8e8e8"
            wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
        }
        Text {
            visible: root.expanded && text !== ""; width: parent.width
            text: [root.entry.urgency === "normal" ? "" : root.entry.urgency, root.entry.category || ""].filter(Boolean).join(" · ")
            textFormat: Text.PlainText
            font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#e8e8e8"; opacity: 0.75
            elide: Text.ElideRight
        }
    }
    Button {
        id: dismissButton
        anchors.right: parent.right; anchors.rightMargin: 4; y: 8
        width: 32; height: 32
        text: "×"; font.family: "JetBrains Mono"; font.pixelSize: 20
        Accessible.name: "Dismiss " + root.entry.label
        hoverEnabled: true
        background: Item {
            Rectangle { anchors.bottom: parent.bottom; width: parent.width * (dismissButton.hovered || dismissButton.visualFocus ? 1 : 0); height: 3; color: "#cc1515"; Behavior on width { NumberAnimation { duration: 220 } } }
        }
        contentItem: Text { text: "×"; color: "#e8e8e8"; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        onClicked: root.dismissed()
    }
    Behavior on fill { NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.InOutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic } }
}
