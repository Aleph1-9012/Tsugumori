pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property string text: ""
    property color color: "#e8e8e8"
    property int pixelSize: 12
    property real letterSpacing: 0.45
    property int alignment: Text.AlignLeft
    property bool reducedMotion: false
    property real progress: 1
    property int seed: 0
    readonly property bool rolling: roll.running
    readonly property string displayText: metrics.elidedText
    implicitWidth: fontMetrics.advanceWidth(text)
    implicitHeight: Math.ceil(fontMetrics.height)
    clip: true

    function startRoll() {
        if (reducedMotion || !visible || !text.length) return
        roll.stop()
        seed = Math.floor(Math.random() * 1000)
        progress = 0
        roll.start()
    }
    function stopRoll() { roll.stop(); progress = 1 }
    onTextChanged: stopRoll()
    onDisplayTextChanged: stopRoll()
    onVisibleChanged: if (!visible) stopRoll()
    onReducedMotionChanged: stopRoll()

    TextMetrics {
        id: metrics
        font: plain.font
        text: root.text
        elide: Text.ElideRight
        elideWidth: root.width
    }
    FontMetrics { id: fontMetrics; font: plain.font }
    Text {
        id: plain
        anchors.fill: parent
        text: root.text
        textFormat: Text.PlainText
        elide: Text.ElideRight
        horizontalAlignment: root.alignment
        verticalAlignment: Text.AlignVCenter
        font.family: "JetBrains Mono"
        font.pixelSize: root.pixelSize
        font.weight: Font.Medium
        font.letterSpacing: root.letterSpacing
        color: root.color
        visible: !root.rolling
    }
    Row {
        x: root.alignment === Text.AlignHCenter ? (root.width - width) / 2 : 0
        height: root.height
        visible: root.rolling
        Repeater {
            model: root.displayText.length
            Item {
                id: cell
                required property int index
                readonly property string character: root.displayText.charAt(index)
                readonly property real localProgress: Math.max(0, Math.min(1,
                    (root.progress * 340 - 85 * index / Math.max(1, root.displayText.length - 1)) / 255))
                width: fontMetrics.advanceWidth(character)
                height: root.height
                clip: true
                Column {
                    y: -2 * cell.height * (1 - Math.pow(1 - cell.localProgress, 3))
                    Repeater {
                        model: 3
                        Text {
                            required property int index
                            width: cell.width
                            height: cell.height
                            text: index === 2 || cell.character === " " ? cell.character
                                : "▸◆▪▫░▒▓█/\\|-_=+*".charAt((root.seed + cell.index * 7 + index * 3) % 16)
                            textFormat: Text.PlainText
                            font: plain.font
                            color: root.color
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
    NumberAnimation {
        id: roll
        target: root; property: "progress"
        from: 0; to: 1; duration: 340
    }
}
