import QtQuick

// Fixed mesh, procedural vertex positions. Animation updates only uniforms;
// no JavaScript path construction, bitmap resampling, or texture uploads.
ShaderEffect {
    id: lines
    signal renderFailed(string description)
    required property real progress
    required property real glyphCount
    required property real pixelRatio
    required property int glyphMode
    required property int rootColumns
    property int rowIndex: 0
    property int firstColumn: 0
    property int batchColumns: rootColumns
    property point pixelOrigin: Qt.point(0, 0)
    readonly property size logicalSize: Qt.size(width, height)
    readonly property int lineCount: glyphMode === 1 ? 9 * 85 * 10 : batchColumns * 21 * 9
    // Degenerate connector triangles keep all the strokes in one draw call.
    mesh: Qt.size(lineCount * 4 - 1, 1)
    vertexShader: "shaders/lines.vert.qsb"
    fragmentShader: "shaders/lines.frag.qsb"
    blending: true
    onStatusChanged: if (status === ShaderEffect.Error) lines.renderFailed(log)
}
