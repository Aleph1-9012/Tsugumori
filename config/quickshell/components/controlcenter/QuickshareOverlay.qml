pragma ComponentBehavior: Bound
import QtQuick
import ".."

Item {
    id: overlay
    required property var controller
    property bool requestedOpen: false
    readonly property bool reducedMotion: controller.reducedMotion
    readonly property bool blocking: presented
    readonly property bool transitioning: reveal.running || conceal.running
    property bool presented: false
    property bool ready: false
    property real entranceOffset: 0
    property real exitOffset: 0
    property real curtainCover: 0
    visible: presented

    // Preserve the last frame while the backend stops and removes its QR file.
    QtObject {
        id: display
        readonly property bool reducedMotion: overlay.reducedMotion
        property string qshareLabel: ""
        property string qshareUrl: ""
        property string qshareQrPath: ""
        property string qshareLastTick: ""
        property bool qshareTunnel: false
        property bool qshareKeepAlive: false
        function stopQshare() { overlay.controller.stopQshare() }
    }

    function captureContent() {
        if (!requestedOpen || controller.qshareUrl === "") return
        display.qshareLabel = controller.qshareLabel
        display.qshareUrl = controller.qshareUrl
        display.qshareQrPath = controller.qshareQrPath
        display.qshareLastTick = controller.qshareLastTick
        display.qshareTunnel = controller.qshareTunnel
        display.qshareKeepAlive = controller.qshareKeepAlive
    }

    function finishClosed() {
        presented = false
        entranceOffset = 0
        exitOffset = 0
        curtainCover = 0
        display.qshareQrPath = ""
        display.qshareUrl = ""
    }

    function updatePresentation() {
        if (!ready) return
        reveal.stop()
        conceal.stop()
        if (requestedOpen) {
            captureContent()
            if (!presented) {
                entranceOffset = panelHost.width + 2
                exitOffset = 0
                curtainCover = 1
                presented = true
            }
            if (reducedMotion) {
                entranceOffset = 0
                exitOffset = 0
                curtainCover = 0
            } else {
                reveal.start()
            }
        } else if (presented) {
            if (reducedMotion) finishClosed()
            else conceal.start()
        }
    }

    onRequestedOpenChanged: updatePresentation()
    onReducedMotionChanged: updatePresentation()
    Component.onCompleted: { ready = true; updatePresentation() }

    Connections {
        target: overlay.controller
        function onQshareLabelChanged() { overlay.captureContent() }
        function onQshareUrlChanged() { overlay.captureContent() }
        function onQshareQrPathChanged() { overlay.captureContent() }
        function onQshareLastTickChanged() { overlay.captureContent() }
        function onQshareTunnelChanged() { overlay.captureContent() }
        function onQshareKeepAliveChanged() { overlay.captureContent() }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: overlay.requestedOpen ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: overlay.reducedMotion ? 0 : 260 } }
    }
    MouseArea {
        anchors.fill: parent
        // Keep consuming clicks until the closing curtain has left the panel.
        onClicked: { if (overlay.requestedOpen) overlay.controller.stopQshare() }
    }

    Item {
        id: panelHost
        objectName: "quicksharePanelHost"
        width: Math.min(400, overlay.width - 48) + 16
        height: dialog.implicitHeight + 16
        x: (overlay.width - width) / 2 + overlay.entranceOffset
        y: (overlay.height - height) / 2
        clip: true

        Item {
            x: overlay.exitOffset
            width: panelHost.width; height: panelHost.height
            QuickshareDialog {
                id: dialog
                objectName: "quickshareDialog"
                controller: display
                x: 8; y: 8; width: parent.width - 16; height: implicitHeight
                enabled: overlay.requestedOpen && !overlay.transitioning
            }
            CurtainSurface {
                objectName: "quickshareCurtain"
                x: parent.width - width
                width: parent.width * overlay.curtainCover
                height: parent.height
            }
            MouseArea {
                anchors.fill: parent
                enabled: overlay.transitioning
            }
        }
    }

    // Match Menu.qml: 440 ms entrance, then a 340 ms curtain reveal.
    SequentialAnimation {
        id: reveal
        ParallelAnimation {
            NumberAnimation { target: overlay; property: "entranceOffset"; to: 0; duration: 440; easing.type: Easing.OutExpo }
            NumberAnimation { target: overlay; property: "exitOffset"; to: 0; duration: 440; easing.type: Easing.OutExpo }
        }
        NumberAnimation { target: overlay; property: "curtainCover"; to: 0; duration: 340; easing.type: Easing.OutExpo }
    }

    // Cover from the right, then carry the covered panel out through the clip.
    ParallelAnimation {
        id: conceal
        NumberAnimation {
            target: overlay; property: "curtainCover"; to: 1; duration: 420
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
        }
        SequentialAnimation {
            PauseAnimation { duration: 270 }
            NumberAnimation {
                target: overlay; property: "exitOffset"; to: panelHost.width * 1.02; duration: 510
                easing.type: Easing.BezierSpline; easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
            }
        }
        onFinished: overlay.finishClosed()
    }
}
