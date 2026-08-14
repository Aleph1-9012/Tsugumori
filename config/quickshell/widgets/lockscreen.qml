import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

ShellRoot {
    id: root

    // Keep the rice's animated presentation while using ext-session-lock-v1
    // as the actual compositor-enforced security boundary.
    property bool fastMode: Quickshell.env("UNIT3_LOCK_FAST") === "1"
    property bool revealing: false
    property bool frozen: false
    property bool hiding: false
    property bool done: false
    property bool releaseRequested: false
    property bool lockEverSecure: false

    property string home: Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    property string currentUser: Quickshell.env("USER") || "user"

    property string lockInput: ""
    property string pamResponse: ""
    property bool pamResponseSent: false
    property bool lockError: false
    property bool lockPending: false

    // Power controls remain part of the original design. logind/polkit still
    // decides whether the active user is permitted to perform either action.
    Process {
        id: powerProc
        command: []
        running: false
    }
    function powerAction(action) {
        if ((action !== "poweroff" && action !== "reboot") || powerProc.running) return
        powerProc.command = ["systemctl", action]
        powerProc.running = true
    }

    PamContext {
        id: auth
        config: "hyprlock"
        // Leave the PAM user unset so Quickshell resolves it from the process
        // UID rather than trusting a display-oriented environment variable.
        user: ""

        onPamMessage: {
            if (!responseRequired) return

            // The configured PAM service expects one hidden password prompt.
            // Never answer an unexpected visible or additional challenge with an
            // empty string: abort it and leave the compositor lock in place.
            if (!responseVisible && !root.pamResponseSent) {
                var response = root.pamResponse
                root.pamResponse = ""
                root.pamResponseSent = true
                respond(response)
            } else {
                root.pamResponse = ""
                console.error("Tsugumori lock: unsupported additional PAM challenge")
                abort()
                root.pamResponseSent = false
                root.lockPending = false
                root.lockError = true
                errTimer.restart()
            }
        }

        onCompleted: result => {
            root.lockPending = false
            root.pamResponse = ""
            root.pamResponseSent = false
            if (result === PamResult.Success) {
                root.lockError = false
                root.doHide()
            } else {
                root.lockInput = ""
                root.lockError = true
                errTimer.restart()
            }
        }
    }

    Timer { id: errTimer; interval: 800; repeat: false; onTriggered: root.lockError = false }

    function doAuth() {
        if (!sessionLock.secure || root.lockPending || root.lockInput === "") return
        root.pamResponse = root.lockInput
        root.pamResponseSent = false
        root.lockInput = ""
        root.lockPending = true
        root.lockError = false
        if (!auth.start()) {
            root.pamResponse = ""
            root.pamResponseSent = false
            root.lockPending = false
            root.lockError = true
            errTimer.restart()
        }
    }

    function doHide() {
        if (root.hiding || root.releaseRequested) return
        root.hiding = true
        unlockAnimationTimer.restart()
    }

    function requestSessionRelease() {
        if (root.releaseRequested) return
        root.releaseRequested = true
        root.done = true
        // Send ext_session_lock_v1.unlock_and_destroy. The lock-state handler
        // performs the final quit after Quickshell has released its lock target.
        sessionLock.locked = false
    }

    Timer {
        id: unlockAnimationTimer
        interval: 1250
        repeat: false
        onTriggered: root.requestSessionRelease()
    }

    Timer {
        id: releaseQuitTimer
        interval: 250
        repeat: false
        onTriggered: Qt.quit()
    }

    // Quickshell does not emit lockStateChanged on every acquisition failure
    // path, so watch the concrete manager state without imposing a timeout on
    // a still-pending compositor handshake.
    Timer {
        interval: 100
        running: !root.lockEverSecure && !root.releaseRequested
        repeat: true
        onTriggered: {
            if (!sessionLock.locked) root.failLockAcquisition()
        }
    }

    function failLockAcquisition() {
        if (root.lockEverSecure || root.releaseRequested) return
        console.error("Tsugumori lock: compositor rejected session-lock acquisition")
        Qt.exit(1)
    }

    Component.onCompleted: {
        // Reloading the QML while it owns a compositor lock is an avoidable
        // failure mode. This applies only to the dedicated lock process.
        Quickshell.watchFiles = false
        if (root.fastMode) {
            root.frozen = true
        } else {
            root.revealing = true
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: true

        onSecureStateChanged: {
            if (secure) {
                root.lockEverSecure = true
            } else if (!root.releaseRequested && root.lockEverSecure) {
                // The compositor forcibly ended a previously secure lock.
                Qt.quit()
            } else if (!root.releaseRequested && !locked) {
                root.failLockAcquisition()
            }
        }

        onLockStateChanged: {
            if (locked) return

            if (root.releaseRequested) {
                // Give the Wayland client one event-loop turn to flush the
                // unlock_and_destroy request before the process exits.
                releaseQuitTimer.restart()
            } else if (!root.lockEverSecure) {
                root.failLockAcquisition()
            }
        }

        WlSessionLockSurface {
            id: lockSurface
            color: "black"

            // Fast mode uses a generated final frame of the original reveal.
            Image {
                id: fastBg
                anchors.fill: parent
                source: root.fastMode ? ("file://" + root.xdgConfigHome + "/quickshell/videos/wave_last_frame.png") : ""
                visible: root.fastMode && !root.hiding && !root.done
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                z: 0
            }

            MediaPlayer {
                id: reveal
                source: root.fastMode ? "" : ("file://" + root.xdgConfigHome + "/quickshell/videos/wave_reveal.mp4")
                videoOutput: voReveal
                audioOutput: null
                loops: 1
                autoPlay: false
                onPositionChanged: function() {
                    if (root.hiding || root.done) return
                    var pos = reveal.position
                    var dur = reveal.duration
                    if (dur > 0 && pos >= dur - 34) {
                        reveal.pause()
                        root.revealing = false
                    }
                }
            }
            VideoOutput {
                id: voReveal
                anchors.fill: parent
                visible: !root.fastMode && !root.done
            }

            MediaPlayer {
                id: hide
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_hide.mp4"
                videoOutput: voHide
                audioOutput: null
                loops: 1
                autoPlay: false
            }
            VideoOutput {
                id: voHide
                anchors.fill: parent
                z: 1
                visible: root.hiding || root.done
                opacity: 1.0
            }

            Timer {
                id: hideFadeTimer
                interval: 800
                repeat: false
                onTriggered: hideFadeAnim.start()
            }
            NumberAnimation {
                id: hideFadeAnim
                target: voHide
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: 400
                easing.type: Easing.InQuad
            }

            Item {
                anchors.fill: parent
                visible: !root.done
                z: 2

                property real uiOp: (root.frozen || root.revealing) ? 1 : 0
                Behavior on uiOp {
                    enabled: !root.fastMode
                    NumberAnimation { duration: 400 }
                }

                Item {
                    anchors { top: parent.top; left: parent.left; topMargin: 28; leftMargin: 30 }
                    z: 5; opacity: parent.uiOp
                    Column { spacing: 2
                        Row { spacing: 5
                            Rectangle { width: 5; height: 5; radius: 3; color: "#e8e8e8"
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity { running: root.frozen; loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 900 }
                                    NumberAnimation { to: 1; duration: 900 }
                                }
                            }
                            Text { text: "SESSION LOCKED"; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2; color: "#e8e8e8" }
                        }
                        Text { text: "NODE · " + root.currentUser + "@arch"; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2; color: "#e8e8e8" }
                        Text { text: "セッションロック中"; font.family: "Noto Sans CJK JP"; font.pixelSize: 8; color: "#e8e8e8"; opacity: 0.7 }
                    }
                }
                Item {
                    anchors { top: parent.top; right: parent.right; topMargin: 28; rightMargin: 30 }
                    z: 5; opacity: parent.uiOp
                    Column { spacing: 2
                        Text { text: root.clockFull; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2; color: "#e8e8e8"; width: 200; horizontalAlignment: Text.AlignRight }
                        Text { text: "LONGVIC · FR"; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2; color: "#e8e8e8"; width: 200; horizontalAlignment: Text.AlignRight }
                    }
                }
                Item {
                    anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 28; leftMargin: 30 }
                    z: 5; opacity: parent.uiOp
                    Column { spacing: 2
                        Text { text: "KERNEL 6.13.2"; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2; color: "#e8e8e8" }
                        Text { text: "WM · hyprland"; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2; color: "#e8e8e8" }
                    }
                }
                Item {
                    anchors { bottom: parent.bottom; right: parent.right; bottomMargin: 28; rightMargin: 30 }
                    z: 5; opacity: parent.uiOp
                    Column { spacing: 2
                        Text { text: "ARCH LINUX · RX 6700 XT"; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2; color: "#e8e8e8"; width: 220; horizontalAlignment: Text.AlignRight }
                    }
                }

                Item {
                    anchors { bottom: parent.bottom; bottomMargin: 65; left: parent.left; right: parent.right }
                    height: 18; z: 5; opacity: parent.uiOp; clip: true
                    Text {
                        id: tickTxt
                        text: "SYSTEM SCAN · OK ▸ MEMORY INTEGRITY · VERIFIED ▸ SESSION LOCKED · SECURE ▸ NETWORK UPLINK · STABLE ▸ THERMAL · NOMINAL ▸ AUTH DAEMON · LISTENING ▸ "
                        font.family: "Share Tech Mono"; font.pixelSize: 8; font.letterSpacing: 3; color: "#e8e8e8"; y: 2
                        NumberAnimation on x { from: lockSurface.width; to: -tickTxt.implicitWidth; duration: 55000; loops: Animation.Infinite; running: root.frozen }
                    }
                }

                Item {
                    id: panelHost
                    width: 380
                    height: panelRect.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    z: 6
                    opacity: root.fastMode ? 1 : 0

                    SequentialAnimation {
                        id: panelReveal
                        PropertyAction { target: panelHost; property: "anchors.verticalCenterOffset"; value: -200 }
                        PropertyAction { target: panelHost; property: "opacity"; value: 0 }
                        PropertyAction { target: wipeScale; property: "yScale"; value: 1 }
                        ParallelAnimation {
                            NumberAnimation { target: panelHost; property: "anchors.verticalCenterOffset"; to: 0; duration: 580; easing.type: Easing.OutExpo }
                            NumberAnimation { target: panelHost; property: "opacity"; to: 1; duration: 320 }
                        }
                        NumberAnimation { target: wipeScale; property: "yScale"; to: 0; duration: 460; easing.type: Easing.OutExpo }
                        onFinished: {
                            pwInput.forceActiveFocus()
                            focusRetry.restart()
                        }
                    }

                    SequentialAnimation {
                        id: panelHide
                        NumberAnimation { target: wipeScale; property: "yScale"; from: 0; to: 1; duration: 210; easing.type: Easing.InQuart }
                        ParallelAnimation {
                            NumberAnimation { target: panelHost; property: "anchors.verticalCenterOffset"; to: -200; duration: 360; easing.type: Easing.InExpo }
                            NumberAnimation { target: panelHost; property: "opacity"; to: 0; duration: 280 }
                        }
                    }

                    SequentialAnimation { id: shakeAnim
                        NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; from: 0; to: -10; duration: 55 }
                        NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; to: 10; duration: 75 }
                        NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; to: -7; duration: 65 }
                        NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; to: 7; duration: 65 }
                        NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; to: 0; duration: 55 }
                    }

                    Rectangle {
                        id: panelRect
                        width: 380; color: "#111111"
                        height: panelCol.implicitHeight + 72
                        border.color: "#cc1515"; border.width: 1

                        Repeater { model: 20; Rectangle { x: index * 20; y: 0; width: 1; height: panelRect.height; color: Qt.rgba(204/255, 21/255, 21/255, 0.06) } }
                        Repeater { model: Math.ceil(panelRect.height / 20); Rectangle { x: 0; y: index * 20; width: panelRect.width; height: 1; color: Qt.rgba(204/255, 21/255, 21/255, 0.06) } }

                        Rectangle {
                            x: 0; width: parent.width; height: 1; z: 20
                            gradient: Gradient { orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 0.5; color: "#e8e8e8" }
                                GradientStop { position: 1; color: "transparent" }
                            }
                            SequentialAnimation on y {
                                running: root.frozen; loops: Animation.Infinite
                                NumberAnimation { from: 0; to: panelRect.height; duration: 3500; easing.type: Easing.Linear }
                                PauseAnimation { duration: 600 }
                            }
                        }

                        Rectangle {
                            id: wipeCurtain; anchors.fill: parent; color: "#0a0a0a"; z: 50
                            transform: Scale { id: wipeScale; xScale: 1; yScale: 1; origin.x: 0; origin.y: 0 }
                        }

                        Column {
                            id: panelCol
                            width: 308
                            anchors { top: parent.top; topMargin: 36; horizontalCenter: parent.horizontalCenter }
                            spacing: 0

                            Item { width: parent.width; height: 90
                                Rectangle { width: 76; height: 76; border.color: "#cc1515"; border.width: 1; color: "transparent"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Rectangle { width: 52; height: 52; color: "#cc1515"; anchors.centerIn: parent
                                        transform: Rotation { angle: 45; origin.x: 26; origin.y: 26 }
                                    }
                                    Text { text: "NR"; font.family: "Share Tech Mono"; font.pixelSize: 7; color: "#7a7358"; opacity: 0.5; anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 3 }
                                    Text { text: "2B"; font.family: "Share Tech Mono"; font.pixelSize: 7; color: "#7a7358"; opacity: 0.5; anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 3 }
                                }
                            }
                            Text { text: root.currentUser.toUpperCase(); font.family: "Share Tech Mono"; font.pixelSize: 13; font.letterSpacing: 3; color: "#e8e8e8"; anchors.horizontalCenter: parent.horizontalCenter }
                            Item { width: 1; height: 4 }
                            Text { text: "ユニット · アクティブ"; font.family: "Noto Sans CJK JP"; font.pixelSize: 8; color: "#7a7358"; anchors.horizontalCenter: parent.horizontalCenter }
                            Item { width: 1; height: 20 }
                            Text { text: root.clockStr; font.family: "Share Tech Mono"; font.pixelSize: 46; font.letterSpacing: 2; color: "#e8e8e8"; anchors.horizontalCenter: parent.horizontalCenter }
                            Item { width: 1; height: 6 }
                            Text { text: root.dateStr; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 3; color: "#7a7358"; anchors.horizontalCenter: parent.horizontalCenter }
                            Item { width: 1; height: 20 }
                            Rectangle { width: parent.width; height: 1; color: Qt.rgba(204/255, 21/255, 21/255, 0.12) }
                            Item { width: 1; height: 22 }

                            Item { width: parent.width; height: 40
                                Rectangle { anchors.fill: parent; color: "transparent"
                                    border.color: inputScope.activeFocus ? "#cc1515" : Qt.rgba(204/255, 21/255, 21/255, 0.12); border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: 200 } }
                                }
                                Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "▸"; font.pixelSize: 10; color: "#e8e8e8" }
                                FocusScope {
                                    id: inputScope
                                    anchors { fill: parent; leftMargin: 26; rightMargin: 10 }
                                    // Every lock surface maintains an active input item so
                                    // keyboard focus continues to work on whichever output
                                    // the compositor selects. The password state is shared.
                                    focus: root.frozen
                                    TextInput {
                                        id: pwInput; anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: "Share Tech Mono"; font.pixelSize: 12; font.letterSpacing: 2
                                        color: "#cc1515"; echoMode: TextInput.Password; passwordCharacter: "·"
                                        focus: true; readOnly: root.lockPending
                                        text: root.lockInput
                                        onTextEdited: root.lockInput = text
                                        Keys.onReturnPressed: root.doAuth()
                                        Keys.onEscapePressed: root.lockInput = ""
                                        Text { visible: parent.text === ""; anchors.verticalCenter: parent.verticalCenter
                                            text: root.lockPending ? "authentification..." : "mot de passe..."; font.family: "Share Tech Mono"; font.pixelSize: 11; font.italic: true; color: "#7a7358"; opacity: 0.5
                                        }
                                    }
                                }
                            }
                            Item { width: 1; height: 8 }

                            Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                                Repeater { model: 6; Rectangle { width: 6; height: 6; color: "transparent"; border.color: "#7a7358"; border.width: 1
                                    Rectangle { visible: index < root.lockInput.length; anchors.fill: parent; color: "#cc1515" }
                                } }
                            }
                            Item { width: 1; height: 6 }

                            Text { text: "AUTHENTIFICATION ÉCHOUÉE"; font.family: "Share Tech Mono"; font.pixelSize: 8; font.letterSpacing: 2; color: "#e8e8e8"
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: root.lockError ? 1 : 0; height: 14
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }
                            Item { width: 1; height: 10 }

                            Item { width: 254; height: 30; anchors.horizontalCenter: parent.horizontalCenter
                                Rectangle { anchors.fill: parent; color: "transparent"; border.color: "#cc1515"; border.width: 1 }
                                Rectangle { id: unlockFill; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; color: "#cc1515"; width: 0
                                    Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.InOutQuart } }
                                }
                                Text { anchors.centerIn: parent; text: root.lockPending ? "WAIT" : "Login"; font.family: "Share Tech Mono"; font.pixelSize: 10; font.letterSpacing: 3
                                    color: unlockMA.containsMouse ? "#c8c8c4" : "#cc1515"; Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                MouseArea { id: unlockMA; anchors.fill: parent; hoverEnabled: true; enabled: !root.lockPending
                                    onEntered: unlockFill.width = parent.width; onExited: unlockFill.width = 0
                                    onClicked: root.doAuth()
                                }
                            }

                            Item { width: 1; height: 16 }
                            Item { width: parent.width; height: 34
                                Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 14
                                    Rectangle { width: 120; height: 30; color: "transparent"; border.color: "#cc1515"; border.width: 1
                                        Rectangle { id: shutdownFill; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; color: "#cc1515"; width: 0
                                            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.InOutQuart } }
                                        }
                                        Text { anchors.centerIn: parent; text: "SHUTDOWN"; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2
                                            color: shutdownMA.containsMouse ? "#c8c8c4" : "#cc1515"; Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        MouseArea { id: shutdownMA; anchors.fill: parent; hoverEnabled: true
                                            onEntered: shutdownFill.width = parent.width; onExited: shutdownFill.width = 0
                                            onClicked: root.powerAction("poweroff")
                                        }
                                    }
                                    Rectangle { width: 120; height: 30; color: "transparent"; border.color: "#cc1515"; border.width: 1
                                        Rectangle { id: restartFill; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; color: "#cc1515"; width: 0
                                            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.InOutQuart } }
                                        }
                                        Text { anchors.centerIn: parent; text: "RESTART"; font.family: "Share Tech Mono"; font.pixelSize: 9; font.letterSpacing: 2
                                            color: restartMA.containsMouse ? "#c8c8c4" : "#cc1515"; Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        MouseArea { id: restartMA; anchors.fill: parent; hoverEnabled: true
                                            onEntered: restartFill.width = parent.width; onExited: restartFill.width = 0
                                            onClicked: root.powerAction("reboot")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Timer { id: focusRetry; interval: 50; repeat: true; property int cnt: 0
                    onTriggered: {
                        pwInput.forceActiveFocus()
                        if (++cnt >= 8) { running = false; cnt = 0 }
                    }
                }

                Rectangle { anchors.fill: parent; color: "black"; z: 10; visible: root.done }

            }

            Connections {
                target: root
                function onFrozenChanged() {
                    if (root.fastMode && root.frozen) panelOpenTimer.restart()
                }
                function onHidingChanged() {
                    if (root.hiding) {
                        reveal.stop()
                        panelHide.start()
                        hide.position = 0
                        hide.play()
                        hideFadeTimer.restart()
                    }
                }
                function onRevealingChanged() {
                    if (root.revealing) {
                        root.frozen = true
                        reveal.position = 0
                        reveal.play()
                        panelOpenTimer.restart()
                    }
                }
                function onLockErrorChanged() {
                    if (root.lockError) shakeAnim.restart()
                }
            }

            Timer {
                id: panelOpenTimer
                interval: 100
                repeat: false
                onTriggered: {
                    if (root.fastMode) {
                        wipeScale.yScale = 0
                        pwInput.forceActiveFocus()
                        focusRetry.restart()
                    } else {
                        panelReveal.start()
                    }
                }
            }

            Component.onCompleted: {
                // WlSessionLock creates these surfaces after the root has
                // completed, so initialize from current state instead of
                // relying on root change signals emitted before we existed.
                if (root.fastMode) {
                    wipeScale.yScale = 0
                    panelOpenTimer.restart()
                } else {
                    root.frozen = true
                    reveal.position = 0
                    reveal.play()
                    panelOpenTimer.restart()
                }
            }
        }
    }

    property string clockStr: "--:--"
    property string dateStr: "---- / -- / --"
    property string clockFull: "--:--:--"
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            var d = new Date(), p = function(x) { return String(x).padStart(2, "0") }
            root.clockStr = p(d.getHours()) + ":" + p(d.getMinutes())
            root.clockFull = p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
            root.dateStr = d.getFullYear() + " / " + p(d.getMonth() + 1) + " / " + p(d.getDate())
        }
    }
}
