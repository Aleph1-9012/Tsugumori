pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

Rectangle {
    id: preview
    property url imageSource
    property string fileName: ""
    property int itemNumber: 1
    property int itemCount: 1
    property bool selected: false
    readonly property real dpr: Math.max(1, Screen.devicePixelRatio)

    Accessible.role: Accessible.Graphic
    Accessible.name: fileName

    color: "#0a0a0a"
    border.width: 1
    border.color: selected ? "#655c52" : "#373331"
    Behavior on border.color { ColorAnimation { duration: 200 } }

    Rectangle {
        x: 1; y: 1
        width: parent.width - 2; height: 40
        color: "#0a0a0a"
        Text {
            id: headerTitle
            objectName: "previewTitle"
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, (parent.width - 122) * .55))
            text: "WALLPAPER / PREVIEW"
            color: "#aaa59b"
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; letterSpacing: 1 }
            elide: Text.ElideRight
        }
        Text {
            objectName: "previewFileName"
            anchors {
                left: headerTitle.right; leftMargin: 12
                right: previewCounter.left; rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            text: preview.fileName
            textFormat: Text.PlainText
            color: "#92908d"
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
        }
        Rectangle {
            id: previewCounter
            objectName: "previewCounter"
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: 72; height: 22
            color: preview.selected ? "#cc1515" : "#26221f"
            Text {
                anchors.centerIn: parent
                text: String(preview.itemNumber).padStart(2, "0") + " / " + String(preview.itemCount).padStart(2, "0")
                color: preview.selected ? "#0a0a0a" : "#92908d"
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#373331" }
    }

    Image {
        objectName: "wallpaperImage"
        anchors { fill: parent; leftMargin: 1; rightMargin: 1; topMargin: 41; bottomMargin: 1 }
        source: preview.visible ? preview.imageSource : ""
        fillMode: Image.PreserveAspectCrop
        clip: true
        asynchronous: true
        smooth: true
        cache: true
        sourceSize.width: Math.ceil(width * preview.dpr)
        sourceSize.height: Math.ceil(height * preview.dpr)
    }

    Repeater {
        model: 4
        Item {
            id: corner
            required property int index
            width: 18; height: 18
            x: index % 2 ? preview.width - width : 0
            y: index < 2 ? 0 : preview.height - height
            opacity: preview.selected ? 1 : .3
            Rectangle { width: parent.width; height: 2; y: corner.index < 2 ? 0 : parent.height - height; color: "#cc1515" }
            Rectangle { width: 2; height: parent.height; x: corner.index % 2 ? parent.width - width : 0; color: "#cc1515" }
        }
    }
}
