import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property alias entries: entriesModel
    property string selectedId: ""
    property string query: ""
    property bool pinnedOnly: false
    property bool ready: false
    property bool busy: false
    property bool canUndo: false
    property int total: 0
    property int clearableCount: 0
    property int generation: 0
    property int requestId: 0
    property string errorCode: ""
    property string watcherError: ""
    property var detail: ({ clipId: "", body: "", preview: "", truncated: false })
    readonly property int selectedIndex: {
        // Re-evaluate after in-place model updates, even when its count stays the same.
        const revision = generation
        for (let i = 0; i < entriesModel.count; ++i)
            if (entriesModel.get(i).clipId === selectedId) return i
        return -1
    }
    readonly property var selectedEntry: selectedIndex >= 0 ? entriesModel.get(selectedIndex) : null
    readonly property string errorMessage: {
        switch (errorCode || watcherError) {
        case "restore": return "Could not restore this entry. Your clipboard was not replaced."
        case "missing": return "This entry is no longer in history."
        case "pin-limit": return "Up to 40 entries can be pinned. Unpin one first."
        case "watcher": return "Clipboard capture stopped. Retry to reconnect."
        case "already-running": return "Another clipboard worker is running."
        case "version": return "Clipboard storage uses a newer format. It has not been replaced."
        case "unsafe": return "Clipboard storage has unsafe permissions or links."
        case "path": return "XDG_DATA_HOME must be an absolute path."
        case "": return ""
        default: return "Clipboard storage is unavailable. Retry to reconnect."
        }
    }
    signal restored()

    ListModel { id: entriesModel }
    Timer { id: searchDelay; interval: 130; onTriggered: root.send("sync") }
    Timer {
        id: deadline
        interval: 8000
        onTriggered: { root.busy = false; root.errorCode = "timeout" }
    }
    onQueryChanged: searchDelay.restart()
    onPinnedOnlyChanged: send("sync")

    function select(id) {
        if (selectedId === id) return
        selectedId = id
        detail = { clipId: "", body: "", preview: "", truncated: false }
        send("sync")
    }
    function moveSelection(step) {
        if (!entriesModel.count) return
        select(entriesModel.get((Math.max(0, selectedIndex) + step + entriesModel.count) % entriesModel.count).clipId)
    }
    function send(operation) {
        if (!worker.running || !ready) return
        searchDelay.stop()
        requestId++
        errorCode = ""
        busy = true
        deadline.restart()
        worker.write(JSON.stringify({ operation: operation, requestId: requestId,
            selected: selectedId, query: query, pinnedOnly: pinnedOnly }) + "\n")
    }
    function retry() {
        if (worker.running) worker.running = false
        restartDelay.restart()
    }
    Timer {
        id: restartDelay
        interval: 1200
        onTriggered: {
            if (worker.running) { restart(); return }
            root.ready = false
            root.errorCode = ""
            root.watcherError = ""
            root.requestId = 0
            worker.running = true
        }
    }
    function receive(line) {
        let message
        try { message = JSON.parse(line) } catch (_) { errorCode = "protocol"; return }
        if (message.requestId !== undefined && message.requestId < requestId) {
            if (message.ok && message.restored) restored()
            return
        }
        deadline.stop()
        busy = false
        if (!message.ok) { errorCode = message.error || "storage"; return }
        if (message.event !== "snapshot") return
        const wasReady = ready
        ready = true
        watcherError = message.watcherError || ""
        total = message.total
        clearableCount = message.clearableCount || 0
        canUndo = message.canUndo
        // Reconcile by ID, keeping existing delegates alive for hover-out wipes.
        const next = message.entries
        for (let i = 0; i < next.length; ++i) {
            let found = -1
            for (let j = i; j < entriesModel.count; ++j)
                if (entriesModel.get(j).clipId === next[i].clipId) { found = j; break }
            if (found < 0) entriesModel.insert(i, next[i])
            else {
                if (found !== i) entriesModel.move(found, i, 1)
                entriesModel.set(i, next[i])
            }
        }
        if (entriesModel.count > next.length) entriesModel.remove(next.length, entriesModel.count - next.length)
        selectedId = message.selected
        detail = message.detail
        generation++
        if (message.restored) restored()
        if (!wasReady && (query || pinnedOnly)) send("sync")
    }
    Process {
        id: worker
        // The helper owns both capture processes and ties their lifetime to this worker.
        command: ["python3", "-u", Qt.resolvedUrl("../scripts/clipboard-store.py").toString().replace("file://", ""), "serve"]
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root.receive(data) }
        stderr: StdioCollector {} // Do not forward clipboard/helper output into shell logs.
        onExited: {
            root.ready = false
            root.busy = false
            deadline.stop()
            if (!restartDelay.running && !root.errorCode) root.errorCode = "worker"
        }
    }
    Component.onCompleted: worker.running = true
}
