pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: catalog

    property var entries: []
    property bool loaded: false
    property bool dirty: true
    property int viewers: 0
    property string lastSnapshot: ""

    function open() {
        viewers++
        if (!reader.running) reader.running = true
        else refresh()
    }

    function close() {
        viewers = Math.max(0, viewers - 1)
    }

    function refresh() {
        if (!dirty || !reader.running || viewers === 0) return
        dirty = false
        reader.write("refresh\n")
    }

    Timer {
        id: changedTimer
        interval: 150
        onTriggered: catalog.refresh()
    }

    Process {
        id: reader
        command: ["python3", Qt.resolvedUrl("../scripts/list_apps.py").toString().replace("file://", ""), "--watch"]
        stdinEnabled: true
        onStarted: catalog.refresh()
        onExited: {
            catalog.dirty = true
        }
        stdout: SplitParser {
            onRead: line => {
                const message = JSON.parse(line)
                if (message.type === "changed") {
                    catalog.dirty = true
                    if (catalog.viewers > 0) changedTimer.restart()
                } else if (message.type === "entries") {
                    if (catalog.lastSnapshot !== line) {
                        catalog.lastSnapshot = line
                        catalog.entries = message.entries
                    }
                    catalog.loaded = true
                }
            }
        }
    }
}
