import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property alias notes: notesModel
    property string activeId: ""
    property bool ready: false
    property bool dirty: false
    property bool busy: false
    property bool canRecover: false
    property string errorCode: ""
    property int revision: 0
    property int generation: 0
    property int sentGeneration: 0
    property var undoStack: []
    property var cursors: ({})
    property string editorField: "body"
    property string operation: ""
    property string requestText: ""
    property bool streamDone: false
    property bool processDone: false
    property bool flushPending: false
    readonly property int activeIndex: {
        const changed = generation
        for (let i = 0; i < notesModel.count; ++i)
            if (notesModel.get(i).noteId === activeId) return i
        return -1
    }
    readonly property string status: errorCode ? (ready ? "SAVE FAILED" : "LOAD FAILED")
                                    : !ready ? "LOADING" : dirty || busy ? "SAVING" : "SAVED"
    readonly property string errorMessage: {
        switch (errorCode) {
        case "conflict": return "Notes changed on disk. Your draft is kept here. Copy it before restarting."
        case "invalid": return "The notes file is damaged or uses an unsupported format. It has not been replaced."
        case "path": return "XDG_DATA_HOME must be an absolute path."
        case "unsafe": return "The notes path has unsafe ownership or file links."
        case "busy": return "Another notes writer is busy. Retry when it finishes."
        case "timeout": return "Storage did not respond. Your draft is kept here."
        case "": return ""
        default: return "Cannot access notes storage. Your draft is kept here."
        }
    }
    signal focusTitleRequested()

    ListModel { id: notesModel }
    Timer { id: debounce; interval: 400; onTriggered: root.flush() }
    Timer { id: maxPending; interval: 2000; onTriggered: root.flush() }
    Timer {
        id: deadline
        interval: 10000
        onTriggered: {
            root.errorCode = "timeout"
            worker.running = false
            root.busy = false
            root.requestText = ""
        }
    }

    function find(id) {
        for (let i = 0; i < notesModel.count; ++i)
            if (notesModel.get(i).noteId === id) return i
        return -1
    }
    function noteCopy(index) {
        const note = notesModel.get(index)
        return { noteId: note.noteId, title: note.title, body: note.body,
                 createdAt: note.createdAt, updatedAt: note.updatedAt }
    }
    function markDirty(immediate) {
        generation++
        dirty = true
        // Retry is explicit after failures; do not hammer an inaccessible store.
        if (errorCode) return
        debounce.restart()
        if (!maxPending.running) maxPending.start()
        if (immediate) flush()
    }
    function selectNote(id) {
        if (!ready || id === activeId || find(id) < 0) return
        activeId = id
        markDirty(true)
    }
    function edit(field, value) {
        if (!ready || activeIndex < 0 || (field !== "title" && field !== "body")) return
        if (notesModel.get(activeIndex)[field] === value) return
        notesModel.setProperty(activeIndex, field, value)
        notesModel.setProperty(activeIndex, "updatedAt", new Date().toISOString())
        markDirty(false)
    }
    function createNote() {
        if (!ready) return
        const now = new Date().toISOString()
        let id
        do { id = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2) }
        while (find(id) >= 0)
        notesModel.append({ noteId: id, title: "", body: "", createdAt: now, updatedAt: now })
        activeId = id
        editorField = "title"
        markDirty(true)
        focusTitleRequested()
    }
    function removeNote(id) {
        if (!ready) return
        const index = find(id)
        if (index < 0) return
        undoStack = undoStack.concat([{ note: noteCopy(index), index: index }])
        notesModel.remove(index)
        if (activeId === id)
            activeId = notesModel.count ? notesModel.get(Math.min(index, notesModel.count - 1)).noteId : ""
        markDirty(true)
    }
    function undoDelete() {
        if (!ready || !undoStack.length) return
        const entry = undoStack[undoStack.length - 1]
        undoStack = undoStack.slice(0, -1)
        notesModel.insert(Math.min(entry.index, notesModel.count), entry.note)
        activeId = entry.note.noteId
        markDirty(true)
    }
    function rememberCursor(id, field, position) {
        if (!id) return
        const key = id + "/" + field
        cursors[key] = position
    }
    function cursorFor(id, field) { return cursors[id + "/" + field] || 0 }

    function startRequest(request) {
        if (busy || worker.running) return
        operation = request.operation
        requestText = JSON.stringify(request) + "\n"
        streamDone = false
        processDone = false
        busy = true
        deadline.restart()
        worker.running = true
    }
    function load() {
        if (ready || busy) return
        errorCode = ""
        canRecover = false
        startRequest({ operation: "read" })
    }
    function recover() {
        if (ready || busy || !canRecover) return
        errorCode = ""
        startRequest({ operation: "recover" })
    }
    function retry() {
        if (busy || worker.running) return
        errorCode = ""
        if (!ready) load()
        else flush()
    }
    function flush() {
        debounce.stop()
        maxPending.stop()
        if (!ready || !dirty || errorCode) return
        if (busy) { flushPending = true; return }
        const list = []
        for (let i = 0; i < notesModel.count; ++i) {
            const n = notesModel.get(i)
            list.push({ id: n.noteId, title: n.title, body: n.body,
                        createdAt: n.createdAt, updatedAt: n.updatedAt })
        }
        sentGeneration = generation
        flushPending = false
        startRequest({ operation: "write", expectedRevision: revision,
            document: { schema: 1, revision: revision + 1, activeId: activeId, notes: list } })
    }
    function finishRequest() {
        if (!busy || !streamDone || !processDone) return
        deadline.stop()
        busy = false
        requestText = ""
        let response
        try { response = JSON.parse(output.text) }
        catch (_) { errorCode = "io"; return }
        if (!response.ok) {
            errorCode = response.error || "io"
            canRecover = !ready && !!response.canRecover
            return
        }
        canRecover = false
        if (operation === "write") {
            revision = response.revision
            dirty = generation !== sentGeneration
            if (dirty && (flushPending || !debounce.running)) Qt.callLater(root.flush)
        } else {
            // No edits are allowed before this initial read/recovery completes.
            const doc = response.document
            notesModel.clear()
            for (const n of doc.notes)
                notesModel.append({ noteId: n.id, title: n.title, body: n.body,
                                    createdAt: n.createdAt, updatedAt: n.updatedAt })
            revision = doc.revision
            activeId = doc.activeId
            generation++
            dirty = false
            ready = true
        }
    }

    Process {
        id: worker
        command: ["python3", Qt.resolvedUrl("../scripts/notes-store.py").toString().replace("file://", "")]
        stdinEnabled: true
        onStarted: write(root.requestText)
        stdout: StdioCollector {
            id: output
            onStreamFinished: { root.streamDone = true; Qt.callLater(root.finishRequest) }
        }
        stderr: StdioCollector {} // Do not forward helper errors or note content to shell logs.
        onExited: { root.processDone = true; Qt.callLater(root.finishRequest) }
    }
    Component.onCompleted: load()
}
