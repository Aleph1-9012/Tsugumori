pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../settings"
import "../theme"

Scope {
    id: root
    readonly property NotesStore store: NotesStore {}
    property bool opened: false
    property real reveal: 0
    property real curtainCover: 1
    property bool openPending: false
    property bool togglePending: false
    property string monitorResult: ""
    property string activeMonitor: ""
    property bool recoveryConfirm: false
    readonly property bool reducedMotion: Quickshell.env("TSUGUMORI_REDUCED_MOTION") === "1"
                                          || Settings.revealDuration <= 0
    readonly property real uiScale: Math.max(0.5, Settings.scale)

    function show() {
        requestOpen(false)
    }
    function toggle() {
        // A second press while the monitor lookup is pending cancels opening.
        if (openPending && togglePending) { hide(); return }
        requestOpen(true)
    }
    function requestOpen(toggleRequested) {
        togglePending = toggleRequested
        openPending = true
        if (monitor.running) return
        monitorResult = ""
        monitorTimeout.restart()
        monitor.running = true
    }
    function finishOpen() {
        if (!openPending) return
        openPending = false
        monitorTimeout.stop()
        let target = null
        for (const candidate of Quickshell.screens)
            if (candidate.name === monitorResult) target = candidate
        if (!target) target = panel.screen || Quickshell.screens[0]
        if (!target) return
        const alreadyHere = opened && panel.screen === target
        if (alreadyHere && togglePending) { hide(); return }
        panel.screen = target
        activeMonitor = target.name
        if (alreadyHere) return
        opened = true
        wipeHide.stop()
        wipeReveal.stop()
        if (reducedMotion) {
            reveal = 1
            curtainCover = 0
            Qt.callLater(editor.restoreFocus)
        } else {
            if (reveal <= 0) curtainCover = 1
            wipeReveal.start()
        }
    }
    function hide() {
        openPending = false
        togglePending = false
        monitorTimeout.stop()
        root.store.flush()
        editor.resetCopyFeedback()
        if (!opened) return
        opened = false
        recoveryConfirm = false
        wipeReveal.stop()
        wipeHide.stop()
        if (reducedMotion) { reveal = 0; curtainCover = 1 }
        else wipeHide.start()
    }
    // Match Menu.qml: covered slide-in, curtain reveal, cover, slide-out.
    // Animate from current values so rapid toggles do not reset the geometry.
    SequentialAnimation {
        id: wipeReveal
        NumberAnimation {
            target: root; property: "reveal"; to: 1
            duration: 440; easing.type: Easing.OutExpo
        }
        NumberAnimation {
            target: root; property: "curtainCover"; to: 0
            duration: 340; easing.type: Easing.OutExpo
        }
        onFinished: if (root.opened) Qt.callLater(editor.restoreFocus)
    }
    SequentialAnimation {
        id: wipeHide
        NumberAnimation {
            target: root; property: "curtainCover"; to: 1
            duration: 180; easing.type: Easing.InOutQuart
        }
        NumberAnimation {
            target: root; property: "reveal"; to: 0
            duration: 340; easing.type: Easing.InExpo
        }
    }
    Process {
        id: monitor
        command: ["/bin/sh", Qt.resolvedUrl("../active-monitor.sh").toString().replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: { root.monitorResult = text.trim(); root.finishOpen() }
        }
        onExited: Qt.callLater(root.finishOpen)
    }
    Timer {
        id: monitorTimeout
        interval: 800
        onTriggered: { monitor.running = false; root.finishOpen() }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            let connected = false
            for (const candidate of Quickshell.screens)
                if (candidate.name === root.activeMonitor) connected = true
            if (!connected) root.hide()
        }
    }

    component NotesButton: Button {
        id: button
        property real textSize: 12
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        padding: 9 * root.uiScale
        leftPadding: 12 * root.uiScale
        rightPadding: 12 * root.uiScale
        opacity: enabled ? 1 : 0.4
        background: Rectangle {
            color: "transparent"
            border.color: Qt.alpha(Theme.a1, 0.55)
            Rectangle {
                height: parent.height
                width: button.hovered || button.activeFocus ? parent.width : 0
                color: Theme.a1
                Behavior on width {
                    enabled: !root.reducedMotion
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
                    }
                }
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: 3
                visible: button.activeFocus
                color: "transparent"; border.color: Theme.bg
            }
        }
        contentItem: Text {
            text: button.text
            font.family: Theme.mono
            font.pixelSize: button.textSize * root.uiScale
            font.letterSpacing: root.uiScale
            color: button.hovered || button.activeFocus ? Theme.bg : Theme.fg
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    PanelWindow {
        id: panel
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: root.opened || wipeReveal.running || wipeHide.running || root.reveal > 0
        WlrLayershell.namespace: "tsugumori-notes"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: Region { width: root.opened ? panel.width : 0; height: root.opened ? panel.height : 0 }

        MouseArea { anchors.fill: parent; enabled: root.opened; onClicked: root.hide() }

        Rectangle {
            id: drawer
            readonly property real s: root.uiScale
            readonly property real margin: 20 * s
            readonly property real requestedHeight: (318 + Math.min(170, Math.max(0, root.store.notes.count * 47 - 7))
                                                       + (root.store.undoStack.length ? 46 : 0)
                                                       + (root.store.errorCode ? 115 : 0)) * s
            width: Math.max(1, Math.min(420 * s, panel.width - 2 * margin))
            height: Math.max(1, Math.min(requestedHeight, panel.height - y - margin))
            x: panel.width - width - margin + (width + margin) * (1 - root.reveal)
            y: Math.min((Settings.waybarHeight + 20) * s, panel.height * 0.15)
            color: Theme.bg
            border.color: Theme.a1
            border.width: 1
            clip: true
            enabled: root.opened

            CurtainSurface {
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: parent.width * root.curtainCover
                uiScale: drawer.s
                z: 50
                visible: width > 0
            }

            // Keep clicks inside the frame from reaching outside dismissal.
            MouseArea { anchors.fill: parent }
            Item {
                anchors.fill: parent
                clip: true
                Repeater {
                    model: Math.ceil(drawer.width / (20 * drawer.s))
                    Rectangle { required property int index; x: index * 20 * drawer.s; width: 1; height: drawer.height; color: Qt.alpha(Theme.a1, 0.08) }
                }
                Repeater {
                    model: Math.ceil(drawer.height / (20 * drawer.s))
                    Rectangle { required property int index; y: index * 20 * drawer.s; height: 1; width: drawer.width; color: Qt.alpha(Theme.a1, 0.08) }
                }
            }
            Rectangle { anchors.fill: parent; anchors.margins: 4 * drawer.s; color: "transparent"; border.color: Qt.alpha(Theme.a1, 0.3) }
            Rectangle { x: -1; y: 16 * drawer.s; width: 4 * drawer.s; height: 40 * drawer.s; color: Theme.a1 }
            Repeater {
                model: 4
                Item {
                    required property int index
                    x: index % 2 ? drawer.width - width : 6 * drawer.s
                    y: index < 2 ? -1 : drawer.height - height + 1
                    width: 8 * drawer.s; height: width
                    Rectangle { width: parent.width; height: 2; y: index < 2 ? 0 : parent.height - 2; color: Qt.alpha(Theme.fg, 0.55) }
                    Rectangle { height: parent.height; width: 2; x: index % 2 ? parent.width - 2 : 0; color: Qt.alpha(Theme.fg, 0.55) }
                }
            }

            FocusScope {
                id: editor
                anchors.fill: parent
                anchors.margins: 20 * drawer.s
                property bool syncing: false
                property string loadedId: ""
                property bool copied: false
                readonly property string copyText: bodyField.text

                function resetCopyFeedback() {
                    copied = false
                    copyFeedback.stop()
                }
                function copyNote() {
                    if (!root.store.ready || root.store.activeIndex < 0 || !copyText.length) return
                    Quickshell.clipboardText = copyText
                    copied = true
                    copyFeedback.restart()
                }
                onCopyTextChanged: resetCopyFeedback()
                Timer {
                    id: copyFeedback
                    interval: 1600
                    onTriggered: editor.copied = false
                }

                function syncNote() {
                    resetCopyFeedback()
                    syncing = true
                    loadedId = root.store.activeId
                    const index = root.store.find(loadedId)
                    const note = index >= 0 ? root.store.notes.get(index) : null
                    titleField.text = note ? note.title : ""
                    bodyField.text = note ? note.body : ""
                    titleField.cursorPosition = Math.min(titleField.length, root.store.cursorFor(loadedId, "title"))
                    bodyField.cursorPosition = Math.min(bodyField.length, root.store.cursorFor(loadedId, "body"))
                    syncing = false
                }
                function restoreFocus() {
                    if (!root.opened) return
                    if (!root.store.ready || root.store.activeIndex < 0) newButton.forceActiveFocus()
                    else if (root.store.editorField === "title") titleField.forceActiveFocus()
                    else bodyField.forceActiveFocus()
                }
                Keys.priority: Keys.BeforeItem
                Keys.onEscapePressed: event => { root.hide(); event.accepted = true }
                Connections {
                    target: root.store
                    function onActiveIdChanged() { editor.syncNote() }
                    function onReadyChanged() { editor.syncNote(); if (root.opened) Qt.callLater(editor.restoreFocus) }
                    function onFocusTitleRequested() { Qt.callLater(function() { if (root.opened) titleField.forceActiveFocus() }) }
                }
                Component.onCompleted: syncNote()

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14 * drawer.s
                    RowLayout {
                        Layout.fillWidth: true
                        Column {
                            Layout.fillWidth: true
                            spacing: 8 * drawer.s
                            Text { text: "QUICK NOTES"; font.family: Theme.mono; font.pixelSize: 14 * drawer.s; font.letterSpacing: 3.5 * drawer.s; color: Theme.fg }
                            Rectangle { width: 36 * drawer.s; height: 1; color: Qt.alpha(Theme.a1, 0.55) }
                        }
                        NotesButton {
                            text: "×"; textSize: 21
                            padding: 0; leftPadding: 0; rightPadding: 0
                            implicitWidth: 32 * drawer.s; implicitHeight: 32 * drawer.s
                            Accessible.name: "Close quick notes"
                            onClicked: root.hide()
                        }
                    }
                    ListView {
                        id: noteList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 170 * drawer.s, drawer.height * 0.3)
                        Layout.minimumHeight: 0
                        visible: count > 0
                        model: root.store.notes
                        spacing: 7 * drawer.s
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        reuseItems: false
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: NoteRow {
                            required property int index
                            required property string noteId
                            required property var model
                            title: model.title
                            number: index + 1
                            width: noteList.width
                            uiScale: root.uiScale
                            reducedMotion: root.reducedMotion
                            selected: root.store.activeId === noteId
                            onSelectedRequested: root.store.selectNote(noteId)
                            onDeleteRequested: root.store.removeNote(noteId)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8 * drawer.s
                        visible: root.store.ready && root.store.activeIndex >= 0
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: (root.store.activeIndex + 1).toString().padStart(2, "0") + " / " + root.store.notes.count.toString().padStart(2, "0")
                            font.family: Theme.mono; font.pixelSize: 11 * drawer.s; font.letterSpacing: drawer.s; color: "#909090"
                        }
                        TextField {
                            id: titleField
                            Layout.fillWidth: true
                            font.family: Theme.mono; font.pixelSize: 18 * drawer.s
                            placeholderText: "Untitled note"
                            placeholderTextColor: "#909090"
                            color: Theme.fg
                            selectionColor: Theme.a1; selectedTextColor: Theme.bg
                            padding: 0; bottomPadding: 10 * drawer.s
                            selectByMouse: true
                            Accessible.name: "Note title"
                            background: Rectangle {
                                color: "transparent"
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.alpha(Theme.a1, 0.3) }
                            }
                            onTextEdited: if (!editor.syncing) root.store.edit("title", text)
                            onCursorPositionChanged: if (!editor.syncing) root.store.rememberCursor(editor.loadedId, "title", cursorPosition)
                            onActiveFocusChanged: if (activeFocus) root.store.editorField = "title"
                        }
                        ScrollView {
                            id: bodyScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 40 * drawer.s
                            clip: true
                            contentWidth: availableWidth
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            TextArea {
                                id: bodyField
                                width: bodyScroll.availableWidth
                                font.family: Theme.mono; font.pixelSize: 16 * drawer.s
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                placeholderText: "Write something to remember..."
                                placeholderTextColor: "#909090"
                                color: "#d4d4d4"
                                selectionColor: Theme.a1; selectedTextColor: Theme.bg
                                padding: 0; topPadding: 4 * drawer.s; bottomPadding: 12 * drawer.s
                                selectByMouse: true
                                Accessible.name: "Note contents"
                                background: Item {}
                                onTextChanged: if (!editor.syncing) root.store.edit("body", text)
                                onCursorPositionChanged: if (!editor.syncing) root.store.rememberCursor(editor.loadedId, "body", cursorPosition)
                                onActiveFocusChanged: if (activeFocus) root.store.editorField = "body"
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        visible: !root.store.ready || root.store.activeIndex < 0
                        text: root.store.ready ? "No notes yet" : root.store.busy ? "Loading notes..." : "Notes unavailable"
                        font.family: Theme.mono; font.pixelSize: 16 * drawer.s
                        color: "#909090"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Theme.a1, 0.3) }
                    RowLayout {
                        Layout.fillWidth: true
                        NotesButton { id: newButton; text: "+ NEW NOTE"; enabled: root.store.ready; onClicked: root.store.createNote() }
                        Item { Layout.fillWidth: true }
                        NotesButton {
                            text: editor.copied ? "COPIED" : "COPY"
                            Layout.preferredWidth: newButton.implicitWidth
                            Layout.preferredHeight: newButton.implicitHeight
                            visible: root.store.ready && root.store.activeIndex >= 0
                            enabled: root.store.ready && root.store.activeIndex >= 0 && editor.copyText.length > 0
                            Accessible.name: editor.copied ? "Note copied" : "Copy note"
                            Accessible.description: "Copy only the selected note's contents to the clipboard"
                            onClicked: editor.copyNote()
                        }
                        Text { text: root.store.status; font.family: Theme.mono; font.pixelSize: 11 * drawer.s; color: root.store.errorCode ? Theme.a1 : "#909090" }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.store.undoStack.length > 0
                        Text {
                            Layout.fillWidth: true
                            text: root.store.undoStack.length ? "Deleted " + (root.store.undoStack[root.store.undoStack.length - 1].note.title.trim() || "Untitled note") : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.fg; font.family: Theme.mono; font.pixelSize: 12 * drawer.s
                        }
                        NotesButton { text: "UNDO"; textSize: 11; onClicked: root.store.undoDelete() }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.store.errorCode !== ""
                        Text {
                            Layout.fillWidth: true
                            text: root.recoveryConfirm ? "Replace the unreadable file with its previous backup? The damaged file will be kept." : root.store.errorMessage
                            wrapMode: Text.Wrap
                            font.family: Theme.mono; font.pixelSize: 12 * drawer.s; color: Theme.fg
                        }
                        RowLayout {
                            NotesButton { text: "RETRY"; enabled: !root.store.busy; onClicked: { root.recoveryConfirm = false; root.store.retry() } }
                            NotesButton {
                                text: root.recoveryConfirm ? "CONFIRM RECOVERY" : "RECOVER BACKUP"
                                textSize: 11
                                visible: root.store.canRecover
                                enabled: !root.store.busy
                                onClicked: { if (root.recoveryConfirm) { root.store.recover(); root.recoveryConfirm = false } else root.recoveryConfirm = true }
                            }
                        }
                    }
                }
            }
        }
    }

    component NotesStore: Scope {
        id: storeState

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
        Timer { id: debounce; interval: 400; onTriggered: storeState.flush() }
        Timer { id: maxPending; interval: 2000; onTriggered: storeState.flush() }
        Timer {
            id: deadline
            interval: 10000
            onTriggered: {
                storeState.errorCode = "timeout"
                worker.running = false
                storeState.busy = false
                storeState.requestText = ""
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
                if (dirty && (flushPending || !debounce.running)) Qt.callLater(storeState.flush)
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
            onStarted: write(storeState.requestText)
            stdout: StdioCollector {
                id: output
                onStreamFinished: { storeState.streamDone = true; Qt.callLater(storeState.finishRequest) }
            }
            stderr: StdioCollector {} // Do not forward helper errors or note content to shell logs.
            onExited: { storeState.processDone = true; Qt.callLater(storeState.finishRequest) }
        }
        Component.onCompleted: load()
    }

    component NoteRow: Item {
        id: rowControl

        property string title: ""
        property int number: 1
        property bool selected: false
        property real uiScale: 1
        property bool reducedMotion: false
        readonly property bool highlighted: selected || pointer.hovered || selectButton.activeFocus || deleteButton.activeFocus
        property real fillProgress: 0
        signal selectedRequested()
        signal deleteRequested()

        implicitHeight: 40 * uiScale
        implicitWidth: 378 * uiScale

        // Keep this fill alive when selection changes. Only hover-out animates;
        // selecting a row always cancels the animation and pins it fully red.
        function updateFill() {
            wipe.stop()
            if (selected || reducedMotion) {
                fillProgress = highlighted ? 1 : 0
            } else {
                wipe.from = fillProgress
                wipe.to = highlighted ? 1 : 0
                wipe.start()
            }
        }
        onHighlightedChanged: updateFill()
        onSelectedChanged: updateFill()
        onReducedMotionChanged: updateFill()
        Component.onCompleted: updateFill()

        NumberAnimation {
            id: wipe
            target: rowControl
            property: "fillProgress"
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
        }
        Rectangle { anchors.fill: parent; color: Theme.bg }
        Rectangle {
            width: parent.width * rowControl.fillProgress
            height: parent.height
            color: Theme.a1
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: rowControl.selected ? Theme.a1 : Qt.alpha(Theme.a1, 0.55)
        }
        HoverHandler { id: pointer }
        Button {
            id: selectButton
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: deleteButton.left }
            padding: 0
            focusPolicy: Qt.StrongFocus
            background: Item {}
            Accessible.name: rowControl.number.toString().padStart(2, "0") + "// " + (rowControl.title.trim() || "Untitled note")
            contentItem: Item {
                Rectangle {
                    x: 9 * rowControl.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6 * rowControl.uiScale; height: width
                    rotation: 45
                    visible: rowControl.selected
                    color: Theme.bg
                }
                Text {
                    anchors { left: parent.left; leftMargin: 24 * rowControl.uiScale; right: parent.right; rightMargin: 9 * rowControl.uiScale; verticalCenter: parent.verticalCenter }
                    text: selectButton.Accessible.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.mono
                    font.pixelSize: 16 * rowControl.uiScale
                    color: rowControl.highlighted ? Theme.bg : Theme.fg
                }
            }
            onClicked: { forceActiveFocus(); rowControl.selectedRequested() }
        }
        Button {
            id: deleteButton
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 34 * rowControl.uiScale
            padding: 0
            focusPolicy: Qt.StrongFocus
            Accessible.name: "Delete " + (rowControl.title.trim() || "Untitled note")
            background: Rectangle {
                color: !rowControl.selected && deleteButton.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                Rectangle { width: 1; height: parent.height; color: rowControl.highlighted ? Qt.alpha(Theme.bg, 0.25) : Qt.alpha(Theme.a1, 0.3) }
            }
            contentItem: Text {
                text: "×"
                font.family: Theme.mono
                font.pixelSize: 21 * rowControl.uiScale
                color: rowControl.highlighted ? Theme.bg : Theme.fg
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: rowControl.deleteRequested()
        }
        Rectangle {
            anchors.fill: selectButton.activeFocus ? selectButton : deleteButton
            anchors.margins: 3
            visible: selectButton.activeFocus || deleteButton.activeFocus
            color: "transparent"
            border.color: rowControl.highlighted ? Theme.bg : Theme.fg
        }
    }
}
