pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../components"
import "../settings"
import "../theme"

Item {
    id: root
    readonly property real sc: Settings.scale
    readonly property int pw: Math.round(width)
    readonly property bool narrow: pw <= s(420)
    readonly property bool compact: pw <= s(560)
    readonly property color lineColor: "#3b312c"
    readonly property color mutedColor: "#a7a29e"
    readonly property color headerRed: "#e4372b"
    readonly property bool reducedMotion: Quickshell.env("TSUGUMORI_REDUCED_MOTION") === "1"
    readonly property color surfaceColor: Settings.playerBackground ? Settings.playerBgColor : "transparent"
    property real availableHeight: s(900)
    function s(px) { return Math.round(px * sc) }

    property string mpTitle: "NO MEDIA"
    property string mpArtist: ""
    property string mpAlbum: ""
    property string mpCoverUrl: ""
    property string mpMediaKey: ""
    property int mpTrackNumber: 0
    property bool mpPlaying: false
    property real mpPosition: 0
    property real mpLength: 0
    property bool localMode: false
    property bool mediaAvailable: false
    property bool canPlayPause: false
    property bool canGoNext: false
    property bool canGoPrevious: false
    property bool canSeek: false
    property var localTracks: []
    property int localTrackIndex: -1
    property bool showTrackList: false
    signal playPause()
    signal nextTrack()
    signal prevTrack()
    signal seekToSecs(real secs)
    signal localTrackSelected(string path)

    readonly property int trackCount: localTracks ? localTracks.length : 0
    readonly property int displayNumber: localMode && localTrackIndex >= 0 ? localTrackIndex + 1 : mpTrackNumber
    readonly property string numberText: mediaAvailable && displayNumber > 0 ? String(displayNumber).padStart(2, "0") : "--"
    readonly property string albumText: mpAlbum.trim() || (mediaAvailable ? localMode ? "LOCAL LIBRARY" : "MPRIS SOURCE" : "NO MEDIA SOURCE")
    property bool requestedVisible: false
    property bool componentReady: false
    property real revealProgress: 0
    readonly property int currentInputX: wipeHost.visible
        ? Math.max(0, Math.min(pw, Math.round(Math.max(wipeHost.x, curtain.width)))) : pw
    readonly property int currentInputWidth: wipeHost.visible ? Math.max(0, pw - currentInputX) : 0
    readonly property bool shown: currentInputWidth > 0
    readonly property int collapsedHeight: Math.ceil(header.height + mainRow.height + progress.height + libraryToggle.height + 2)
    readonly property int drawerNaturalHeight: Math.max(0, Math.min(s(240), availableHeight - collapsedHeight,
        s(14) + (trackCount > 0 ? trackCount * s(58) : s(44))))
    readonly property int currentContentHeight: Math.ceil(collapsedHeight + drawer.height)
    property int maxContentHeight: 0
    implicitWidth: Settings.playerWidth
    implicitHeight: Math.max(currentContentHeight, maxContentHeight)

    function reserveHeight() {
        if (componentReady) maxContentHeight = Math.max(maxContentHeight, collapsedHeight + drawerNaturalHeight)
    }
    onCollapsedHeightChanged: reserveHeight()
    onDrawerNaturalHeightChanged: reserveHeight()
    onCurrentContentHeightChanged: if (componentReady) maxContentHeight = Math.max(maxContentHeight, currentContentHeight)
    onRequestedVisibleChanged: animateVisibility()
    function animateVisibility() {
        if (!componentReady) return
        visibilityAnim.stop()
        var target = requestedVisible ? 1 : 0
        if (requestedVisible) wipeHost.visible = true
        var distance = Math.abs(target - revealProgress)
        if (reducedMotion || distance < 0.001) {
            revealProgress = target; wipeHost.visible = requestedVisible; return
        }
        visibilityAnim.from = revealProgress; visibilityAnim.to = target
        visibilityAnim.duration = Math.max(1, Math.round((requestedVisible ? Settings.revealDuration : Settings.hideDuration) * distance))
        visibilityAnim.start()
    }
    function fmtTime(value) {
        var secs = Number(value)
        if (!Number.isFinite(secs) || secs < 0) secs = 0
        secs = Math.floor(secs)
        var hours = Math.floor(secs / 3600), minutes = Math.floor(secs / 60) % 60
        return (hours ? hours + ":" : "") + String(minutes).padStart(2, "0") + ":" + String(secs % 60).padStart(2, "0")
    }
    function trackName(path) { return String(path).split("/").pop().replace(/\.[^.]+$/, "") }
    function trackKind(path) {
        var match = String(path).match(/\.([^.\/]+)$/)
        return "LOCAL FILE" + (match ? " // " + match[1].toUpperCase() : "")
    }

    Item {
        id: wipeHost
        width: root.pw; height: root.currentContentHeight
        visible: false; clip: true
        x: root.revealProgress < 0.58 ? (root.pw + 2) * (1 - root.revealProgress / 0.58) : 0

        Rectangle {
            anchors.fill: parent
            color: root.surfaceColor; border.width: 1; border.color: "#453a34"
        }
        Column {
            x: 1; y: 1; width: root.pw - 2

            Item {
                id: header
                readonly property int inset: root.s(root.narrow ? 12 : 16)
                readonly property bool wrapSource: brand.implicitWidth + sourceLabel.implicitWidth
                    + 2 * inset + root.s(16) > width
                width: parent.width; height: root.s(wrapSource ? 65 : 40)

                Row {
                    id: brand
                    x: header.inset; y: root.s(10)
                    height: root.s(18); spacing: root.s(root.narrow ? 6 : 11)
                    Rectangle { width: root.s(5); height: root.s(18); color: Theme.a1 }
                    Row {
                        id: wordmark
                        height: parent.height; spacing: root.s(root.narrow ? 5 : 8)
                        Text {
                            id: brandTitle
                            anchors.verticalCenter: parent.verticalCenter
                            text: "TSUGUMORI"; color: "#d8d3cd"
                            font.family: Theme.mono; font.pixelSize: root.s(11)
                            font.letterSpacing: (root.narrow ? 0.3 : 1.5) * root.sc
                        }
                        Text {
                            id: brandDivider
                            anchors.verticalCenter: parent.verticalCenter
                            text: "//"; color: root.headerRed
                            font.family: Theme.mono; font.pixelSize: root.s(11)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, Math.min(implicitWidth, header.width - 2 * header.inset
                                - root.s(5) - brand.spacing - brandTitle.implicitWidth
                                - brandDivider.implicitWidth - 2 * wordmark.spacing))
                            text: "東亜重工製 一七式衛人 白月改 継衛"; color: root.headerRed
                            font.family: "Noto Sans CJK JP"; font.pixelSize: root.s(11)
                            font.letterSpacing: root.narrow ? 0 : 0.66 * root.sc
                            elide: Text.ElideRight; textFormat: Text.PlainText
                        }
                    }
                }
                Row {
                    id: sourceLabel
                    x: header.wrapSource ? header.inset : header.width - header.inset - width
                    y: header.wrapSource ? root.s(39) : Math.round((header.height - height) / 2)
                    spacing: root.s(7)
                    Text {
                        text: "SOURCE"; color: root.mutedColor
                        font.family: Theme.mono; font.pixelSize: root.s(11); font.letterSpacing: 0.8 * root.sc
                    }
                    Text {
                        text: root.mediaAvailable ? root.localMode ? "LOCAL" : "MPRIS" : "NONE"
                        color: Theme.fg; font.family: Theme.mono; font.pixelSize: root.s(11)
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }
            }

            Item {
                id: mainRow
                width: parent.width
                height: root.narrow ? matrixArea.naturalHeight + copyArea.naturalHeight
                    : Math.max(matrixArea.naturalHeight, copyArea.naturalHeight)

                Item {
                    id: matrixArea
                    readonly property int inset: root.s(root.narrow ? 12 : root.compact ? 10 : 8)
                    readonly property real squareSize: Math.max(0, width - 2 * inset)
                    readonly property real naturalHeight: squareSize + 2 * inset
                    width: root.narrow ? parent.width : Math.max(root.s(150), Math.round(parent.width * 0.30))
                    height: root.narrow ? naturalHeight : mainRow.height

                    Item {
                        anchors.centerIn: parent
                        width: matrixArea.squareSize; height: width
                        PlayerGlyph {
                            anchors.fill: parent
                            artworkUrl: root.mpCoverUrl; mediaKey: root.mpMediaKey
                            trackTitle: root.mpTitle; trackArtist: root.mpArtist
                            mediaAvailable: root.mediaAvailable; active: root.shown
                            reducedMotion: root.reducedMotion
                        }
                        Rectangle { anchors.top: parent.top; anchors.right: parent.right; width: root.s(15); height: 1; color: "#7d6b5e" }
                        Rectangle { anchors.top: parent.top; anchors.right: parent.right; width: 1; height: root.s(15); color: "#7d6b5e" }
                        Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; width: root.s(15); height: 1; color: "#7d6b5e" }
                        Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; width: 1; height: root.s(15); color: "#7d6b5e" }
                    }
                    Rectangle {
                        x: root.narrow ? 0 : parent.width - 1
                        y: root.narrow ? parent.height - 1 : 0
                        width: root.narrow ? parent.width : 1
                        height: root.narrow ? 1 : parent.height
                        color: root.lineColor
                    }
                }

                Item {
                    id: copyArea
                    readonly property int horizontalInset: root.s(root.narrow ? 16 : root.compact ? 12 : 18)
                    readonly property int verticalInset: root.s(root.compact ? 12 : 14)
                    readonly property real naturalHeight: details.implicitHeight + 2 * verticalInset
                    readonly property int gridStep: Math.max(1, root.s(24))
                    x: root.narrow ? 0 : matrixArea.width
                    y: root.narrow ? matrixArea.height : 0
                    width: root.narrow ? parent.width : parent.width - matrixArea.width
                    height: root.narrow ? naturalHeight : mainRow.height
                    clip: true

                    // The approved design keeps a faint grid only behind the metadata.
                    Repeater {
                        model: Math.ceil(copyArea.width / copyArea.gridStep)
                        Rectangle {
                            required property int index
                            x: index * copyArea.gridStep
                            width: 1; height: copyArea.height
                            color: Theme.a1; opacity: 0.035
                        }
                    }
                    Repeater {
                        model: Math.ceil(copyArea.height / copyArea.gridStep)
                        Rectangle {
                            required property int index
                            y: index * copyArea.gridStep
                            width: copyArea.width; height: 1
                            color: Theme.a1; opacity: 0.035
                        }
                    }
                    Column {
                        id: details
                        x: copyArea.horizontalInset; y: copyArea.verticalInset
                        width: parent.width - 2 * copyArea.horizontalInset

                        Item {
                            width: parent.width; height: root.s(17)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.numberText + " //"; color: "#d76151"
                                font.family: Theme.mono; font.pixelSize: root.s(11); font.letterSpacing: root.sc
                            }
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                spacing: root.s(7)
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(4); height: width
                                    color: root.mpPlaying ? Theme.a1 : "#77655a"
                                }
                                Text {
                                    text: !root.mediaAvailable ? "IDLE" : root.mpPlaying ? "PLAYING" : "PAUSED"
                                    color: root.mutedColor; font.family: Theme.mono
                                    font.pixelSize: root.s(11); font.letterSpacing: root.sc
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: song.implicitHeight + root.s(root.compact ? 20 : 22)
                            Column {
                                id: song
                                width: parent.width; y: root.s(root.compact ? 10 : 12)
                                spacing: root.s(6)
                                Text {
                                    width: parent.width; text: root.mpTitle; textFormat: Text.PlainText
                                    color: Theme.fg; font.family: Theme.mono
                                    font.pixelSize: root.s(root.compact ? 26 : 30); font.weight: Font.Medium
                                    font.letterSpacing: -root.sc
                                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: root.mpArtist || (root.mediaAvailable ? "UNKNOWN ARTIST" : "")
                                    textFormat: Text.PlainText; elide: Text.ElideRight
                                    font.family: Theme.mono; font.pixelSize: root.s(13); color: "#b8b2ac"
                                }
                            }
                        }

                        Item {
                            width: parent.width; height: albumRow.implicitHeight + root.s(9)
                            Rectangle { width: parent.width; height: 1; color: "#342b26" }
                            RowLayout {
                                id: albumRow
                                y: root.s(8); width: parent.width; spacing: root.s(10)
                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    text: "ALBUM"; color: "#8f847c"
                                    font.family: Theme.mono; font.pixelSize: root.s(11); font.letterSpacing: 1.5 * root.sc
                                }
                                Text {
                                    Layout.fillWidth: true; Layout.minimumWidth: 0
                                    text: root.albumText; textFormat: Text.PlainText
                                    color: "#b8b2ac"; font.family: Theme.mono; font.pixelSize: root.s(11)
                                    font.letterSpacing: 0.5 * root.sc
                                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                }
                            }
                        }
                        Item { width: 1; height: root.s(12) }
                        RowLayout {
                            width: parent.width; spacing: root.s(root.compact ? 6 : 9)
                            PlayerTransportButton {
                                text: "PREV"; glyph: "\uf048"
                                enabled: root.mediaAvailable && root.canGoPrevious
                                uiScale: root.sc; reducedMotion: root.reducedMotion; stacked: root.pw <= root.s(520)
                                Layout.fillWidth: true; Layout.preferredWidth: root.s(100); Layout.minimumWidth: 0
                                onClicked: root.prevTrack()
                            }
                            PlayerTransportButton {
                                text: root.mpPlaying ? "PAUSE" : "PLAY"; glyph: root.mpPlaying ? "\uf04c" : "\uf04b"
                                enabled: root.mediaAvailable && root.canPlayPause; primary: true
                                uiScale: root.sc; reducedMotion: root.reducedMotion; stacked: root.pw <= root.s(520)
                                Layout.fillWidth: true; Layout.preferredWidth: root.s(160); Layout.minimumWidth: 0
                                onClicked: root.playPause()
                            }
                            PlayerTransportButton {
                                text: "NEXT"; glyph: "\uf051"
                                enabled: root.mediaAvailable && root.canGoNext
                                uiScale: root.sc; reducedMotion: root.reducedMotion; stacked: root.pw <= root.s(520)
                                Layout.fillWidth: true; Layout.preferredWidth: root.s(100); Layout.minimumWidth: 0
                                onClicked: root.nextTrack()
                            }
                        }
                    }
                }
            }

            Item {
                id: progress
                width: parent.width; height: seek.y + seek.height + root.s(8)
                Rectangle { width: parent.width; height: 1; color: root.lineColor }
                Item {
                    id: timeRow
                    x: root.s(16); y: root.s(8); width: parent.width - root.s(32); height: root.s(20)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fmtTime(seek.pressed && seek.scrubMediaKey === root.mpMediaKey ? seek.scrubTarget : root.mpPosition)
                        font.family: Theme.mono; font.pixelSize: root.s(18); color: Theme.fg
                        font.letterSpacing: -0.5 * root.sc
                    }
                    Text {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: "TOTAL // " + (root.mpLength > 0 ? root.fmtTime(root.mpLength) : "--:--")
                        font.family: Theme.mono; font.pixelSize: root.s(11); color: root.mutedColor
                    }
                }
                Item {
                    id: ruler
                    x: root.s(16); y: timeRow.y + timeRow.height + root.s(4)
                    width: parent.width - root.s(32); height: root.s(6)
                    Repeater {
                        model: 21
                        Rectangle {
                            required property int index
                            x: index * (ruler.width - width) / 20; width: 1
                            height: root.s(index % 5 === 0 ? 6 : 3); anchors.bottom: parent.bottom
                            color: index % 5 === 0 ? "#85715f" : "#514239"
                        }
                    }
                }
                Slider {
                    id: seek
                    x: root.s(16); y: ruler.y + ruler.height
                    width: parent.width - root.s(32); height: root.s(25); padding: 0
                    from: 0; to: Number.isFinite(root.mpLength) && root.mpLength > 0 ? root.mpLength : 1
                    enabled: root.mediaAvailable && root.canSeek && root.mpLength > 0
                    focusPolicy: Qt.StrongFocus
                    Accessible.name: "Seek track"
                    property real scrubTarget: 0
                    property string scrubMediaKey: ""
                    onPressedChanged: {
                        if (pressed) { scrubMediaKey = root.mpMediaKey; scrubTarget = value }
                        else if (enabled && scrubMediaKey === root.mpMediaKey) root.seekToSecs(scrubTarget)
                    }
                    onMoved: { if (pressed) scrubTarget = value; else if (enabled) root.seekToSecs(value) }
                    Binding {
                        target: seek; property: "value"; when: !seek.pressed
                        value: Number.isFinite(root.mpPosition) ? Math.max(0, Math.min(seek.to, root.mpPosition)) : 0
                        restoreMode: Binding.RestoreNone
                    }
                    background: Rectangle {
                        x: 0; y: (seek.height - height) / 2
                        width: seek.width; height: root.s(2); color: "#483b34"
                        Rectangle { width: parent.width * seek.position; height: parent.height; color: Theme.a1 }
                    }
                    handle: Rectangle {
                        x: seek.visualPosition * (seek.width - width); y: (seek.height - height) / 2
                        width: root.s(5); height: root.s(15); color: seek.enabled ? Theme.fg : "#665b55"
                        border.width: seek.activeFocus ? 1 : 0; border.color: Theme.a1
                    }
                }
            }

            Button {
                id: libraryToggle
                width: parent.width; implicitHeight: root.s(40)
                leftPadding: root.s(16); rightPadding: root.s(16)
                topPadding: root.s(8); bottomPadding: root.s(8)
                text: (root.showTrackList ? "CLOSE TRACKS // " : "LOCAL TRACKS // ") + String(root.trackCount).padStart(2, "0")
                focusPolicy: Qt.StrongFocus
                Accessible.name: text
                readonly property bool interactionActive: hovered || down || activeFocus
                property real underlineProgress: interactionActive ? 1 : 0
                Behavior on underlineProgress {
                    NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                onClicked: root.showTrackList = !root.showTrackList

                background: Item {
                    Rectangle { width: parent.width; height: 1; color: root.lineColor }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width * libraryToggle.underlineProgress; height: root.s(2); color: Theme.a1
                    }
                }
                contentItem: RowLayout {
                    spacing: root.s(12)
                    Text {
                        Layout.fillWidth: true
                        text: libraryToggle.text; color: libraryToggle.interactionActive ? Theme.a1 : "#bab1a8"
                        font.family: Theme.mono; font.pixelSize: root.s(11); font.letterSpacing: 1.1 * root.sc
                        elide: Text.ElideRight
                    }
                    Text {
                        text: root.showTrackList ? "−" : "+"; color: Theme.fg
                        font.family: Theme.mono; font.pixelSize: root.s(19)
                    }
                }
            }

            Item {
                id: drawer
                width: parent.width; height: root.showTrackList ? root.drawerNaturalHeight : 0
                clip: true; visible: height > 0
                Behavior on height { NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic } }
                Rectangle { width: parent.width; height: 1; color: root.lineColor }
                ListView {
                    id: trackList
                    x: root.s(7); y: root.s(7); width: parent.width - root.s(14)
                    height: Math.max(0, parent.height - root.s(14)); clip: true
                    model: root.localTracks; boundsBehavior: Flickable.StopAtBounds; reuseItems: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: PlayerTrackRow {
                        required property string modelData
                        required property int index
                        width: trackList.width; number: index + 1
                        selected: root.localMode && index === root.localTrackIndex
                        trackTitle: selected ? root.mpTitle : root.trackName(modelData)
                        subtitle: selected && root.mpArtist && root.mpArtist !== "LOCAL FILE" ? root.mpArtist : root.trackKind(modelData)
                        durationText: selected && root.mpLength > 0 ? root.fmtTime(root.mpLength) : ""
                        uiScale: root.sc; reducedMotion: root.reducedMotion
                        onClicked: root.localTrackSelected(modelData)
                    }
                    Text {
                        anchors.centerIn: parent; visible: root.trackCount === 0
                        text: "NO LOCAL TRACKS FOUND"; color: root.mutedColor
                        font.family: Theme.mono; font.pixelSize: root.s(11)
                    }
                }
            }
        }
        Rectangle { x: 0; y: 0; width: root.s(11); height: 1; color: Theme.a1 }
        Rectangle { x: 0; y: 0; width: 1; height: root.s(11); color: Theme.a1 }
        Rectangle { x: parent.width - width; y: parent.height - 1; width: root.s(11); height: 1; color: Theme.a1 }
        Rectangle { x: parent.width - 1; y: parent.height - height; width: 1; height: root.s(11); color: Theme.a1 }
        Rectangle {
            id: curtain
            anchors.top: parent.top; anchors.bottom: parent.bottom
            x: 0; z: 10; color: Settings.curtainColor
            width: root.revealProgress <= 0.58 ? root.pw : root.pw * (1 - (root.revealProgress - 0.58) / 0.42)
        }
    }
    NumberAnimation {
        id: visibilityAnim; target: root; property: "revealProgress"; easing.type: Easing.InOutCubic
        onFinished: { root.revealProgress = root.requestedVisible ? 1 : 0; wipeHost.visible = root.requestedVisible }
    }
    Component.onCompleted: { componentReady = true; reserveHeight(); animateVisibility() }
}
