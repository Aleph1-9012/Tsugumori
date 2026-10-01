import QtQuick
import QtTest
import "../../../../config/quickshell/components"

Item {
    width: 256; height: 256
    PlayerGlyph {
        id: glyph
        anchors.fill: parent
        active: true
        mediaAvailable: true
        reducedMotion: true
    }
    TestCase {
        name: "PlayerArtwork"
        when: windowShown

        function test_bounded_decode_preserves_centre_crop_data() {
            return [
                {tag: "landscape", width: 256, height: 128},
                {tag: "portrait", width: 128, height: 256}
            ]
        }
        function test_bounded_decode_preserves_centre_crop(data) {
            glyph.artworkUrl = Qt.resolvedUrl("fixtures/" + data.tag + ".svg")
            glyph.mediaKey = data.tag
            var cover = findChild(glyph, "decodedCover")
            var sampler = findChild(glyph, "artworkSampler")
            tryCompare(glyph, "loadedMediaKey", data.tag + "\u0000true")
            tryCompare(glyph, "artworkReady", true)
            tryVerify(function() { return !glyph.needsSample && glyph.cells.length === 1024
                                           && glyph.cells[0].rgb !== null })
            // Qt may rasterize vector artwork at an integer HiDPI scale.
            verify(cover.implicitWidth <= data.width * 2)
            verify(cover.implicitHeight <= data.height * 2)
            compare(cover.implicitWidth / cover.implicitHeight, data.width / data.height)
            // The blue margins must be cropped, not stretched into the glyphs.
            for (var i = 0; i < glyph.cells.length; ++i) {
                verify(glyph.cells[i].rgb.r > 0.95)
                verify(glyph.cells[i].rgb.b < 0.05)
            }
            compare(sampler.sampleUrl, "")
            verify(!sampler.isImageLoaded(glyph.artworkUrl))
        }
    }
}
