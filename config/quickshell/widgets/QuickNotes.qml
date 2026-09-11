import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../services"
import "../settings"
import "../theme"

Scope {
    id: root
    required property NotesService store
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

            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: parent.width * root.curtainCover
                color: Theme.fg
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

                function syncNote() {
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
}
