import QtQuick

// Corner decorations — four SVG cassette-futurist corners.
// Usage:
//   CornerDeco { anchors.fill: parent }

Item {
    id:           root
    anchors.fill: parent
    enabled:      false   // Does not capture events.

    property color  lineColor: Qt.rgba(232/255, 232/255, 232/255, 0.4)
    property int    size:      18    // Pixel size of each corner.
    property real   lineWidth: 0.8

    // ── TOP-LEFT CORNER ──
    Canvas {
        id:     ctl
        x:      0; y: 0
        width:  root.size; height: root.size
        onPaint: drawCorner(getContext("2d"), false, false)
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // ── TOP-RIGHT CORNER ──
    Canvas {
        id:     ctr
        x:      parent.width - root.size; y: 0
        width:  root.size; height: root.size
        onPaint: drawCorner(getContext("2d"), true, false)
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // ── BOTTOM-LEFT CORNER ──
    Canvas {
        id:     cbl
        x:      0; y: parent.height - root.size
        width:  root.size; height: root.size
        onPaint: drawCorner(getContext("2d"), false, true)
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // ── BOTTOM-RIGHT CORNER ──
    Canvas {
        id:     cbr
        x:      parent.width - root.size
        y:      parent.height - root.size
        width:  root.size; height: root.size
        onPaint: drawCorner(getContext("2d"), true, true)
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // Redraw all corners when the parent size changes.
    onWidthChanged:  { ctl.requestPaint(); ctr.requestPaint(); cbl.requestPaint(); cbr.requestPaint() }
    onHeightChanged: { ctl.requestPaint(); ctr.requestPaint(); cbl.requestPaint(); cbr.requestPaint() }

    // ── DRAWING FUNCTION ──
    // flipH = true  → right corner
    // flipV = true  → bottom corner
    function drawCorner(ctx, flipH, flipV) {
        var w = root.size
        var h = root.size
        ctx.clearRect(0, 0, w, h)

        ctx.save()

        // Flip horizontal
        if (flipH) {
            ctx.translate(w, 0)
            ctx.scale(-1, 1)
        }
        // Flip vertical
        if (flipV) {
            ctx.translate(0, h)
            ctx.scale(1, -1)
        }

        var c = root.lineColor.toString()
        ctx.strokeStyle = c
        ctx.fillStyle   = c
        ctx.lineWidth   = root.lineWidth

        var seg = Math.round(w * 0.33)  // Segment length.
        var dot = Math.round(w * 0.10)  // Square marker size.

        // Horizontal line.
        ctx.beginPath()
        ctx.moveTo(0, seg)
        ctx.lineTo(seg - dot * 0.5, seg)
        ctx.stroke()

        // Vertical line.
        ctx.beginPath()
        ctx.moveTo(seg, 0)
        ctx.lineTo(seg, seg - dot * 0.5)
        ctx.stroke()

        // Square marker at the intersection.
        ctx.fillRect(seg - dot * 0.5, seg - dot * 0.5, dot, dot)

        ctx.restore()
    }
}
