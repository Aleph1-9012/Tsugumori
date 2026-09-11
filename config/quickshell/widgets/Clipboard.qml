import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../services"
import "../settings"

Scope {
    id: root
    required property ClipboardService store
    property bool opened: false
    property bool clearPending: false
    property real xOffset: -40 * s
    property real xShake: 0
    property real cardOpacity: 0
    property real scanProgress: 0
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
        exitAnimation.stop()
        enterAnimation.stop()
        if (reducedMotion) {
            xOffset = 0; xShake = 0; cardOpacity = 1; scanProgress = 1
            Qt.callLater(root.focusSearch)
        } else {
            if (cardOpacity <= 0) xOffset = -40 * s
            scanProgress = 0
            enterAnimation.start()
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
        enterAnimation.stop(); exitAnimation.stop()
        if (reducedMotion) { cardOpacity = 0; xOffset = 30 * s; xShake = 0; scanProgress = 1 }
        else exitAnimation.start()
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
    // Match Notifications.qml: slide/fade with a scan, then shake and fade out.
    // Start from current values so a rapid toggle can reverse an in-flight close.
    ParallelAnimation {
        id: enterAnimation
        NumberAnimation { target: root; property: "xOffset"; to: 0; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "cardOpacity"; to: 1; duration: 240 }
        NumberAnimation { target: root; property: "xShake"; to: 0; duration: 150 }
        NumberAnimation { target: root; property: "scanProgress"; to: 1; duration: 550; easing.type: Easing.OutQuad }
        onFinished: root.focusSearch()
    }
    SequentialAnimation {
        id: exitAnimation
        NumberAnimation { target: root; property: "xShake"; to: 6 * root.s; duration: 50 }
        NumberAnimation { target: root; property: "xShake"; to: -4 * root.s; duration: 50 }
        NumberAnimation { target: root; property: "xShake"; to: 0; duration: 50 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "xOffset"; to: 30 * root.s; duration: 280; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "cardOpacity"; to: 0; duration: 280 }
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
        visible: root.opened || enterAnimation.running || exitAnimation.running || root.cardOpacity > 0
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
            x: margin + root.xOffset + root.xShake
            // Halfway from top alignment to vertical-centre alignment.
            y: topInset + Math.max(0, panel.height - topInset - margin - height) * 0.25
            opacity: root.cardOpacity
            color: root.paper; border.color: root.line
            clip: true; enabled: root.opened
            MouseArea { anchors.fill: parent }
            Item {
                anchors.fill: parent; clip: true
                Repeater {
                    model: Math.ceil(drawer.width / (24 * root.s))
                    Rectangle { required property int index; x: index * 24 * root.s; width: 1; height: drawer.height; color: Qt.alpha(root.accent, root.dark ? 0.18 : 0.16) }
                }
                Repeater {
                    model: Math.ceil(drawer.height / (24 * root.s))
                    Rectangle { required property int index; y: index * 24 * root.s; height: 1; width: drawer.width; color: Qt.alpha(root.accent, root.dark ? 0.18 : 0.16) }
                }
            }
            FocusScope {
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
            Rectangle {
                x: root.scanProgress * parent.width - 40 * root.s
                y: 0; width: 80 * root.s; height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#406e2a2a" }
                    GradientStop { position: 1; color: "transparent" }
                }
                opacity: root.scanProgress > 0 && root.scanProgress < 1 ? 1 : 0
                Behavior on opacity { enabled: !root.reducedMotion; NumberAnimation { duration: 100 } }
                z: 50
            }
        }
    }
}
