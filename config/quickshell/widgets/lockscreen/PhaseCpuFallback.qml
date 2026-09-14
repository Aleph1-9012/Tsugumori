pragma ComponentBehavior: Bound
import QtQuick
import "PhaseArt.js" as Art

// Software-only fallback. A static background avoids full-screen frame paints.
// Render into a larger canvas and scale it down, keeping the logical bounds.
Item {
    id: fallback
    property bool isGlyph: false
    property real glyphCount: 0
    property real pixelRatio: 1
    readonly property int paintCount: bitmap.paintCount
    onGlyphCountChanged: if (isGlyph) bitmap.requestPaint()

    Canvas {
        id: bitmap
        property int paintCount: 0
        width: Math.ceil(fallback.width * fallback.pixelRatio)
        height: Math.ceil(fallback.height * fallback.pixelRatio)
        scale: 1 / fallback.pixelRatio
        transformOrigin: Item.TopLeft
        onAvailableChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var c = getContext("2d");
            Art.prepare(c, width, height);
            c.scale(fallback.pixelRatio, fallback.pixelRatio);
            if (fallback.isGlyph)
                Art.drawGlyph(c, fallback.width, fallback.glyphCount, 1, fallback.pixelRatio);
            else
                Art.drawField(c, Art.buildField(fallback.width, fallback.height), 1, fallback.pixelRatio);
            paintCount++;
        }
    }
}
