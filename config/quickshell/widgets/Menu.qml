import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "../theme"

Item {
    id: root

    readonly property int lw: 980
    readonly property int lh: 600
    property real screenW: 1920
    property real screenH: 1080

    property bool   menuOpen:        false
    property bool   wipeHideRunning: false  // stays true during the closing animation
    property string currentCat: "all"
    property string searchQuery: ""
    property int    focusIdx:   -1
    property string clockStr:   "--:--:--"

    implicitWidth:  screenW
    implicitHeight: screenH

    // Palette.
    readonly property color paper:    Qt.rgba(10/255, 10/255, 10/255, 0.88)
    readonly property color ink:       "#cc1515"
    readonly property color inkStrong: "#e8e8e8"
    readonly property color inkSoft:   "#909090"
    readonly property color lineSoft:  Qt.rgba(204/255,21/255,21/255,0.15)
    readonly property color lineVsoft: Qt.rgba(204/255,21/255,21/255,0.08)
    readonly property color accent:    "#9e1010"

    // Keep the app-list typography local to this widget.
    FontLoader {
        id: menuRegularFont
        source: Qt.resolvedUrl("../assets/fonts/ibm-plex-mono/IBMPlexMono-Regular.ttf")
    }
    FontLoader {
        id: menuMediumFont
        source: Qt.resolvedUrl("../assets/fonts/ibm-plex-mono/IBMPlexMono-Medium.ttf")
    }
    readonly property string listFont: menuRegularFont.status === FontLoader.Ready
                                       ? menuRegularFont.name : Theme.mono
    readonly property string listNameFont: menuMediumFont.status === FontLoader.Ready
                                           ? menuMediumFont.name : root.listFont

    // Apps
    property var  apps: []
    property bool appsLoaded: false

    readonly property var catLabels: ({
        "all":"ALL","dev":"DEVELOP","sys":"SYSTEM","net":"NETWORK",
        "media":"MEDIA","office":"OFFICE","graphics":"GRAPHICS",
        "games":"GAMES","other":"OTHER"
    })

    readonly property var catOrder: ["all","dev","sys","net","media","office","graphics","games","other"]

    readonly property var catKeys: {
        var present = {"all": true}
        for (var i = 0; i < apps.length; i++) present[apps[i].cat] = true
        return catOrder.filter(function(k) { return present[k] })
    }

    readonly property var filteredApps: {
        var q = searchQuery.toLowerCase().trim()
        return apps.filter(function(a) {
            var catOk = currentCat === "all" || a.cat === currentCat
            var qOk = !q || a.name.toLowerCase().indexOf(q) >= 0 || a.meta.toLowerCase().indexOf(q) >= 0
            return catOk && qOk
        })
    }

    // ── Read .desktop entries ──
    Process {
        id: desktopReader
        command: ["bash", Qt.resolvedUrl("../list-apps.sh").toString().replace("file://","")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var result = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (!line) continue
                    var parts = line.split("|")
                    if (parts.length < 2) continue
                    var name      = parts[0].trim()
                    var desktopId = parts[1].trim()
                    var cats      = parts[2] || ""
                    var rawExec   = (parts[3] || "").replace(/%[A-Za-z]/g,"").trim()
                    if (!name || !desktopId) continue
                    // Use the raw exec when available; otherwise use the desktop ID.
                    var launchCmd = rawExec || desktopId

                    var cat = "other"
                    if (/Development|IDE|TextEditor|Debugger/i.test(cats))          cat = "dev"
                    else if (/WebBrowser|Email|Chat|Network|FileTransfer/i.test(cats)) cat = "net"
                    else if (/Audio|Video|Player|Music/i.test(cats))                cat = "media"
                    else if (/Office|Spreadsheet|WordProcessor|Presentation/i.test(cats)) cat = "office"
                    else if (/Graphics|Photography|2DGraphics/i.test(cats))         cat = "graphics"
                    else if (/Game|Emulator/i.test(cats))                           cat = "games"
                    else if (/System|Utility|Monitor|Settings/i.test(cats))         cat = "sys"

                    var nl = name.toLowerCase()
                    var ico = "·"
                    if (/terminal|kitty|alacritty|console/.test(nl)) ico = "▸"
                    else if (/firefox|chromium|browser/.test(nl))     ico = "○"
                    else if (/nvim|vim|editor|code|helix/.test(nl))   ico = "⌥"
                    else if (/file|yazi|ranger/.test(nl))             ico = "▤"
                    else if (/btop|htop|monitor/.test(nl))            ico = "▲"
                    else if (/music|audio|pulse/.test(nl))            ico = "♪"
                    else if (/video|mpv|vlc/.test(nl))                ico = "▶"
                    else if (/lock|hyprlock/.test(nl))                ico = "⬡"
                    else if (/libre|office|calc|writer/.test(nl))     ico = "≡"
                    else if (/gimp|inkscape|image/.test(nl))          ico = "⬜"
                    else if (cat === "dev")      ico = "⌥"
                    else if (cat === "net")      ico = "○"
                    else if (cat === "media")    ico = "▶"
                    else if (cat === "sys")      ico = "◈"
                    else if (cat === "office")   ico = "≡"

                    result.push({
                        id:        String(i+1).padStart(2,"0"),
                        name:      name,
                        cat:       cat,
                        meta:      desktopId,
                        desktopId: launchCmd,
                        cmd:       launchCmd,
                        icon:      ico
                    })
                }
                root.apps = result
                root.appsLoaded = true
            }
        }
    }

    // One Process — use sh -c for the complete command.
    Process {
        id: launchProc
        property string pending: ""
        command: ["sh", "-c", pending]
        running: false
    }

    function launchApp(cmd) {
        if (!cmd) return
        // nohup plus redirection avoids EPIPE for Electron apps (Discord, etc.).
        launchProc.pending = "nohup " + cmd + " > /dev/null 2>&1 &"
        launchProc.running = true
        root.closeMenu()
    }

    // Launch a direct command (footer).
    function launch(cmd) {
        if (!cmd || cmd === "") return
        launchProc.pending = "nohup " + cmd + " > /dev/null 2>&1 &"
        launchProc.running = true
        root.closeMenu()
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            var d = new Date()
            root.clockStr = String(d.getHours()).padStart(2,"0") + ":"
                + String(d.getMinutes()).padStart(2,"0") + ":"
                + String(d.getSeconds()).padStart(2,"0")
        }
    }

    Timer {
        id: focusTimer; interval: 50; repeat: true; running: false
        property int attempts: 0
        onTriggered: {
            searchInput.forceActiveFocus()
            attempts++
            if (attempts >= 8) { running = false; attempts = 0 }
        }
    }

    Component.onCompleted: {
        var d = new Date()
        clockStr = String(d.getHours()).padStart(2,"0") + ":"
            + String(d.getMinutes()).padStart(2,"0") + ":"
            + String(d.getSeconds()).padStart(2,"0")
        desktopReader.running = true
    }

    // ── Overlay ──
    Rectangle {
        anchors.fill: parent
        color: root.menuOpen ? Qt.rgba(10/255,10/255,10/255,0.75) : "transparent"
        visible: true
        Behavior on color { ColorAnimation { duration: 260 } }
        MouseArea {
            anchors.fill: parent
            enabled: root.menuOpen
            onClicked: root.closeMenu()
        }
    }

    // ── Panel host (clip + wipe) ──
    Item {
        id: panelHost
        property real closeOffset: 0
        x: (root.screenW - root.lw) / 2
        y: (root.screenH - root.lh) / 2
        width:  root.lw
        height: root.lh
        clip:   true
        visible: root.menuOpen || wipeReveal.running || wipeHide.running

        // Content.
        Rectangle {
            id:     panelContent
            anchors.fill: parent
            transform: Translate { x: panelHost.closeOffset }
            color:  root.paper
            border.color: root.ink; border.width: 1

            // Fine grid.
            Repeater {
                model: Math.floor(root.lw/20)+1
                Rectangle { x:index*20; y:0; width:1; height:root.lh; color:root.lineVsoft }
            }
            Repeater {
                model: Math.floor(root.lh/20)+1
                Rectangle { x:0; y:index*20; width:root.lw; height:1; color:root.lineVsoft }
            }

            // Click anywhere to focus search.
            MouseArea {
                anchors.fill: parent; z: -1
                onClicked: searchInput.forceActiveFocus()
                propagateComposedEvents: true
            }

            // Scan line
            Rectangle {
                id: scanLine; x:0; width:root.lw; height:2; z:20; opacity:0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position:0.0; color:"transparent" }
                    GradientStop { position:0.5; color:root.accent }
                    GradientStop { position:1.0; color:"transparent" }
                }
                NumberAnimation on y {
                    id: scanAnim; from:0; to:root.lh; duration:700; running:false
                    easing.type: Easing.Linear
                    onStarted:  scanLine.opacity = 1
                    onFinished: scanLine.opacity = 0
                }
            }

            // ── HEADER ──
            Item {
                id: header
                width: parent.width
                height: 52

                Row {
                    anchors { left:parent.left; leftMargin:24; verticalCenter:parent.verticalCenter }
                    spacing: 14

                    Item {
                        width: systemLabel.implicitWidth + 24
                        height: 28
                        Text {
                            id: systemLabel
                            anchors.centerIn: parent
                            text: "SYSTEM"
                            font.family: Theme.mono
                            font.pixelSize: 12
                            font.letterSpacing: 3
                            font.weight: Font.Medium
                            color: root.inkStrong
                        }
                        Rectangle { x:0; y:0; width:7; height:1; color:root.ink }
                        Rectangle { x:0; y:0; width:1; height:7; color:root.ink }
                        Rectangle { x:parent.width-7; y:parent.height-1; width:7; height:1; color:root.ink }
                        Rectangle { x:parent.width-1; y:parent.height-7; width:1; height:7; color:root.ink }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "//"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: root.ink
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "システム"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.letterSpacing: 2
                        color: "#aaa5a0"
                    }
                }

                Row {
                    anchors { right:parent.right; rightMargin:24; verticalCenter:parent.verticalCenter }
                    spacing: 18

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SID0NIA"
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                        color: root.ink
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: 14
                        color: Qt.alpha(root.ink, 0.4)
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.appsLoaded ? String(root.apps.length).padStart(2, "0") : "--"
                            font.family: Theme.mono
                            font.pixelSize: 11
                            color: root.inkStrong
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "APPS"
                            font.family: Theme.mono
                            font.pixelSize: 9
                            font.letterSpacing: 1.5
                            color: root.inkSoft
                        }
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: 14
                        color: Qt.alpha(root.ink, 0.4)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.clockStr
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        color: "#b0aba6"
                    }
                }
                Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:1; color:root.lineSoft }
            }

            // ── BODY ──
            Item {
                id: body
                anchors { top:header.bottom; bottom:footer.top }
                width: parent.width

                // Sidebar
                Item {
                    id:sidebar; width:160; height:parent.height
                    Rectangle { anchors.right:parent.right; width:1; height:parent.height; color:root.lineSoft }
                    Column {
                        anchors { top:parent.top; topMargin:16 }
                        width:parent.width

                        Repeater {
                            model: root.catKeys
                            delegate: Item {
                                width:160; height:34
                                property bool isActive: root.currentCat === modelData

                                Rectangle {
                                    anchors.fill:parent
                                    color: parent.isActive ? root.ink : (catMA.containsMouse ? Qt.rgba(232/255,232/255,232/255,0.05) : "transparent")
                                    Behavior on color { ColorAnimation { duration:150 } }
                                }
                                Row {
                                    anchors { left:parent.left; leftMargin:22; verticalCenter:parent.verticalCenter }
                                    spacing:8
                                    Rectangle {
                                        anchors.verticalCenter:parent.verticalCenter
                                        width: catMA.containsMouse || parent.parent.isActive ? 10 : 4; height:1
                                        color: parent.parent.isActive ? root.paper : root.inkSoft
                                        Behavior on width { NumberAnimation { duration:200; easing.type:Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration:150 } }
                                    }
                                    Text {
                                        anchors.verticalCenter:parent.verticalCenter
                                        text: root.catLabels[modelData] || modelData.toUpperCase()
                                        font.pixelSize:10; font.letterSpacing:2
                                        color: parent.parent.isActive ? root.paper : (catMA.containsMouse ? root.inkStrong : root.inkSoft)
                                        Behavior on color { ColorAnimation { duration:150 } }
                                    }
                                }
                                Text {
                                    anchors { right:parent.right; rightMargin:12; verticalCenter:parent.verticalCenter }
                                    text: root.apps.filter(function(a){ return modelData==="all"||a.cat===modelData }).length.toString().padStart(2,"0")
                                    font.pixelSize:9; font.letterSpacing:1
                                    color: parent.isActive ? Qt.rgba(204/255,21/255,21/255,0.20) : Qt.rgba(204/255,21/255,21/255,0.12)
                                }
                                MouseArea { id:catMA; anchors.fill:parent; hoverEnabled:true
                                    onClicked: { root.currentCat=modelData; root.focusIdx=-1; searchInput.forceActiveFocus() } }
                            }
                        }

                        Item {
                            width:160; height:48
                            Column {
                                anchors { left:parent.left; leftMargin:22; bottom:parent.bottom; bottomMargin:6 }
                                spacing:4
                                Text {
                                    text: root.filteredApps.length + "/" + root.apps.length + " NODES"
                                    font.family: root.listNameFont
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    font.letterSpacing: 1
                                    font.hintingPreference: Font.PreferFullHinting
                                    renderType: Text.NativeRendering
                                    color: root.inkSoft
                                }
                                Rectangle {
                                    width:72; height:2; color:root.lineSoft
                                    Rectangle {
                                        height:parent.height; color:root.accent
                                        SequentialAnimation on x { running:root.menuOpen; loops:Animation.Infinite
                                            NumberAnimation { from:0; to:44; duration:1400; easing.type:Easing.InOutSine }
                                            NumberAnimation { from:44; to:0; duration:1400; easing.type:Easing.InOutSine } }
                                        SequentialAnimation on width { running:root.menuOpen; loops:Animation.Infinite
                                            NumberAnimation { from:10; to:28; duration:1400; easing.type:Easing.InOutSine }
                                            NumberAnimation { from:28; to:10; duration:1400; easing.type:Easing.InOutSine } }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right panel
                Item {
                    anchors { left:sidebar.right; right:parent.right; top:parent.top; bottom:parent.bottom }
                    Column {
                        anchors.fill:parent

                        // Search
                        Item {
                            width:parent.width; height:46
                            Rectangle {
                                anchors { fill:parent; leftMargin:14; rightMargin:14; topMargin:7; bottomMargin:7 }
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.alpha(root.ink, 0.42)
                                Rectangle {
                                    anchors { left:parent.left; top:parent.top; bottom:parent.bottom }
                                    width: 3
                                    color: root.ink
                                }
                            }
                            Row {
                                anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                                          leftMargin:24; rightMargin:24 }
                                spacing:10
                                Text { anchors.verticalCenter:parent.verticalCenter; text:"▸"; font.family:root.listFont; font.pixelSize:13; color:root.ink }
                                FocusScope {
                                    id:searchScope; width:parent.width-60; height:30
                                    anchors.verticalCenter:parent.verticalCenter
                                    focus: root.menuOpen

                                    TextInput {
                                        id:           searchInput
                                        anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family:root.listFont
                                        font.pixelSize:15; font.weight:Font.Normal
                                        color:        root.inkStrong
                                        cursorVisible:activeFocus
                                        focus:        true
                                        selectByMouse:true
                                        text:         root.searchQuery

                                        onTextEdited: { root.searchQuery=text; root.focusIdx=0 }

                                        Keys.onEscapePressed: root.closeMenu()
                                        Keys.onUpPressed: {
                                            root.focusIdx=Math.max(0,root.focusIdx-1)
                                            appList.positionViewAtIndex(root.focusIdx, ListView.Contain)
                                        }
                                        Keys.onDownPressed: {
                                            root.focusIdx=Math.min(root.filteredApps.length-1,root.focusIdx+1)
                                            appList.positionViewAtIndex(root.focusIdx, ListView.Contain)
                                        }
                                        Keys.onReturnPressed: {
                                            var a=root.filteredApps[root.focusIdx]
                                            if(a) root.launchApp(a.desktopId)
                                        }

                                        Text {
                                            visible:parent.text===""
                                            anchors.verticalCenter:parent.verticalCenter
                                            text:"Search application…"
                                            font:searchInput.font
                                            color:"#99928d"
                                        }
                                    }
                                }
                            }
                            Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:1; color:root.lineSoft }
                        }

                        // List
                        ListView {
                            id:appList; width:parent.width; height:parent.parent.height-46
                            clip:true; model:root.filteredApps; keyNavigationEnabled:false

                            HoverHandler {
                                parent: appList
                                // Watch the viewport, not individual rows or the scrolling content.
                                onHoveredChanged: {
                                    if (!hovered) root.focusIdx = -1
                                }
                            }

                            delegate: Item {
                                id:appDelegate; width:appList.width; height:46
                                property bool isFocused: index===root.focusIdx

                                Rectangle {
                                    anchors.fill:parent; color:root.ink
                                    opacity: appDelegate.isFocused ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration:120 } }
                                }
                                Rectangle {
                                    anchors { fill:parent; leftMargin:6; rightMargin:6; topMargin:5; bottomMargin:5 }
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(10/255,10/255,10/255,0.38)
                                    opacity: appDelegate.isFocused ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration:120 } }
                                }

                                Item {
                                    id: appRow
                                    readonly property bool highlighted: appDelegate.isFocused
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: appRow.highlighted ? 32 : 24
                                        rightMargin: 24
                                    }
                                    height: parent.height

                                    Behavior on anchors.leftMargin {
                                        NumberAnimation {
                                            duration: 180
                                            easing.type: Easing.OutQuart
                                        }
                                    }

                                    Text {
                                        id: appId
                                        anchors {
                                            left: parent.left
                                            verticalCenter: parent.verticalCenter
                                        }
                                        width: 22
                                        text: modelData.id
                                        font.family: root.listFont
                                        font.pixelSize: 11
                                        font.letterSpacing: 0.4
                                        color: appRow.highlighted
                                               ? "#0a0a0a" : "#b1a8a2"
                                        Behavior on color { ColorAnimation { duration:120 } }
                                    }

                                    Item {
                                        id: appIcon
                                        property color ink: appRow.highlighted ? "#0a0a0a" : root.ink
                                        anchors {
                                            left: appId.right
                                            leftMargin: 14
                                            verticalCenter: parent.verticalCenter
                                        }
                                        width: 28
                                        height: 28
                                        Behavior on ink { ColorAnimation { duration:120 } }

                                        Rectangle { x:0; y:0; width:7; height:1; color:appIcon.ink }
                                        Rectangle { x:0; y:0; width:1; height:7; color:appIcon.ink }
                                        Rectangle { x:parent.width-7; y:parent.height-1; width:7; height:1; color:appIcon.ink }
                                        Rectangle { x:parent.width-1; y:parent.height-7; width:1; height:7; color:appIcon.ink }

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.icon
                                            font.family: root.listFont
                                            font.pixelSize: 16
                                            color: appIcon.ink
                                        }
                                    }

                                    Row {
                                        id: appRightInfo
                                        anchors {
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                        }
                                        spacing: 14

                                        Text {
                                            // Stable per app, including while filtering the list.
                                            readonly property int labelVariant: (parseInt(modelData.id, 10) || 0) % 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: [-1, -4, 2, 5, -2, 3, -5, 1, 0][labelVariant]
                                            rightPadding: [0, 30, 9, 44, 18, 4, 36, 13, 24][labelVariant]
                                            text: (root.catLabels[modelData.cat] || modelData.cat).toUpperCase()
                                            font.pixelSize: 9
                                            font.letterSpacing: [2.1, 1.1, 2.7, 1.5, 3.1, 1.8, 2.4, 1.3, 2.9][labelVariant]
                                            color: appRow.highlighted
                                                   ? Qt.rgba(10/255,10/255,10/255,0.65)
                                                   : root.inkSoft
                                            Behavior on color { ColorAnimation { duration:120 } }
                                        }

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 6
                                            height: width
                                            rotation: 45
                                            color: "#0a0a0a"
                                            opacity: appRow.highlighted ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration:120 } }
                                        }
                                    }

                                    Text {
                                        anchors {
                                            left: appIcon.right
                                            right: appRightInfo.left
                                            leftMargin: 14
                                            rightMargin: 20
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: modelData.name
                                        elide: Text.ElideRight
                                        font.family: root.listNameFont
                                        font.pixelSize: 14
                                        font.letterSpacing: -0.25
                                        font.weight: Font.Medium
                                        color: appRow.highlighted
                                               ? "#0a0a0a" : root.ink
                                        Behavior on color { ColorAnimation { duration:120 } }
                                    }
                                }

                                MouseArea {
                                    id:appMA; anchors.fill:parent; hoverEnabled:true
                                    onEntered: root.focusIdx=index
                                    onClicked: root.launchApp(modelData.desktopId)
                                }
                            }

                            Item {
                                visible: root.filteredApps.length===0 && root.appsLoaded
                                width:appList.width; height:60
                                Text { anchors.centerIn:parent; text:"▸ NO RESULTS"; font.pixelSize:10; font.letterSpacing:3; color:root.inkSoft; opacity:0.5 }
                            }
                        }
                    }
                }
            }

            // ── FOOTER ──
            Item {
                id: footer
                anchors.bottom: parent.bottom
                width: parent.width
                height: 44
                readonly property bool reducedMotion: Quickshell.env("TSUGUMORI_REDUCED_MOTION") === "1"
                Keys.onEscapePressed: root.closeMenu()
                Rectangle { anchors.top:parent.top; width:parent.width; height:1; color:root.lineSoft }

                Row {
                    id: launchActions
                    anchors { left:parent.left; leftMargin:24; verticalCenter:parent.verticalCenter }
                    spacing: 8
                    MenuFooterButton {
                        text: "TERMINAL"
                        reducedMotion: footer.reducedMotion
                        onClicked: root.launch("kitty")
                    }
                    MenuFooterButton {
                        text: "FILES"
                        reducedMotion: footer.reducedMotion
                        onClicked: root.launch("kitty -e yazi")
                    }
                }

                Row {
                    id: sessionActions
                    anchors { right:parent.right; rightMargin:24; verticalCenter:parent.verticalCenter }
                    spacing: 8
                    MenuFooterButton {
                        text: "LOCK"
                        reducedMotion: footer.reducedMotion
                        onClicked: root.launch("${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/lock.sh")
                    }
                    MenuFooterButton {
                        text: "SHUTDOWN"
                        reducedMotion: footer.reducedMotion
                        onClicked: root.launch("systemctl poweroff")
                    }
                    MenuFooterButton {
                        text: "RESTART"
                        reducedMotion: footer.reducedMotion
                        onClicked: root.launch("systemctl reboot")
                    }
                }
            }
        }

        // Wipe curtain — sibling of the content.
        CurtainSurface {
            id:wipeCurtain
            anchors{top:parent.top;bottom:parent.bottom}
            transform: Translate { x: panelHost.closeOffset }
            z:50; width:2; x:root.lw-2
        }
    }

    // ── ANIMATIONS WIPE ──
    SequentialAnimation {
        id: wipeReveal
        onStarted: {
            panelHost.visible = true
            panelHost.closeOffset = 0
            panelHost.x       = (root.screenW - root.lw) / 2 + root.lw + 2
            wipeCurtain.x     = 0
            wipeCurtain.width = root.lw
        }
        NumberAnimation {
            target:panelHost; property:"x"
            from:(root.screenW-root.lw)/2+root.lw+2; to:(root.screenW-root.lw)/2
            duration:440; easing.type:Easing.OutExpo
        }
        ParallelAnimation {
            NumberAnimation { target:wipeCurtain; property:"x";     from:0;       to:root.lw-2; duration:340; easing.type:Easing.OutExpo }
            NumberAnimation { target:wipeCurtain; property:"width"; from:root.lw; to:2;         duration:340; easing.type:Easing.OutExpo }
        }
        onFinished: {
            wipeCurtain.width = 0
            scanAnim.start()
            focusTimer.attempts = 0
            focusTimer.restart()
        }
    }

    ParallelAnimation {
        id: wipeHide
        // Match the preview: right-edge cover, then a clipped slide with overlap.
        // 780 ms total, matching the opening transition.
        onStarted: wipeCurtain.x = root.lw - wipeCurtain.width
        ParallelAnimation {
            NumberAnimation {
                target: wipeCurtain; property: "x"; to: 0; duration: 420
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
            }
            NumberAnimation {
                target: wipeCurtain; property: "width"; to: root.lw; duration: 420
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 270 }
            NumberAnimation {
                target: panelHost; property: "closeOffset"; to: root.lw * 1.02; duration: 510
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
            }
        }
        onFinished: { panelHost.visible=false; root.wipeHideRunning=false }
    }

    // ── API ──
    function openMenu() {
        if (menuOpen) return
        menuOpen    = true
        searchQuery = ""
        focusIdx    = -1
        currentCat  = "all"
        // Sync TextInput text with the empty property.
        searchInput.text = ""
        if (!appsLoaded) desktopReader.running = true
        wipeHide.stop()
        wipeReveal.start()
    }

    function closeMenu() {
        if (!menuOpen) return
        menuOpen         = false
        wipeHideRunning  = true
        wipeReveal.stop()
        wipeHide.start()
    }
}
