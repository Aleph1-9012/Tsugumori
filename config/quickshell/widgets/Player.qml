import QtQuick
import QtQuick.Effects
import "../components"
import "../settings"

Item {
    id: root

    // ── Shorthand Settings (scale global) ──
    readonly property int  pw:      Settings.playerWidth
    readonly property real sc:      Settings.scale
    readonly property color surfaceColor: Settings.playerBackground
                                          ? Settings.playerBgColor
                                          : "transparent"
    property int  coverSz: s(200)   // Calculated dynamically for 100% bottom symmetry
    function s(px) { return Math.round(px * sc) }

    function progressFraction(position, length) {
        var pos = Number(position)
        var total = Number(length)
        if (!Number.isFinite(pos) || !Number.isFinite(total) || total <= 0)
            return 0
        return Math.max(0, Math.min(1, pos / total))
    }

    function placeholderSeed() {
        var text = mpTitle + "\u0000" + mpArtist
        var hash = 5381
        for (var i = 0; i < text.length; ++i)
            hash = (hash * 33 + text.charCodeAt(i)) % 2147483647
        return Math.max(1, hash)
    }

    function clearCoverVisual() {
        coverRetryTimer.stop()
        hoverDecayTimer.stop()
        coverImage.retryCount = 0
        coverImage.requestGeneration = -1
        coverImage.mediaUrl = ""
        coverImage.requestedUrl = ""
        coverImage.source = ""
        hoverMask.clearMask()
    }

    function requestCoverLoad() {
        coverGeneration++
        coverRetryTimer.stop()
        hoverDecayTimer.stop()
        hoverMask.clearMask()
        coverImage.retryCount = 0
        coverImage.fallbackAttempted = false

        var requested = String(mpCoverUrl)
        coverImage.mediaUrl = requested
        if (requested.length > 0)
            startCoverDecode(coverGeneration, requested)
        else
            clearCoverVisual()
    }

    function startCoverDecode(generation, url) {
        if (generation !== coverGeneration
                || coverImage.mediaUrl !== String(mpCoverUrl))
            return

        coverImage.requestGeneration = generation
        coverImage.requestedUrl = url
        // Force a fresh asynchronous decode. This matters for browser artwork
        // backed by short-lived cache files whose URL may be reused.
        coverImage.source = ""
        coverImage.source = url
    }

    function handleCoverDecodeFailure(generation, url) {
        if (generation !== coverGeneration
                || url !== coverImage.requestedUrl
                || coverImage.mediaUrl !== String(mpCoverUrl))
            return

        if (coverImage.retryCount < 4) {
            coverImage.retryCount++
            coverRetryTimer.generation = generation
            coverRetryTimer.url = url
            coverRetryTimer.restart()
            return
        }

        // YouTube's highest-resolution thumbnail is optional. Keep the media
        // URL stable for generation guards, but try its reliable HQ variant
        // after the bounded maxres retries are exhausted.
        if (!coverImage.fallbackAttempted && url.indexOf("maxresdefault.jpg") >= 0) {
            coverImage.fallbackAttempted = true
            coverImage.retryCount = 0
            coverImage.requestedUrl = url.replace("maxresdefault.jpg", "hqdefault.jpg")
            coverImage.source = ""
            coverImage.source = coverImage.requestedUrl
            return
        }

        // Do not leave the previous track's artwork under a broken URL.
        coverImage.requestGeneration = -1
        coverImage.source = ""
        hoverMask.clearMask()
    }

    // ── Media state supplied by shell.qml ──
    property string mpTitle:    "END OF EVANGELION"
    property string mpArtist:   "NEON GENESIS // ANNO"
    property string mpCoverUrl: ""
    property bool   mpPlaying:  false
    property real   mpPosition: 0
    property real   mpLength:   341
    property bool   localMode:  false
    property bool   mediaAvailable: true

    signal playPause
    signal nextTrack
    signal prevTrack
    signal seekToSecs(real secs)
    property var    localTracks: []
    property int    localTrackIndex: -1
    property bool   showTrackList: false
    signal localTrackSelected(string path)

    // This is the single visibility source of truth. shell.qml binds it to its
    // global playerVisible state, so late-created monitor instances immediately
    // converge on the correct state instead of waiting for a toggle edge.
    property bool requestedVisible: false
    property real revealProgress: 0
    property bool componentReady: false
    readonly property int currentInputX: wipeHost.visible
                                         ? Math.max(0, Math.min(pw, Math.round(
                                               Math.max(wipeHost.x, curtain.width))))
                                         : pw
    readonly property int currentInputWidth: wipeHost.visible
                                             ? Math.max(0, pw - currentInputX)
                                             : 0
    readonly property bool shown: currentInputWidth > 0

    onRequestedVisibleChanged: animateVisibility()

    // Keep the track drawer bounded even for very large music libraries.
    readonly property int drawerMaxHeight: s(240)
    readonly property int trackCount: localTracks && localTracks.length !== undefined
                                      ? localTracks.length : 0
    readonly property int drawerNaturalHeight: Math.min(drawerMaxHeight,
        trackCount > 0
            ? s(12) + trackCount * s(24) + Math.max(0, trackCount - 1) * s(4)
            : s(44))

    onDrawerNaturalHeightChanged: {
        var theoreticalMax = collapsedBaseHeight + drawerNaturalHeight
        if (theoreticalMax > maxContentHeight)
            maxContentHeight = theoreticalMax
    }

    // Invalidates asynchronous image work from an older URL.
    property int coverGeneration: 0
    readonly property bool coverArtReady: coverImage.status === Image.Ready

    // ── Window sizing: buffer stays CONSTANT (no resize → no Wayland jump) ──
    // Real fix for the "dead zone blocks clicks/scroll/hover" bug is the PanelWindow's
    // `mask` in shell.qml, not this. This property just needs to (a) never shrink the
    // buffer, to avoid a visible resize pop, while (b) still growing to fit the tallest
    // state the drawer ever reaches, so content never gets clipped by the window itself.
    property int  maxContentHeight: 0
    // Captured once at startup (drawer is guaranteed collapsed=0 at that point) — the
    // "everything except the drawer" height. Combined with the drawer's bounded natural
    // height, this lets us reserve the true expanded-state total analytically, WITHOUT
    // ever letting the drawer actually expand beyond its scrolling viewport.
    // That's what lets maxContentHeight get reserved proactively, before the user ever
    // opens the drawer — so the real open/close animation below can freely animate the
    // actual visible height (border included) with zero Wayland-buffer risk.
    property real collapsedBaseHeight: 0
    // Real, exact current visible height (collapsed or expanded) — changes instantly,
    // no animation — used by shell.qml to size the input mask precisely to what's
    // actually drawn right now, independent of the padded window buffer above.
    readonly property int currentContentHeight: content.implicitHeight

    onCurrentContentHeightChanged: {
        if (currentContentHeight > maxContentHeight) maxContentHeight = currentContentHeight
    }

    implicitWidth:  pw
    implicitHeight: maxContentHeight > 0 ? maxContentHeight : currentContentHeight

    // ──────────────────────────────────────────────────────────────
    // WIPE HOST — Item clipé contenant rideau + contenu comme frères
    // ──────────────────────────────────────────────────────────────
    Item {
        id:      wipeHost
        width:   pw
        height:  content.implicitHeight
        clip:    true
        x: root.revealProgress < 0.58
             ? (pw + 2) * (1 - root.revealProgress / 0.58)
             : 0
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
                        color: root.surfaceColor
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
                            text: root.mediaAvailable
                                  ? "NR-2B // " + root.mpArtist + " // " + root.mpTitle
                                    + " // " + (root.localMode ? "LOCAL SOURCE" : "MPRIS SOURCE")
                                    + " // " + (root.mpPlaying ? "NOW PLAYING" : "PAUSED")
                                    + " //\u00a0"
                                  : "NR-2B // NO MEDIA SOURCE // IDLE //\u00a0"
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
                            color: root.surfaceColor
                            border.color: Qt.rgba(204/255,21/255,21/255,0.35); border.width: 1
                        }

                        Item {
                            id:     coverArea
                            anchors.fill: parent
                            anchors.margins: 1
                            clip: true

                            // Decode once at the source's native resolution. Both rendered
                            // layers use this exact item, so crop and pointer coordinates stay
                            // aligned regardless of compositor scale or monitor count.
                            Image {
                                id: coverImage
                                anchors.fill: parent
                                visible: false
                                asynchronous: true
                                cache: false
                                retainWhileLoading: false
                                fillMode: Image.PreserveAspectCrop
                                horizontalAlignment: Image.AlignHCenter
                                verticalAlignment: Image.AlignVCenter
                                smooth: true
                                mipmap: true
                                // Effects sample the Image's rendered layer so PreserveAspectCrop
                                // and both center alignments are retained by grayscale/color passes.
                                layer.enabled: true
                                layer.smooth: true
                                property string mediaUrl: ""
                                property string requestedUrl: ""
                                property int requestGeneration: -1
                                property int retryCount: 0
                                property bool fallbackAttempted: false

                                onStatusChanged: {
                                    if (requestGeneration !== root.coverGeneration)
                                        return

                                    if (status === Image.Ready) {
                                        coverRetryTimer.stop()
                                        retryCount = 0
                                    } else if (status === Image.Error) {
                                        root.handleCoverDecodeFailure(requestGeneration,
                                                                      requestedUrl)
                                    }
                                }
                            }

                            MultiEffect {
                                anchors.fill: parent
                                source: coverImage
                                saturation: -1.0
                                visible: root.coverArtReady
                            }

                            Canvas {
                                id: hoverMask
                                anchors.fill: parent
                                renderTarget: Canvas.FramebufferObject
                                property real cursorX: -1000
                                property real cursorY: -1000
                                property real opacityLevel: 0
                                property var trailPoints: []
                                readonly property real brushRadius: Math.max(24, width * 0.16)
                                readonly property int trailCellSize: Math.max(5, Math.round(width / 40))
                                readonly property int trailMaxPoints: 48
                                readonly property real trailStartOpacity: 0.36
                                readonly property int trailDurationMs: 480
                                readonly property int trailAlphaBuckets: 12

                                function clearMask() {
                                    hoverTrailTimer.stop()
                                    trailPoints = []
                                    cursorX = -1000
                                    cursorY = -1000
                                    opacityLevel = 0
                                    requestPaint()
                                }

                                function addTrailPoint(x, y) {
                                    var points = trailPoints.slice(0)
                                    var last = points.length > 0 ? points[points.length - 1] : null
                                    var now = Date.now()

                                    if (last) {
                                        var dx = x - last.x
                                        var dy = y - last.y
                                        var distance = Math.sqrt(dx * dx + dy * dy)
                                        if (distance < 0.75)
                                            return

                                        // Fill gaps between pointer events without snapping the
                                        // cursor itself. Pixelation is applied only while painting.
                                        var spacing = Math.max(2, trailCellSize * 0.75)
                                        var steps = Math.max(1, Math.ceil(distance / spacing))
                                        for (var step = 1; step <= steps; ++step) {
                                            var amount = step / steps
                                            points.push({ x: last.x + dx * amount,
                                                          y: last.y + dy * amount,
                                                          born: now })
                                        }
                                    } else {
                                        points.push({ x: x, y: y, born: now })
                                    }

                                    if (points.length > trailMaxPoints)
                                        points.splice(0, points.length - trailMaxPoints)
                                    trailPoints = points
                                    if (!hoverTrailTimer.running)
                                        hoverTrailTimer.start()
                                }

                                function fadeTrail() {
                                    var points = trailPoints
                                    var faded = []
                                    var now = Date.now()
                                    for (var i = 0; i < points.length; ++i) {
                                        if (now - points[i].born < trailDurationMs)
                                            faded.push(points[i])
                                    }
                                    trailPoints = faded
                                    requestPaint()
                                    if (faded.length === 0)
                                        hoverTrailTimer.stop()
                                }

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    var points = trailPoints
                                    var cell = trailCellSize
                                    var cols = Math.ceil(width / cell)
                                    var rows = Math.ceil(height / cell)
                                    var cellLevels = new Array(cols * rows)
                                    var now = Date.now()
                                    for (var i = 0; i < points.length; ++i) {
                                        var radius = brushRadius
                                        var radiusSquared = radius * radius
                                        var age = now - points[i].born
                                        var remaining = Math.max(0, 1 - age / trailDurationMs)
                                        var level = Math.max(1, Math.ceil(remaining * trailAlphaBuckets))
                                        var minCol = Math.max(0, Math.floor((points[i].x - radius) / cell))
                                        var maxCol = Math.min(cols - 1, Math.floor((points[i].x + radius) / cell))
                                        var minRow = Math.max(0, Math.floor((points[i].y - radius) / cell))
                                        var maxRow = Math.min(rows - 1, Math.floor((points[i].y + radius) / cell))

                                        for (var row = minRow; row <= maxRow; ++row) {
                                            for (var col = minCol; col <= maxCol; ++col) {
                                                var cx = (col + 0.5) * cell
                                                var cy = (row + 0.5) * cell
                                                var dx = cx - points[i].x
                                                var dy = cy - points[i].y
                                                if (dx * dx + dy * dy <= radiusSquared) {
                                                    var index = row * cols + col
                                                    cellLevels[index] = Math.max(cellLevels[index] || 0,
                                                                                 level)
                                                }
                                            }
                                        }
                                    }

                                    // Collapse overlapping stamps into one draw per pixel cell,
                                    // grouped by opacity so dual-monitor repaints stay lightweight.
                                    var buckets = new Array(trailAlphaBuckets + 1)
                                    for (var bucket = 1; bucket <= trailAlphaBuckets; ++bucket)
                                        buckets[bucket] = []
                                    for (var index = 0; index < cellLevels.length; ++index) {
                                        var cellLevel = cellLevels[index] || 0
                                        if (cellLevel > 0)
                                            buckets[cellLevel].push(index)
                                    }
                                    for (var bucket = 1; bucket <= trailAlphaBuckets; ++bucket) {
                                        var bucketCells = buckets[bucket]
                                        if (bucketCells.length === 0)
                                            continue
                                        ctx.beginPath()
                                        for (var entry = 0; entry < bucketCells.length; ++entry) {
                                            var index = bucketCells[entry]
                                            var col = index % cols
                                            var row = Math.floor(index / cols)
                                            var x = col * cell
                                            var y = row * cell
                                            ctx.rect(x, y, Math.min(cell, width - x),
                                                     Math.min(cell, height - y))
                                        }
                                        ctx.fillStyle = "rgba(255,255,255," +
                                                        (trailStartOpacity * bucket /
                                                         trailAlphaBuckets) + ")"
                                        ctx.fill()
                                    }

                                    if (opacityLevel <= 0.001)
                                        return

                                    var gradient = ctx.createRadialGradient(cursorX, cursorY, 0,
                                                                            cursorX, cursorY,
                                                                            brushRadius)
                                    gradient.addColorStop(0, "rgba(255,255,255," + opacityLevel + ")")
                                    gradient.addColorStop(0.58, "rgba(255,255,255," + (opacityLevel * 0.72) + ")")
                                    gradient.addColorStop(1, "rgba(255,255,255,0)")
                                    ctx.fillStyle = gradient
                                    ctx.fillRect(cursorX - brushRadius, cursorY - brushRadius,
                                                 brushRadius * 2, brushRadius * 2)
                                }
                            }

                            // Canvas can paint while hidden without exposing a texture to an
                            // effect on every renderer. Capture it explicitly, hide only its
                            // scene representation, and feed the live texture to MultiEffect.
                            ShaderEffectSource {
                                id: hoverMaskTexture
                                anchors.fill: parent
                                sourceItem: hoverMask
                                hideSource: true
                                live: true
                                recursive: false
                                visible: false
                            }

                            MultiEffect {
                                anchors.fill: parent
                                source: coverImage
                                visible: root.coverArtReady
                                         && (hoverMask.opacityLevel > 0.001
                                             || hoverMask.trailPoints.length > 0)
                                maskEnabled: true
                                maskSource: hoverMaskTexture
                            }

                            Timer {
                                id: coverRetryTimer
                                interval: 300
                                property int generation: -1
                                property string url: ""
                                onTriggered: {
                                    if (generation !== root.coverGeneration
                                            || url !== coverImage.requestedUrl
                                            || coverImage.mediaUrl !== String(root.mpCoverUrl))
                                        return
                                    root.startCoverDecode(generation, url)
                                }
                            }

                            Connections {
                                target: root
                                function onMpCoverUrlChanged() {
                                    root.requestCoverLoad()
                                }
                            }

                            Timer {
                                id: hoverDecayTimer
                                interval: 16
                                repeat: true
                                onTriggered: {
                                    hoverMask.opacityLevel = Math.max(0, hoverMask.opacityLevel - 0.045)
                                    hoverMask.requestPaint()
                                    if (hoverMask.opacityLevel <= 0)
                                        stop()
                                }
                            }

                            Timer {
                                id: hoverTrailTimer
                                interval: 16
                                repeat: true
                                onTriggered: hoverMask.fadeTrail()
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: 4
                                hoverEnabled: true
                                cursorShape: Qt.CrossCursor
                                onPositionChanged: {
                                    hoverDecayTimer.stop()
                                    hoverMask.addTrailPoint(mouseX, mouseY)
                                    hoverMask.cursorX = mouseX
                                    hoverMask.cursorY = mouseY
                                    hoverMask.opacityLevel = 1
                                    hoverMask.requestPaint()
                                }
                                onExited: hoverDecayTimer.start()
                            }

                            Canvas {
                                id: coverPlaceholder
                                anchors.fill: parent
                                visible: !root.coverArtReady
                                smooth: false

                                onPaint: {
                                    var ctx = getContext("2d")
                                    var size = width
                                    var grid = 32
                                    var seed = root.placeholderSeed()
                                    function rand() {
                                        seed = (seed * 16807) % 2147483647
                                        return (seed - 1) / 2147483646
                                    }
                                    ctx.clearRect(0, 0, width, height)
                                    for (var row = 0; row < grid; row++) {
                                        for (var col = 0; col < grid; col++) {
                                            var noise = rand()
                                            var dx = (col - grid / 2) / (grid / 2)
                                            var dy = (row - grid / 2) / (grid / 2)
                                            var distance = Math.sqrt(dx * dx + dy * dy)
                                            var value = Math.max(0, Math.min(255,
                                                (1 - distance * 0.55) * 210 + noise * 70 - 30))
                                            ctx.fillStyle = "rgb(" + Math.round(value) + ","
                                                                   + Math.round(value) + ","
                                                                   + Math.round(value) + ")"
                                            var x0 = Math.floor(col * size / grid)
                                            var x1 = Math.floor((col + 1) * size / grid)
                                            var y0 = Math.floor(row * size / grid)
                                            var y1 = Math.floor((row + 1) * size / grid)
                                            ctx.fillRect(x0, y0, x1 - x0, y1 - y0)
                                        }
                                    }
                                }

                                Connections {
                                    target: root
                                    function onMpTitleChanged() { coverPlaceholder.requestPaint() }
                                    function onMpArtistChanged() { coverPlaceholder.requestPaint() }
                                }
                            }

                            Item {
                                anchors.fill: parent; z: 3
                                // The scanline motif belongs to the generated placeholder.
                                // Real artwork remains edge-to-edge and unobscured.
                                visible: !root.coverArtReady
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
                        height: panelCol.implicitHeight + s(18)

                        Connections {
                            target: panelCol
                            function onImplicitHeightChanged() {
                                if (!root.showTrackList && drawer.implicitHeight === 0) {
                                    root.coverSz = panelCol.implicitHeight + s(18)
                                }
                            }
                        }

                        Component.onCompleted: {
                            root.coverSz = panelCol.implicitHeight + s(18)
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: root.surfaceColor
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

                            Item { width: 1; height: s(6) }

                            // Divider — quiet break before the title
                            Rectangle {
                                width: parent.width; height: 1
                                color: Qt.rgba(204/255,21/255,21/255,0.15)
                            }

                            Item { width: 1; height: s(8) }

                            // Titre
                            Row {
                                width:   parent.width
                                spacing: 0

                                Text {
                                    id:    titlePrefix
                                    text:  "// "
                                    font.family: "Share Tech Mono"
                                    font.pixelSize: s(21)
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.5
                                    color: Qt.rgba(224/255,50/255,50/255,0.4)
                                }

                                // Wrapper isolates ciTitle's own x=0 baseline so the existing
                                // titleSlideIn reveal animation and the text-change Behavior
                                // (both target ciTitle.x with absolute values like -12/-10/0)
                                // keep working unchanged — they don't need to know a prefix exists.
                                Item {
                                    width:  parent.width - titlePrefix.implicitWidth
                                    height: ciTitle.implicitHeight
                                    clip:   true

                                    Text {
                                        id:    ciTitle
                                        width: parent.width
                                        text:  root.mpTitle
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: s(21)
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
                                }
                            }

                            Item { width: 1; height: 4 }

                            // Artiste
                            Text {
                                id:    ciArtist
                                width: parent.width
                                text:  root.mpArtist
                                font.family: "Share Tech Mono"
                                font.pixelSize: s(13)
                                font.letterSpacing: 1
                                color: Qt.rgba(204/255,21/255,21/255,0.5)
                                elide: Text.ElideRight
                            }

                            Item { width: 1; height: 9 }

                            // Tags
                            Row {
                                spacing: 6
                                Repeater {
                                    model: root.mediaAvailable
                                           ? [root.localMode ? "LOCAL" : "MPRIS",
                                              root.mpPlaying ? "PLAYING" : "PAUSED",
                                              "AUDIO"]
                                           : ["NO SOURCE", "IDLE", "MEDIA"]
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

                            Item { width: 1; height: 12 }

                            // ── CONTRÔLES (MOCKUP PILL BUTTONS) ──
                            Row {
                                width: parent.width
                                spacing: s(8)

                                // PREV
                                CBtn {
                                    id: prevBtn
                                    width: s(46)
                                    height: s(32)
                                    radius: 0
                                    onClicked: root.prevTrack()
                                    Text {
                                        anchors.centerIn: parent
                                        text: "«"
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: s(15)
                                        font.weight: Font.Bold
                                        color: prevBtn.textColor
                                        z: 1
                                    }
                                }

                                // PLAY / PAUSE (WIDE PILL)
                                CBtn {
                                    id: playBtn
                                    isPlay: true
                                    width: parent.width - (s(46) * 2) - s(16)
                                    height: s(32)
                                    radius: 0
                                    onClicked: root.playPause()
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.mpPlaying ? "PAUSE" : "PLAY"
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: s(13)
                                        font.weight: Font.Bold
                                        font.letterSpacing: 2
                                        color: playBtn.textColor
                                        z: 1
                                    }
                                }

                                // NEXT
                                CBtn {
                                    id: nextBtn
                                    width: s(46)
                                    height: s(32)
                                    radius: 0
                                    onClicked: root.nextTrack()
                                    Text {
                                        anchors.centerIn: parent
                                        text: "»"
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: s(15)
                                        font.weight: Font.Bold
                                        color: nextBtn.textColor
                                        z: 1
                                    }
                                }
                            }

                            Item { width: 1; height: 12 }

                            // ── SEEK / PROGRESS ──
                            Column {
                                width: parent.width
                                spacing: s(4)

                                // Progress Line
                                Item {
                                    id:     seekBar
                                    width:  parent.width;  height: s(6)

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: s(4)
                                        radius: s(2)
                                        color: Qt.rgba(204/255,21/255,21/255,0.15)
                                    }
                                    Rectangle {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left }
                                        height: s(4)
                                        radius: s(2)
                                        color:  Qt.rgba(224/255,50/255,50/255,0.9)
                                        width: seekBar.width * root.progressFraction(
                                                   root.mpPosition, root.mpLength)
                                    }

                                    MouseArea {
                                        anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                                        property bool dragging: false
                                        onPressed:  { dragging = true;  doSeek(mouseX) }
                                        // Always send the release coordinate. If an earlier
                                        // drag update was coalesced by the backend, the user's
                                        // final intended position still wins.
                                        onReleased: { doSeek(mouseX); dragging = false }
                                        onPositionChanged: if (dragging) doSeek(mouseX)
                                        function doSeek(mx) {
                                            if (seekBar.width <= 0 || root.mpLength <= 0)
                                                return
                                            var pct = Math.max(0, Math.min(1, mx / seekBar.width))
                                            var targetSecs = pct * root.mpLength
                                            // shell.qml owns backend selection and command
                                            // serialization for both local and MPRIS media.
                                            root.seekToSecs(targetSecs)
                                        }
                                    }
                                }

                                // Timestamp Readouts
                                Item {
                                    width: parent.width;  height: s(14)
                                    Text {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        text: root.fmtTime(root.mpPosition)
                                        font.family: "Share Tech Mono"; font.pixelSize: s(12); font.letterSpacing: 1
                                        color: Qt.rgba(204/255,21/255,21/255,0.5)
                                    }
                                    Text {
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        text: root.fmtTime(root.mpLength)
                                        font.family: "Share Tech Mono"; font.pixelSize: s(12); font.letterSpacing: 1
                                        color: Qt.rgba(204/255,21/255,21/255,0.5)
                                    }
                                }
                            }

                            Item { width: 1; height: 10 }

                            // ── TRACKS TOGGLE BUTTON ──
                            CBtn {
                                id: tracksBtn
                                fullWidth: true
                                height: s(30)
                                radius: 0
                                onClicked: root.showTrackList = !root.showTrackList
                                Text {
                                    anchors.centerIn: parent
                                    text: (root.showTrackList ? "▲ CLOSE" : "▼ TRACKS")
                                    font.family: "Share Tech Mono"
                                    font.pixelSize: s(12); font.letterSpacing: 2; font.weight: Font.Bold
                                    color: tracksBtn.textColor
                                    z: 1
                                }
                            }

                            // ── BOUNDED, SCROLLABLE TRACK DRAWER ──
                            Item {
                                id: drawer
                                width: parent.width
                                implicitHeight: root.showTrackList ? root.drawerNaturalHeight : 0
                                clip: true

                                Behavior on implicitHeight {
                                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                }

                                ListView {
                                    id: trackList
                                    anchors {
                                        fill: parent
                                        topMargin: s(6)
                                        bottomMargin: s(6)
                                        rightMargin: s(5)
                                    }
                                    model: root.localTracks
                                    spacing: s(4)
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    currentIndex: root.localTrackIndex
                                    keyNavigationEnabled: true
                                    reuseItems: true

                                    delegate: Item {
                                        width: trackList.width
                                        height: s(24)

                                        readonly property bool isCurrent: index === root.localTrackIndex
                                        readonly property string rawName: String(modelData).split("/").pop().replace(/\.[^.]+$/, "")
                                        readonly property string numStr: (index + 1 < 10 ? "0" : "") + (index + 1)

                                            // Hover / Active Background Highlight
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 0
                                                color: trackMa.containsMouse
                                                    ? Qt.rgba(204/255, 21/255, 21/255, 0.18)
                                                    : (isCurrent ? Qt.rgba(204/255, 21/255, 21/255, 0.08) : "transparent")
                                                border.width: 1
                                                border.color: trackMa.containsMouse
                                                    ? Qt.rgba(224/255, 50/255, 50/255, 0.3)
                                                    : Qt.rgba(224/255, 50/255, 50/255, 0.0)

                                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            }

                                            // Active Track / Hover Indicator Bar — grows + fades in smoothly instead of snapping on/off
                                            Rectangle {
                                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                                width: trackMa.containsMouse ? 4 : 3
                                                radius: 0
                                                color: Qt.rgba(224/255,50/255,50/255,0.95)
                                                opacity: isCurrent ? 1.0 : (trackMa.containsMouse ? 0.7 : 0.0)

                                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                                Behavior on width   { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            }

                                            // Track Info Row — subtle slide-in on hover
                                            Row {
                                                id: trackInfoRow
                                                anchors { fill: parent; leftMargin: s(10) + (trackMa.containsMouse ? s(3) : 0); rightMargin: s(6) }
                                                spacing: 0

                                                Behavior on anchors.leftMargin { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                                Text {
                                                    id: trackNumText
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: numStr + " // "
                                                    font.family: "Share Tech Mono"
                                                    font.pixelSize: s(13)
                                                    font.weight: (isCurrent || trackMa.containsMouse) ? Font.Bold : Font.Normal
                                                    font.letterSpacing: 1
                                                    color: Qt.rgba(224/255,50/255,50/255,0.95)
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: rawName
                                                    font.family: "Share Tech Mono"
                                                    font.pixelSize: s(13)
                                                    font.weight: (isCurrent || trackMa.containsMouse) ? Font.Bold : Font.Normal
                                                    font.letterSpacing: 1
                                                    color: (isCurrent || trackMa.containsMouse)
                                                        ? Qt.rgba(224/255,50/255,50/255,0.95)
                                                        : Qt.rgba(204/255,21/255,21/255,0.45)
                                                    elide: Text.ElideRight
                                                    width: trackInfoRow.width - trackNumText.implicitWidth

                                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                }
                                            }

                                            MouseArea {
                                                id: trackMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.localTrackSelected(modelData)
                                                    root.showTrackList = false
                                                }
                                            }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: root.trackCount === 0
                                    text: "NO LOCAL TRACKS FOUND"
                                    font.family: "Share Tech Mono"
                                    font.pixelSize: s(11)
                                    font.letterSpacing: 1
                                    color: Qt.rgba(204/255,21/255,21/255,0.5)
                                }

                                Rectangle {
                                    width: 2
                                    radius: 1
                                    color: Qt.rgba(224/255,50/255,50/255,0.55)
                                    visible: trackList.contentHeight > trackList.height
                                    height: visible
                                            ? Math.max(s(12), trackList.height * trackList.visibleArea.heightRatio)
                                            : 0
                                    x: drawer.width - width
                                    y: trackList.y + trackList.height * trackList.visibleArea.yPosition
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

                // ── FOOTER CAPTION BAR ──
                Item {
                    width: pw;  height: s(18)

                    Rectangle {
                        anchors.fill: parent
                        color: root.surfaceColor
                    }

                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width; height: 1
                        color: Qt.rgba(224/255,50/255,50/255,0.4)
                    }

                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: s(4) }
                        Text {
                            text: "SOURCE // " + (root.mediaAvailable
                                                   ? (root.localMode ? "LOCAL" : "MPRIS")
                                                   : "NONE")
                            font.family: "Share Tech Mono"; font.pixelSize: s(8); font.letterSpacing: 1.5
                            color: Qt.rgba(224/255,50/255,50/255,0.5)
                        }
                    }
                    Row {
                        anchors.centerIn: parent
                        Text {
                            text: "TSUGUMORI PLAYER"
                            font.family: "Share Tech Mono"; font.pixelSize: s(8); font.letterSpacing: 1.5
                            color: Qt.rgba(224/255,50/255,50/255,0.5)
                        }
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: s(4) }
                        Text {
                            text: "REV 2"
                            font.family: "Share Tech Mono"; font.pixelSize: s(8); font.letterSpacing: 1.5
                            color: Qt.rgba(224/255,50/255,50/255,0.5)
                        }
                    }
                }
            }
        }

        // ── RIDEAU ──
        Rectangle {
            id:    curtain
            anchors { top: parent.top; bottom: parent.bottom }
            color: Settings.curtainColor
            z:     10
            x: 0
            width: root.revealProgress <= 0.58
                     ? pw
                     : pw * (1 - (root.revealProgress - 0.58) / 0.42)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // REVERSIBLE VISIBILITY ANIMATION
    // ─────────────────────────────────────────────────────────────────
    // A single normalized progress value drives both the host and curtain. A
    // direction change therefore continues from the exact current frame instead
    // of resetting either animation to a hard-coded endpoint.
    NumberAnimation {
        id: visibilityAnim
        target: root
        property: "revealProgress"
        easing.type: Easing.InOutCubic
        onFinished: {
            root.revealProgress = root.requestedVisible ? 1 : 0
            if (!root.requestedVisible)
                wipeHost.visible = false
            else {
                titleSlideIn.start()
                artistFadeIn.start()
            }
        }
    }

    function animateVisibility() {
        if (!componentReady)
            return

        var target = requestedVisible ? 1 : 0
        visibilityAnim.stop()
        if (target > 0)
            wipeHost.visible = true

        var distance = Math.abs(target - revealProgress)
        if (distance < 0.001) {
            revealProgress = target
            wipeHost.visible = target > 0
            return
        }

        visibilityAnim.from = revealProgress
        visibilityAnim.to = target
        visibilityAnim.duration = Math.max(1, Math.round(
            (requestedVisible ? Settings.revealDuration : Settings.hideDuration) * distance))
        visibilityAnim.start()
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

    function fmtTime(secs) {
        var value = Number(secs)
        if (!Number.isFinite(value)) return "0:00"
        var s = Math.max(0, Math.floor(value))
        var h = Math.floor(s/3600)
        var m = Math.floor((s%3600)/60)
        var ss = String(s%60).padStart(2,"0")
        if (h > 0) return h + ":" + String(m).padStart(2,"0") + ":" + ss
        return m + ":" + ss
    }

    Component.onCompleted: {
        collapsedBaseHeight = content.implicitHeight
        maxContentHeight = Math.max(maxContentHeight,
                                    collapsedBaseHeight + drawerNaturalHeight)
        componentReady = true
        requestCoverLoad()
        animateVisibility()
    }

    // ── COMPOSANT BOUTON CONTRÔLE (PILL ROUNDED) ──
    component CBtn: Item {
        id:            btnRoot
        property bool isPlay:  false
        property bool fullWidth: false
        property real radius: 0
        signal clicked

        width:  fullWidth ? btnRoot.parent.width : (isPlay ? 44 : 22)
        height: 22

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: btnRoot.radius
            border.width: 1
            border.color: parent.isPlay
                ? Qt.rgba(204/255,21/255,21/255,0.4)
                : Qt.rgba(204/255,21/255,21/255,0.3)

            Rectangle {
                id:    cbFill
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 0; z: 0
                radius: btnRoot.radius
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
