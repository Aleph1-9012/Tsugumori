import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ── Shared state ──
    property bool   revealing: false
    property bool   frozen:    false
    property bool   hiding:    false
    property bool   done:      false

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
                root.revealing = true
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
        if (root.wallpapers.length === 0) return
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
            required property var modelData
            screen: modelData
            anchors.top:true;anchors.left:true;anchors.right:true;anchors.bottom:true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitWidth: modelData.width; implicitHeight: modelData.height
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.frozen && !root.hiding && !root.done
                                          && modelData.name === root.activeMonitor)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            property bool isPrimary: modelData.name === root.activeMonitor
            property bool isActive:  modelData.name === root.activeMonitor

            // --- Solid opaque backdrop to stop edge/window bleed-through ---
            Rectangle {
                anchors.fill: parent
                color: "#0c0c0c"
                z: -2
            }

            // --- Full-screen click-trap for input passthrough ---
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: {
                    if (root.activeMonitor !== modelData.name) {
                        root.activeMonitor = modelData.name
                    }
                }
            }

            // ── Reveal video ──
            MediaPlayer {
                id: reveal
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_reveal.mp4"
                videoOutput: voReveal
                audioOutput: null
                loops: 1; autoPlay: false
                onPositionChanged: function() {
                    if (root.hiding || root.done) return
                    var pos = reveal.position
                    var dur = reveal.duration
                    if (dur > 0 && pos >= dur - 34) {
                        reveal.pause()
                        root.revealing = false
                    }
                }
            }
            VideoOutput {
                id: voReveal
                anchors.fill: parent
                visible: !root.done
            }

            // ── Hide video ──
            MediaPlayer {
                id: hide
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_hide.mp4"
                videoOutput: voHide
                audioOutput: null
                loops: 1; autoPlay: false
            }
            VideoOutput {
                id: voHide
                anchors.fill: parent; z:1
                visible: root.hiding || root.done
                opacity: 1.0
            }

            Timer {
                id: hideFadeTimer; interval:800; repeat:false
                onTriggered: hideFadeAnim.start()
            }
            Timer { id:applyDelayTimer; interval:800; repeat:false
                property int pendingIdx: -1
                property string pendingMon: ""
                onTriggered: if (pendingIdx >= 0) root.applyWallpaper(pendingIdx, pendingMon)
            }
            NumberAnimation {
                id: hideFadeAnim
                target: voHide; property: "opacity"
                from:1.0; to:0.0; duration:0
                onFinished: { root.done=true; exitTimer.restart() }
            }
            Timer { id:exitTimer; interval:50; repeat:false
                onTriggered: Qt.quit()
            }
            Rectangle { anchors.fill:parent; color:"black"; z:10; visible:root.done }

            // ── UI — active screen only ──
            Item {
                anchors.fill: parent
                visible: !root.done && isActive
                z: 2

                property real uiOp: (root.frozen || root.revealing) ? 1 : 0
                Behavior on uiOp { NumberAnimation { duration:400 } }

                // Mouse scroll across the entire surface.
                MouseArea {
                    anchors.fill: parent
                    onWheel: function(e) {
                        root.navigate(e.angleDelta.y < 0 ? 1 : -1)
                    }
                }

                // Corner decorations.
                Item {
                    anchors{top:parent.top;left:parent.left;topMargin:28;leftMargin:30}
                    z:5; opacity:parent.uiOp
                    Column { spacing:2
                        Row { spacing:5
                            Rectangle { width:5;height:5;radius:3;color:"#9e1010"
                                anchors.verticalCenter:parent.verticalCenter
                                SequentialAnimation on opacity { running:root.frozen; loops:Animation.Infinite
                                    NumberAnimation{to:0.3;duration:900} NumberAnimation{to:1;duration:900} }
                            }
                            Text{text:"WALLPAPER SELECT";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#e8e8e8"}
                        }
                        Text{text:"NODE · "+root.activeMonitor;font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#e8e8e8"}
                    }
                }
                Item {
                    anchors{top:parent.top;right:parent.right;topMargin:28;rightMargin:30}
                    z:5; opacity:parent.uiOp
                    Text{text:root.clockFull;font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#e8e8e8"}
                }
                Item {
                    anchors{bottom:parent.bottom;left:parent.left;bottomMargin:28;leftMargin:30}
                    z:5; opacity:parent.uiOp
                    Text{text:"↑↓ / SCROLL  NAVIGATE  ·  ESC  QUIT";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#e8e8e8"}
                }

                // ── Apply buttons — always visible ──
                Item {
                    id: applyPanel
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 60
                    width: 420
                    height: applyCol.implicitHeight + 48
                    z: 7
                    opacity: root.frozen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration:300 } }

                    Rectangle {
                        anchors.fill: parent
                        color: "#c8c8c4"
                        border.color: "#cc1515"; border.width: 1

                        Repeater { model:22; Rectangle{x:index*20;y:0;width:1;height:parent.height;color:Qt.rgba(70/255,63/255,46/255,0.06)} }

                        Column {
                            id: applyCol
                            width: 348
                            anchors{top:parent.top;topMargin:20;horizontalCenter:parent.horizontalCenter}
                            spacing: 10

                            Text {
                                text: "APPLY WALLPAPER"
                                font.family:"Share Tech Mono";font.pixelSize:10;font.letterSpacing:3
                                color:"#cc1515";anchors.horizontalCenter:parent.horizontalCenter
                            }
                            Rectangle { width:parent.width;height:1;color:Qt.rgba(70/255,63/255,46/255,0.22) }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                // Active-screen button.
                                Item { width:162; height:42
                                    Rectangle { anchors.fill:parent;color:"transparent";border.color:"#cc1515";border.width:1 }
                                    Rectangle { id:fill1;anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;color:"#cc1515";width:0
                                        Behavior on width{NumberAnimation{duration:220}} }
                                    Text { anchors.centerIn:parent
                                        text:"THIS SCREEN"
                                        font.family:"Share Tech Mono";font.pixelSize:10;font.letterSpacing:2
                                        color:ma1.containsMouse?"#c8c8c4":"#cc1515"
                                        Behavior on color{ColorAnimation{duration:200}} }
                                    MouseArea { id:ma1;anchors.fill:parent;hoverEnabled:true
                                        onEntered:fill1.width=parent.width;onExited:fill1.width=0
                                        onClicked:{ root.doClose(); applyDelayTimer.pendingIdx=root.currentIndex; applyDelayTimer.pendingMon=root.activeMonitor; applyDelayTimer.restart() } }
                                }

                                // Both-screens button.
                                Item { width:162; height:42
                                    Rectangle { anchors.fill:parent;color:"transparent";border.color:"#cc1515";border.width:1 }
                                    Rectangle { id:fill2;anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;color:"#cc1515";width:0
                                        Behavior on width{NumberAnimation{duration:220}} }
                                    Text { anchors.centerIn:parent
                                        text:"ALL SCREENS"
                                        font.family:"Share Tech Mono";font.pixelSize:10;font.letterSpacing:2
                                        color:ma2.containsMouse?"#c8c8c4":"#cc1515"
                                        Behavior on color{ColorAnimation{duration:200}} }
                                    MouseArea { id:ma2;anchors.fill:parent;hoverEnabled:true
                                        onEntered:fill2.width=parent.width;onExited:fill2.width=0
                                        onClicked:{ root.doClose(); applyDelayTimer.pendingIdx=root.currentIndex; applyDelayTimer.pendingMon="both"; applyDelayTimer.restart() } }
                                }
                            }
                        }
                    }
                }

                // ── Carousel ──
                Item {
                    id: carousel
                    anchors.top: parent.top
                    anchors.topMargin: 80
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: parent.height - 220
                    z: 6
                    opacity: root.frozen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration:300 } }

                    focus: root.frozen && isActive
                    Keys.onEscapePressed: root.doClose()
                    Keys.onLeftPressed:   root.navigate(-1)
                    Keys.onRightPressed:  root.navigate(1)
                    Keys.onUpPressed:     root.navigate(-1)
                    Keys.onDownPressed:   root.navigate(1)
                    Keys.onReturnPressed:  { root.applyWallpaper(root.currentIndex, "both"); root.doClose() }
                    Keys.onSpacePressed:  { root.applyWallpaper(root.currentIndex, "both"); root.doClose() }
                    readonly property int n: root.wallpapers.length

                    // Base dimensions (central thumbnail size at full scale).
                    readonly property int baseW: 800
                    readonly property int baseH: 500
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

                            Rectangle {
                                anchors.fill: parent
                                color: "#0f0d0a"
                                border.color: thumb.absDelta === 0 ? "#e8e8e8" : "#cc1515"
                                border.width: thumb.absDelta === 0 ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration:260 } }

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: "file://" + root.wallpaperDir + "/" + root.wallpapers[thumb.wIdx]
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    cache: true
                                    sourceSize.width: 800
                                    sourceSize.height: 500
                                }

                                // Name banner, visible only on the central thumbnail.
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 24
                                    color: Qt.rgba(0,0,0,0.6)
                                    opacity: thumb.absDelta === 0 ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration:200 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.wallpapers[thumb.wIdx]
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: 8
                                        color: "#e8e8e8"
                                    }
                                }
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
            }

            // ── State connections ──
            Connections {
                target: root
                function onRevealingChanged() {
                    if (root.revealing) {
                        root.frozen = true
                        reveal.position = 0
                        reveal.play()
                        panelOpenTimer.restart()
                    }
                }
                function onHidingChanged() {
                    if (root.hiding) {
                        reveal.stop()
                        hide.position = 0
                        hide.play()
                        if (isPrimary) hideFadeTimer.restart()
                    }
                }
            }
            Timer { id:panelOpenTimer; interval:100; repeat:false; onTriggered: carousel.focus=true }
        }
    }

    // ── Navigation ──
    function navigate(dir) {
        var n = root.wallpapers.length
        if (n === 0) return
        root.currentIndex = ((root.currentIndex + dir) % n + n) % n
    }

    function doClose() {
        root.hiding = true
    }
}
