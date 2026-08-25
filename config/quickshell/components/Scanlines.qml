import QtQuick

// Scanline overlay — place it over any widget.
// Usage:
//   Scanlines { anchors.fill: parent }

Item {
    id:              root
    anchors.fill:    parent
    property real   lineOpacity: 0.06
    property int    lineSpacing: 3    // Pixel gap between lines.
    property bool   grain:       true // Add texture grain.

    // Does not capture events.
    enabled:         false

    // Draw scanlines with Canvas; lighter than a rectangle Repeater.
    Canvas {
        id:           cv
        anchors.fill: parent
        opacity:      1

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = "rgba(0,0,0," + root.lineOpacity + ")"
            for (var y = 0; y < height; y += root.lineSpacing + 1) {
                ctx.fillRect(0, y, width, 1)
            }
        }

        // Redraw when the size changes.
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()

        Component.onCompleted: requestPaint()
    }

    // Subtle grain (random semi-transparent points).
    Canvas {
        id:           grainCv
        anchors.fill: parent
        visible:      root.grain
        opacity:      0.35

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            // Light grain: one pixel per roughly 8 square pixels.
            var density = Math.floor(width * height / 8)
            for (var i = 0; i < density; i++) {
                var x = Math.floor(Math.random() * width)
                var y = Math.floor(Math.random() * height)
                var a = Math.random() * 0.12
                ctx.fillStyle = "rgba(200,184,154," + a + ")"
                ctx.fillRect(x, y, 1, 1)
            }
        }

        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
}
