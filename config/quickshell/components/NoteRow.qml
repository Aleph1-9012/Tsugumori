import QtQuick
import QtQuick.Controls
import "../theme"

Item {
    id: root

    property string title: ""
    property int number: 1
    property bool selected: false
    property real uiScale: 1
    property bool reducedMotion: false
    readonly property bool highlighted: selected || pointer.hovered || selectButton.activeFocus || deleteButton.activeFocus
    property real fillProgress: 0
    signal selectedRequested()
    signal deleteRequested()

    implicitHeight: 40 * uiScale
    implicitWidth: 378 * uiScale

    // Keep this fill alive when selection changes. Only hover-out animates;
    // selecting a row always cancels the animation and pins it fully red.
    function updateFill() {
        wipe.stop()
        if (selected || reducedMotion) {
            fillProgress = highlighted ? 1 : 0
        } else {
            wipe.from = fillProgress
            wipe.to = highlighted ? 1 : 0
            wipe.start()
        }
    }
    onHighlightedChanged: updateFill()
    onSelectedChanged: updateFill()
    onReducedMotionChanged: updateFill()
    Component.onCompleted: updateFill()

    NumberAnimation {
        id: wipe
        target: root
        property: "fillProgress"
        duration: 220
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
    }
    Rectangle { anchors.fill: parent; color: Theme.bg }
    Rectangle {
        width: parent.width * root.fillProgress
        height: parent.height
        color: Theme.a1
    }
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: root.selected ? Theme.a1 : Qt.alpha(Theme.a1, 0.55)
    }
    HoverHandler { id: pointer }
    Button {
        id: selectButton
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: deleteButton.left }
        padding: 0
        focusPolicy: Qt.StrongFocus
        background: Item {}
        Accessible.name: root.number.toString().padStart(2, "0") + "// " + (root.title.trim() || "Untitled note")
        contentItem: Item {
            Rectangle {
                x: 9 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                width: 6 * root.uiScale; height: width
                rotation: 45
                visible: root.selected
                color: Theme.bg
            }
            Text {
                anchors { left: parent.left; leftMargin: 24 * root.uiScale; right: parent.right; rightMargin: 9 * root.uiScale; verticalCenter: parent.verticalCenter }
                text: selectButton.Accessible.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.mono
                font.pixelSize: 16 * root.uiScale
                color: root.highlighted ? Theme.bg : Theme.fg
            }
        }
        onClicked: { forceActiveFocus(); root.selectedRequested() }
    }
    Button {
        id: deleteButton
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: 34 * root.uiScale
        padding: 0
        focusPolicy: Qt.StrongFocus
        Accessible.name: "Delete " + (root.title.trim() || "Untitled note")
        background: Rectangle {
            color: !root.selected && deleteButton.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
            Rectangle { width: 1; height: parent.height; color: root.highlighted ? Qt.alpha(Theme.bg, 0.25) : Qt.alpha(Theme.a1, 0.3) }
        }
        contentItem: Text {
            text: "×"
            font.family: Theme.mono
            font.pixelSize: 21 * root.uiScale
            color: root.highlighted ? Theme.bg : Theme.fg
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: root.deleteRequested()
    }
    Rectangle {
        anchors.fill: selectButton.activeFocus ? selectButton : deleteButton
        anchors.margins: 3
        visible: selectButton.activeFocus || deleteButton.activeFocus
        color: "transparent"
        border.color: root.highlighted ? Theme.bg : Theme.fg
    }
}
