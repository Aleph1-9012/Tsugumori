import QtQuick
import Quickshell.Io
import "../components"
import "../settings"

Item {
    id: root

    // ── Shorthand Settings (scale global) ──
    readonly property int  pw:      Settings.playerWidth
    readonly property real sc:      Settings.scale
    property int  coverSz: s(200)   // Calculated dynamically on completed for symmetry
    function s(px) { return Math.round(px * sc) }

    // ── Bindings playerctl depuis shell.qml ──
    property string mpTitle:    "END OF EVANGELION"
    property string mpArtist:   "NEON GENESIS // ANNO"
    property string mpCoverUrl: ""
    property bool   mpPlaying:  false
    property real   mpPosition: 0
    property real   mpLength:   341

    signal playPause
    signal nextTrack
    signal prevTrack
    property var    localTracks: []
    property bool   showTrackList: false
    signal localTrackSelected(string path)

    property bool   shown:    false
    property string clockStr: "--:--"

    // Stabilize Wayland window size to prevent surface reconfiguration jump
    implicitWidth:  pw
    implicitHeight: s(420)

    // ──────────────────────────────────────────────────────────────
    // WIPE HOST — Item clipé contenant rideau + contenu comme frères
    // ──────────────────────────────────────────────────────────────
    Item {
        id:      wipeHost
        width:   pw
        height:  content.implicitHeight
        clip:    true
        x:       pw+2          // commence hors-écran à droite (caché)
        opacity: 1
        visible: false         // invisible au démarrage

        // ── CONTENU (player réel) ──
        Item {
            id:      content
            width:   pw
            implicitHeight: playerCol.implicitHeight

            Column {
                id:    playerCol
                width: pw

                // ── TOP STRIP — bordure noire, ticks +, ticker défilant ──
                Item {
                    id: topStrip
                    width: pw; height: s(16)

                    Rectangle {
                        anchors.fill: parent
                        color: "#0a0505"
                        border.color: Qt.rgba(204/255,21/255,21/255,0.2); border.width: 0
                    }
                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width; height: 1
                        color: Qt.rgba(224/255,50/255,50/255,0.4)
                    }
                    // Corner ticks (+)
                    Text {
                        text: "+"; font.pixelSize: 10
                        color: Qt.rgba(224/255,50/255,50/255,0.5)
                        x: -2; y: -6
                    }
                    Text {
                        text: "+"; font.pixelSize: 10
                        color: Qt.rgba(224/255,50/255,50/255,0.5)
                        anchors.right: parent.right; anchors.rightMargin: -2; y: -6
                    }

                    // Ticker défilant
                    Item {
                        anchors.fill: parent; clip: true
                        Text {
                            id:   ticker
                            text: "NR-2B // " + root.mpArtist + " // " + root.mpTitle
                                  + " // LOSSLESS 48kHz/24bit // NOW PLAYING //\u00a0"
                            font.family: "Share Tech Mono"
                            font.pixelSize: s(8)
                            font.letterSpacing: 1
                            color: Qt.rgba(204/255,21/255,21/255,0.4)
                            y: 3
                            NumberAnimation on x {
                                from: pw; to: -ticker.implicitWidth
                                duration: 22000; loops: Animation.Infinite; running: true
                            }
                        }
                    }
                }

                // ── MAIN ROW — glyph carré + panel large ──
                Row {
                    id: mainRow
                    width: pw
                    spacing: 0

                    // ── GLYPH BOX ──
                    Item {
                        id: glyphBox
                        width: coverSz; height: coverSz

                        Rectangle {
                            anchors.fill: parent
                            color: Settings.playerBackground ? Settings.playerBgColor : "#0a0505"
                            border.color: Qt.rgba(204/255,21/255,21/255,0.35); border.width: 1
                        }

                        Item {
                            id:     coverArea
                            anchors.fill: parent
                            anchors.margins: 1
                            clip: true

                            property var hoverIntensity: new Array(32*32).fill(0)
                            property var hoverR:         new Array(32*32).fill(200)
                            property var hoverG:         new Array(32*32).fill(184)
                            property var hoverB:         new Array(32*32).fill(154)

                            Canvas {
                                id:     coverMain
                                width:  coverSz; height: coverSz
                                smooth: false

                                property var  imgPixels:     null
                                property var  nextImgPixels: null
                                property int  blockStep:     0

                                onPaint: {
                                    var ctx  = getContext("2d")
                                    var GRID = 32, SZ = width
                                    var CELL = SZ / 32.0
                                    ctx.clearRect(0, 0, SZ, SZ)

                                    if (!imgPixels) {
                                        var seed = root.mpTitle.length * 1234567 + root.mpArtist.length * 89 + 42
                                        function rand() { seed=(seed*16807+0)%2147483647; return(seed-1)/2147483646 }
                                        for (var r=0; r<GRID; r++) for (var cc=0; cc<GRID; cc++) {
                                            var n=rand(); var dx=(cc-GRID/2)/(GRID/2); var dy=(r-GRID/2)/(GRID/2)
                                            var d=Math.sqrt(dx*dx+dy*dy)
                                            var v=Math.max(0,Math.min(255,(1-d*0.55)*210+n*70-30))
                                            ctx.fillStyle="rgb("+Math.round(v)+","+Math.round(v)+","+Math.round(v)+")"
                                            ctx.fillRect(Math.floor(cc*CELL),Math.floor(r*CELL),Math.floor(CELL)-1,Math.floor(CELL)-1)
                                        }
                                        return
                                    }

                                    var bs = (blockStep === 0) ? Math.floor(CELL) : Math.floor(CELL) + blockStep
                                    bs = Math.max(1, bs)

                                    var src = imgPixels
                                    var cols = Math.ceil(SZ / bs)
                                    var rows = Math.ceil(SZ / bs)
                                    for (var row=0; row<rows; row++) for (var col=0; col<cols; col++) {
                                        var sx  = Math.min(col*bs + Math.floor(bs/2), SZ-1)
                                        var sy  = Math.min(row*bs + Math.floor(bs/2), SZ-1)
                                        var idx = (sy*SZ + sx)*4
                                        var lum = 0.299*src[idx] + 0.587*src[idx+1] + 0.114*src[idx+2]
                                        var gv  = Math.round(Math.min(255, Math.max(0, (lum-10)*(255/235))))
                                        ctx.fillStyle = "rgb("+gv+","+gv+","+gv+")"
                                        ctx.fillRect(col*bs, row*bs, bs-1, bs-1)
                                    }
                                }

                                Component.onCompleted: requestPaint()

                                Connections {
                                    target: root
                                    function onMpTitleChanged() {
                                        if (!coverMain.imgPixels) coverMain.requestPaint()
                                    }
                                }
                            }

                            Timer {
                                id:       blockTimer
                                interval: 30; repeat: true; running: false
                                property int step: 0; property int steps: 12

                                onTriggered: {
                                    step++
                                    if (step < steps/2) {
                                        coverMain.blockStep = Math.floor(step * 3)
                                        coverMain.requestPaint()
                                    } else if (step === Math.floor(steps/2)) {
                                        if (coverMain.nextImgPixels) {
                                            coverMain.imgPixels = coverMain.nextImgPixels
                                            coverMain.nextImgPixels = null
                                        }
                                    } else {
                                        coverMain.blockStep = Math.floor((steps-step) * 3)
                                        coverMain.requestPaint()
                                    }
                                    if (step >= steps) { running = false; step = 0; coverMain.blockStep = 0 }
                                }
                            }

                            Image {
                                id:       coverSrc
                                width:    coverSz; height: coverSz
                                visible:  true; opacity: 0
                                smooth:   false
                                fillMode: Image.PreserveAspectCrop
                                z:        -1

                                onStatusChanged: {
                                    if (status !== Image.Ready) return
                                    grabToImage(function(result) {
                                        extractCanvas.grabResult = result
                                        extractCanvas.requestPaint()
                                    }, Qt.size(coverSz, coverSz))
                                }
                            }

                            Canvas {
                                id:      extractCanvas
                                width:   coverSz; height: coverSz
                                visible: false
                                property var grabResult: null

                                onPaint: {
                                    if (!grabResult) return
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.drawImage(grabResult.url, 0, 0, width, height)
                                    var raw = ctx.getImageData(0, 0, width, height).data
                                    if (coverMain.imgPixels === null) {
                                        coverMain.imgPixels = raw
                                        coverMain.requestPaint()
                                    } else {
                                        coverMain.nextImgPixels = raw
                                        blockTimer.step = 0
                                        blockTimer.running = true
                                    }
                                    coverArea.hoverIntensity = new Array(32*32).fill(0)
                                    coverArea.hoverR = new Array(32*32).fill(200)
                                    coverArea.hoverG = new Array(32*32).fill(184)
                                    coverArea.hoverB = new Array(32*32).fill(154)
                                    coverHover.requestPaint()
                                }
                            }

                            Connections {
                                target: root
                                function onMpCoverUrlChanged() {
                                    if (root.mpCoverUrl !== "") {
                                        coverSrc.source = ""
                                        coverSrc.source = root.mpCoverUrl
                                    } else {
                                        coverMain.imgPixels = null
                                        coverMain.requestPaint()
                                    }
                                }
                            }

                            Canvas {
                                id:     coverHover
                                width:  coverSz; height: coverSz
                                smooth: false; z: 2

                                onPaint: {
                                    var ctx  = getContext("2d")
                                    var GRID = 32, CELL = width/GRID
                                    var ci = coverArea.hoverIntensity
                                    var cr = coverArea.hoverR
                                    var cg = coverArea.hoverG
                                    var cb = coverArea.hoverB
                                    ctx.clearRect(0, 0, width, height)
                                    for (var r = 0; r < GRID; r++) for (var c = 0; c < GRID; c++) {
                                        var i = r*GRID + c
                                        if (ci[i] > 0.01) {
                                            ctx.fillStyle = "rgba(" + cr[i] + "," + cg[i] + "," + cb[i] + "," + ci[i] + ")"
                                            ctx.fillRect(c*CELL, r*CELL, Math.ceil(CELL)+1, Math.ceil(CELL)+1)
                                        }
                                    }
                                }
                            }

                            Timer {
                                id: decayTimer; interval: 16; repeat: true; running: false
                                onTriggered: {
                                    var ci = coverArea.hoverIntensity.slice()
                                    var active = false
                                    for (var i = 0; i < 32*32; i++) {
                                        if (ci[i] > 0) { ci[i] = Math.max(0, ci[i] - 0.014); active = true }
                                    }
                                    coverArea.hoverIntensity = ci
                                    coverHover.requestPaint()
                                    if (!active) decayTimer.running = false
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.CrossCursor
                                onPositionChanged: {
                                    var GRID = 32, CELL = coverSz/GRID, BRUSH_R = 2
                                    var cc = Math.floor(mouseX / CELL)
                                    var cr = Math.floor(mouseY / CELL)
                                    var ci = coverArea.hoverIntensity.slice()
                                    var cr2 = coverArea.hoverR.slice()
                                    var cg  = coverArea.hoverG.slice()
                                    var cb  = coverArea.hoverB.slice()
                                    var src = coverMain.imgPixels
                                    for (var dr = -BRUSH_R; dr <= BRUSH_R; dr++) {
                                        for (var dc = -BRUSH_R; dc <= BRUSH_R; dc++) {
                                            var nc = cc+dc, nr = cr+dr
                                            if (nc<0||nc>=GRID||nr<0||nr>=GRID) continue
                                            var dist = Math.sqrt(dc*dc + dr*dr)
                                            var alpha = Math.max(0, 1 - dist/(BRUSH_R+0.5))
                                            var strength = alpha*alpha
                                            if (strength < 0.01) continue
                                            if (src) {
                                                var sx  = Math.min(Math.floor(nc*CELL + CELL/2), coverSz-1)
                                                var sy  = Math.min(Math.floor(nr*CELL + CELL/2), coverSz-1)
                                                var idx = (sy*coverSz + sx)*4
                                                if (strength > ci[nr*GRID+nc]*0.6) {
                                                    cr2[nr*GRID+nc] = src[idx]
                                                    cg[nr*GRID+nc]  = src[idx+1]
                                                    cb[nr*GRID+nc]  = src[idx+2]
                                                }
                                            }
                                            ci[nr*GRID+nc] = Math.min(1, ci[nr*GRID+nc] + strength*0.9)
                                        }
                                    }
                                    coverArea.hoverIntensity = ci
                                    coverArea.hoverR = cr2; coverArea.hoverG = cg; coverArea.hoverB = cb
                                    coverHover.requestPaint()
                                    decayTimer.running = true
                                }
                                onExited: decayTimer.running = true
                            }

                            Item {
                                anchors.fill: parent; z: 3
                                Repeater {
                                    model: Math.ceil(coverSz/3)+1
                                    Rectangle {
                                        y:     index*3 + 2
                                        width: parent.width; height: 1
                                        color: Qt.rgba(0, 0, 0, 0.14)
                                    }
                                }
                            }
                        }
                    }

                    // ── PANEL (large, contient tout le reste) ──
                    Item {
                        id: panel
                        width: pw - coverSz
                        height: panelCol.implicitHeight + 18

                        Component.onCompleted: {
                            // Set coverSz to exact collapsed panel height (including 18px margins) for symmetry
                            root.coverSz = panelCol.implicitHeight + 18
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Settings.playerBackground ? Settings.playerBgColor : "transparent"
                            border.color: Qt.rgba(204/255,21/255,21/255,0.35); border.width: 1
                        }

                        Column {
                            id: panelCol
                            anchors { left: parent.left; top: parent.top; right: parent.right }
                            anchors.margins: 9
                            spacing: 0

                            // ── STATUS LINE ──
                            Row {
                                width: parent.width
                                spacing: 5
                                layoutDirection: Qt.RightToLeft

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "継衛 // 型17 // 衛人一号機"
                                    font.family: "Share Tech Mono"
                                    font.pixelSize: s(11)
                                    font.letterSpacing: 1
                                    color: Qt.rgba(204/255,21/255,21/255,0.35)
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5; height: 5
                                    color: Qt.rgba(224/255,50/255,50/255,0.8)
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.25; duration: 800 }
                                        NumberAnimation { to: 1;    duration: 800 }
                                    }
                                }
                            }

                            Item { width: 1; height: 6 }

                            // Titre
                            Text {
                                id:    ciTitle
                                width: parent.width
                                text:  root.mpTitle
                                font.family: "Share Tech Mono"
                                font.pixelSize: s(19)
                                font.weight: Font.Bold
                                font.letterSpacing: 1.5
                                color: Qt.rgba(224/255,50/255,50/255,0.95)
                                elide: Text.ElideRight

                                Behavior on text {
                                    SequentialAnimation {
                                        PropertyAnimation { target: ciTitle; property: "opacity"; to: 0; duration: 80 }
                                        PropertyAnimation { target: ciTitle; property: "x"; to: -10; duration: 0 }
                                        PropertyAnimation { target: ciTitle; property: "x"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                                        PropertyAnimation { target: ciTitle; property: "opacity"; to: 1; duration: 180 }
                                    }
                                }
                            }

                            Item { width: 1; height: 4 }

                            // Artiste
                            Text {
                                id:    ciArtist
                                width: parent.width
                                text:  root.mpArtist
                                font.family: "Share Tech Mono"
                                font.pixelSize: s(12)
                                font.letterSpacing: 1
                                color: Qt.rgba(204/255,21/255,21/255,0.5)
                                elide: Text.ElideRight
                            }

                            Item { width: 1; height: 9 }

                            // Tags
                            Row {
                                spacing: 6
                                Repeater {
                                    model: ["LOSSLESS","48k","FLAC"]
                                    Rectangle {
                                        implicitWidth: tagTxt.implicitWidth + 14
                                        height: s(19); color: "transparent"
                                        border.width: 1
                                        border.color: index < 2
                                            ? Qt.rgba(204/255,21/255,21/255,0.35)
                                            : Qt.rgba(204/255,21/255,21/255,0.18)
                                        Text {
                                            id: tagTxt
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.family: "Share Tech Mono"
                                            font.pixelSize: s(10)
                                            font.letterSpacing: 1
                                            color: index < 2
                                                ? Qt.rgba(204/255,21/255,21/255,0.6)
                                                : Qt.rgba(204/255,21/255,21/255,0.35)
                                        }
                                    }
                                }
                            }

                            Item { width: 1; height: 14 }

                            // Contrôles
                            Row {
                                spacing: 8

                                // PREV
                                CBtn {
                                    id: prevBtn
                                    onClicked: root.prevTrack()
                                    Text {
                                        anchors.centerIn: parent
                                        text: "◀"
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: 12
                                        color: prevBtn.textColor
                                        z: 1
                                    }
                                }

                                // PLAY / PAUSE
                                CBtn {
                                    id: playBtn
                                    isPlay: true
                                    onClicked: root.playPause()
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.mpPlaying ? "PAUSE" : "PLAY"
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: 7
                                        font.letterSpacing: 1
                                        color: playBtn.textColor
                                        z: 1
                                    }
                                }

                                // NEXT
                                CBtn {
                                    id: nextBtn
                                    onClicked: root.nextTrack()
                                    Text {
                                        anchors.centerIn: parent
                                        text: "▶"
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: 12
                                        color: nextBtn.textColor
                                        z: 1
                                    }
                                }
                            }

                            Item { width: 1; height: 14 }

                            // ── SEEK / PROGRESS ──
                            Item {
                                width: parent.width;  height: s(14)
                                Text {
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    text: root.fmtTime(root.mpPosition)
                                    font.family: "Share Tech Mono"; font.pixelSize: s(11); font.letterSpacing: 1
                                    color: Qt.rgba(204/255,21/255,21/255,0.5)
                                }
                                Text {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    text: root.fmtTime(root.mpLength)
                                    font.family: "Share Tech Mono"; font.pixelSize: s(11); font.letterSpacing: 1
                                    color: Qt.rgba(204/255,21/255,21/255,0.5)
                                }
                            }

                            Item { width: 1; height: 5 }

                            Item {
                                id:     seekBar
                                width:  parent.width;  height: s(4)

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 4
                                    color: Qt.rgba(204/255,21/255,21/255,0.15)
                                }
                                Rectangle {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left }
                                    height: 4
                                    color:  Qt.rgba(224/255,50/255,50/255,0.85)
                                    width:  root.mpLength > 0
                                            ? seekBar.width * root.mpPosition / root.mpLength
                                            : 0
                                }

                                MouseArea {
                                    anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                                    property bool dragging: false
                                    onPressed:  { dragging = true;  doSeek(mouseX) }
                                    onReleased: { dragging = false }
                                    onPositionChanged: if (dragging) doSeek(mouseX)
                                    function doSeek(mx) {
                                        var pct  = Math.max(0, Math.min(1, mx / seekBar.width))
                                        seekProc.seekSecs = pct * root.mpLength
                                        seekProc.running  = true
                                    }
                                }
                            }

                            Item { width: 1; height: 14 }

                            // ── TRACKS TOGGLE ──
                            CBtn {
                                id: tracksBtn
                                fullWidth: true
                                onClicked: root.showTrackList = !root.showTrackList
                                Text {
                                    anchors.centerIn: parent
                                    text: (root.showTrackList ? "▲ CLOSE" : "▼ TRACKS")
                                    font.family: "Share Tech Mono"
                                    font.pixelSize: s(11); font.letterSpacing: 2; font.weight: Font.Bold
                                    color: tracksBtn.textColor
                                    z: 1
                                }
                            }

                            // ── DRAWER (Smooth Push-Down) ──
                            Item {
                                id: drawer
                                width: parent.width
                                implicitHeight: root.showTrackList ? drawerCol.implicitHeight : 0
                                clip: true

                                Behavior on implicitHeight {
                                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                }

                                Column {
                                    id: drawerCol
                                    width: parent.width

                                    Rectangle {
                                        width: parent.width; height: 1
                                        color: Qt.rgba(204/255,21/255,21/255,0.15)
                                    }
                                    Item { width: 1; height: 10 }

                                    Repeater {
                                        model: root.localTracks
                                        Rectangle {
                                            width: parent.width; height: s(18)
                                            color: "transparent"
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.split("/").pop()
                                                font.family: "Share Tech Mono"; font.pixelSize: s(12)
                                                color: Qt.rgba(224/255,50/255,50/255,0.85)
                                                elide: Text.ElideRight; width: parent.width
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    root.localTrackSelected(modelData)
                                                    root.showTrackList = false
                                                }
                                            }
                                        }
                                    }

                                    Item { width: 1; height: 8 }
                                }
                            }

                            Item { width: 1; height: 9 }
                        }

                        CornerDeco {
                            anchors.fill: parent
                            lineColor: Qt.rgba(204/255,21/255,21/255,0.3)
                            size: 18
                            z:    5
                        }
                    }
                }
            }
        }

        // ── RIDEAU ──
        Rectangle {
            id:    curtain
            anchors { top: parent.top; bottom: parent.bottom }
            color: "#e8e8e8"
            z:     10
            width: 2
            x:     pw-2
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // TOGGLE ANIMATIONS
    // ─────────────────────────────────────────────────────────────────

    SequentialAnimation {
        id: revealAnim

        ParallelAnimation {
            NumberAnimation {
                target: wipeHost; property: "x"
                from: pw+2; to: 0
                duration: 460
                easing.type: Easing.OutExpo
            }
            NumberAnimation {
                target: curtain; property: "width"
                from: pw; to: pw
                duration: 460
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: curtain; property: "x"
                from: 0; to: 0
                duration: 340
            }
            NumberAnimation {
                target: curtain; property: "width"
                from: pw; to: 0
                duration: 340
                easing.type: Easing.OutExpo
            }
        }

        onStarted: {
            wipeHost.x = pw+2
            wipeHost.opacity = 1
            wipeHost.visible = true
            curtain.x        = 0
            curtain.width = pw
        }
        onFinished: {
            wipeHost.x    = 0
            curtain.x     = 0
            curtain.width = 0
            titleSlideIn.start()
            artistFadeIn.start()
        }
    }

    SequentialAnimation {
        id: hideAnim

        ParallelAnimation {
            NumberAnimation {
                target: curtain; property: "x"
                from: 0; to: 0
                duration: 180
            }
            NumberAnimation {
                target: curtain; property: "width"
                from: 0; to: pw
                duration: 180
                easing.type: Easing.InOutQuart
            }
        }

        NumberAnimation {
            target: wipeHost; property: "x"
            from: 0; to: pw+2
            duration: 380
            easing.type: Easing.InExpo
        }

        onStarted: {
            curtain.x     = 0
            curtain.width = 0
        }
        onFinished: {
            wipeHost.visible = false
            wipeHost.x = pw+2
            curtain.x        = 0
            curtain.width = pw
        }
    }

    SequentialAnimation {
        id: titleSlideIn
        PropertyAction  { target: ciTitle;  property: "x";       value: -12 }
        PropertyAction  { target: ciTitle;  property: "opacity";  value: 0  }
        PropertyAction  { target: ciArtist; property: "opacity";  value: 0  }
        PauseAnimation  { duration: 80 }
        ParallelAnimation {
            NumberAnimation { target: ciTitle;  property: "x";      from: -12; to: 0; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: ciTitle;  property: "opacity"; from: 0;  to: 1; duration: 200 }
        }
    }
    NumberAnimation {
        id: artistFadeIn
        target: ciArtist; property: "opacity"
        from: 0; to: 1
        duration: 280
        easing.type: Easing.OutQuad
    }

    // ── SEEK PROCESS ──
    Process {
        id: seekProc
        property real seekSecs: 0
        command: ["playerctl", "position", String(Math.round(seekSecs))]
        running: false
    }

    // ── CLOCK ──
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            var d = new Date()
            root.clockStr = String(d.getHours()).padStart(2,"0") + ":"
                          + String(d.getMinutes()).padStart(2,"0")
        }
    }

    // ── API PUBLIQUE ──
    function toggleVisible() {
        if (root.shown) {
            root.shown = false
            revealAnim.stop()
            hideAnim.start()
        } else {
            root.shown = true
            hideAnim.stop()
            revealAnim.start()
        }
    }

    // ── Expose toggle via IPC Quickshell ──
    IpcHandler {
        target: "player"
        function toggle(): void { root.toggleVisible() }
        function show(): void   { if (!root.shown) root.toggleVisible() }
        function hide(): void   { if ( root.shown) root.toggleVisible() }
    }

    function fmtTime(secs) {
        if (isNaN(secs) || secs === undefined || secs === null) return "0:00"
        var s = Math.max(0, Math.floor(secs))
        return Math.floor(s/60) + ":" + String(s%60).padStart(2,"0")
    }

    Component.onCompleted: {
        var d = new Date()
        clockStr = String(d.getHours()).padStart(2,"0") + ":" + String(d.getMinutes()).padStart(2,"0")
    }

    // ── COMPOSANT BOUTON CONTRÔLE ──
    component CBtn: Item {
        id:            btnRoot
        property bool isPlay:  false
        property bool fullWidth: false
        signal clicked

        width:  fullWidth ? btnRoot.parent.width : (isPlay ? 44 : 22)
        height: 22

        Rectangle {
            anchors.fill: parent; color: "transparent"
            border.width: 1
            border.color: parent.isPlay
                ? Qt.rgba(204/255,21/255,21/255,0.3)
                : Qt.rgba(204/255,21/255,21/255,0.3)

            Rectangle {
                id:    cbFill
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 0; z: 0
                color: Qt.rgba(204/255,21/255,21/255,0.8)
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.InOutQuart } }
            }
        }

        property color textColor: cbMa.containsMouse
            ? "#0a0a0a"
            : (isPlay
                ? Qt.rgba(204/255,21/255,21/255,0.85)
                : Qt.rgba(204/255,21/255,21/255,0.65))

        MouseArea {
            id:           cbMa
            anchors.fill: parent
            hoverEnabled: true
            onEntered:    cbFill.width = btnRoot.width
            onExited:     cbFill.width = 0
            onClicked:    btnRoot.clicked()
            onPressed:    btnRoot.scale = 0.95
            onReleased:   btnRoot.scale = 1.0
        }
    }
}
