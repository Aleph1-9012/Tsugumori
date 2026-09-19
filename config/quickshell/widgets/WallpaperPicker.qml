import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "wallpaper"
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
}
