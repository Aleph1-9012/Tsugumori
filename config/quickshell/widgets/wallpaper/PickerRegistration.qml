pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "../lockscreen/PhaseArt.js" as Art

// Flat registration ticks assemble around the selected preview during motion.
Item {
    id: frame
    required property real progress
    readonly property real dpr: Math.max(1, Screen.devicePixelRatio)
    enabled: false
    visible: progress > 0 && progress < 1
    opacity: Art.ramp(progress, .06, .17) * (1 - Art.ramp(progress, .65, .86))
    Repeater {
        model: 38
        Rectangle {
            required property int index
            readonly property real tickHeight: Art.lerp(7, 1, Art.ramp(frame.progress, .18, .73))
            x: Math.round(((index % 19) + .5) * frame.width / 19 * frame.dpr) / frame.dpr
            y: Math.round(((index < 19 ? 0 : frame.height) - tickHeight) * frame.dpr) / frame.dpr
            width: 1 / frame.dpr; height: Math.round(tickHeight * 2 * frame.dpr) / frame.dpr
            color: index % 6 === 0 ? "#d1161c" : "#999486"
        }
    }
    Repeater {
        model: 4
        Item {
            id: corner
            required property int index
            readonly property real arm: 32 * Art.ramp(frame.progress, .08, .6)
            x: index % 2 ? frame.width : 0
            y: index < 2 ? 0 : frame.height
            Rectangle { x: corner.index % 2 ? -width : 0; width: corner.arm; height: 1 / frame.dpr; color: "#b91a20" }
            Rectangle { y: corner.index < 2 ? 0 : -height; width: 1 / frame.dpr; height: corner.arm; color: "#b91a20" }
        }
    }
}
