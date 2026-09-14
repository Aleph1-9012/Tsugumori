pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "../lockscreen"
import "../lockscreen/PhaseArt.js" as Art

// Reuse the approved lockscreen's GPU field, not its login or lock logic.
Item {
    id: field
    required property real progress
    // Pass real file URLs from the entry point. Quickshell can resolve inherited
    // relative shader URLs against this consumer directory or its virtual URL.
    required property url vertexShaderUrl
    required property url fragmentShaderUrl
    property bool shaderFailed: false
    readonly property bool gpuRendering: GraphicsInfo.api !== GraphicsInfo.Software && !shaderFailed
    readonly property real dpr: Math.max(1, Screen.devicePixelRatio)
    readonly property int columns: Math.ceil(width / 84)
    readonly property int rows: Math.ceil(height / 84)
    readonly property int batches: Math.ceil(columns / 32)
    readonly property PhaseCpuFallback cpuRenderer: cpuField.item as PhaseCpuFallback
    readonly property int paintCount: cpuRenderer ? cpuRenderer.paintCount : 0
    clip: true

    Rectangle { anchors.fill: parent; color: "#080808" }
    Loader {
        anchors.fill: parent
        active: field.gpuRendering
        sourceComponent: Item {
            Repeater {
                model: field.rows * field.batches
                PhaseLines {
                    required property int index
                    vertexShader: field.vertexShaderUrl
                    fragmentShader: field.fragmentShaderUrl
                    width: field.width; height: 84
                    y: (field.height - field.rows * 84) / 2 + rowIndex * 84
                    rowIndex: Math.floor(index / field.batches)
                    firstColumn: (index % field.batches) * 32
                    batchColumns: Math.min(32, field.columns - firstColumn)
                    rootColumns: field.columns
                    glyphMode: 0; glyphCount: 0
                    progress: field.progress
                    pixelRatio: field.dpr
                    pixelOrigin: Qt.point(0, y)
                    onRenderFailed: description => {
                        if (!field.shaderFailed) console.error("Wallpaper picker: static artwork fallback:", description);
                        field.shaderFailed = true;
                    }
                }
            }
        }
    }
    Loader {
        id: cpuField
        anchors.fill: parent
        active: !field.gpuRendering
        opacity: Art.ramp(field.progress, .10, .35)
        sourceComponent: PhaseCpuFallback { pixelRatio: field.dpr }
    }
}
