import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick
import "widgets"
import "components"
import "settings"
import "services"

ShellRoot {
    id: root

    // ── NOTIFICATIONS ──
    Notifications {}

    // ── CONTROLCENTER ──
    ControlCenter {}

    // ── VOLUMEBAR ──
    VolumeBar {}

    // ── PLAYER STATE ──
    property bool   playerVisible: false
    property bool   playerOnTop:   true
    property string mpTitle:    "NO MEDIA"
    property string mpArtist:   ""
    property string mpCoverUrl: ""
    property bool   mpPlaying:  false
    property real   mpPosition: 0
    property real   mpLength:   0
    property double localPreferenceUntil: 0
    property string externalMediaKey: ""
    property string externalServiceKey: ""
    property bool   externalTrackChangePending: false
    property var    externalTrackChangePlayer: null
    property string externalTrackChangeMediaKey: ""
    property string externalTrackChangeTitle: ""
    property string externalTrackChangeArtist: ""
    property bool   externalPositionAwaitingFresh: false
    readonly property bool externalMediaAvailable: externalPlayer !== null
                                                   || noPlayerGraceTimer.running

    // One authoritative non-mpv MPRIS player. Playing players win, followed by
    // the previously selected player, then the first controllable player.
    property var externalPlayer: null

    function isLocalMpvPlayer(player) {
        if (!player) return false
        var name = String(player.dbusName || "").toLowerCase()
        var identity = String(player.identity || "").toLowerCase()
        var desktop = String(player.desktopEntry || "").toLowerCase()
        return name.indexOf("org.mpris.mediaplayer2.mpv") === 0
            || identity === "mpv" || desktop === "mpv"
    }

    function serviceKeyForPlayer(player) {
        if (!player) return ""
        // The well-known MPRIS bus name distinguishes simultaneous instances
        // while surviving a normal owner loss/reacquire of the same service.
        var name = String(player.dbusName || "").trim().toLowerCase()
        if (name.length > 0) return "dbus:" + name
        var desktop = String(player.desktopEntry || "").trim().toLowerCase()
        if (desktop.length > 0) return "desktop:" + desktop
        var identity = String(player.identity || "").trim().toLowerCase()
        if (identity.length > 0) return "identity:" + identity
        return ""
    }

    function hasExternalService(serviceKey) {
        if (serviceKey.length === 0) return false
        var players = Mpris.players.values
        for (var i = 0; i < players.length; ++i) {
            var player = players[i]
            if (!root.isLocalMpvPlayer(player)
                    && root.serviceKeyForPlayer(player) === serviceKey)
                return true
        }
        return false
    }

    function selectExternalPlayer() {
        var players = Mpris.players.values
        var fallback = null
        for (var i = 0; i < players.length; ++i) {
            var player = players[i]
            if (root.isLocalMpvPlayer(player) || !player.canControl) continue
            if (player.isPlaying) return player
            if (root.serviceKeyForPlayer(player) === root.externalServiceKey)
                fallback = player
            else if (!fallback) fallback = player
        }
        return fallback
    }

    function clearExternalState() {
        if (root.localMode) return
        root.externalMediaKey = ""
        root.externalServiceKey = ""
        root.externalTrackChangePending = false
        root.externalTrackChangePlayer = null
        root.externalTrackChangeMediaKey = ""
        root.externalTrackChangeTitle = ""
        root.externalTrackChangeArtist = ""
        root.externalPositionAwaitingFresh = false
        root.mpTitle = "NO MEDIA"
        root.mpArtist = ""
        root.mpCoverUrl = ""
        root.mpPlaying = false
        root.mpPosition = 0
        root.mpLength = 0
    }

    function normalizedCoverUrl(value) {
        var url = String(value || "").trim()
        if (url.length === 0) return ""
        if (url.charAt(0) === "/") return "file://" + url
        return url
    }

    function youtubeVideoId(mediaUrl) {
        var url = String(mediaUrl || "").trim()
        if (url.length === 0) return ""

        var direct = url.match(/(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:embed|shorts|live)\/)([A-Za-z0-9_-]{6,})/i)
        if (direct) return direct[1]

        if (url.indexOf("youtube.com/") !== -1) {
            var watch = url.match(/[?&]v=([A-Za-z0-9_-]{6,})/i)
            if (watch) return watch[1]
        }
        return ""
    }

    function coverUrlForPlayer(player) {
        if (!player) return ""

        var direct = root.normalizedCoverUrl(player.trackArtUrl)
        if (direct.length > 0) return direct

        var metadata = player.metadata
        var mediaUrl = metadata && metadata["xesam:url"] !== undefined
                ? String(metadata["xesam:url"]) : ""
        var videoId = root.youtubeVideoId(mediaUrl)
        return videoId.length > 0
                ? "https://i.ytimg.com/vi/" + encodeURIComponent(videoId) + "/maxresdefault.jpg"
                : ""
    }

    function metadataString(player, name) {
        if (!player || !player.metadata || player.metadata[name] === undefined
                || player.metadata[name] === null)
            return ""
        var value = player.metadata[name]
        if (Array.isArray(value))
            return value.length > 0 ? String(value[0]).trim() : ""
        return String(value).trim()
    }

    // Mozilla may briefly publish an incomplete metadata map around pause/play
    // and track transitions. Prefer identifiers that remain stable through those
    // gaps, falling back to Quickshell's per-track id and finally visible text.
    function mediaKeyForPlayer(player) {
        if (!player) return ""
        var mediaUrl = root.metadataString(player, "xesam:url")
        if (mediaUrl.length > 0) return "url:" + mediaUrl
        var trackId = root.metadataString(player, "mpris:trackid")
        if (trackId.length > 0) return "track:" + trackId
        var title = String(player.trackTitle || "").trim()
        var artist = String(player.trackArtist || "").trim()
        return title.length > 0 || artist.length > 0
                ? "text:" + title + "\u0000" + artist : ""
    }

    function mediaKeyRank(key) {
        if (key.indexOf("url:") === 0) return 3
        if (key.indexOf("track:") === 0) return 2
        if (key.indexOf("text:") === 0) return 1
        return 0
    }

    function visibleMetadataConflicts(player) {
        var title = String(player.trackTitle || "").trim()
        var artist = String(player.trackArtist || "").trim()
        var knownTitle = root.mpTitle !== "NO MEDIA" && root.mpTitle !== "NO TITLE"
                ? root.mpTitle : ""
        var knownArtist = root.mpArtist !== "UNKNOWN ARTIST" ? root.mpArtist : ""
        if (title.length > 0 && knownTitle.length > 0 && title !== knownTitle)
            return true
        return artist.length > 0 && knownArtist.length > 0
                && title === knownTitle && artist !== knownArtist
    }

    function scheduleExternalRefresh() {
        externalSettleTimer.restart()
    }

    function adoptExternalPlayer(player) {
        if (!player) return
        noPlayerGraceTimer.stop()
        root.externalServiceKey = root.serviceKeyForPlayer(player)
        root.externalPlayer = player
        root.syncExternalState(false)
        root.scheduleExternalRefresh()
    }

    function reselectExternalPlayer() {
        var selected = root.selectExternalPlayer()
        if (selected) {
            var previousServiceMissing = root.externalServiceKey.length > 0
                    && !root.hasExternalService(root.externalServiceKey)
            // If the selected browser service vanished, do not flash metadata
            // from an unrelated paused player while Firefox/Zen recreates it.
            // A genuinely playing replacement still wins immediately.
            if (previousServiceMissing && !selected.isPlaying) {
                noPlayerGraceTimer.restart()
                root.externalPlayer = null
                return
            }
            root.adoptExternalPlayer(selected)
        } else if (!root.localMode) {
            // Firefox/Zen commonly replaces its MPRIS service during media
            // transitions. Retain the last valid presentation for a short grace.
            noPlayerGraceTimer.restart()
            root.externalPlayer = null
        }
    }

    function beginExternalTrackChange(player) {
        if (root.localMode || player !== root.externalPlayer) return
        root.externalTrackChangePending = true
        root.externalTrackChangePlayer = player
        root.externalTrackChangeMediaKey = root.externalMediaKey
        root.externalTrackChangeTitle = root.mpTitle
        root.externalTrackChangeArtist = root.mpArtist
    }

    function finishExternalTrackChange(player) {
        if (!root.externalTrackChangePending
                || player !== root.externalTrackChangePlayer) {
            // Track notifications from a non-selected player must not consume
            // the selected player's pending pre/post snapshot.
            root.reselectExternalPlayer()
            root.scheduleExternalRefresh()
            return
        }
        var candidateKey = root.mediaKeyForPlayer(player)
        var title = String(player ? player.trackTitle || "" : "").trim()
        var artist = String(player ? player.trackArtist || "" : "").trim()
        var oldTitle = root.externalTrackChangeTitle
        var oldArtist = root.externalTrackChangeArtist
        var titleChanged = title.length > 0 && oldTitle.length > 0
                && oldTitle !== "NO MEDIA" && oldTitle !== "NO TITLE"
                && title !== oldTitle
        var artistChanged = artist.length > 0 && oldArtist.length > 0
                && oldArtist !== "UNKNOWN ARTIST" && artist !== oldArtist
        var forceNewMedia = root.externalTrackChangePending
                && player === root.externalTrackChangePlayer
                && candidateKey.length > 0
                && candidateKey === root.externalTrackChangeMediaKey
                && (titleChanged || artistChanged)

        root.externalTrackChangePending = false
        root.externalTrackChangePlayer = null
        root.externalTrackChangeMediaKey = ""
        root.externalTrackChangeTitle = ""
        root.externalTrackChangeArtist = ""

        root.reselectExternalPlayer()
        if (forceNewMedia && root.externalPlayer === player)
            root.syncExternalState(true)
        root.scheduleExternalRefresh()
    }

    function syncExternalState(forceNewMedia, allowPositionUpdate) {
        var player = root.externalPlayer
        if (!player) {
            if (!root.localMode && !noPlayerGraceTimer.running)
                root.clearExternalState()
            return
        }
        if (!player.canControl) {
            root.reselectExternalPlayer()
            return
        }
        if (player.isPlaying && root.localMode
                && Date.now() >= root.localPreferenceUntil) {
            root.localMode = false
            root.mpvSend(["set_property", "pause", true])
        }
        if (root.localMode) return

        var candidateKey = root.mediaKeyForPlayer(player)
        var newMedia = Boolean(forceNewMedia) && candidateKey.length > 0
        if (candidateKey.length > 0 && candidateKey !== root.externalMediaKey) {
            if (root.externalMediaKey.length === 0) {
                newMedia = true
            } else {
                var candidateRank = root.mediaKeyRank(candidateKey)
                var currentRank = root.mediaKeyRank(root.externalMediaKey)
                if (candidateRank === currentRank) {
                    newMedia = true
                } else if (candidateRank < currentRank) {
                    // Do not downgrade a URL/track-id cache merely because
                    // Mozilla temporarily published a partial metadata map.
                    newMedia = root.visibleMetadataConflicts(player)
                } else if (root.visibleMetadataConflicts(player)) {
                    newMedia = true
                } else {
                    // A stronger identifier arrived after title metadata for
                    // the same track. Upgrade the key without blanking the UI.
                    root.externalMediaKey = candidateKey
                }
            }
        }
        if (newMedia) {
            var hadPreviousExternalMedia = root.externalMediaKey.length > 0
            // A genuine non-empty identity change is visible immediately. Missing
            // fields start empty/zero for this new track rather than leaking the
            // previous track's artwork or timer.
            root.externalMediaKey = candidateKey
            root.mpTitle = "NO TITLE"
            root.mpArtist = "UNKNOWN ARTIST"
            root.mpCoverUrl = ""
            root.mpPosition = 0
            root.mpLength = 0
            // Quickshell requests Position asynchronously after trackChanged.
            // Only an actual transition needs to wait for that reply; the first
            // player adopted at startup may use its already-loaded position.
            root.externalPositionAwaitingFresh = hadPreviousExternalMedia
        }

        var title = String(player.trackTitle || "").trim()
        var artist = String(player.trackArtist || "").trim()
        var cover = root.coverUrlForPlayer(player)
        if (title.length > 0) root.mpTitle = title
        if (artist.length > 0) root.mpArtist = artist
        if (cover.length > 0) root.mpCoverUrl = cover
        root.mpPlaying = player.isPlaying

        // Apply timing field-by-field. A transient missing/zero duration for the
        // same key must not erase known timing, while a new key was reset above.
        var length = Number(player.length)
        if (player.lengthSupported && isFinite(length) && length > 0)
            root.mpLength = length
        var position = Number(player.position)
        var freshPositionEvent = Boolean(allowPositionUpdate)
        if ((!root.externalPositionAwaitingFresh || freshPositionEvent)
                && player.positionSupported && isFinite(position) && position >= 0) {
            if (freshPositionEvent)
                root.externalPositionAwaitingFresh = false
            // Firefox can briefly (or for some sites permanently) expose zero
            // while pausing/resuming. Keep a known positive value unless this
            // is a new track or the UI already expects the beginning.
            if (position > 0 || newMedia || root.mpPosition <= 0) {
                root.mpPosition = root.mpLength > 0
                        ? Math.min(position, root.mpLength) : position
            }
        }
    }

    onExternalPlayerChanged: {
        if (externalPlayer) noPlayerGraceTimer.stop()
        syncExternalState(false)
    }

    Instantiator {
        model: Mpris.players
        delegate: QtObject {
            required property var modelData
            property Connections playerConnections: Connections {
                target: modelData
                function onTrackChanged() {
                    root.beginExternalTrackChange(modelData)
                    root.reselectExternalPlayer()
                }
                function onPostTrackChanged() { root.finishExternalTrackChange(modelData) }
                function onTrackTitleChanged() { root.syncExternalState(); root.scheduleExternalRefresh() }
                function onTrackArtistChanged() { root.syncExternalState(); root.scheduleExternalRefresh() }
                function onTrackArtUrlChanged() { root.syncExternalState(); root.scheduleExternalRefresh() }
                function onMetadataChanged() { root.syncExternalState(); root.scheduleExternalRefresh() }
                function onCanControlChanged() { root.reselectExternalPlayer() }
                function onIsPlayingChanged() { root.reselectExternalPlayer() }
                function onPlaybackStateChanged() { root.reselectExternalPlayer() }
                function onLengthChanged() { root.syncExternalState(); root.scheduleExternalRefresh() }
                function onPositionChanged() { root.syncExternalState(false, true) }
            }
        }
        onObjectAdded: root.reselectExternalPlayer()
        onObjectRemoved: root.reselectExternalPlayer()
    }

    Timer {
        id: externalSettleTimer
        interval: 150
        repeat: false
        onTriggered: root.syncExternalState()
    }

    Timer {
        id: noPlayerGraceTimer
        interval: 500
        repeat: false
        onTriggered: {
            var selected = root.selectExternalPlayer()
            if (selected) {
                root.adoptExternalPlayer(selected)
            } else {
                root.clearExternalState()
            }
        }
    }

    Timer {
        interval: 1000
        running: !root.localMode && root.externalPlayer !== null
        repeat: true
        onTriggered: {
            var player = root.externalPlayer
            if (!player || !player.isPlaying) return
            // A real Position reply is already in flight after trackChanged.
            // Do not let this synthetic UI refresh expose the previous track's
            // cached positive value before that reply arrives.
            if (root.externalPositionAwaitingFresh) return
            // Quickshell intentionally updates MPRIS position lazily. Emitting
            // this documented signal makes bindings re-read the current value.
            player.positionChanged()
            root.syncExternalState()
        }
    }

    // ── LOCAL MUSIC ──
    readonly property string homeDir: String(Quickshell.env("HOME") || "")
    readonly property string runtimeBase: Quickshell.env("XDG_RUNTIME_DIR") || (homeDir + "/.cache/tsugumori/runtime")
    readonly property string runtimeDir: runtimeBase + (Quickshell.env("XDG_RUNTIME_DIR") ? "/tsugumori" : "")
    property var    localTracks: []
    property bool   localMode: false
    readonly property string mpvSocket: runtimeDir + "/mpv.sock"

    Process {
        id: runtimeInitProc
        command: ["install", "-d", "-m", "0700", root.runtimeDir]
        running: true
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) root.runtimeReady = true
        }
    }

    property bool runtimeReady: false

    Process {
        id: musicScanProc
        command: ["find", root.homeDir + "/Music", "-type","f","(",
                  "-iname","*.mp3","-o","-iname","*.flac","-o",
                  "-iname","*.wav","-o","-iname","*.m4a","-o",
                  "-iname","*.ogg",")", "-print0"]
        running: false
        onExited: function(exitCode, exitStatus) {
            if (root.musicScanPending) {
                root.musicScanPending = false
                musicScanProc.running = true
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\u0000").filter(function(l){ return l.length>0 })
                lines.sort(function(a, b) { return a.localeCompare(b) })
                root.localTracks = lines
                root.localTrackIndex = root.localTrackPath !== ""
                                       ? lines.indexOf(root.localTrackPath) : -1
            }
        }
    }

    property bool musicScanPending: false

    function requestMusicScan() {
        if (root.homeDir === "") return
        if (musicScanProc.running) root.musicScanPending = true
        else musicScanProc.running = true
    }

    Process {
        id: mpvProc
        command: ["mpv", "--idle=yes", "--no-video", "--no-terminal",
                  "--reset-on-next-file=pause", "--input-ipc-server=" + root.mpvSocket]
        running: false
        onExited: function(exitCode, exitStatus) {
            root.mpvReady = false
            if (root.localMode) {
                root.mpPlaying = false
                root.mpPosition = 0
            }
        }
    }

    Process {
        id: mpvBridge
        command: ["python3", Quickshell.shellPath("scripts/mpv_ctl.py"), root.mpvSocket]
        stdinEnabled: true
        running: false
        stdout: SplitParser {
            onRead: data => root.handleMpvMessage(data)
        }
        onExited: function(exitCode, exitStatus) {
            root.mpvReady = false
            if (root.localMode) mpvBridgeRestart.start()
        }
    }

    Timer {
        id: mpvBridgeRestart
        interval: 300
        repeat: false
        onTriggered: if (root.localMode && !mpvBridge.running) mpvBridge.running = true
    }

    property bool mpvReady: false
    property var mpvCommandQueue: []
    onRuntimeReadyChanged: if (runtimeReady && mpvCommandQueue.length > 0) startMpvIfNeeded()

    function startMpvIfNeeded() {
        if (!root.runtimeReady) return
        if (!mpvProc.running) mpvProc.running = true
        if (!mpvBridge.running) mpvBridge.running = true
    }

    function flushMpvCommands() {
        if (!root.mpvReady || !mpvBridge.running) return
        while (root.mpvCommandQueue.length > 0) {
            var command = root.mpvCommandQueue.shift()
            mpvBridge.write(JSON.stringify({ type: "command", command: command }) + "\n")
        }
        root.mpvCommandQueue = root.mpvCommandQueue
    }

    function handleMpvMessage(data) {
        var message
        try { message = JSON.parse(data) } catch (error) { return }

        if (message.type === "ready") {
            root.mpvReady = true
            root.flushMpvCommands()
            return
        }
        if (message.type === "disconnected") {
            root.mpvReady = false
            return
        }
        if (message.type !== "state") return

        if (root.localMode) {
            var pos = Number(message.position)
            var len = Number(message.duration)
            var ended = Boolean(message.eofReached) || Boolean(message.idleActive)
            if (isFinite(len) && len > 0) root.mpLength = len
            if (!ended && isFinite(pos) && pos >= 0) root.mpPosition = pos
            root.mpPlaying = !Boolean(message.pause) && !ended
            if (ended && root.mpLength > 0) root.mpPosition = root.mpLength
        }
    }

    function mpvSend(cmdArr) {
        root.mpvCommandQueue.push(cmdArr)
        root.mpvCommandQueue = root.mpvCommandQueue
        root.startMpvIfNeeded()
        root.flushMpvCommands()
    }

    function togglePlayback() {
        if (root.localMode) {
            root.mpvSend(["cycle", "pause"])
            return
        }
        var player = root.externalPlayer
        if (player && player.canTogglePlaying) player.togglePlaying()
    }

    function nextTrack() {
        if (root.localMode) root.nextLocalTrack()
        else if (root.externalPlayer && root.externalPlayer.canGoNext) root.externalPlayer.next()
    }

    function previousTrack() {
        if (root.localMode) root.prevLocalTrack()
        else if (root.externalPlayer && root.externalPlayer.canGoPrevious) root.externalPlayer.previous()
    }

    function seekTo(seconds) {
        var target = Math.max(0, Number(seconds))
        if (!isFinite(target)) return
        root.mpPosition = root.mpLength > 0 ? Math.min(target, root.mpLength) : target
        if (root.localMode) {
            root.mpvSend(["set_property", "time-pos", root.mpPosition])
        } else if (root.externalPlayer && root.externalPlayer.canSeek
                   && root.externalPlayer.positionSupported) {
            root.externalPlayer.position = root.mpPosition
        }
    }

    property string localTrackPath: ""
    property int localTrackIndex: -1

    function playLocalTrack(path) {
        root.externalMediaKey = ""
        root.localTrackPath = path
        root.localTrackIndex = root.localTracks.indexOf(path)
        root.localPreferenceUntil = Date.now() + 1500
        var players = Mpris.players.values
        for (var i = 0; i < players.length; ++i) {
            var player = players[i]
            if (!root.isLocalMpvPlayer(player) && player.isPlaying && player.canPause)
                player.pause()
        }
        root.localMode = true
        var fname = path.split("/").pop().replace(/\.[^.]+$/, "")
        root.mpTitle = fname
        root.mpArtist = "LOCAL FILE"
        root.mpPosition = 0
        root.mpCoverUrl = ""
        root.mpvSend(["loadfile", path, "replace"])
        // Selecting a drawer row is a play action even if the prior file was
        // paused. The persistent bridge preserves this order after loadfile.
        root.mpvSend(["set_property", "pause", false])
        root.mpPlaying = true
    }

    function nextLocalTrack() {
        if (root.localTracks.length === 0) return
        var i = root.localTrackIndex >= 0
                ? (root.localTrackIndex + 1) % root.localTracks.length : 0
        root.playLocalTrack(root.localTracks[i])
    }

    function prevLocalTrack() {
        if (root.localTracks.length === 0) return
        var i = root.localTrackIndex >= 0
                ? (root.localTrackIndex - 1 + root.localTracks.length) % root.localTracks.length
                : root.localTracks.length - 1
        root.playLocalTrack(root.localTracks[i])
    }

    readonly property string currentUser: String(Quickshell.env("USER") || "user")

    property string menuActiveMonitor: Quickshell.screens.length>0 ? Quickshell.screens[0].name : ""
    signal menuFireToggle()

    Process {
        id: detectMonitor
        command: ["/bin/sh", Qt.resolvedUrl("active-monitor.sh").toString().replace("file://","")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var name = this.text.trim()
                if (name !== "") root.menuActiveMonitor = name
                root.menuFireToggle()
            }
        }
    }

    ShellIpc {
        onMenuRequested: {
            if (!detectMonitor.running) detectMonitor.running = true
        }
        onPlayerRequested: {
            if (!root.playerVisible) root.playerOnTop = true
            root.playerVisible = !root.playerVisible
        }
        onPlayerShowRequested: {
            root.playerOnTop = true
            root.playerVisible = true
        }
        onPlayerHideRequested: root.playerVisible = false
        onFrontRequested: root.playerOnTop = !root.playerOnTop
    }

    // ── MENU ──
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen:modelData
            anchors.top:true;anchors.left:true;anchors.right:true;anchors.bottom:true
            exclusionMode:ExclusionMode.Ignore
            aboveWindows:menuItem.menuOpen||menuItem.wipeHideRunning
            color:"transparent"
            visible:menuItem.menuOpen||menuItem.wipeHideRunning
            WlrLayershell.keyboardFocus:menuItem.menuOpen?WlrKeyboardFocus.Exclusive:WlrKeyboardFocus.None
            implicitWidth:modelData.width;implicitHeight:modelData.height
            Menu{id:menuItem;anchors.fill:parent;screenW:modelData.width;screenH:modelData.height}
            Connections{target:root;function onMenuFireToggle(){
                if(root.menuActiveMonitor!==modelData.name)return
                if(menuItem.menuOpen)menuItem.closeMenu();else menuItem.openMenu()
            }}
        }
    }

    // ── PLAYER ──
    Variants {
        model:Quickshell.screens
        PanelWindow {
            required property var modelData;screen:modelData
            anchors.top:true;anchors.right:true
            margins.top:Math.round(modelData.height*Settings.playerPositionY);margins.right:Settings.playerMarginRight
            exclusionMode:ExclusionMode.Ignore
            WlrLayershell.namespace: "tsugumori-player"
            WlrLayershell.layer: root.playerOnTop ? WlrLayer.Overlay : WlrLayer.Bottom
            color:"transparent"
            implicitWidth:Settings.playerWidth;implicitHeight:playerItem.implicitHeight
            // Real input-accepting region — must track the ACTUAL current visible content
            // (collapsed or expanded, per the drawer state), not the padded window buffer
            // above. Without this, a transparent layer-shell surface claims pointer input
            // across its whole rectangle regardless of what's drawn, silently blocking
            // clicks/scroll/hover in the empty space below the real content. When the
            // player is hidden (mid wipe-out/before wipe-in), the mask collapses to
            // nothing so the screen area is fully click-through.
            mask: Region {
                x: playerItem.currentInputX; y: 0
                width: playerItem.currentInputWidth
                height: playerItem.currentInputWidth > 0 ? playerItem.currentContentHeight : 0
            }
            Player{id:playerItem;anchors.fill:parent
                mpTitle:root.mpTitle;mpArtist:root.mpArtist;mpCoverUrl:root.mpCoverUrl
                mpPlaying:root.mpPlaying;mpPosition:root.mpPosition;mpLength:root.mpLength
                localTracks:root.localTracks
                localMode:root.localMode
                mediaAvailable:root.localMode || root.externalMediaAvailable
                requestedVisible:root.playerVisible
                localTrackIndex:root.localTrackIndex
                onPlayPause:root.togglePlayback()
                onNextTrack:root.nextTrack()
                onPrevTrack:root.previousTrack()
                onLocalTrackSelected: function(path){ root.playLocalTrack(path) }
                onShowTrackListChanged: {
                    // Re-scan on open so newly added files show up without a full
                    // QuickShell restart — the original scan only ever ran once at startup.
                    if (showTrackList) root.requestMusicScan()
                }
                onSeekToSecs: function(secs){ root.seekTo(secs) }
            }
        }
    }

    Component.onCompleted: {
        root.requestMusicScan()
        root.reselectExternalPlayer()
    }
}
