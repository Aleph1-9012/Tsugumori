import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "widgets"
import "components"
import "settings"
import "services"

ShellRoot {
    id: root

    // ── NOTIFICATIONS ──
    Notifications { id: notificationDaemon }

    // ── CONTROLCENTER ──
    ControlCenter { notificationSource: notificationDaemon }

    // Standalone notes drawer, separate from the Control Center.
    QuickNotes { id: quickNotes }

    // Visual clipboard history, separate from the Control Center and notes.
    Clipboard { id: clipboardDrawer }

    property bool playerVisible: false
    property bool playerOnTop: true

    PlayerService {
        id: playerService
        playerVisible: root.playerVisible
    }

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
        onClipboardShowRequested: clipboardDrawer.show()
        onClipboardHideRequested: clipboardDrawer.hide()
        onClipboardToggleRequested: clipboardDrawer.toggle()
        onNotesShowRequested: quickNotes.show()
        onNotesHideRequested: quickNotes.hide()
        onNotesToggleRequested: quickNotes.toggle()
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
            id: playerWindow
            required property var modelData;screen:modelData
            visible: playerItem.presentationActive
            anchors.top:true;anchors.right:true
            // Keep the collapsed player anchored while Local Tracks expands below it.
            margins.top:Math.max(0, Math.round((modelData.height-playerItem.collapsedHeight)*Settings.playerPositionY))
            margins.right:Settings.playerMarginRight
            exclusionMode:ExclusionMode.Ignore
            WlrLayershell.namespace: "tsugumori-player"
            WlrLayershell.layer: root.playerOnTop ? WlrLayer.Overlay : WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color:"transparent"
            implicitWidth:Math.min(Settings.playerWidth, Math.max(1, modelData.width-2*Settings.playerMarginRight))
            implicitHeight:Math.min(playerItem.implicitHeight, Math.max(1, modelData.height-playerWindow.margins.top))
            // Real input-accepting region — must track the ACTUAL current visible content
            // (collapsed or expanded, per the drawer state), not the padded window buffer
            // above. Without this, a transparent layer-shell surface claims pointer input
            // across its whole rectangle regardless of what's drawn, silently blocking
            // clicks/scroll/hover in the empty space below the real content. When the
            // player is hidden (mid wipe-out/before wipe-in), the mask collapses to
            // nothing so the screen area is fully click-through.
            mask: Region {
                x: playerItem.currentInputX; y: playerItem.y
                width: playerItem.currentInputWidth
                height: playerItem.currentInputWidth > 0 ? playerItem.currentContentHeight : 0
            }
            Player{id:playerItem;width:parent.width;height:parent.height
                mpTitle:playerService.mpTitle;mpArtist:playerService.mpArtist;mpCoverUrl:playerService.mpCoverUrl
                mpAlbum:playerService.mpAlbum;mpTrackNumber:playerService.mpTrackNumber;mpMediaKey:String(playerService.mediaRevision)
                mpPlaying:playerService.mpPlaying;mpPosition:playerService.mpPosition;mpLength:playerService.mpLength
                canPlayPause:playerService.localMode ? playerService.localTrackPath.length > 0 : Boolean(playerService.externalPlayer && playerService.externalPlayer.canTogglePlaying)
                canGoNext:playerService.localMode ? playerService.localTracks.length > 0 : Boolean(playerService.externalPlayer && playerService.externalPlayer.canGoNext)
                canGoPrevious:playerService.localMode ? playerService.localTracks.length > 0 : Boolean(playerService.externalPlayer && playerService.externalPlayer.canGoPrevious)
                canSeek:playerService.localMode ? playerService.mpLength > 0 : Boolean(playerService.externalPlayer && playerService.externalPlayer.canSeek && playerService.externalPlayer.positionSupported)
                availableHeight:Math.max(0, modelData.height-playerWindow.margins.top-Math.round(20*Settings.scale))
                localTracks:playerService.localTracks
                localMode:playerService.localMode
                mediaAvailable:playerService.localMode || playerService.externalMediaAvailable
                requestedVisible:root.playerVisible
                localTrackIndex:playerService.localTrackIndex
                onPlayPause:playerService.togglePlayback()
                onNextTrack:playerService.nextTrack()
                onPrevTrack:playerService.previousTrack()
                onLocalTrackSelected: function(path){ playerService.playLocalTrack(path) }
                onShowTrackListChanged: {
                    // Scan on demand, including the first open, so login does
                    // not walk a music library the user may never open.
                    if (showTrackList) playerService.requestMusicScan()
                }
                onSeekToSecs: function(secs){ playerService.seekTo(secs) }
            }
        }
    }
}
