import QtQuick
import "../theme"

Item {
    id: root
    property string artworkUrl: ""
    property string mediaKey: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property bool mediaAvailable: false
    property bool active: false
    property bool reducedMotion: false
    readonly property bool artworkReady: cover.status === Image.Ready && cover.decodeGeneration === generation
    property int generation: 0
    property string loadedMediaKey: ""
    property string loadedUrl: ""
    property bool completed: false
    property bool syncQueued: false
    property bool needsSample: false
    property var cells: []
    property var oldCells: []
    property real transitionProgress: 1
    property var trailPoints: []
    property bool pointerPresent: false
    property real pointerX: 0
    property real pointerY: 0
    readonly property real revealRadius: width * 0.171
    readonly property int trailDuration: 1100
    readonly property int maxTrailPoints: 64
    readonly property bool hoverActive: active && artworkReady && !needsSample && !transition.running
                                       && (pointerPresent || trailPoints.length > 0)
    clip: true
    Accessible.role: Accessible.Graphic
    Accessible.name: artworkReady ? "Album artwork reconstructed as glyphs. Hover to colour the symbols."
                                  : mediaAvailable ? "Generated glyph signature for " + trackTitle : "No media playing"

    function clamp(v, low, high) { return Math.max(low, Math.min(high, v)) }
    function smoothStep(a, b, v) { var p = clamp((v - a) / (b - a), 0, 1); return p * p * (3 - 2 * p) }
    function hash(text) {
        var h = 2166136261
        for (var i = 0; i < text.length; ++i) { h ^= text.charCodeAt(i); h = Math.imul(h, 16777619) }
        return h >>> 0
    }
    function random(seed) {
        var state = seed || 1
        return function() { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 4294967296 }
    }
    function signatureSeed() { return hash(trackTitle + "\u0000" + trackArtist) }
    function hoverColour(rgb) {
        var peak = Math.max(rgb.r, rgb.g, rgb.b)
        var span = peak - Math.min(rgb.r, rgb.g, rgb.b)
        var value = Math.min(1, Math.pow(peak, 0.65) * 1.18)
        // Lift brightness and saturation without shifting the artwork's hue.
        if (span < 0.00001) return { r: value, g: value, b: value }
        var saturation = Math.min(1, span / peak * 1.65)
        return {
            r: value * (1 - (peak - rgb.r) / span * saturation),
            g: value * (1 - (peak - rgb.g) / span * saturation),
            b: value * (1 - (peak - rgb.b) / span * saturation)
        }
    }
    function compileCells(raw, red, seed, adaptive, colours) {
        var sorted = raw.slice().sort(function(a, b) { return a - b })
        var lo = adaptive && sorted[972] - sorted[51] > 0.1 ? Math.max(0, sorted[51] - 0.02) : 0
        var hi = adaptive && sorted[972] - sorted[51] > 0.1 ? Math.min(1, sorted[972] + 0.06) : 1
        var ramp = " .:;=+x*#%@", result = []
        for (var row = 0; row < 32; ++row) for (var col = 0; col < 32; ++col) {
            var index = row * 32 + col
            var tone = Math.pow(clamp((raw[index] - lo) / Math.max(0.27, hi - lo), 0, 1), 0.72)
            var glyph = ramp[Math.min(ramp.length - 1, Math.floor(tone * (ramp.length - 1)))]
            var gx = raw[row * 32 + Math.min(31, col + 1)] - raw[row * 32 + Math.max(0, col - 1)]
            var gy = raw[Math.min(31, row + 1) * 32 + col] - raw[Math.max(0, row - 1) * 32 + col]
            if (tone > 0.16 && tone < 0.55 && Math.sqrt(gx * gx + gy * gy) > 0.23)
                glyph = Math.abs(gx) > Math.abs(gy) * 1.8 ? "|" : Math.abs(gy) > Math.abs(gx) * 1.8 ? "=" : gx * gy > 0 ? "\\" : "/"
            result.push({ glyph: glyph, alpha: 0.24 + 0.76 * Math.sqrt(tone), red: red[index],
                          rgb: colours ? hoverColour(colours[index]) : null,
                          noise: ((Math.imul(index + 1, 2654435761) ^ seed) >>> 0) / 4294967296 })
        }
        return result
    }
    function signature() {
        var seed = signatureSeed(), rand = random(seed), raw = [], red = []
        var cx = 0.25 + rand() * 0.5, cy = 0.28 + rand() * 0.44
        var radius = 0.19 + rand() * 0.15, angle = rand() * Math.PI, offset = rand() * 0.25 - 0.125
        for (var row = 0; row < 32; ++row) for (var col = 0; col < 32; ++col) {
            var x = (col + 0.5) / 32, y = (row + 0.5) / 32
            var dist = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
            var ring = Math.exp(-Math.abs(dist - radius) * 50)
            var inner = Math.exp(-Math.abs(dist - radius * 0.54) * 60) * 0.48
            var axis = Math.exp(-Math.abs((x - 0.5) * Math.cos(angle) + (y - 0.5) * Math.sin(angle) - offset) * 55) * 0.70
            raw.push(mediaAvailable ? clamp(ring * 0.82 + inner + axis + (rand() > 0.95 ? 0.24 : 0), 0, 1) : 0.025)
            red.push(mediaAvailable && axis > 0.53 && dist < radius * 1.13)
        }
        return compileCells(raw, red, seed, false)
    }
    function repaintGlyph() {
        if (glyphCanvas.available) glyphCanvas.requestPaint()
        if (motionCanvas.available && motionCanvas.visible) motionCanvas.requestPaint()
    }
    function repaintHover() {
        if (motionCanvas.available && hoverActive) motionCanvas.requestPaint()
    }
    function commitCells(nextCells, animate) {
        if (animate) {
            transition.stop(); oldCells = cells; transitionProgress = 1
        }
        cells = nextCells
        if (animate && oldCells.length > 0 && active && !reducedMotion) {
            clearHover(); transitionProgress = 0; transition.start()
        }
        repaintGlyph()
    }
    function scheduleSync() {
        if (!completed || syncQueued) return
        syncQueued = true
        Qt.callLater(function() { root.syncQueued = false; root.syncMedia() })
    }
    function syncMedia() {
        var key = mediaKey + "\u0000" + String(mediaAvailable)
        var url = mediaAvailable ? String(artworkUrl).trim() : ""
        var changed = key !== loadedMediaKey
        if (!changed && url === loadedUrl) {
            if (!artworkReady) commitCells(signature(), false)
            return
        }
        loadedMediaKey = key; loadedUrl = url
        generation++; retry.stop(); clearHover(); needsSample = false
        sampler.releaseImage()
        cover.decodeGeneration = -1; cover.source = ""; cover.attempts = 0; cover.usedFallback = false
        commitCells(signature(), changed)
        if (url.length) decode(url)
    }
    function decode(url) {
        cover.decodeGeneration = generation; cover.requestedUrl = url
        cover.source = ""; cover.source = url
    }
    function decodeFailed() {
        if (cover.decodeGeneration !== generation) return
        if (cover.attempts < 4) { cover.attempts++; retry.generation = generation; retry.restart(); return }
        if (!cover.usedFallback && cover.requestedUrl.indexOf("maxresdefault.jpg") >= 0) {
            cover.usedFallback = true; cover.attempts = 0
            decode(cover.requestedUrl.replace("maxresdefault.jpg", "hqdefault.jpg")); return
        }
        cover.decodeGeneration = -1; cover.source = ""; clearHover()
    }
    function clearHover() {
        pointerPresent = false; trailPoints = []
        repaintGlyph()
    }
    function movePointer(x, y) {
        if (!active || !artworkReady || needsSample || transition.running) return
        var now = Date.now(), points = trailPoints.slice()
        if (pointerPresent && !reducedMotion) {
            var dx = x - pointerX, dy = y - pointerY
            var count = Math.min(16, Math.ceil(Math.sqrt(dx * dx + dy * dy) / Math.max(1, width * 18 / 640)))
            for (var i = 1; i <= count; ++i)
                points.push({ x: pointerX + dx * i / count, y: pointerY + dy * i / count, born: now, strength: 0.68 })
        }
        pointerX = clamp(x, 0, width); pointerY = clamp(y, 0, height); pointerPresent = true
        trailPoints = points.slice(-maxTrailPoints)
        repaintHover()
    }
    function leavePointer() {
        if (pointerPresent && !reducedMotion && artworkReady) {
            var points = trailPoints.slice(1 - maxTrailPoints)
            points.push({ x: pointerX, y: pointerY, born: Date.now(), strength: 1 }); trailPoints = points
        }
        pointerPresent = false
        if (reducedMotion) trailPoints = []
        repaintHover()
    }
    function hoverAmounts() {
        var amounts = new Array(1024).fill(0), now = Date.now()
        var cellW = width / 32, cellH = height / 32, radius = Math.max(1, revealRadius)
        function stamp(x, y, strength) {
            var left = Math.max(0, Math.floor((x - radius) / cellW))
            var right = Math.min(31, Math.floor((x + radius) / cellW))
            var top = Math.max(0, Math.floor((y - radius) / cellH))
            var bottom = Math.min(31, Math.floor((y + radius) / cellH))
            for (var row = top; row <= bottom; ++row) for (var col = left; col <= right; ++col) {
                var dx = (col + 0.5) * cellW - x, dy = (row + 0.5) * cellH - y
                var distance = Math.sqrt(dx * dx + dy * dy)
                if (distance >= radius) continue
                var index = row * 32 + col
                var amount = strength * (1 - smoothStep(radius * 0.22, radius, distance))
                amounts[index] = Math.max(amounts[index], amount)
            }
        }
        for (var i = 0; i < trailPoints.length; ++i) {
            var point = trailPoints[i]
            var strength = Math.pow(1 - clamp((now - point.born) / trailDuration, 0, 1), 1.7) * point.strength
            if (strength > 0) stamp(point.x, point.y, strength)
        }
        if (pointerPresent) stamp(pointerX, pointerY, 1)
        return amounts
    }
    function drawCells(ctx, frame, progress, outgoing, colourAmounts) {
        var cellW = width / 32, cellH = height / 32
        ctx.font = (cellW * 0.95) + 'px "' + Theme.mono + '"'
        ctx.textAlign = "center"; ctx.textBaseline = "middle"
        for (var i = 0; i < frame.length; ++i) {
            var g = frame[i], x = (i % 32 + 0.5) * cellW, y = (Math.floor(i / 32) + 0.5) * cellH, alpha = 1
            if (progress < 1) {
                var u = clamp((progress - g.noise * 0.16) / 0.84, 0, 1)
                var motion = outgoing ? smoothStep(0.04, 0.65, u) : 1 - smoothStep(0.32, 1, u)
                alpha = 1 - motion
                x += Math.sin(g.noise * 40) * cellW * 1.35 * motion * (outgoing ? 1 : -0.65)
                y += Math.cos(g.noise * 31) * cellH * 1.35 * motion * (outgoing ? 1 : -0.65)
            }
            if (alpha <= 0) continue
            ctx.globalAlpha = g.alpha * alpha; ctx.fillStyle = g.red ? "#e4372b" : "#e8e8df"
            if (g.rgb && colourAmounts && colourAmounts[i] > 0) {
                var mix = 1 - Math.pow(1 - colourAmounts[i], 1.6)
                ctx.globalAlpha = (g.alpha + (1 - g.alpha) * mix) * alpha
                var r = g.red ? 228 / 255 : 232 / 255
                var green = g.red ? 55 / 255 : 232 / 255
                var b = g.red ? 43 / 255 : 223 / 255
                ctx.fillStyle = Qt.rgba(r + (g.rgb.r - r) * mix,
                                       green + (g.rgb.g - green) * mix,
                                       b + (g.rgb.b - b) * mix, 1)
            }
            ctx.fillText(g.glyph, x, y)
        }
        ctx.globalAlpha = 1
    }

    onArtworkUrlChanged: scheduleSync()
    onMediaKeyChanged: scheduleSync()
    onMediaAvailableChanged: scheduleSync()
    onTrackTitleChanged: scheduleSync()
    onTrackArtistChanged: scheduleSync()
    onActiveChanged: {
        if (!active) { transition.stop(); transitionProgress = 1; oldCells = []; clearHover() }
        else { repaintGlyph(); if (needsSample) Qt.callLater(sampler.prepareImage) }
    }
    onReducedMotionChanged: {
        if (reducedMotion) { transition.stop(); transitionProgress = 1; oldCells = []; clearHover(); repaintGlyph() }
    }
    onWidthChanged: { clearHover(); repaintGlyph() }
    onHeightChanged: { clearHover(); repaintGlyph() }
    onTransitionProgressChanged: if (motionCanvas.available) motionCanvas.requestPaint()
    Component.onCompleted: { completed = true; scheduleSync() }
    Component.onDestruction: { retry.stop(); transition.stop() }

    Rectangle { anchors.fill: parent; color: "#090909" }
    Image {
        id: cover
        anchors.fill: parent; visible: false
        asynchronous: true; cache: false; retainWhileLoading: false
        property int decodeGeneration: -1
        property int attempts: 0
        property bool usedFallback: false
        property string requestedUrl: ""
        onStatusChanged: {
            if (decodeGeneration !== root.generation) return
            if (status === Image.Ready) {
                retry.stop(); attempts = 0; root.needsSample = true
                // Image.status handlers can run before the artworkReady binding updates.
                // Sample after those bindings settle, including when the drawer is already open.
                Qt.callLater(sampler.prepareImage)
            } else if (status === Image.Error) root.decodeFailed()
        }
    }
    Timer {
        id: retry; interval: 300; property int generation: -1
        onTriggered: if (generation === root.generation) root.decode(cover.requestedUrl)
    }
    // Canvas keeps its own image cache, even when drawImage receives an Image item.
    // Load the accepted cover URL there before sampling the matching centred crop.
    Canvas {
        id: sampler
        width: 128; height: 128; opacity: 0
        renderTarget: Canvas.Image; renderStrategy: Canvas.Immediate
        property string sampleUrl: ""
        property int sampleGeneration: -1
        function releaseImage() {
            if (sampleUrl) unloadImage(sampleUrl)
            sampleUrl = ""; sampleGeneration = -1
        }
        function prepareImage() {
            if (!available || !root.needsSample || !root.active || !root.artworkReady) return
            var url = String(cover.source)
            if (sampleUrl !== url || sampleGeneration !== root.generation) {
                releaseImage(); sampleUrl = url; sampleGeneration = root.generation
                loadImage(sampleUrl)
            }
            if (isImageLoaded(sampleUrl)) requestPaint()
        }
        onAvailableChanged: if (available) Qt.callLater(prepareImage)
        onImageLoaded: if (sampleGeneration === root.generation && isImageLoaded(sampleUrl)) requestPaint()
        onPaint: {
            if (!root.needsSample || !root.active || !root.artworkReady) return
            if (sampleGeneration !== root.generation || !isImageLoaded(sampleUrl)) { prepareImage(); return }
            var token = root.generation, ctx = getContext("2d")
            var sw = cover.sourceSize.width, sh = cover.sourceSize.height
            if (sw <= 0 || sh <= 0) return
            var side = Math.min(sw, sh)
            ctx.reset(); ctx.clearRect(0, 0, 128, 128)
            ctx.drawImage(sampleUrl, (sw - side) / 2, (sh - side) / 2, side, side, 0, 0, 128, 128)
            var pixels = ctx.getImageData(0, 0, 128, 128).data, raw = [], red = [], colours = []
            for (var row = 0; row < 32; ++row) for (var col = 0; col < 32; ++col) {
                var r = 0, g = 0, b = 0
                for (var dy = 0; dy < 4; ++dy) for (var dx = 0; dx < 4; ++dx) {
                    var p = ((row * 4 + dy) * 128 + col * 4 + dx) * 4
                    r += pixels[p]; g += pixels[p + 1]; b += pixels[p + 2]
                }
                raw.push((r * 0.2126 + g * 0.7152 + b * 0.0722) / (16 * 255))
                red.push(r > g * 1.42 && r > b * 1.28 && r / 16 > 62)
                colours.push({ r: r / (16 * 255), g: g / (16 * 255), b: b / (16 * 255) })
            }
            if (token !== root.generation) return
            root.needsSample = false
            root.commitCells(root.compileCells(raw, red, root.signatureSeed(), true, colours), false)
        }
    }
    Canvas {
        id: glyphCanvas; anchors.fill: parent; visible: !transition.running && !root.hoverActive
        renderTarget: Canvas.Image
        onAvailableChanged: if (available) requestPaint()
        onVisibleChanged: if (visible && available) requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0, 0, width, height)
            root.drawCells(ctx, root.cells, 1, false)
        }
    }
    Canvas {
        id: motionCanvas; anchors.fill: parent; visible: transition.running || root.hoverActive
        renderTarget: Canvas.Image
        onAvailableChanged: if (available) requestPaint()
        onVisibleChanged: if (visible && available) requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0, 0, width, height)
            if (transition.running) {
                root.drawCells(ctx, root.oldCells, root.transitionProgress, true)
                root.drawCells(ctx, root.cells, root.transitionProgress, false)
            } else root.drawCells(ctx, root.cells, 1, false, root.hoverAmounts())
        }
    }
    NumberAnimation {
        id: transition; target: root; property: "transitionProgress"
        from: 0; to: 1; duration: 720
        onFinished: { root.oldCells = []; root.repaintGlyph() }
    }
    Timer {
        interval: 16; repeat: true
        running: root.active && root.trailPoints.length > 0
        onTriggered: {
            var now = Date.now()
            root.trailPoints = root.trailPoints.filter(function(point) { return now - point.born < root.trailDuration })
            root.repaintHover()
        }
    }
    MouseArea {
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.CrossCursor
        onPositionChanged: root.movePointer(mouseX, mouseY)
        onPressed: root.movePointer(mouseX, mouseY)
        onExited: root.leavePointer()
        onCanceled: root.leavePointer()
    }
}
