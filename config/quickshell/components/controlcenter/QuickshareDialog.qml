pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as C

Frame {
    id: dialog
    required property var controller
    readonly property real qrSize: Math.min(280, width - 64)
    implicitWidth: 400
    implicitHeight: body.implicitHeight + 82
    number: "02"; title: "Quickshare"
    active: true; headerHeight: 32; titleRightPadding: 44
    reducedMotion: controller.reducedMotion

    // Consume empty-space clicks so they cannot reach the stop backdrop.
    MouseArea { anchors.fill: parent }
    C.Button {
        id: closeButton
        objectName: "quickshareClose"
        x: parent.width - 40; y: 8; width: 32; height: 32
        text: "×"; Accessible.name: "Stop sharing and close"
        hoverEnabled: true
        background: Item {
            Rectangle { width: 1; height: parent.height; color: "#55080808" }
            Rectangle {
                anchors.bottom: parent.bottom
                width: closeButton.hovered || closeButton.visualFocus ? parent.width : 0
                height: 3; color: "#080808"
                Behavior on width { NumberAnimation { duration: dialog.reducedMotion ? 0 : 220 } }
            }
        }
        contentItem: Text {
            text: "×"; font.family: "JetBrains Mono"; font.pixelSize: 20
            color: closeButton.hovered ? "#e8e8e8" : "#080808"
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        onClicked: dialog.controller.stopQshare()
    }
    Column {
        id: body
        x: 16; y: 62; width: parent.width - 32
        spacing: 12
        Row {
            width: parent.width; spacing: 9
            Rectangle { y: 4; width: 7; height: 7; color: "#cc1515" }
            Text {
                width: parent.width - 16
                text: (dialog.controller.qshareLabel.indexOf("receiving") === 0 ? "RECEIVE" : "SEND")
                    + " // " + (dialog.controller.qshareTunnel ? "INTERNET" : "LOCAL NETWORK")
                textFormat: Text.PlainText; elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.pixelSize: 12; font.letterSpacing: 0.45
                color: "#e8e8e8"
            }
        }
        Text {
            width: parent.width; text: dialog.controller.qshareLabel
            textFormat: Text.PlainText; elide: Text.ElideMiddle
            font.family: "JetBrains Mono"; font.pixelSize: 12; color: "#a2a2a2"
        }
        Item {
            width: parent.width; height: dialog.qrSize + 16
            Rectangle {
                id: qrFrame
                anchors.centerIn: parent
                width: dialog.qrSize; height: width
                color: "#111111"; border.width: 1; border.color: "#858585"
                Image {
                    id: qrImage
                    anchors.fill: parent; anchors.margins: 6
                    source: dialog.controller.qshareQrPath ? "file://" + dialog.controller.qshareQrPath : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: false; cache: false; asynchronous: true
                    Accessible.name: "Scan this QR code on your phone to open the transfer"
                }
                Text {
                    anchors.centerIn: parent
                    visible: qrImage.status !== Image.Ready
                    text: qrImage.status === Image.Error ? "QR UNAVAILABLE" : "GENERATING…"
                    font.family: "JetBrains Mono"; font.pixelSize: 12; color: "#a2a2a2"
                }
                Repeater {
                    model: 4
                    Item {
                        required property int index
                        x: index % 2 === 0 ? -4 : qrFrame.width - 6
                        y: index < 2 ? -4 : qrFrame.height - 6
                        width: 10; height: 10
                        Rectangle { width: 10; height: 2; y: parent.index < 2 ? 0 : 8; color: "#cc1515" }
                        Rectangle { width: 2; height: 10; x: parent.index % 2 === 0 ? 0 : 8; color: "#cc1515" }
                    }
                }
            }
        }
        Text {
            width: parent.width; text: dialog.controller.qshareUrl
            textFormat: Text.PlainText; elide: Text.ElideMiddle
            font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#a2a2a2"
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            width: parent.width
            text: dialog.controller.qshareLastTick || "SCAN WITH PHONE"
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            font.family: "JetBrains Mono"; font.pixelSize: 12; color: "#e8e8e8"
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle { width: parent.width; height: 1; color: "#858585"; opacity: 0.55 }
        Row {
            width: parent.width; spacing: 12
            Text {
                width: parent.width - stopButton.width - 12; height: stopButton.height
                text: dialog.controller.qshareKeepAlive ? "KEEP ALIVE // ON" : "SINGLE SESSION"
                font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#a2a2a2"
                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            }
            ActionButton {
                id: stopButton
                objectName: "quickshareStop"
                width: 116; text: "STOP"; diamond: false
                reducedMotion: dialog.reducedMotion
                onClicked: dialog.controller.stopQshare()
            }
        }
    }
}
