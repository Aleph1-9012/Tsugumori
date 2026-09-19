pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../settings"

Scope {
    id: root
    readonly property ClipboardStore store: ClipboardStore {}
    property bool opened: false
    property bool clearPending: false
    property real reveal: 0
    property real curtainCover: 1
    property bool openPending: false
    property bool togglePending: false
    property string monitorResult: ""
    property string activeMonitor: ""
    property double now: Date.now()
    // Clipboard-only scale; leave the other desktop widgets unchanged.
    readonly property real s: Math.max(0.5, Settings.scale) * 0.9
    readonly property bool reducedMotion: Quickshell.env("TSUGUMORI_REDUCED_MOTION") === "1" || Settings.revealDuration <= 0
    readonly property bool dark: Settings.clipboardDark
    readonly property color paper: dark ? "#111112" : "#c8c8c4"
    readonly property color ink: dark ? "#c5c4c2" : "#252424"
    readonly property color muted: dark ? "#92908e" : "#62605a"
    readonly property color line: dark ? "#373435" : "#a4a4a0"
    readonly property color faint: dark ? "#282526" : "#b4b4b0"
    readonly property color accent: "#d4161c"
    readonly property color actionInk: dark ? "#ee5155" : "#a3181e"

    function show() { requestOpen(false) }
    function toggle() {
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
        now = Date.now()
        root.store.send("sync")
        wipeHide.stop()
        wipeReveal.stop()
        if (reducedMotion) {
            reveal = 1
            curtainCover = 0
            Qt.callLater(root.focusSearch)
        } else {
            if (reveal <= 0) curtainCover = 1
            wipeReveal.start()
        }
    }
    function focusSearch() {
        if (!opened) return
        if (clearPending) cancelClearButton.forceActiveFocus()
        else search.forceActiveFocus()
    }
    function hide() {
        openPending = false; togglePending = false
        clearPending = false
        monitorTimeout.stop()
        if (!opened) return
        opened = false
        wipeReveal.stop(); wipeHide.stop()
        if (reducedMotion) { reveal = 0; curtainCover = 1 }
        else wipeHide.start()
    }
    function age(seconds) {
        const minutes = Math.max(0, Math.floor((now / 1000 - seconds) / 60))
        if (minutes === 0) return "JUST NOW"
        if (minutes < 60) return minutes + " MIN AGO"
        if (minutes < 1440) return Math.floor(minutes / 60) + " HR AGO"
        return Math.floor(minutes / 1440) + " D AGO"
    }
    function sizeLabel(bytes) {
        return bytes < 1024 ? bytes + " B" : bytes < 1048576 ? Math.round(bytes / 1024) + " KB" : (bytes / 1048576).toFixed(1) + " MB"
    }
    // Match Quick Notes, mirrored for the clipboard's left-side placement.
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
        onFinished: if (root.opened) Qt.callLater(root.focusSearch)
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
        stdout: StdioCollector { onStreamFinished: { root.monitorResult = text.trim(); root.finishOpen() } }
        onExited: Qt.callLater(root.finishOpen)
    }
    Timer { id: monitorTimeout; interval: 800; onTriggered: { monitor.running = false; root.finishOpen() } }
    Timer { interval: 15000; running: root.opened; repeat: true; onTriggered: root.now = Date.now() }
    Connections { target: root.store; function onRestored() { root.hide() } }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            let found = false
            for (const candidate of Quickshell.screens)
                if (candidate.name === root.activeMonitor) found = true
            if (!found) root.hide()
        }
    }

    component SmallText: Text {
        color: root.muted
        font.family: "Inter"; font.pixelSize: 11 * root.s; font.letterSpacing: 1.6 * root.s
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component FlatButton: Button {
        id: button
        property color restingColor: root.muted
        property real textSize: 11
        property bool outlined: false
        readonly property bool redFillActive: enabled && (hovered || activeFocus || (outlined && (down || checked)))
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        padding: 10 * root.s
        leftPadding: 12 * root.s; rightPadding: 12 * root.s
        implicitHeight: 36 * root.s
        opacity: enabled ? 1 : 0.35
        background: Rectangle {
            id: buttonBackground
            color: button.outlined ? root.paper : "transparent"
            border.color: root.accent
            border.width: button.outlined ? 1 : 0
            Rectangle {
                x: buttonBackground.border.width; y: x
                height: Math.max(0, parent.height - 2 * x)
                width: button.redFillActive ? Math.max(0, parent.width - 2 * x) : 0
                color: root.accent
                Behavior on width {
                    enabled: !root.reducedMotion
                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                }
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: 3 * root.s
                visible: button.activeFocus; color: "transparent"
                border.color: !button.outlined || button.redFillActive ? "#090909" : root.ink
            }
        }
        contentItem: Text {
            text: button.text
            font.family: "Inter"; font.pixelSize: button.textSize * root.s
            font.letterSpacing: button.outlined && button.text.length === 1 ? 0 : 1.6 * root.s
            color: button.redFillActive ? "#090909" : button.restingColor
            verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
        }
    }
    component Divider: Rectangle { implicitHeight: 1; color: root.line; Layout.fillWidth: true }

    PanelWindow {
        id: panel
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: root.opened || wipeReveal.running || wipeHide.running || root.reveal > 0
        WlrLayershell.namespace: "tsugumori-clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: Region { width: root.opened ? panel.width : 0; height: root.opened ? panel.height : 0 }
        MouseArea { anchors.fill: parent; enabled: root.opened; onClicked: root.hide() }

        Rectangle {
            id: drawer
            readonly property real margin: 24 * root.s
            readonly property real topInset: Math.min((Settings.waybarHeight + 20) * root.s, panel.height * 0.15)
            readonly property bool narrow: width < 550 * root.s
            width: Math.max(1, Math.min(690 * root.s, panel.width - margin * 2))
            height: Math.max(1, Math.min((narrow ? 720 : 520) * root.s, panel.height - topInset - margin))
            x: margin - (width + margin) * (1 - root.reveal)
            // Halfway from top alignment to vertical-centre alignment.
            y: topInset + Math.max(0, panel.height - topInset - margin - height) * 0.25
            color: root.paper; border.color: root.line
            clip: true; enabled: root.opened
            MouseArea { anchors.fill: parent }
            Item {
                id: contentGridBackground
                // Keep the original grid alignment, but only draw behind the content.
                x: clipboardContent.x
                y: clipboardContent.y + contentArea.y
                width: clipboardContent.width
                height: contentArea.height
                clip: true
                Repeater {
                    model: Math.ceil(drawer.width / (24 * root.s))
                    Rectangle { required property int index; x: index * 24 * root.s - contentGridBackground.x; width: 1; height: contentGridBackground.height; color: Qt.alpha(root.accent, root.dark ? 0.18 : 0.16) }
                }
                Repeater {
                    model: Math.ceil(contentGridBackground.height / (24 * root.s)) + 1
                    Rectangle { required property int index; y: index * 24 * root.s - contentGridBackground.y % (24 * root.s); height: 1; width: contentGridBackground.width; color: Qt.alpha(root.accent, root.dark ? 0.18 : 0.16) }
                }
            }
            FocusScope {
                id: clipboardContent
                anchors.fill: parent; anchors.margins: 1
                Keys.priority: Keys.BeforeItem
                Keys.onEscapePressed: event => {
                    if (root.clearPending) { root.clearPending = false; root.focusSearch() }
                    else root.hide()
                    event.accepted = true
                }
                Keys.onPressed: event => {
                    if (root.clearPending) return
                    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                        root.store.moveSelection(event.key === Qt.Key_Down ? 1 : -1)
                        history.positionViewAtIndex(root.store.selectedIndex, ListView.Contain)
                        event.accepted = true
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                               && (search.activeFocus || history.activeFocus)) {
                        if (root.store.selectedId && !root.store.busy) root.store.send("use")
                        event.accepted = true
                    } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                        search.forceActiveFocus(); search.selectAll(); event.accepted = true
                    }
                }
                ColumnLayout {
                    anchors.fill: parent; spacing: 0
                    RowLayout {
                        Layout.fillWidth: true; Layout.preferredHeight: 64 * root.s
                        Layout.leftMargin: 21 * root.s; Layout.rightMargin: 21 * root.s
                        spacing: 16 * root.s
                        SmallText { text: "CLIPBOARD"; color: root.ink; font.pixelSize: 13 * root.s; font.letterSpacing: 2.8 * root.s }
                        Rectangle { width: 25 * root.s; height: 1; color: root.muted }
                        SmallText { text: "履歴"; font.family: "Noto Sans CJK JP"; font.pixelSize: 12 * root.s }
                        Item { Layout.fillWidth: true }
                        FlatButton {
                            outlined: true
                            text: "×"; textSize: 21; padding: 0
                            implicitWidth: 32 * root.s; implicitHeight: 32 * root.s
                            restingColor: root.actionInk
                            Accessible.name: "Close clipboard"
                            onClicked: root.hide()
                        }
                    }
                    Divider {}
                    RowLayout {
                        Layout.fillWidth: true; Layout.preferredHeight: 57 * root.s
                        enabled: !root.clearPending
                        Layout.leftMargin: 21 * root.s; Layout.rightMargin: 14 * root.s
                        spacing: 12 * root.s
                        Text { text: "⌕"; font.family: "Inter"; font.pixelSize: 22 * root.s; color: root.accent }
                        TextField {
                            id: search
                            Layout.fillWidth: true; Layout.minimumWidth: 30 * root.s
                            placeholderText: "Search copied items…"
                            text: root.store.query
                            onTextEdited: root.store.query = text
                            font.family: "Inter"; font.pixelSize: 14 * root.s
                            color: root.ink; placeholderTextColor: root.muted
                            selectionColor: root.accent; selectedTextColor: "#090909"
                            padding: 5 * root.s; selectByMouse: true
                            background: Item {}
                            Accessible.name: "Search clipboard history"
                        }
                        FlatButton {
                            outlined: true
                            text: "PINNED"
                            checkable: true; checked: root.store.pinnedOnly
                            restingColor: checked ? root.actionInk : root.muted
                            onClicked: root.store.pinnedOnly = !root.store.pinnedOnly
                        }
                    }
                    Divider {}
                    GridLayout {
                        id: contentArea
                        Layout.fillWidth: true; Layout.fillHeight: true
                        enabled: !root.clearPending
                        columns: drawer.narrow ? 1 : 3
                        rowSpacing: 0; columnSpacing: 0
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.preferredWidth: 355 * root.s
                            Layout.minimumHeight: 100 * root.s
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true; Layout.preferredHeight: 47 * root.s
                                Layout.leftMargin: 21 * root.s; Layout.rightMargin: 21 * root.s
                                SmallText { Layout.fillWidth: true; text: root.store.pinnedOnly ? "PINNED COPIES" : "RECENT COPIES" }
                                SmallText { text: root.store.entries.count.toString().padStart(2, "0"); font.family: "JetBrainsMono Nerd Font" }
                            }
                            Divider { color: root.faint }
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                ListView {
                                    id: history
                                    anchors.fill: parent
                                    clip: true; model: root.store.entries
                                    boundsBehavior: Flickable.StopAtBounds
                                    reuseItems: false
                                    currentIndex: root.store.selectedIndex
                                    // Let the parent route arrows through the store and preview.
                                    keyNavigationEnabled: false
                                    ScrollBar.vertical: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle { implicitWidth: 3 * root.s; color: root.muted; opacity: 0.6 }
                                        background: Item {}
                                    }
                                    delegate: ClipboardRow {
                                        required property int index
                                        required property var model
                                        width: history.width
                                        number: index + 1; title: model.title; kind: model.kind
                                        pinned: model.pinned; age: root.age(model.copiedAt)
                                        selected: root.store.selectedId === model.clipId
                                        uiScale: root.s; reducedMotion: root.reducedMotion
                                        ink: root.ink; muted: root.muted; line: root.faint; accent: root.accent
                                        onClicked: { root.store.select(model.clipId); history.forceActiveFocus() }
                                    }
                                }
                                Text {
                                    anchors.fill: parent; anchors.margins: 21 * root.s
                                    visible: root.store.entries.count === 0
                                    text: !root.store.ready ? "Clipboard unavailable" : root.store.query ? "No matching entries" : root.store.pinnedOnly ? "No pinned entries" : "Copy text or an image\nto start your history"
                                    wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    font.family: "Inter"; font.pixelSize: 13 * root.s; color: root.muted
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillHeight: !drawer.narrow; Layout.fillWidth: drawer.narrow
                            implicitWidth: 1; implicitHeight: 1; color: root.line
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.preferredWidth: 330 * root.s; Layout.minimumHeight: 160 * root.s
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true; Layout.preferredHeight: 47 * root.s
                                Layout.leftMargin: 20 * root.s; Layout.rightMargin: 20 * root.s
                                SmallText { Layout.fillWidth: true; text: "PREVIEW" }
                                SmallText { text: root.store.selectedEntry ? (root.store.selectedIndex + 1).toString().padStart(2, "0") + " / " + root.store.selectedEntry.kind : "EMPTY"; font.family: "JetBrainsMono Nerd Font"; font.letterSpacing: 0.4 * root.s }
                            }
                            Divider { color: root.faint }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Layout.margins: 20 * root.s; Layout.topMargin: 18 * root.s; Layout.bottomMargin: 10 * root.s
                                spacing: 13 * root.s
                                Item {
                                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 30 * root.s
                                    Image {
                                        id: previewImage
                                        anchors.fill: parent
                                        source: root.store.detail.clipId === root.store.selectedId ? root.store.detail.preview : ""
                                        visible: source.toString().length > 0
                                        fillMode: Image.PreserveAspectFit
                                        horizontalAlignment: Image.AlignLeft; verticalAlignment: Image.AlignTop
                                        cache: false; asynchronous: true
                                    }
                                    ScrollView {
                                        id: textPreview
                                        anchors.fill: parent; clip: true
                                        visible: root.store.selectedEntry && root.store.selectedEntry.kind !== "IMAGE"
                                        contentWidth: availableWidth
                                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                        TextArea {
                                            width: textPreview.availableWidth
                                            text: root.store.detail.clipId === root.store.selectedId ? root.store.detail.body : ""
                                            readOnly: true; selectByMouse: true; textFormat: TextEdit.PlainText
                                            wrapMode: TextEdit.Wrap; padding: 0
                                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 * root.s
                                            color: root.ink; selectionColor: root.accent; selectedTextColor: "#090909"
                                            background: Item {}
                                        }
                                    }
                                    SmallText {
                                        anchors.centerIn: parent
                                        visible: !root.store.selectedId || (previewImage.visible && previewImage.status === Image.Error)
                                        text: !root.store.selectedId ? "NO ENTRY SELECTED" : "PREVIEW UNAVAILABLE"
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.store.selectedEntry ? root.store.selectedEntry.title : ""
                                    textFormat: Text.PlainText; elide: Text.ElideRight
                                    font.family: "Inter"; font.pixelSize: 13 * root.s; color: root.ink
                                }
                                SmallText {
                                    Layout.fillWidth: true
                                    text: root.store.selectedEntry ? root.sizeLabel(root.store.selectedEntry.byteSize)
                                          + (root.store.detail.truncated ? " // PREVIEW TRUNCATED" : "") : ""
                                    font.family: "JetBrainsMono Nerd Font"; font.letterSpacing: 0
                                }
                                Divider { color: root.faint }
                                RowLayout {
                                    Layout.fillWidth: true
                                    FlatButton {
                                        text: root.store.selectedEntry && root.store.selectedEntry.pinned ? "UNPIN" : "PIN"
                                        restingColor: root.store.selectedEntry && root.store.selectedEntry.pinned ? root.actionInk : root.muted
                                        enabled: !!root.store.selectedId && !root.store.busy
                                        onClicked: root.store.send("pin")
                                    }
                                    Item { Layout.fillWidth: true }
                                    FlatButton {
                                        text: "×"; textSize: 21; Accessible.name: "Delete selected clipboard entry"
                                        enabled: !!root.store.selectedId && !root.store.busy
                                        onClicked: root.store.send("delete")
                                    }
                                }
                            }
                        }
                    }
                    Divider {}
                    GridLayout {
                        visible: !root.clearPending
                        Layout.fillWidth: true; Layout.preferredHeight: 65 * root.s
                        Layout.leftMargin: 21 * root.s; Layout.rightMargin: 14 * root.s
                        columns: drawer.narrow ? 2 : 4
                        columnSpacing: 8 * root.s; rowSpacing: 0
                        SmallText {
                            Layout.fillWidth: true
                            Layout.columnSpan: drawer.narrow ? 2 : 1
                            Layout.minimumWidth: 0
                            text: root.store.total.toString().padStart(2, "0") + " ENTRIES // LOCAL"
                            font.family: "JetBrainsMono Nerd Font"; font.letterSpacing: 0
                        }
                        FlatButton {
                            outlined: true
                            text: "CLEAR HISTORY"; restingColor: root.actionInk
                            enabled: root.store.ready && !root.store.busy && root.store.clearableCount > 0
                            Accessible.description: "Clear unpinned clipboard history. Confirmation required."
                            onClicked: { root.clearPending = true; Qt.callLater(root.focusSearch) }
                        }
                        FlatButton { text: "UNDO"; visible: root.store.canUndo; restingColor: root.actionInk; enabled: !root.store.busy; onClicked: root.store.send("undo") }
                        FlatButton {
                            outlined: true
                            text: "USE ENTRY  ↵"; restingColor: root.actionInk
                            Layout.alignment: Qt.AlignRight
                            enabled: !!root.store.selectedId && !root.store.busy
                            onClicked: root.store.send("use")
                        }
                    }
                    GridLayout {
                        visible: root.clearPending
                        Layout.fillWidth: true; Layout.preferredHeight: 65 * root.s
                        Layout.leftMargin: 21 * root.s; Layout.rightMargin: 14 * root.s
                        columns: drawer.narrow ? 2 : 3
                        columnSpacing: 8 * root.s; rowSpacing: 4 * root.s
                        Text {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            Layout.columnSpan: drawer.narrow ? 2 : 1
                            text: "Clear all unpinned history?\nPinned entries stay. Undo within 30 seconds."
                            textFormat: Text.PlainText; wrapMode: Text.WordWrap
                            font.family: "Inter"; font.pixelSize: 11 * root.s; color: root.ink
                        }
                        FlatButton {
                            id: cancelClearButton
                            outlined: true; text: "CANCEL"
                            onClicked: { root.clearPending = false; root.focusSearch() }
                        }
                        FlatButton {
                            outlined: true; text: "CLEAR"; restingColor: root.actionInk
                            enabled: root.store.ready && !root.store.busy && root.store.clearableCount > 0
                            onClicked: {
                                root.store.send("clear")
                                root.clearPending = false
                                root.focusSearch()
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; Layout.margins: 14 * root.s; Layout.topMargin: 0
                        visible: root.store.errorMessage !== ""
                        Text {
                            Layout.fillWidth: true; text: root.store.errorMessage
                            wrapMode: Text.WordWrap; font.family: "Inter"; font.pixelSize: 12 * root.s; color: root.actionInk
                        }
                        FlatButton { text: "RETRY"; onClicked: root.store.retry() }
                    }
                }
            }
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.accent }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.accent }
            CurtainSurface {
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: parent.width * root.curtainCover
                uiScale: root.s
                z: 50
                visible: width > 0
            }
        }
    }

    component ClipboardStore: Scope {
        id: storeState
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
        Timer { id: searchDelay; interval: 130; onTriggered: storeState.send("sync") }
        Timer {
            id: deadline
            interval: 8000
            onTriggered: { storeState.busy = false; storeState.errorCode = "timeout" }
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
            const nextIndex = Math.max(0, Math.min(entriesModel.count - 1, selectedIndex + step))
            select(entriesModel.get(nextIndex).clipId)
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
                storeState.ready = false
                storeState.errorCode = ""
                storeState.watcherError = ""
                storeState.requestId = 0
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
            stdout: SplitParser { onRead: data => storeState.receive(data) }
            stderr: StdioCollector {} // Do not forward clipboard/helper output into shell logs.
            onExited: {
                storeState.ready = false
                storeState.busy = false
                deadline.stop()
                if (!restartDelay.running && !storeState.errorCode) storeState.errorCode = "worker"
            }
        }
        Component.onCompleted: worker.running = true
    }

    component ClipboardRow: Button {
        id: rowControl
        property string title: ""
        property string kind: "TEXT"
        property string age: ""
        property bool pinned: false
        property int number: 1
        property bool selected: false
        property bool reducedMotion: false
        property real uiScale: 1
        property color ink: "#252424"
        property color muted: "#62605a"
        property color line: "#c3bcb2"
        property color accent: "#d4161c"
        property real fillProgress: 0
        readonly property bool rowHighlighted: selected || hovered
        implicitHeight: 71 * uiScale
        padding: 0
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: number.toString().padStart(2, "0") + "// " + title + (pinned ? ", pinned" : "")
        Accessible.description: selected ? "Selected clipboard entry" : "Preview clipboard entry"

        function updateFill() {
            wipe.stop()
            if (selected || reducedMotion) fillProgress = rowHighlighted ? 1 : 0
            else { wipe.from = fillProgress; wipe.to = rowHighlighted ? 1 : 0; wipe.start() }
        }
        onRowHighlightedChanged: updateFill()
        onSelectedChanged: updateFill()
        onReducedMotionChanged: updateFill()
        Component.onCompleted: updateFill()
        NumberAnimation {
            id: wipe
            target: rowControl; property: "fillProgress"
            duration: 280
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.2, 0.7, 0.2, 1, 1, 1]
        }
        background: Item {
            Rectangle { width: parent.width * rowControl.fillProgress; height: parent.height; color: rowControl.accent }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: rowControl.line }
            Rectangle {
                anchors.fill: parent; anchors.margins: 3 * rowControl.uiScale
                visible: rowControl.activeFocus; color: "transparent"
                border.color: rowControl.rowHighlighted ? "#090909" : rowControl.muted
            }
        }
        contentItem: Item {
            Text {
                x: 21 * rowControl.uiScale; y: 16 * rowControl.uiScale
                text: rowControl.number.toString().padStart(2, "0") + "//"
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 * rowControl.uiScale
                color: rowControl.rowHighlighted ? "#090909" : rowControl.muted
            }
            Column {
                x: 63 * rowControl.uiScale; y: 13 * rowControl.uiScale
                width: Math.max(1, parent.width - x - 36 * rowControl.uiScale)
                spacing: 7 * rowControl.uiScale
                Text {
                    width: parent.width
                    text: rowControl.title; textFormat: Text.PlainText; elide: Text.ElideRight
                    font.family: "Inter"; font.pixelSize: 14 * rowControl.uiScale; font.letterSpacing: 0.35 * rowControl.uiScale
                    color: rowControl.rowHighlighted ? "#090909" : rowControl.ink
                }
                Text {
                    width: parent.width
                    text: (rowControl.kind === "IMAGE" ? "IMG" : rowControl.kind === "LINK" ? "URL" : "TXT")
                          + "  " + rowControl.age + (rowControl.pinned ? "  / PIN" : "")
                    elide: Text.ElideRight
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 * rowControl.uiScale
                    color: rowControl.rowHighlighted ? "#090909" : rowControl.muted
                }
            }
            Rectangle {
                anchors { right: parent.right; rightMargin: 19 * rowControl.uiScale; verticalCenter: parent.verticalCenter }
                width: 6 * rowControl.uiScale; height: width; rotation: 45
                visible: rowControl.selected; color: "#090909"
            }
        }
    }
}
