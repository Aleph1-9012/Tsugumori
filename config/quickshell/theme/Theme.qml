pragma Singleton
import QtQuick

QtObject {
  // Couleurs principales
  readonly property color bg:   "#0a0a0a"
  readonly property color bg2:  "#111111"
  readonly property color bg3:  "#1e1e1e"
  readonly property color fg:   "#e8e8e8"
  readonly property color fgd:  Qt.rgba(232/255, 232/255, 232/255, 0.5)
  readonly property color fgdd: Qt.rgba(232/255, 232/255, 232/255, 0.2)

  // Accents
  readonly property color a1:   "#cc1515"
  readonly property color a2:   "#7a8faa"
  readonly property color a3:   "#7a8faa"
  readonly property color a4:   "#9e1010"

  // Bordures
  readonly property color ln:   Qt.rgba(204/255, 21/255, 21/255, 0.15)
  readonly property color lnm:  Qt.rgba(204/255, 21/255, 21/255, 0.28)

  // Font
  readonly property string mono:  "Share Tech Mono"

  // Timings animations
  readonly property int durationFast:   150
  readonly property int durationMid:    380
  readonly property int durationSlow:   650
}
