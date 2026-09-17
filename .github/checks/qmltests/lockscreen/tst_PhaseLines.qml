import QtQuick
import QtTest
import "../../../../config/quickshell/widgets/lockscreen"

Item {
    id: scene
    width: 500; height: 400
    Rectangle { anchors.fill: parent; color: "#080808" }
    PhaseLines {
        id: field
        width: 500; height: 84
        glyphMode: 0; rootColumns: 6; pixelRatio: 1; glyphCount: 0; progress: 1
    }
    PhaseLines {
        id: glyph
        x: 169; y: 140; width: 162; height: 162
        glyphMode: 1; rootColumns: 3; pixelRatio: 1; glyphCount: 4; progress: 1
    }
    TestCase {
        name: "PhaseGpuLines"
        when: windowShown
        function test_shader_render() {
            if (scene.GraphicsInfo.api === GraphicsInfo.Software) skip("Shader check requires the RHI renderer");
            wait(500);
            console.log("Graphics API", scene.GraphicsInfo.api, "shader", field.status, glyph.status);
            compare(field.status, ShaderEffect.Compiled);
            compare(glyph.status, ShaderEffect.Compiled);
            var frame = grabImage(scene), count = 0;
            for (var y = 0; y < 84; y++) for (var x = 0; x < 500; x++) if (frame.red(x,y) > 20) count++;
            verify(count > 200, "GPU field must render visible strokes");
        }
    }
}
