pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "lockscreen"
import "lockscreen/PhaseArt.js" as Art

ShellRoot {
    id: root

    // ── Shared state ──
    readonly property bool hiding: motion.closing
    readonly property bool done: motion.finished
    property int pendingIndex: -1
    property string pendingMonitor: ""
    PickerMotion {
        id: motion
        onClosed: {
            // Unmap the picker after the exit, then finish the queued apply.
            if (root.pendingIndex >= 0) root.applyWallpaper(root.pendingIndex, root.pendingMonitor)
            else Qt.quit()
        }
    }

    // ── Wallpapers ──
    property var    wallpapers:    []
    property int    currentIndex:  0
    // Default path: $HOME/Pictures/wallpapers (or XDG_PICTURES_DIR when set).
    property string home:          Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    property string xdgPictures:   Quickshell.env("XDG_PICTURES_DIR") || (home + "/Pictures")
    property string wallpaperDir:  xdgPictures + "/wallpapers"
    property string activeMonitor: ""   // active monitor name (where the mouse is)

    // ── Detect the active monitor ──
    Process {
        id: getMonitorProc
        command: ["sh","-c","hyprctl cursorpos -j | python3 -c \"\nimport sys,json,subprocess\npos=json.load(sys.stdin)\nmons=json.loads(subprocess.check_output(['hyprctl','monitors','-j']))\nfor m in mons:\n    x,y=m['x'],m['y']\n    w,h=m['width'],m['height']\n    if x<=pos['x']<x+w and y<=pos['y']<y+h:\n        print(m['name'])\n        break\n\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var n = this.text.trim()
                if (n !== "") root.activeMonitor = n
                else if (Quickshell.screens.length > 0) root.activeMonitor = Quickshell.screens[0].name
                motion.open()
            }
        }
    }

    // ── List wallpapers ──
    Process {
        id: listWallpapers
        command: [
            "find", root.wallpaperDir,
            "-maxdepth", "1", "-type", "f",
            "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
            "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")",
            "-printf", "%f\\n"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var files = this.text.trim().split("\n").filter(function(f){ return f !== "" })
                root.wallpapers = files
            }
        }
    }

    // ── Apply wallpaper ──
    function applyWallpaper(idx, monitor) {
        if (idx < 0 || idx >= root.wallpapers.length) { Qt.quit(); return }
        var file = root.wallpaperDir + "/" + root.wallpapers[idx]
        applyProc.command = [
            root.xdgConfigHome + "/quickshell/setwallpaper.sh",
            file,
            monitor
        ]
        applyProc.running = true
    }

    Process {
        id: applyProc
        command: ["true"]
        running: false
        // A failed process start may not emit exited. Do not leave an invisible picker running.
        onRunningChanged: if (!running && root.done) Qt.callLater(function() { if (!applyProc.running) Qt.quit() })
        onExited: function(exitCode) {
            if (exitCode !== 0) console.error("Wallpaper picker: wallpaper application failed:", exitCode)
            Qt.quit()
        }
    }

    // ── Hyprland cursor handling ──
    // The native Hyprland cursor stays visible permanently; do not set it
    // Do not set cursor:invisible before or during closing.

    // Clock.
    property string clockFull: "--:--:--"
    Timer {
        interval:1000;running:true;repeat:true
        onTriggered:{
            var d=new Date(),p=function(x){return String(x).padStart(2,"0")}
            root.clockFull=p(d.getHours())+":"+p(d.getMinutes())+":"+p(d.getSeconds())
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: pickerWindow
            required property var modelData
            screen: modelData
            visible: !root.done
            anchors.top:true;anchors.left:true;anchors.right:true;anchors.bottom:true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitWidth: modelData.width; implicitHeight: modelData.height
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (!root.hiding && !root.done
                                          && modelData.name === root.activeMonitor)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            property bool isActive:  modelData.name === root.activeMonitor

            // --- Solid opaque backdrop to stop edge/window bleed-through ---
            PickerBackdrop {
                anchors.fill: parent
                progress: motion.progress
                vertexShaderUrl: "file://" + root.xdgConfigHome + "/quickshell/widgets/lockscreen/shaders/lines.vert.qsb"
                fragmentShaderUrl: "file://" + root.xdgConfigHome + "/quickshell/widgets/lockscreen/shaders/lines.frag.qsb"
                z: -2
            }

            // --- Full-screen click-trap for input passthrough ---
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: {
                    if (!root.hiding && root.activeMonitor !== modelData.name) {
                        root.activeMonitor = modelData.name
                    }
                }
            }

            // ── UI — active screen only ──
            Item {
                anchors.fill: parent
                visible: !root.done && pickerWindow.isActive
                z: 2
                Keys.onEscapePressed: root.doClose()

                // Mouse scroll across the entire surface.
                MouseArea {
                    anchors.fill: parent
                    onWheel: function(e) {
                        root.navigate(e.angleDelta.y < 0 ? 1 : -1)
                    }
                }

                PickerCorners {
                    anchors.fill: parent
                    z: 5
                    progress: motion.progress
                    live: motion.inputReady && pickerWindow.isActive
                    hiding: root.hiding
                    monitorName: root.activeMonitor
                    clockText: root.clockFull
                }

                // ── Apply buttons — always visible ──
                PickerApplyPanel {
                    id: applyPanel
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 60
                    width: Math.min(420, parent.width - 32)
                    height: implicitHeight
                    z: 7
                    opacity: Art.ramp(motion.progress, .59, .87)
                    enabled: motion.inputReady
                    monitorName: root.activeMonitor
                    fileName: root.wallpapers[root.currentIndex] || ""
                    onApplyRequested: target => root.requestApply(target)
                }

                // ── Carousel ──
                Item {
                    id: carousel
                    anchors.top: parent.top
                    anchors.topMargin: 80
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: Math.max(200, applyPanel.y - y - 24)
                    z: 6
                    opacity: Art.ramp(motion.progress, .22, .73)

                    // Escape can reverse an unfinished entrance. Other input waits.
                    focus: !root.hiding && pickerWindow.isActive
                    Keys.onEscapePressed: root.doClose()
                    Keys.onLeftPressed:   root.navigate(-1)
                    Keys.onRightPressed:  root.navigate(1)
                    Keys.onUpPressed:     root.navigate(-1)
                    Keys.onDownPressed:   root.navigate(1)
                    Keys.onReturnPressed: root.requestApply("both")
                    Keys.onSpacePressed: root.requestApply("both")
                    readonly property int n: root.wallpapers.length

                    // Base dimensions (central thumbnail size at full scale).
                    readonly property int baseW: Math.min(800, Math.max(280, parent.width - 64))
                    readonly property int baseH: Math.min(540, Math.max(180, height - 24))
                    // Shared baseline: all thumbnails align their bottom edge here.
                    readonly property int baselineY: height / 2 + baseH / 2

                    // Scale by distance (slot) from the center.
                    readonly property real scaleCenter: 1.0
                    readonly property real scaleNear:   0.54   // ~280/520
                    readonly property real scaleFar:    0.35   // ~180/520

                    // X spacing (half-axes between thumbnail centers) by slot.
                    readonly property int offsetNear: 280
                    readonly property int offsetFar:  576

                    // One thumbnail per wallpaper. Each thumbnail chooses its place
                    // based on the signed offset toward currentIndex (shortest path
                    // around the loop). Position, scale, and opacity are animated.
                    // Zoom is smooth and starts from the bottom (transformOrigin: Bottom).
                    Repeater {
                        model: root.wallpapers

                        Item {
                            id: thumb
                            required property int index
                            property int wIdx: index
                            // Signed offset (-n/2 .. n/2) is the shortest path to currentIndex.
                            property int rawDelta: carousel.n > 0 ? (wIdx - root.currentIndex) : 0
                            property int delta: {
                                if (carousel.n === 0) return 0
                                var d = rawDelta
                                var half = carousel.n / 2
                                if (d >  half) d -= carousel.n
                                if (d < -half) d += carousel.n
                                return d
                            }
                            property int absDelta: Math.abs(delta)

                            // X position and scale derived from the slot.
                            property real targetScale:
                                  absDelta === 0 ? carousel.scaleCenter
                                : absDelta === 1 ? carousel.scaleNear
                                :                  carousel.scaleFar
                            property real targetOpacity:
                                  absDelta === 0 ? 1.0
                                : absDelta === 1 ? 0.65
                                : absDelta === 2 ? 0.3
                                :                  0.0
                            property int targetOffsetX:
                                  absDelta === 0 ? 0
                                : absDelta === 1 ? (delta > 0 ?  carousel.offsetNear : -carousel.offsetNear)
                                :                  (delta > 0 ?  carousel.offsetFar  : -carousel.offsetFar)

                            width: carousel.baseW
                            height: carousel.baseH
                            x: carousel.width/2 + targetOffsetX - carousel.baseW/2
                            y: carousel.baselineY - carousel.baseH
                            scale: targetScale
                            opacity: targetOpacity
                            z: absDelta === 0 ? 10 : (3 - absDelta)
                            visible: absDelta <= 2
                            transformOrigin: Item.Bottom

                            // Smooth animations — scale starts from the bottom via transformOrigin.
                            Behavior on x       { NumberAnimation { duration:320; easing.type:Easing.OutCubic } }
                            Behavior on scale   { NumberAnimation { duration:320; easing.type:Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration:320; easing.type:Easing.OutCubic } }

                            PickerPreview {
                                anchors.fill: parent
                                selected: thumb.absDelta === 0
                                imageSource: "file://" + root.wallpaperDir + "/" + root.wallpapers[thumb.wIdx]
                                fileName: root.wallpapers[thumb.wIdx]
                                itemNumber: thumb.wIdx + 1
                                itemCount: carousel.n
                            }

                            MouseArea {
                                anchors.fill: parent
                                // Click a neighbor to navigate to it.
                                onClicked: if (thumb.delta !== 0) root.navigate(thumb.delta)
                                onWheel: function(e) { root.navigate(e.angleDelta.y < 0 ? 1 : -1) }
                            }
                        }
                    }
                }
                PickerRegistration {
                    x: carousel.x + (carousel.width - carousel.baseW) / 2
                    y: carousel.y + carousel.baselineY - carousel.baseH
                    width: carousel.baseW; height: carousel.baseH
                    progress: motion.progress
                    z: 8
                }
            }
        }
    }

    // ── Navigation ──
    function navigate(dir) {
        if (!motion.inputReady) return
        var n = root.wallpapers.length
        if (n === 0) return
        root.currentIndex = ((root.currentIndex + dir) % n + n) % n
    }

    function doClose() {
        motion.close()
    }

    function requestApply(monitor) {
        if (!motion.inputReady || root.wallpapers.length === 0) return
        root.pendingIndex = root.currentIndex
        root.pendingMonitor = monitor
        motion.close()
    }

    component PickerMotion: Item {
        id: timeline
        property real progress: 0
        property bool started: false
        property bool opening: false
        property bool closing: false
        property bool finished: false
        readonly property bool inputReady: started && !opening && !closing && !finished && progress === 1
        signal closed()

        function open() {
            if (started || closing || finished) return;
            started = true;
            opening = true;
            appear.start();
        }
        function close() {
            if (closing || finished) return;
            appear.stop();
            opening = false;
            closing = true;
            disappear.from = progress;
            disappear.duration = Math.max(1, Math.round(950 * progress));
            disappear.start();
        }
        NumberAnimation {
            id: appear
            target: timeline; property: "progress"
            from: 0; to: 1; duration: 1450
            onFinished: timeline.opening = false
        }
        NumberAnimation {
            id: disappear
            target: timeline; property: "progress"
            to: 0
            onFinished: { timeline.finished = true; timeline.closed(); }
        }
    }

    component PickerBackdrop: Item {
        id: field
        required property real progress
        // Pass real file URLs from the entry point. Quickshell can resolve inherited
        // relative shader URLs against this consumer directory or its virtual URL.
        required property url vertexShaderUrl
        required property url fragmentShaderUrl
        property bool shaderFailed: false
        readonly property bool gpuRendering: GraphicsInfo.api !== GraphicsInfo.Software && !shaderFailed
        readonly property real dpr: Math.max(1, Screen.devicePixelRatio)
        readonly property int columns: Math.ceil(width / 84)
        readonly property int rows: Math.ceil(height / 84)
        readonly property int batches: Math.ceil(columns / 32)
        readonly property PhaseCpuFallback cpuRenderer: cpuField.item as PhaseCpuFallback
        readonly property int paintCount: cpuRenderer ? cpuRenderer.paintCount : 0
        clip: true

        Rectangle { anchors.fill: parent; color: "#080808" }
        Loader {
            anchors.fill: parent
            active: field.gpuRendering
            sourceComponent: Item {
                Repeater {
                    model: field.rows * field.batches
                    PhaseLines {
                        required property int index
                        vertexShader: field.vertexShaderUrl
                        fragmentShader: field.fragmentShaderUrl
                        width: field.width; height: 84
                        y: (field.height - field.rows * 84) / 2 + rowIndex * 84
                        rowIndex: Math.floor(index / field.batches)
                        firstColumn: (index % field.batches) * 32
                        batchColumns: Math.min(32, field.columns - firstColumn)
                        rootColumns: field.columns
                        glyphMode: 0; glyphCount: 0
                        progress: field.progress
                        pixelRatio: field.dpr
                        pixelOrigin: Qt.point(0, y)
                        onRenderFailed: description => {
                            if (!field.shaderFailed) console.error("Wallpaper picker: static artwork fallback:", description);
                            field.shaderFailed = true;
                        }
                    }
                }
            }
        }
        Loader {
            id: cpuField
            anchors.fill: parent
            active: !field.gpuRendering
            opacity: Art.ramp(field.progress, .10, .35)
            sourceComponent: PhaseCpuFallback { pixelRatio: field.dpr }
        }
    }

    component PickerCorners: Item {
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

    component PickerRegistration: Item {
        id: frame
        required property real progress
        readonly property real dpr: Math.max(1, Screen.devicePixelRatio)
        enabled: false
        visible: progress > 0 && progress < 1
        opacity: Art.ramp(progress, .06, .17) * (1 - Art.ramp(progress, .65, .86))
        Repeater {
            model: 38
            Rectangle {
                required property int index
                readonly property real tickHeight: Art.lerp(7, 1, Art.ramp(frame.progress, .18, .73))
                x: Math.round(((index % 19) + .5) * frame.width / 19 * frame.dpr) / frame.dpr
                y: Math.round(((index < 19 ? 0 : frame.height) - tickHeight) * frame.dpr) / frame.dpr
                width: 1 / frame.dpr; height: Math.round(tickHeight * 2 * frame.dpr) / frame.dpr
                color: index % 6 === 0 ? "#d1161c" : "#999486"
            }
        }
        Repeater {
            model: 4
            Item {
                id: corner
                required property int index
                readonly property real arm: 32 * Art.ramp(frame.progress, .08, .6)
                x: index % 2 ? frame.width : 0
                y: index < 2 ? 0 : frame.height
                Rectangle { x: corner.index % 2 ? -width : 0; width: corner.arm; height: 1 / frame.dpr; color: "#b91a20" }
                Rectangle { y: corner.index < 2 ? 0 : -height; width: 1 / frame.dpr; height: corner.arm; color: "#b91a20" }
            }
        }
    }

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

    component PickerApplyPanel: Rectangle {
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

    component PickerPreview: Rectangle {
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
}
