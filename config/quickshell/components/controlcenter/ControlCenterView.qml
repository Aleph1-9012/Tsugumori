pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as C

Item {
    id: view
    required property var controller
    property real availableHeight: 800
    property bool reducedMotion: false
    readonly property bool expanded: controller.level === 3 && controller.open && !controller.closing
    readonly property bool compact: width < 660
    readonly property real cardWidth: compact ? Math.min(300, width - 64) : (width - 140) / 3
    readonly property real branchWidth: compact ? Math.min(376, width - 24) : Math.min(240, (width - 36) * 0.4)
    readonly property real detailWidth: compact ? branchWidth : Math.min(376, width - branchWidth - 36)
    readonly property real branchX: compact ? (width - branchWidth) / 2 : (width - branchWidth - 36 - detailWidth) / 2
    readonly property real branchY: 42
    readonly property real overviewHeight: compact ? 92 + 4 * 170 : 470
    property string displaySlot: "top"
    property string displaySub: "wifi"
    property string detailTitle: "WI-FI"
    property string detailStatus: ""
    property bool detailOn: false
    property real expansion: expanded ? 1 : 0
    property real spread: controller.open && !controller.closing ? 1 : 0
    readonly property var slots: [
        {key:"top",number:"01",title:"Connection"},
        {key:"left",number:"02",title:"Quickshare"},
        {key:"right",number:"03",title:"Notifications"},
        {key:"bottom",number:"04",title:"Audio / Display"},
        {key:"center",number:"00",title:"Menu"}
    ]
    readonly property var currentSlot: slots.find(entry => entry.key === displaySlot)
    implicitHeight: expanded || expansion > 0.01
        ? Math.max(overviewHeight, branchY + 118 + 24 + subColumn.height, details.y + details.height)
        : overviewHeight

    Behavior on expansion { NumberAnimation { duration: view.reducedMotion ? 0 : 380; easing.type: Easing.InOutQuint } }
    Behavior on spread { NumberAnimation { duration: view.reducedMotion ? 0 : 250; easing.type: Easing.InCirc } }
    onExpandedChanged: if (expanded) refresh()

    function selectSub(key) {
        controller.keyboardNavigation = false
        if (!expanded || controller.sub === key) return
        controller.sub = key
        controller.action = controller.firstAction()
    }
    function openSlot(key) {
        if (key === "center") { controller.slot = "center"; return }
        if (expanded) { controller.back(); return }
        controller.slot = key
        controller.sub = controller.firstSub(key)
        controller.level = 3
        controller.action = controller.firstAction()
    }
    function refresh() {
        if (!expanded) return
        displaySlot = controller.slot
        displaySub = controller.sub
        detailTitle = controller.detailH3().toUpperCase()
        detailStatus = controller.detailStatus()
        detailOn = controller.detailOn()
        const entries = controller.actList()
        // Keyed updates keep hovered/focused delegates alive across system polls.
        for (let i = 0; i < entries.length; ++i) {
            const data = entries[i]
            let found = -1
            for (let j = i; j < actionModel.count; ++j) {
                const old = actionModel.get(j).entry
                if ((old.identity || old.key) === (data.identity || data.key)) { found = j; break }
            }
            if (found < 0) actionModel.insert(i, {entry:data})
            else {
                if (found !== i) actionModel.move(found, i, 1)
                actionModel.setProperty(i, "entry", data)
            }
        }
        if (actionModel.count > entries.length) actionModel.remove(entries.length, actionModel.count - entries.length)
    }
    function overviewX(key) {
        const center = (width - cardWidth) / 2
        if (compact) return center
        return center + (key === "left" ? -center : key === "right" ? center : 0) * spread
    }
    function overviewY(key) {
        if (compact) return key === "center" ? 0 : 144 + ({top:0,left:1,bottom:2,right:3})[key] * 170
        const center = (overviewHeight - (key === "center" ? 92 : 118)) / 2
        return center + (key === "top" ? -176 : key === "bottom" ? 176 : 0) * spread
    }
    function selectOverview(key, keyboard = false) {
        if (!expanded && !controller.closing) {
            controller.keyboardNavigation = keyboard
            controller.slot = key
        }
    }
    Connections {
        target: view.controller
        function onLevelChanged() { view.refresh() }
        function onSlotChanged() { view.refresh() }
        function onSubChanged() { view.refresh(); detailScroll.contentY = 0 }
        function onWifiNetworksChanged() { view.refresh() }
        function onWifiEnabledChanged() { view.refresh() }
        function onWifiCurrentSSIDChanged() { view.refresh() }
        function onBtDevicesChanged() { view.refresh() }
        function onBtEnabledChanged() { view.refresh() }
        function onBtScanningChanged() { view.refresh() }
        function onAudioSinksChanged() { view.refresh() }
        function onAudioVolumeChanged() { view.refresh() }
        function onAudioMutedChanged() { view.refresh() }
        function onBrightnessLevelChanged() { view.refresh() }
        function onBrightnessAvailableChanged() { view.refresh() }
        function onNotificationsChanged() { view.refresh() }
        function onDndEnabledChanged() { view.refresh() }
        function onPendingFilePathChanged() { view.refresh() }
        function onQshareTunnelChanged() { view.refresh() }
        function onQshareKeepAliveChanged() { view.refresh() }
        function onQshareOutputDirChanged() { view.refresh() }
        function onQshareUrlChanged() { view.refresh() }
    }
    ListModel { id: actionModel; dynamicRoles: true }

    Repeater {
        model: view.slots
        C.Button {
            id: card
            required property var modelData
            readonly property bool center: modelData.key === "center"
            readonly property bool selected: view.controller.slot === modelData.key
            readonly property bool inBranch: view.expanded && selected && !center
            readonly property var summary: view.controller.summaryForSlot(modelData.key)
            objectName: "controlCard-" + modelData.key
            x: inBranch ? view.branchX : view.overviewX(modelData.key) + (!view.expanded && selected && !center ? (modelData.key === "left" ? -8 : modelData.key === "right" ? 8 : 0) : 0)
            y: inBranch ? view.branchY : view.overviewY(modelData.key) + (!view.expanded && selected ? (modelData.key === "top" ? -8 : modelData.key === "bottom" ? 8 : 0) : 0)
            width: inBranch ? view.branchWidth : view.cardWidth
            height: center ? 92 : 118
            z: inBranch ? 4 : 2
            padding: 0
            opacity: view.expanded && !inBranch ? 0 : 1
            visible: opacity > 0.01
            enabled: !view.controller.closing && (!view.expanded || inBranch)
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Accessible.name: center ? "Menu, control center" : (inBranch ? "Collapse " : "Open ") + modelData.title
            onHoveredChanged: {
                if (hovered) {
                    if (!selected || center) cardFrame.startRoll()
                    view.selectOverview(modelData.key)
                } else cardFrame.stopRoll()
            }
            onPressed: cardFrame.stopRoll()
            onActiveFocusChanged: if (activeFocus) view.selectOverview(modelData.key, focusReason !== Qt.MouseFocusReason)
            onClicked: view.openSlot(modelData.key)
            background: Frame {
                id: cardFrame
                number: card.modelData.number; title: card.modelData.title
                active: card.center || card.selected
                titleLetterSpacing: card.center ? 2 : 0.25
                cornersActive: card.center ? card.hovered || card.visualFocus : card.selected
                reducedMotion: view.reducedMotion
            }
            contentItem: Item {
                Text {
                    visible: !card.center
                    x: 20; y: 52; width: parent.width - 40; height: 20
                    text: card.summary[0]; textFormat: Text.PlainText
                    font.family: "JetBrains Mono"; font.pixelSize: 14
                    color: card.selected ? "#e8e8e8" : "#c6c6c6"; elide: Text.ElideRight
                }
                Text {
                    visible: !card.center; x: 20; y: parent.height - 32; width: (parent.width - 50) / 2
                    text: card.summary[1]; textFormat: Text.PlainText
                    font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#a2a2a2"; elide: Text.ElideRight
                }
                Text {
                    visible: !card.center; anchors.right: parent.right; anchors.rightMargin: 20; y: parent.height - 32; width: (parent.width - 50) / 2
                    text: card.summary[2]; textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignRight
                    font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#a2a2a2"; elide: Text.ElideRight
                }
                Text {
                    visible: card.center; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 33
                    text: "CONTROL CENTER"; font.family: "JetBrains Mono"; font.pixelSize: 11; font.letterSpacing: 0.8; color: "#a2a2a2"
                }
                Rectangle { anchors.fill: parent; anchors.margins: 3; color: "transparent"; border.color: "#e8e8e8"; visible: card.visualFocus }
            }
            Item {
                width: 18; height: 14
                x: card.modelData.key === "top" || card.modelData.key === "bottom" ? (card.width - width) / 2 : card.modelData.key === "right" ? card.width + 14 : -32
                y: card.modelData.key === "top" ? -32 : card.modelData.key === "bottom" ? card.height + 18 : (card.height - height) / 2
                rotation: card.modelData.key === "top" ? 90 : card.modelData.key === "bottom" ? -90 : card.modelData.key === "right" ? 180 : 0
                opacity: card.selected && !card.center && !view.expanded ? 1 : 0
                Rectangle { x: 0; y: 3; width: 7; height: 7; rotation: 45; color: "#e8e8e8" }
                Canvas {
                    x: 10; y: 1; width: 8; height: 12
                    onPaint: { const ctx = getContext("2d"); ctx.reset(); ctx.strokeStyle = "#e8e8e8"; ctx.lineWidth = 1.2; ctx.beginPath(); ctx.moveTo(1,1); ctx.lineTo(7,6); ctx.lineTo(1,11); ctx.stroke() }
                }
                Behavior on opacity { NumberAnimation { duration: view.reducedMotion ? 0 : 220 } }
            }
            Behavior on x { NumberAnimation { duration: view.reducedMotion ? 0 : 480; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: view.reducedMotion ? 0 : 480; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: view.reducedMotion ? 0 : 480; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: view.reducedMotion ? 0 : 240 } }
        }
    }
    Repeater {
        model: ["top","left","right","bottom"]
        Item {
            id: arrow
            required property string modelData
            readonly property bool selected: view.controller.slot === modelData
            width: 36; height: 36
            x: modelData === "left" ? (view.cardWidth / 2 + view.width / 2) / 2 - 18 : modelData === "right" ? (view.width - view.cardWidth / 2 + view.width / 2) / 2 - 18 : view.width / 2 - 18
            y: modelData === "top" ? 129 : modelData === "bottom" ? 305 : 217
            rotation: (modelData === "top" ? -90 : modelData === "bottom" ? 90 : modelData === "left" ? 180 : 0) + (selected ? 180 : 0)
            opacity: view.expanded || view.controller.closing ? 0 : selected ? 1 : 0.65
            visible: !view.compact && opacity > 0.01
            Repeater {
                model: 4
                Item {
                    required property int index
                    x: index % 2 === 0 ? 6 : 24; y: index < 2 ? 6 : 24; width: 6; height: 6
                    Rectangle { width: 6; height: 1.3; y: parent.index < 2 ? 0 : 4.7; color: "#e8e8e8" }
                    Rectangle { width: 1.3; height: 6; x: parent.index % 2 === 0 ? 0 : 4.7; color: "#e8e8e8" }
                }
            }
            Canvas {
                id: arrowCanvas
                anchors.fill: parent
                onPaint: { const ctx = getContext("2d"); ctx.reset(); ctx.strokeStyle = arrow.selected ? "#cc1515" : "#e8e8e8"; ctx.lineWidth = 1.8; ctx.beginPath(); ctx.moveTo(11,18); ctx.lineTo(25,18); ctx.moveTo(19,12); ctx.lineTo(25,18); ctx.lineTo(19,24); ctx.stroke() }
                Connections { target: arrow; function onSelectedChanged() { arrowCanvas.requestPaint() } }
            }
            Behavior on rotation { NumberAnimation { duration: view.reducedMotion ? 0 : 320; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: view.reducedMotion ? 0 : 220 } }
        }
    }
    ActionButton {
        objectName: "controlBack"
        x: view.branchX; y: 0; width: view.branchWidth; height: 30
        text: "← MENU"; diamond: false
        opacity: view.expansion
        visible: opacity > 0.01; enabled: view.expanded
        reducedMotion: view.reducedMotion
        onClicked: view.controller.back()
    }
    Rectangle {
        x: view.branchX + view.branchWidth / 2; y: view.branchY + 118
        width: 1; height: 24; color: "#858585"
        opacity: view.expansion
        visible: opacity > 0.01
    }
    Column {
        id: subColumn
        x: view.branchX; y: view.branchY + 142; width: view.branchWidth
        spacing: 12
        opacity: view.expansion
        visible: opacity > 0.01; enabled: view.expanded
        Repeater {
            model: view.controller.subList(view.displaySlot)
            ActionButton {
                id: subButton
                required property var modelData
                required property int index
                property real reveal: view.expanded ? 1 : 0
                objectName: "controlSub-" + modelData.key
                width: subColumn.width; height: 40
                text: modelData.label.toUpperCase(); rowStyle: true
                selected: view.displaySub === modelData.key
                opacity: reveal
                transform: Translate { x: -12 * (1 - subButton.reveal); y: -8 * (1 - subButton.reveal) }
                reducedMotion: view.reducedMotion
                onHoverEntered: view.selectSub(modelData.key)
                onClicked: view.selectSub(modelData.key)
                Behavior on reveal {
                    SequentialAnimation {
                        PauseAnimation { duration: view.expanded && !view.reducedMotion ? 280 + subButton.index * 80 : 0 }
                        NumberAnimation { duration: view.reducedMotion ? 0 : view.expanded ? 380 : 180; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
    Frame {
        id: details
        objectName: "controlDetails"
        x: view.compact ? view.branchX : view.branchX + view.branchWidth + 36
        y: view.compact ? subColumn.y + subColumn.height + 24 : view.branchY
        width: view.detailWidth
        height: Math.min(detailColumn.implicitHeight + 82, Math.max(200, view.availableHeight - y))
        number: view.currentSlot.number; title: view.currentSlot.title
        active: true; reducedMotion: view.reducedMotion
        headerHeight: 32; titleRightPadding: 44
        opacity: view.expansion
        visible: opacity > 0.01; enabled: view.expanded
        transform: Translate { y: -8 * (1 - view.expansion) }
        C.Button {
            id: closeButton
            x: parent.width - 40; y: 8; width: 32; height: 32
            text: "×"; Accessible.name: "Close " + view.currentSlot.title
            hoverEnabled: true
            background: Item {
                Rectangle { width: 1; height: parent.height; color: "#55080808" }
                Rectangle { anchors.bottom: parent.bottom; width: closeButton.hovered || closeButton.activeFocus ? parent.width : 0; height: 3; color: "#080808"; Behavior on width { NumberAnimation { duration: 220 } } }
            }
            contentItem: Text { text: "×"; font.pixelSize: 20; color: closeButton.hovered ? "#e8e8e8" : "#080808"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            onClicked: view.controller.back()
        }
        Flickable {
            id: detailScroll
            x: 16; y: 62; width: parent.width - 32; height: parent.height - 82
            contentWidth: width; contentHeight: detailColumn.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: C.ScrollBar { policy: C.ScrollBar.AsNeeded }
            Column {
                id: detailColumn
                width: detailScroll.width
                spacing: 0
                Text { width: parent.width; text: view.detailTitle; font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 1.5; color: "#a2a2a2"; elide: Text.ElideRight }
                Item { width: 1; height: 8 }
                Rectangle { width: 34; height: 1; color: "#858585" }
                Item { width: 1; height: 14 }
                Row {
                    width: parent.width; spacing: 9
                    Rectangle { y: 5; width: 7; height: 7; radius: 3.5; color: view.detailOn ? "#cc1515" : "#777777" }
                    Text { width: parent.width - 16; text: view.detailStatus; textFormat: Text.PlainText; font.family: "JetBrains Mono"; font.pixelSize: 12; color: "#e8e8e8"; wrapMode: Text.Wrap }
                }
                Item { width: 1; height: 16 }
                Column {
                    id: actionColumn
                    width: parent.width; spacing: 8
                    Repeater {
                        model: actionModel
                        Loader {
                            id: actionLoader
                            required property var entry
                            width: actionColumn.width
                            sourceComponent: entry.key.indexOf("notif:") === 0 ? noticeComponent : actionComponent
                            Component {
                                id: actionComponent
                                ActionButton {
                                    text: actionLoader.entry.label.toUpperCase()
                                    rowStyle: actionLoader.entry.kind === "row"
                                    primary: !!actionLoader.entry.primary
                                    selected: !!actionLoader.entry.selected
                                    metadata: actionLoader.entry.metadata || ""
                                    signalBars: actionLoader.entry.signalBars === undefined ? -1 : actionLoader.entry.signalBars
                                    secured: !!actionLoader.entry.secured
                                    navigationFocus: view.controller.keyboardNavigation && view.controller.action === actionLoader.entry.key
                                    reducedMotion: view.reducedMotion
                                    enabled: actionLoader.entry.key !== "none"
                                    onHoverEntered: { view.controller.keyboardNavigation = false; view.controller.action = actionLoader.entry.key }
                                    onClicked: {
                                        view.controller.action = actionLoader.entry.key
                                        view.controller.dispatchAction(view.displaySlot, view.displaySub, actionLoader.entry.key)
                                    }
                                }
                            }
                            Component {
                                id: noticeComponent
                                NoticeButton {
                                    entry: actionLoader.entry
                                    expanded: view.controller.expandedNotifIdx === entry.notifIdx
                                    navigationFocus: view.controller.keyboardNavigation && view.controller.action === entry.key
                                    reducedMotion: view.reducedMotion
                                    onHoverEntered: { view.controller.keyboardNavigation = false; view.controller.action = entry.key }
                                    onDismissed: view.controller.dismissNotif(entry.notifIdx)
                                    onClicked: {
                                        view.controller.action = entry.key
                                        if (expanded) view.controller.invokeNotif(entry.notifIdx)
                                        else view.controller.expandedNotifIdx = entry.notifIdx
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: view.displaySlot === "right" && view.displaySub === "history" && actionModel.count === 0
                    width: parent.width; height: 64
                    text: "No saved notifications"; font.family: "JetBrains Mono"; font.pixelSize: 12; color: "#a2a2a2"
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                Item { width: 1; height: 8; visible: actionModel.count > 0 }
                ActionButton {
                    width: parent.width; text: "CLEAR HISTORY"
                    visible: view.displaySlot === "right" && view.displaySub === "history"
                    enabled: view.controller.notifications.length > 0
                    reducedMotion: view.reducedMotion
                    onClicked: view.controller.dismissAllNotifs()
                }
                ChannelSlider {
                    width: parent.width
                    visible: view.displaySlot === "bottom" && view.displaySub === "volume"
                    label: "VOLUME"; value: view.controller.audioVolume * 100; muted: view.controller.audioMuted
                    onMoved: value => view.controller.dispatchAction("bottom", "volume", "set-volume:" + Math.round(value))
                    onMuteRequested: view.controller.dispatchAction("bottom", "volume", "mute-toggle")
                }
                ChannelSlider {
                    width: parent.width
                    visible: view.displaySlot === "bottom" && view.displaySub === "brightness"
                    enabled: view.controller.brightnessAvailable
                    label: "BRIGHTNESS"; minimum: 1; value: view.controller.brightnessLevel * 100
                    onMoved: value => view.controller.setBrightnessPercent(value, view.controller.activeMonitor)
                }
                Column {
                    id: passwordColumn
                    width: parent.width; spacing: 8
                    visible: view.displaySlot === "top" && view.displaySub === "wifi" && view.controller.wifiPromptSSID !== ""
                    Item { width: 1; height: 8 }
                    Text { width: parent.width; text: "PASSWORD · " + view.controller.wifiPromptSSID; textFormat: Text.PlainText; font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#e8e8e8"; elide: Text.ElideRight }
                    C.TextField {
                        id: passwordInput
                        width: parent.width; height: 36
                        Accessible.name: "Wi-Fi password"
                        echoMode: TextInput.Password
                        font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#e8e8e8"
                        background: Rectangle { color: "#111111"; border.color: passwordInput.activeFocus ? "#e8e8e8" : "#858585"; border.width: 1 }
                        onTextEdited: view.controller.wifiPasswordInput = text
                        onAccepted: view.controller.dispatchAction("top", "wifi", "submit-password")
                        Keys.onEscapePressed: event => { view.controller.dispatchAction("top", "wifi", "cancel-prompt"); event.accepted = true }
                    }
                    Text { visible: view.controller.wifiError !== ""; width: parent.width; text: view.controller.wifiError; textFormat: Text.PlainText; font.family: "JetBrains Mono"; font.pixelSize: 11; color: "#ef7664"; wrapMode: Text.Wrap }
                    Row {
                        width: parent.width; spacing: 8
                        ActionButton { width: (parent.width - 8) / 2; text: "CONNECT"; primary: true; reducedMotion: view.reducedMotion; onClicked: view.controller.dispatchAction("top", "wifi", "submit-password") }
                        ActionButton { width: (parent.width - 8) / 2; text: "CANCEL"; reducedMotion: view.reducedMotion; onClicked: view.controller.dispatchAction("top", "wifi", "cancel-prompt") }
                    }
                    onVisibleChanged: if (visible && view.visible) passwordFocus.restart()
                    Timer {
                        id: passwordFocus
                        interval: 50
                        onTriggered: {
                            if (!passwordColumn.visible || !view.visible) return
                            passwordInput.clear(); passwordInput.forceActiveFocus()
                            detailScroll.contentY = Math.max(0, detailScroll.contentHeight - detailScroll.height)
                        }
                    }
                    Connections {
                        target: view.controller
                        function onWifiPasswordClearSerialChanged() { passwordInput.clear() }
                        function onWifiPromptSSIDChanged() { if (view.controller.wifiPromptSSID === "") passwordInput.clear() }
                    }
                }
            }
        }
    }
}
