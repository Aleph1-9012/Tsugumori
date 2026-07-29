import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "widgets"
import "components"
import "settings"

ShellRoot {
    id: root

    // ── NOTIFICATIONS ──
    Notifications {}

    // ── CONTROLCENTER ──
    ControlCenter {}


    // ── VOLUMEBAR ──
    VolumeBar {}

    // ── PLAYERCTL ──
    property bool   playerVisible: false
    property bool   playerOnTop:   false
    property string mpTitle:    "END OF EVANGELION"
    property string mpArtist:   "NEON GENESIS // ANNO"
    property string mpCoverUrl: ""
    property bool   mpPlaying:  false
    property real   mpPosition: 0
    property real   mpLength:   341

    Process {
        id: playerctlMeta
        command: ["playerctl","metadata","--format",
                  "{{title}}|{{artist}}|{{mpris:artUrl}}|{{status}}|{{position}}|{{mpris:length}}"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                var p = data.trim().split("|")
                if (p.length >= 4) {
                    if (p[0]) root.mpTitle    = p[0]
                    if (p[1]) root.mpArtist   = p[1]
                    root.mpCoverUrl = p[2] || ""
                    root.mpPlaying  = (p[3] === "Playing")
                    root.mpPosition = parseFloat(p[4] || "0") / 1000000
                    root.mpLength   = Math.max(1, parseFloat(p[5] || "341000000") / 1000000)
                }
            }
        }
    }
    Process { id: pcPlay; command: ["playerctl","play-pause"]; running: false }
    Process { id: pcNext; command: ["playerctl","next"];       running: false }
    Process { id: pcPrev; command: ["playerctl","previous"];   running: false }
    Timer { interval:1000; running:true; repeat:true; onTriggered: playerctlMeta.running=true }

    // ── LOCAL MUSIC ──
    property string homeDir: ""
    property var    localTracks: []
    property bool   localMode: false
    property string mpvSocket: "/tmp/mpv-tsugumori.sock"

    Process {
        id: getHomeProc
        command: ["sh","-c","echo $HOME"]
        running: true
        stdout: SplitParser { onRead: data => { var h=data.trim(); if(h!=="") { root.homeDir=h; musicScanProc.running=true } } }
    }

    Process {
        id: musicScanProc
        command: ["find", root.homeDir + "/Music", "-type","f","(",
                  "-iname","*.mp3","-o","-iname","*.flac","-o",
                  "-iname","*.wav","-o","-iname","*.m4a","-o",
                  "-iname","*.ogg",")"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n").filter(function(l){ return l.length>0 })
                root.localTracks = lines
            }
        }
    }

    Process {
        id: mpvProc
        command: ["mpv","--idle","--no-video","--input-ipc-server=" + root.mpvSocket]
        running: false
    }

    Process {
        id: mpvSendProc
        property string pendingCmd: ""
        command: ["python3", root.homeDir + "/.config/quickshell/scripts/mpv_ctl.py", root.mpvSocket, pendingCmd]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.indexOf("ERR") === 0 || this.text.trim() === "") {
                    if (!mpvProc.running) { mpvProc.running = true }
                }
            }
        }
    }

    function mpvSend(cmdArr) {
        mpvSendProc.pendingCmd = JSON.stringify({ command: cmdArr })
        mpvSendProc.running = true
    }

    property int localTrackIndex: -1

    function playLocalTrack(path) {
        root.localTrackIndex = root.localTracks.indexOf(path)
        root.localMode = true
        if (!mpvProc.running) { mpvProc.running = true }
        mpvSend(["loadfile", path, "replace"])
        root.mpPlaying = true
    }

    function nextLocalTrack() {
        if (root.localTracks.length === 0) return
        var i = (root.localTrackIndex + 1) % root.localTracks.length
        root.playLocalTrack(root.localTracks[i])
    }

    function prevLocalTrack() {
        if (root.localTracks.length === 0) return
        var i = (root.localTrackIndex - 1 + root.localTracks.length) % root.localTracks.length
        root.playLocalTrack(root.localTracks[i])
    }


    property string currentUser: "user"
    Process {
        id: getUserProc; command:["sh","-c","echo $USER"]; running:true
        stdout: SplitParser { onRead: data => { var u=data.trim(); if(u!=="") root.currentUser=u } }
    }

    property int _lastToggle: 0; property int _lastFront: 0
    property int _lastMenu:   0

    Process { id:chkToggle; command:["sh","-c","wc -l < /tmp/qs-toggle 2>/dev/null || echo 0"]; running:false
        stdout:StdioCollector{ onStreamFinished:{ var n=parseInt(this.text.trim())||0; if(n!==root._lastToggle){root._lastToggle=n;root.playerVisible=!root.playerVisible} }}
    }
    Process { id:chkFront; command:["sh","-c","wc -l < /tmp/qs-front 2>/dev/null || echo 0"]; running:false
        stdout:StdioCollector{ onStreamFinished:{ var n=parseInt(this.text.trim())||0; if(n!==root._lastFront){root._lastFront=n;root.playerOnTop=!root.playerOnTop} }}
    }
    Process { id:chkMenu; command:["sh","-c","wc -l < /tmp/qs-menu 2>/dev/null || echo 0"]; running:false
        stdout:StdioCollector{ onStreamFinished:{ var n=parseInt(this.text.trim())||0; if(n!==root._lastMenu){root._lastMenu=n;detectMonitor.running=true} }}
    }

    Timer { interval:200; running:true; repeat:true
        onTriggered:{ chkToggle.running=true;chkFront.running=true;chkMenu.running=true }
    }

    Component.onCompleted: {
        Qt.createQmlObject(
            'import Quickshell.Io; Process{command:["sh","-c","rm -f /tmp/qs-menu /tmp/qs-toggle /tmp/qs-front"];running:true}',
            root, "cleanup")
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
            margins.top:Math.round(modelData.height*Settings.playerPositionY);margins.right:20
            exclusionMode:ExclusionMode.Ignore;aboveWindows:root.playerOnTop;color:"transparent"
            implicitWidth:Settings.playerWidth;implicitHeight:playerItem.implicitHeight
            Player{id:playerItem;anchors.fill:parent
                mpTitle:root.mpTitle;mpArtist:root.mpArtist;mpCoverUrl:root.mpCoverUrl
                mpPlaying:root.mpPlaying;mpPosition:root.mpPosition;mpLength:root.mpLength
                localTracks:root.localTracks
                onPlayPause:{ if(root.localMode){root.mpvSend(["cycle","pause"])} else {pcPlay.running=true} }
                onNextTrack:{ if(root.localMode){root.nextLocalTrack()} else {pcNext.running=true} }
                onPrevTrack:{ if(root.localMode){root.prevLocalTrack()} else {pcPrev.running=true} }
                onLocalTrackSelected: function(path){ root.playLocalTrack(path) }
            }
            Connections{target:root;function onPlayerVisibleChanged(){playerItem.toggleVisible()}}
        }
    }


    // ── COMPANIONS ──
    Variants {
        model:Settings.companionsEnabled ? Quickshell.screens : []
        PanelWindow {
            required property var modelData;screen:modelData
            anchors.bottom:true;anchors.right:true;margins.right:Settings.companionsMarginRight
            exclusionMode:ExclusionMode.Ignore;color:"transparent"
            implicitWidth:Settings.companionsSpriteSize+58;implicitHeight:compItem.implicitHeight
            Companions{id:compItem;anchors.fill:parent}
        }
    }
}
