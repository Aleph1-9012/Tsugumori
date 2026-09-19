pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "lockscreen"

ShellRoot {
    id: root

    // Keep the rice's animated presentation while using ext-session-lock-v1
    // as the actual compositor-enforced security boundary.
    property bool fastMode: Quickshell.env("UNIT3_LOCK_FAST") === "1"
    property real presentationProgress: 0
    property bool presentationStarted: false
    property int submittedLength: 0
    property bool hiding: false
    property bool done: false
    property bool releaseRequested: false
    property bool lockEverSecure: false
    property bool secureSignalConfirmed: false
    property bool releaseAuthorized: false
    property bool releaseRequestRecorded: false

    property string home: Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    property string handshakeDir: Quickshell.env("TSUGUMORI_LOCK_HANDSHAKE_DIR") || ""
    property string handshakeHelper: xdgConfigHome + "/quickshell/lock-handshake.sh"
    property string currentUser: Quickshell.env("USER") || "user"

    property string lockInput: ""
    property string pamResponse: ""
    property bool pamResponseSent: false
    property bool lockError: false
    property bool lockPending: false
    property string powerError: ""
    readonly property bool powerBusy: powerProc.running

    // logind/polkit decides whether the locked user may power off or reboot.
    // Never release the compositor lock to perform a power action.
    Process {
        id: powerProc
        command: []
        onExited: function(exitCode) {
            root.powerError = exitCode === 0 ? "" : "POWER REQUEST FAILED"
        }
    }

    function requestPower(action) {
        if ((action !== "poweroff" && action !== "reboot")
                || !sessionLock.secure || !root.secureSignalConfirmed
                || root.presentationProgress < .96 || root.powerBusy
                || root.lockPending || root.releaseAuthorized || root.hiding
                || root.releaseRequested || root.done || releaseAuthorizeProc.running) return
        root.lockInput = ""
        root.lockError = false
        // Also covers a failure to start the process, which has no exit status.
        root.powerError = "POWER REQUEST FAILED"
        powerProc.command = ["systemctl", "--no-ask-password", action]
        powerProc.running = true
    }

    // The launcher accepts readiness only after WlSessionLock.secure becomes
    // true. Release authorization is committed before the hide animation can
    // start, allowing the supervisor to distinguish a harmless duplicate from
    // a new lock request that races an authenticated release.
    Process {
        id: secureSignalProc
        command: [root.handshakeHelper, root.handshakeDir, "secure"]
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.secureSignalConfirmed = true
            } else {
                console.error("Tsugumori lock: could not confirm secure startup")
                Qt.exit(1)
            }
        }
    }

    Process {
        id: releaseAuthorizeProc
        command: [root.handshakeHelper, root.handshakeDir, "release-authorized"]
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.releaseAuthorized = true
                root.beginHide()
            } else {
                console.error("Tsugumori lock: could not authorize the session release")
                Qt.exit(1)
            }
        }
    }

    Process {
        id: releaseRequestProc
        command: [root.handshakeHelper, root.handshakeDir, "release-requested"]
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.releaseRequestRecorded = true
                releaseQuitTimer.restart()
            } else {
                console.error("Tsugumori lock: could not record the authenticated release request")
                Qt.exit(1)
            }
        }
    }

    function signalSecureAcquired() {
        if (root.secureSignalConfirmed || secureSignalProc.running) return
        secureSignalProc.running = true
    }

    function recordReleaseRequest() {
        if (!root.releaseRequested || sessionLock.secure
                || root.releaseRequestRecorded || releaseRequestProc.running) return
        releaseRequestProc.running = true
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
        if (!sessionLock.secure || !root.secureSignalConfirmed
                || root.lockPending || root.powerBusy || root.releaseAuthorized || root.hiding
                || releaseAuthorizeProc.running || root.lockInput === "") return
        root.submittedLength = root.lockInput.length
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
        if (root.hiding || root.releaseRequested || root.releaseAuthorized
                || releaseAuthorizeProc.running) return
        releaseAuthorizeProc.running = true
    }

    function beginHide() {
        if (!root.releaseAuthorized || root.hiding || root.releaseRequested) return
        root.hiding = true
        appearAnimation.stop()
        disappearAnimation.from = root.presentationProgress
        disappearAnimation.duration = Math.round(950 * root.presentationProgress)
        disappearAnimation.start()
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
        interval: 1000
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
        if (root.handshakeDir === "") {
            console.error("Tsugumori lock: supervised handshake environment is missing")
            Qt.exit(1)
            return
        }

        // Reloading the QML while it owns a compositor lock is an avoidable
        // failure mode. This applies only to the dedicated lock process.
        Quickshell.watchFiles = false
    }

    WlSessionLock {
        id: sessionLock
        locked: true

        onSecureStateChanged: {
            if (secure) {
                root.lockEverSecure = true
                root.signalSecureAcquired()
                root.startPresentation()
            } else if (root.releaseRequested && root.lockEverSecure) {
                root.recordReleaseRequest()
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
                // `locked` is the requested state. Record a clean exit only
                // after `secure` goes false when unlock_and_destroy is issued.
                root.recordReleaseRequest()
            } else if (!root.lockEverSecure) {
                root.failLockAcquisition()
            }
        }

        WlSessionLockSurface {
            id: lockSurface
            color: "black"

            PhaseLockView {
                anchors.fill: parent
                visible: !root.done
                progress: root.presentationProgress
                userName: root.currentUser
                password: root.lockInput
                // Retain only the submitted character count during authentication
                // and exit; the PAM response is still cleared by the secure wrapper.
                glyphLength: root.lockPending || releaseAuthorizeProc.running || root.releaseAuthorized
                    ? root.submittedLength : root.lockInput.length
                inputReady: sessionLock.secure && root.secureSignalConfirmed
                    && root.presentationProgress >= .96
                    && !releaseAuthorizeProc.running && !root.releaseAuthorized
                pending: root.lockPending
                error: root.lockError
                powerBusy: root.powerBusy
                powerError: root.powerError
                hiding: root.hiding
                now: root.clockDate
                onPasswordEdited: value => { root.lockInput = value; root.lockError = false; root.powerError = "" }
                onSubmitted: root.doAuth()
                onCleared: { root.lockInput = ""; root.lockError = false; root.powerError = "" }
                onPowerRequested: action => root.requestPower(action)
            }
        }
    }

    function startPresentation() {
        if (root.presentationStarted) return
        root.presentationStarted = true
        if (root.fastMode) root.presentationProgress = 1
        else appearAnimation.start()
    }

    NumberAnimation {
        id: appearAnimation
        target: root
        property: "presentationProgress"
        from: 0; to: 1; duration: 1450
        easing.type: Easing.Linear
    }
    NumberAnimation {
        id: disappearAnimation
        target: root
        property: "presentationProgress"
        to: 0; duration: 950
        easing.type: Easing.Linear
    }

    property date clockDate: new Date()
    Timer {
        interval: 1000
        running: !root.done
        repeat: true
        onTriggered: {
            var next = new Date()
            if (Math.floor(next.getTime() / 60000) !== Math.floor(root.clockDate.getTime() / 60000))
                root.clockDate = next
        }
    }
}
