import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"
import "../components/controlcenter"

// ═════════════════════════════════════════════════════════════════════
//   Knights of Sidonia Control Center — Quickshell module
//   Live services with the approved B2 control-center presentation
//   IPC : qs ipc call ctrl toggle
// ═════════════════════════════════════════════════════════════════════

ShellRoot {
    id: root

    // ── Paths ──
    property string home:          Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    readonly property string runtimeBase: Quickshell.env("XDG_RUNTIME_DIR") || (home + "/.cache/tsugumori/runtime")
    readonly property string runtimeDir: runtimeBase + (Quickshell.env("XDG_RUNTIME_DIR") ? "/tsugumori" : "")
    Process {
        id: runtimeInitProc
        command: ["install", "-d", "-m", "700", root.runtimeDir]
        running: true
    }

    // ── State ──
    property bool   open:    false
    property bool   closing: false   // intermediate state: slots return to center, then fade
    property int    level:   1
    property string slot:    "center"
    property string sub:     ""
    property string action:  ""
    property bool keyboardNavigation: false
    property bool reducedMotion: false
    property var lastSubs: ({})

    // ── Data ──
    readonly property var subs: ({
        top:    [ {key:"wifi",      label:"Wi-Fi"},
                  {key:"bluetooth", label:"Bluetooth"} ],
        bottom: [ {key:"output",    label:"Output"},
                  {key:"volume",    label:"Volume"},
                  {key:"brightness",label:"Brightness"},
                  {key:"gpu",       label:"GPU"} ],
        left:   [ {key:"send",      label:"Send"},
                  {key:"receive",   label:"Receive"} ],
        right:  [ {key:"history",   label:"History"},
                  {key:"dnd",       label:"Do Not Disturb"} ]
    })

    readonly property var details: ({
        "top.wifi":         {h3:"Wi-Fi",               status:"—",    on:false,
                              actions:[{key:"toggle",label:"Toggle Wi-Fi"}]},
        "top.bluetooth":    {h3:"Bluetooth",           status:"—",    on:false,
                              actions:[{key:"toggle",label:"Toggle Bluetooth"}]},
        "bottom.output":    {h3:"Audio Output",        status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "bottom.volume":    {h3:"Volume",              status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "bottom.brightness":{h3:"Brightness",          status:"—",    on:false,
                              actions:[]},
        "left.send":        {h3:"Send Files",          status:"Ready", on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "left.receive":     {h3:"Receive Files",       status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "right.history":    {h3:"Notification History",status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "right.dnd":        {h3:"Do Not Disturb",      status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]}
    })

    function detailKey() { return slot + "." + sub }
    function subList(s)  { return root.subs[s] || [] }

    function summaryForSlot(key) {
        if (key === "top") return [
            wifiEnabled ? (wifiCurrentSSID || "Wi-Fi enabled") : "Wi-Fi disabled",
            "WI-FI " + (wifiEnabled ? "ON" : "OFF"), "BT " + (btEnabled ? "ON" : "OFF")]
        if (key === "bottom") {
            var sink = audioSinks.find(function(item) { return item.isDefault })
            return [sink ? sink.description : audioDefaultSink || "No output",
                "VOL " + (audioMuted ? "MUTE" : Math.round(audioVolume * 100) + "%"),
                "BRT " + (brightnessAvailable ? Math.round(brightnessLevel * 100) + "%" : "—")]
        }
        if (key === "right") return [notifications.length + " notifications", "HISTORY", "DND " + (dndEnabled ? "ON" : "OFF")]
        if (key === "left") return [qshareUrl ? "Transfer active" : "Send / receive", qshareUrl ? "ACTIVE" : "READY", qshareTunnel ? "INTERNET" : "LOCAL"]
        return ["", "", ""]
    }

    // ── Build the action list dynamically for the focused sub-menu ──
    function actList() {
        var key = detailKey()
        // Wi-Fi: toggle plus one button per scanned network.
        if (key === "top.wifi") {
            var acts = [{key:"toggle", label: wifiEnabled ? "Disable Wi-Fi" : "Enable Wi-Fi", primary:true}]
            if (wifiEnabled) {
                for (var i = 0; i < wifiNetworks.length; i++) {
                    var n = wifiNetworks[i]
                    acts.push({
                        key: "connect:" + n.ssid,
                        label: n.ssid, kind:"row", selected:!!n.active,
                        signalBars:n.signal >= 75 ? 3 : n.signal >= 50 ? 2 : n.signal >= 25 ? 1 : 0,
                        secured:!!n.security && n.security !== "--"
                    })
                }
            }
            return acts
        }
        // Bluetooth
        if (key === "top.bluetooth") {
            var acts2 = [{key:"toggle", label: btEnabled ? "Disable Bluetooth" : "Enable Bluetooth", primary:true}]
            if (btEnabled) {
                acts2.push({key: "scan", label: btScanning ? "Stop scanning" : "Scan for devices"})
                for (var j = 0; j < btDevices.length; j++) {
                    var d = btDevices[j]
                    var aKey
                    if (d.connected)      aKey = "disconnect:" + d.mac
                    else if (d.paired)    aKey = "connect:"    + d.mac
                    else                  aKey = "pair:"       + d.mac
                    acts2.push({key: aKey, identity:"device:" + d.mac, label:d.name, kind:"row", selected:!!d.connected,
                        metadata:d.connected ? "LINKED" : d.paired ? "PAIRED" : "NEW"})
                    if (d.paired) {
                        acts2.push({key: "remove:" + d.mac, label: "Remove " + d.name})
                    }
                }
            }
            return acts2
        }
        // Audio output: list of sinks.
        if (key === "bottom.output") {
            var acts3 = []
            for (var k = 0; k < audioSinks.length; k++) {
                var s = audioSinks[k]
                acts3.push({key: "set-sink:" + s.name, label: s.description, kind:"row", selected:!!s.isDefault})
            }
            if (acts3.length === 0) acts3.push({key:"none", label:"No outputs found"})
            return acts3
        }
        // Audio volume: no list, only the separately rendered slider.
        if (key === "bottom.volume") {
            return [{key:"mute-toggle", label: audioMuted ? "Unmute audio" : "Mute audio", primary:true}]
        }
        // GPU choices are staged until explicitly saved for the next login.
        if (key === "bottom.gpu") {
            var gpuActions = [{key:"select:auto", label:"Automatic", kind:"row",
                selected:gpuSelection === "auto", disabled:gpuBusy,
                metadata:gpuBadge("auto")}]
            for (var g = 0; g < gpuStatus.gpus.length; ++g) {
                var gpu = gpuStatus.gpus[g]
                gpuActions.push({key:"select:" + gpu.id, label:gpu.name + " / " + gpu.id,
                    kind:"row", selected:gpuSelection === gpu.id, disabled:gpuBusy,
                    metadata:gpuBadge(gpu.id)})
            }
            gpuActions.push({key:"save", label:"Save for next login", primary:true, disabled:!gpuCanSave})
            gpuActions.push({key:"refresh", label:"Refresh GPUs", disabled:gpuBusy})
            return gpuActions
        }
        // Quickshare Send (qshare.py)
        if (key === "left.send") {
            var acts4 = []
            acts4.push({key:"pick-file", label: pendingFilePath
                ? pendingFilePath.split("/").pop()
                : "Pick a file", primary:true})
            if (pendingFilePath !== "") {
                acts4.push({key:"clear-file", label: "Cancel selection"})
            }
            acts4.push({key:"toggle-tunnel",
                label:"Internet tunnel", metadata:qshareTunnel ? "ON" : "OFF"})
            acts4.push({key:"toggle-keepalive",
                label:"Keep alive", metadata:qshareKeepAlive ? "ON" : "OFF"})
            if (pendingFilePath !== "") {
                acts4.push({key:"start-send", label: "Generate QR", primary:true})
            }
            return acts4
        }
        // Quickshare Receive (qshare.py)
        if (key === "left.receive") {
            var acts5 = []
            var dirShort = qshareOutputDir.replace(home, "~")
            acts5.push({key:"cycle-output", label: "Output: " + dirShort})
            acts5.push({key:"toggle-tunnel",
                label:"Internet tunnel", metadata:qshareTunnel ? "ON" : "OFF"})
            acts5.push({key:"toggle-keepalive",
                label:"Keep alive", metadata:qshareKeepAlive ? "ON" : "OFF"})
            acts5.push({key:"start-recv", label: "Open receiver", primary:true})
            return acts5
        }
        // Notifications History
        if (key === "right.history") {
            var acts6 = []
            for (var p = 0; p < notifications.length; p++) {
                var n2 = notifications[p]
                acts6.push({
                    key: "notif:" + p,
                    identity:"notification:" + (n2.id === undefined ? p : n2.id),
                    label: n2.summary || "(empty)",
                    body: n2.body || "",
                    app: n2.app || "",
                    appIcon: n2.appIcon || "",
                    category: n2.category || "",
                    urgency: n2.urgency || "normal",
                    timeout: n2.timeout >= 0 ? n2.timeout : -1,
                    desktopEntry: n2.desktopEntry || "",
                    actions: n2.actions || [],
                    notifIdx: p
                })
            }
            return acts6
        }
        // Notifications DND
        if (key === "right.dnd") {
            return [{key:"toggle-dnd", label: dndEnabled ? "Disable do not disturb" : "Enable do not disturb", primary:true}]
        }
        // Other slots: static actions from the details dictionary.
        var dd = root.details[key]
        return dd ? dd.actions : []
    }

    function detailH3() {
        var key = detailKey()
        if (key === "top.wifi")          return "Wi-Fi"
        if (key === "top.bluetooth")     return "Bluetooth"
        if (key === "bottom.output")     return "Audio Output"
        if (key === "bottom.volume")     return "Volume"
        if (key === "bottom.brightness") return "Brightness"
        if (key === "bottom.gpu")        return "GPU / Primary Renderer"
        if (key === "left.send")         return "Send Files"
        if (key === "left.receive")      return "Receive Files"
        if (key === "right.history")     return "Notifications"
        if (key === "right.dnd")         return "Do Not Disturb"
        var d = root.details[key]
        return d ? d.h3 : ""
    }
    function detailStatus() {
        var key = detailKey()
        if (key === "top.wifi") {
            if (!wifiEnabled) return "Disabled"
            if (wifiCurrentSSID) return "Connected · " + wifiCurrentSSID
            return "Enabled · Scanning"
        }
        if (key === "top.bluetooth") {
            if (!btEnabled) return "Disabled"
            var connected = btDevices.filter(function(d){return d.connected})
            if (connected.length) return "Connected · " + connected[0].name
            return "Enabled · " + btDevices.length + " device" + (btDevices.length !== 1 ? "s" : "")
        }
        if (key === "bottom.output") {
            // Find the default sink description.
            for (var i = 0; i < audioSinks.length; i++) {
                if (audioSinks[i].isDefault) return audioSinks[i].description
            }
            return audioDefaultSink || "—"
        }
        if (key === "bottom.volume") {
            if (audioMuted) return "Muted"
            return Math.round(audioVolume * 100) + "%"
        }
        if (key === "bottom.brightness") {
            if (!brightnessAvailable) return "Unavailable"
            return Math.round(brightnessLevel * 100) + "%"
        }
        if (key === "bottom.gpu") {
            if (gpuBusy) return "Reading / saving GPU settings…"
            var gpuSummary = "Active · " + gpuActiveLabel()
            if (gpuFailed) return gpuSummary
            if (gpuSelection !== gpuStatus.saved) gpuSummary += "\nSelection not saved"
            else if (gpuStatus.pending) gpuSummary += "\nNext login · " + gpuLabel(gpuStatus.saved)
            return gpuSummary
        }
        if (key === "left.send") {
            if (pendingFilePath === "") return "Ready · pick a file"
            return qshareTunnel ? "Tunnel mode" : "LAN mode"
        }
        if (key === "left.receive") {
            return qshareTunnel ? "Tunnel · " + qshareOutputDir.replace(home, "~")
                                : "LAN · " + qshareOutputDir.replace(home, "~")
        }
        if (key === "right.history") {
            return notifications.length + " notification" + (notifications.length !== 1 ? "s" : "")
        }
        if (key === "right.dnd") {
            return dndEnabled ? "Active" : "Off"
        }
        var d2 = root.details[key]
        return d2 ? d2.status : ""
    }
    function detailOn() {
        var key = detailKey()
        if (key === "top.wifi")          return wifiEnabled
        if (key === "top.bluetooth")     return btEnabled
        if (key === "bottom.output")     return true
        if (key === "bottom.volume")     return !audioMuted
        if (key === "bottom.brightness") return brightnessAvailable
        if (key === "bottom.gpu")        return gpuActiveId !== ""
        if (key === "left.send")         return pendingFilePath !== ""
        if (key === "left.receive")      return qshareUrl !== ""
        if (key === "right.history")     return notifications.length > 0
        if (key === "right.dnd")         return dndEnabled
        var d3 = root.details[key]
        return d3 ? d3.on : false
    }
    // ── Desktop GPU preference (applied by UWSM at the next login) ──
    property var gpuStatus: ({ gpus: [], saved: "auto", session: "auto", active: null, supported: false })
    property string gpuSelection: "auto"
    property string gpuMessage: ""
    property bool gpuFailed: false
    readonly property bool gpuBusy: gpuProc.running
    readonly property string gpuActiveId: !gpuFailed && gpuStatus.active
        && gpuStatus.gpus.some(function(gpu) { return gpu.id === gpuStatus.active }) ? gpuStatus.active : ""
    readonly property bool gpuCanSave: !gpuBusy && !gpuFailed
        && gpuSelection !== gpuStatus.saved
        && ((gpuStatus.supported && gpuStatus.gpus.length > 1)
            || (gpuSelection === "auto" && gpuStatus.saved !== "auto"))

    function gpuLabel(id) {
        if (id === "auto") return "Automatic"
        for (var i = 0; i < gpuStatus.gpus.length; ++i)
            if (gpuStatus.gpus[i].id === id) return gpuStatus.gpus[i].name
        return "Unavailable GPU " + id
    }

    function gpuActiveLabel() {
        return gpuActiveId ? gpuLabel(gpuActiveId) : "UNKNOWN"
    }

    function gpuBadge(id) {
        if (gpuFailed) return ""
        var badges = []
        if (id === gpuActiveId) badges.push("ACTIVE")
        if (gpuStatus.pending && id === gpuStatus.saved) badges.push("NEXT LOGIN")
        return badges.join(" / ")
    }

    function gpuSelectionDetails() {
        if (gpuSelection === "auto") return "Let Hyprland choose its primary renderer."
        var gpu = gpuStatus.gpus.find(function(item) { return item.id === gpuSelection })
        if (!gpu) return "This GPU is unavailable; login will fall back to automatic selection."
        return gpu.name + "\n" + gpu.id + " / " + gpu.driver
            + (gpu.outputs.length ? "\nDisplays: " + gpu.outputs.join(", ") : "")
    }

    function gpuRequest(request) {
        if (gpuBusy || (request === "save" && !gpuCanSave)) return
        gpuMessage = ""
        gpuFailed = false
        gpuProc.command = ["python3", Qt.resolvedUrl("../scripts/gpu_ctl.py").toString().replace("file://", ""), request]
            .concat(request === "save" ? [gpuSelection] : [])
        gpuProc.running = true
        gpuTimeout.restart()
    }

    Process {
        id: gpuProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                gpuTimeout.stop()
                try {
                    var result = JSON.parse(this.text)
                    if (!result.ok) throw new Error(result.error || "GPU settings could not be read.")
                    if (!Array.isArray(result.gpus) || typeof result.saved !== "string")
                        throw new Error("Invalid GPU information returned.")
                    root.gpuStatus = result
                    root.gpuSelection = result.saved
                    root.gpuMessage = result.message || ""
                } catch (error) {
                    root.gpuFailed = true
                    root.gpuMessage = String(error.message || error)
                }
            }
        }
        onExited: exitCode => {
            gpuTimeout.stop()
            if (exitCode !== 0 && !root.gpuFailed) {
                root.gpuFailed = true
                root.gpuMessage = "GPU helper failed. No change was confirmed; refresh to check the saved choice."
            }
        }
    }
    Timer {
        id: gpuTimeout
        interval: 12000
        onTriggered: {
            gpuProc.running = false
            root.gpuFailed = true
            root.gpuMessage = "GPU helper timed out. Refresh to check the saved choice."
        }
    }

    // ── System data: Wi-Fi ──
    // Public names stay on root so the presentation and keyboard flow are unchanged.
    property alias wifiEnabled: wifiService.enabled
    property alias wifiCurrentSSID: wifiService.currentSsid
    property alias wifiNetworks: wifiService.networks
    property alias wifiPasswordInput: wifiService.passwordInput
    property int wifiPasswordClearSerial: 0
    property string wifiPromptSSID: ""   // SSID whose password is being entered (empty = no prompt)
    property string wifiError: ""        // error message after a failed connection

    WifiService {
        id: wifiService
        helperPath: root.networkScriptPath
        active: root.open

        onPasswordConnectionFinished: success => {
            if (success) {
                root.wifiPromptSSID = ""
                root.wifiError = ""
            } else {
                root.wifiError = "Connection failed"
            }
        }
        onPasswordConsumed: root.wifiPasswordClearSerial += 1
    }

    // ── System data: Bluetooth ──
    property bool   btEnabled: false
    property var    btDevices: []   // [{name, mac, connected, paired}]
    property bool   btScanning: false

    // ── System data: Audio ──
    property var    audioSinks: []        // [{name, description, default}]
    property string audioDefaultSink: ""
    property real   audioVolume: 0.5      // 0.0 - 1.0
    property bool   audioMuted: false
    property int pendingAudioPercent: -1

    Timer {
        interval: 1500; running: root.open; repeat: true; triggeredOnStart: true
        onTriggered: pollAudio.running = true
    }
    Process {
        id: pollAudio
        command: ["sh","-c",
            "echo \"DEFAULT:$(pactl get-default-sink 2>/dev/null)\"; " +
            "echo \"VOLUME:$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\\d+%' | head -1 | tr -d '%')\"; " +
            "echo \"MUTE:$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}')\"; " +
            "pactl list short sinks 2>/dev/null | while read line; do " +
            "  id=$(echo \"$line\" | awk '{print $1}'); " +
            "  name=$(echo \"$line\" | awk '{print $2}'); " +
            "  desc=$(pactl list sinks 2>/dev/null | awk -v n=\"$name\" '$1==\"Name:\" && $2==n{f=1} f && /Description:/{$1=\"\"; print substr($0,2); exit}'); " +
            "  echo \"SINK:$name|$desc\"; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var sinks = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i]
                    if (line.indexOf("DEFAULT:") === 0) {
                        root.audioDefaultSink = line.substring(8).trim()
                    } else if (line.indexOf("VOLUME:") === 0) {
                        var v = parseInt(line.substring(7))
                        if (!isNaN(v) && root.pendingAudioPercent < 0 && !volumeWriteTimer.running && !setVolumeProc.running)
                            root.audioVolume = v / 100
                    } else if (line.indexOf("MUTE:") === 0) {
                        root.audioMuted = line.substring(5).trim() === "yes"
                    } else if (line.indexOf("SINK:") === 0) {
                        var parts = line.substring(5).split("|")
                        sinks.push({
                            name: parts[0],
                            description: parts[1] || parts[0],
                            isDefault: parts[0] === root.audioDefaultSink
                        })
                    }
                }
                // Mark the default sink on a second pass in case it was read after the sinks.
                for (var j = 0; j < sinks.length; j++) {
                    sinks[j].isDefault = sinks[j].name === root.audioDefaultSink
                }
                root.audioSinks = sinks
            }
        }
    }

    // Keep the last slider value even while a previous write is still running.
    function setAudioPercent(value) {
        var percent = Math.max(0, Math.min(100, Math.round(value)))
        audioVolume = percent / 100
        pendingAudioPercent = percent
        if (!volumeWriteTimer.running) volumeWriteTimer.start()
    }
    function flushVolume() {
        if (setVolumeProc.running || pendingAudioPercent < 0) return
        var percent = pendingAudioPercent
        pendingAudioPercent = -1
        setVolumeProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", percent + "%"]
        setVolumeProc.running = true
    }
    Timer { id: volumeWriteTimer; interval: 60; onTriggered: root.flushVolume() }
    Process {
        id: setVolumeProc
        running: false
        onExited: exitCode => {
            if (exitCode !== 0) console.warn("ControlCenter: volume update failed")
            if (root.pendingAudioPercent >= 0) root.flushVolume()
            else pollAudio.running = true
        }
    }

    // ── System data: Display brightness ──
    property real   brightnessLevel: 1.0
    property bool   brightnessAvailable: false
    property string brightnessLoadingMonitor: ""
    property int    brightnessRequestedPercent: 100
    property int    brightnessPendingPercent: -1
    property string brightnessPendingMonitor: ""
    property var    brightnessByMonitor: ({})

    function monitorBrightness(name) {
        var value = brightnessByMonitor[name]
        return value === undefined ? 1.0 : Math.max(0.01, Math.min(1.0, value))
    }

    function rememberMonitorBrightness(name, value) {
        if (name === "") return
        var next = {}
        for (var key in brightnessByMonitor)
            next[key] = brightnessByMonitor[key]
        next[name] = Math.max(0.01, Math.min(1.0, value))
        brightnessByMonitor = next
    }

    function brightnessStatePath(name) {
        return runtimeDir + "/brightness-" + name
    }

    function loadBrightness() {
        if (setBrightnessProc.running || brightnessPendingPercent >= 0
                || loadBrightnessProc.running)
            return

        var monitor = activeMonitor
        if (monitor === "") return

        brightnessLoadingMonitor = monitor
        loadBrightnessProc.command = ["sh", "-c",
            "if [ -r \"$1\" ]; then cat -- \"$1\"; else printf '100\\n'; fi",
            "brightness-state", brightnessStatePath(monitor)]
        loadBrightnessProc.running = true
    }

    Process {
        id: loadBrightnessProc
        command: []
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                // Do not let a load overwrite a drag that is being applied.
                if (root.brightnessPendingPercent >= 0 || setBrightnessProc.running)
                    return
                root.brightnessAvailable = false

                var percent = parseInt(this.text.trim())
                if (isNaN(percent)) return
                percent = Math.max(1, Math.min(100, percent))
                root.brightnessLevel = percent / 100
                root.brightnessRequestedPercent = percent
                root.rememberMonitorBrightness(root.brightnessLoadingMonitor,
                    root.brightnessLevel)
                root.brightnessAvailable = true
            }
        }
    }

    Process {
        id: setBrightnessProc
        property int appliedPercent: -1
        property string appliedMonitor: ""
        command: []
        running: false
        stderr: StdioCollector { id: brightnessSetError }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.brightnessAvailable = false
                console.warn("Brightness write failed:", brightnessSetError.text.trim())
            }
            if (root.brightnessPendingPercent >= 0
                    && (root.brightnessPendingPercent !== appliedPercent
                        || root.brightnessPendingMonitor !== appliedMonitor)) {
                root.startBrightnessWrite()
                return
            }
            root.brightnessPendingPercent = -1
            root.brightnessPendingMonitor = ""
            if (exitCode === 0)
                root.brightnessAvailable = true
        }
    }

    function setBrightnessPercent(value, monitorName) {
        if (!brightnessAvailable) return
        var monitor = monitorName || activeMonitor
        if (monitor === "") return
        var percent = Math.max(1, Math.min(100, Math.round(value)))
        brightnessRequestedPercent = percent
        brightnessLevel = percent / 100
        rememberMonitorBrightness(monitor, brightnessLevel)
        brightnessPendingPercent = percent
        brightnessPendingMonitor = monitor
        if (!setBrightnessProc.running)
            startBrightnessWrite()
    }

    function startBrightnessWrite() {
        if (setBrightnessProc.running || brightnessPendingPercent < 0) return
        var monitor = brightnessPendingMonitor
        if (!/^[A-Za-z0-9_.:-]+$/.test(monitor)) {
            brightnessPendingPercent = -1
            brightnessPendingMonitor = ""
            brightnessAvailable = false
            return
        }

        setBrightnessProc.appliedPercent = brightnessPendingPercent
        setBrightnessProc.appliedMonitor = monitor
        brightnessPendingPercent = -1
        brightnessPendingMonitor = ""

        setBrightnessProc.command = ["sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"",
            "brightness-state", String(setBrightnessProc.appliedPercent),
            brightnessStatePath(monitor)]
        setBrightnessProc.running = true
    }

    // ── Notifications via IPC to Notifications.qml (which owns the D-Bus bus) ──
    property bool dndEnabled: false
    property var notifications: []     // [{id, summary, body, app, ts}]
    property int expandedNotifIdx: -1  // expanded notification index (-1 = none)

    // Poll notification history from the Notifications.qml daemon via IPC.
    Timer {
        interval: 1500
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            pollNotifsHistory.running = true
            pollNotifsDnd.running = true
        }
    }
    Process {
        id: pollNotifsHistory
        command: ["sh","-c","qs ipc call notifs getHistory 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text.trim() || "[]")
                    root.notifications = parsed
                } catch(e) {
                    root.notifications = []
                }
            }
        }
    }
    Process {
        id: pollNotifsDnd
        command: ["sh","-c","qs ipc call notifs getDnd 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.dndEnabled = this.text.trim() === "true"
            }
        }
    }
    // Process for actions sent to the notification daemon.
    Process {
        id: notifActProc
        command: ["sh","-c","true"]
        running: false
    }

    // Helpers: call the daemon IPC.
    function dismissNotif(idx) {
        notifActProc.command = ["sh","-c","qs ipc call notifs dismissAt " + idx]
        notifActProc.running = true
        // Refresh local state immediately (optimistic update).
        var list = root.notifications.slice()
        list.splice(idx, 1)
        root.notifications = list
        root.expandedNotifIdx = -1
    }
    function dismissAllNotifs() {
        notifActProc.command = ["sh","-c","qs ipc call notifs clearAll"]
        notifActProc.running = true
        root.notifications = []
        root.expandedNotifIdx = -1
    }
    function invokeNotif(idx) {
        // The daemon invokes and dismisses in one call.
        dismissNotif(idx)
    }
    function setDnd(state) {
        notifActProc.command = ["sh","-c","qs ipc call notifs setDnd " + (state ? "true" : "false")]
        notifActProc.running = true
        dndEnabled = state
    }

    // ── System data: Quickshare (qshare.py) ──
    property string pendingFilePath: ""   // selected file path waiting to be sent

    // ── qshare state ──
    property bool   qshareTunnel:    false
    property bool   qshareKeepAlive: false
    property string qshareOutputDir: home + "/Downloads"
    property string qshareUrl:       ""     // active URL (modal visible when non-empty)
    property string qshareQrPath:    ""     // QR PNG path
    property string qshareLabel:     ""     // e.g. "sending: photo.jpg" or "receiving → ~/Downloads"
    property string qshareLastTick:  ""     // last file transferred (for feedback)
    property bool   qshareCancelled: false
    property string qshareRunId:     "idle"
    readonly property string qshareScriptPath: xdgConfigHome + "/quickshell/scripts/qshare.py"
    readonly property string networkScriptPath: xdgConfigHome + "/quickshell/scripts/network_ctl.py"
    readonly property string filePickerScriptPath: xdgConfigHome + "/quickshell/scripts/launch_file_picker.py"
    readonly property string qshareEventFile: runtimeDir + "/qshare-events-" + qshareRunId
    readonly property string qshareQrFile: runtimeDir + "/qshare-qr-" + qshareRunId + ".png"

    readonly property var qshareOutputDirs: [
        home + "/Downloads",
        home + "/Pictures",
        home + "/Documents",
        "/tmp"
    ]

    // Open a graphical picker to choose a file.
    Process {
        id: filePickerProc
        running: false
        command: ["python3", root.filePickerScriptPath]
        // The graphical picker exits after writing the selected path.
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) filePickerReadProc.running = true
        }
    }
    Process {
        id: filePickerReadProc
        command: ["python3", root.filePickerScriptPath, "--read-choice"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                // Remove the helper's final newline, preserving filename spaces.
                var path = this.text.replace(/\n$/, "")
                if (path) {
                    root.pendingFilePath = path
                    // Reopen the Control Center on left.send with the selected file.
                    if (!root.open) {
                        root.open = true
                        root.closing = false
                        root.level = 3
                        root.slot = "left"
                        root.sub = "send"
                        root.action = root.firstAction()
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //   qshare.py — process, event polling, start/stop
    // ═══════════════════════════════════════════════════════════════════

    function startQshare(mode, filePath) {
        // Keep the active process bound to the run-specific event and QR files.
        if (qshareProc.running)
            return

        // Reset state
        root.qshareRunId = Date.now().toString()
        root.qshareUrl = ""
        root.qshareQrPath = ""
        root.qshareLastTick = ""
        root.qshareCancelled = false

        // Build the command.
        var args = ["python3", qshareScriptPath, mode]
        if (mode === "send") {
            args.push(filePath)
            qshareLabel = "sending: " + filePath.split("/").pop()
        } else {
            args.push("-o"); args.push(qshareOutputDir)
            qshareLabel = "receiving → " + qshareOutputDir.replace(home, "~")
        }
        if (qshareTunnel)    args.push("--tunnel")
        if (qshareKeepAlive) args.push("--keep-alive")
        args.push("--qr-out");     args.push(qshareQrFile)
        args.push("--event-file"); args.push(qshareEventFile)

        qshareProc.command = args
        qshareProc.running = true
        qshareEventPoll.running = true
    }

    function stopQshare() {
        qshareCancelled = true
        qshareProc.running = false   // SIGTERM
        qshareEventPoll.running = false
        qshareUrl = ""
        qshareQrPath = ""
        // Reset pendingFilePath after a send.
        pendingFilePath = ""
    }

    Process {
        id: qshareProc
        running: false
        command: ["sh","-c","true"]
        // stdout/stderr ignored — rely on the event file.
        onRunningChanged: {
            if (!running) {
                // Process finished → close the modal after a short delay to
                // Give the final tick time to appear.
                qshareEventPoll.running = false
                qshareCloseTimer.restart()
            }
        }
    }

    Timer {
        id: qshareCloseTimer
        interval: qshareCancelled ? 0 : 600
        repeat: false
        onTriggered: {
            qshareUrl = ""
            qshareQrPath = ""
            qshareLastTick = ""
            qshareCleanupProc.command = ["rm", "-f", root.qshareEventFile, root.qshareQrFile]
            qshareCleanupProc.running = true
            // Reset pendingFilePath after a successful send transfer.
            if (!qshareCancelled && root.sub === "send") {
                pendingFilePath = ""
            }
        }
    }

    Process {
        id: qshareCleanupProc
        running: false
    }

    // Poll the event file for URL/QR/TICK/DONE.
    Timer {
        id: qshareEventPoll
        interval: 500
        repeat: true
        running: false
        onTriggered: qshareEventReader.running = true
    }

    Process {
        id: qshareEventReader
        running: false
        command: ["cat", root.qshareEventFile]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (!line) continue
                    if (line.indexOf("URL ") === 0) {
                        root.qshareUrl = line.substring(4)
                    } else if (line.indexOf("QR ") === 0) {
                        root.qshareQrPath = line.substring(3)
                    } else if (line.indexOf("TICK ") === 0) {
                        root.qshareLastTick = line.substring(5)
                    } else if (line === "DONE") {
                        // The process stops on its own; onRunningChanged handles it.
                    } else if (line === "CANCELLED") {
                        root.qshareCancelled = true
                    }
                }
            }
        }
    }

    Timer {
        interval: 3000; running: root.open; repeat: true; triggeredOnStart: true
        onTriggered: pollBt.running = true
    }
    Process {
        id: pollBt
        // Fetch powered state and all devices (paired and discovered),
        // including connected and paired state for differentiation.
        command: ["sh","-c",
            "echo \"$(bluetoothctl show 2>/dev/null | grep -i 'powered:' | awk '{print $2}')\"; " +
            "bluetoothctl devices 2>/dev/null | while read line; do " +
            "  mac=$(echo \"$line\" | awk '{print $2}'); " +
            "  name=$(echo \"$line\" | cut -d' ' -f3-); " +
            "  info=$(bluetoothctl info \"$mac\" 2>/dev/null); " +
            "  conn=$(echo \"$info\" | grep -i 'Connected:' | awk '{print $2}'); " +
            "  paired=$(echo \"$info\" | grep -i 'Paired:' | awk '{print $2}'); " +
            "  trusted=$(echo \"$info\" | grep -i 'Trusted:' | awk '{print $2}'); " +
            "  echo \"$mac|$name|$conn|$paired|$trusted\"; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                root.btEnabled = (lines[0] || "").trim() === "yes"
                var seen = ({})
                for (var i = 1; i < lines.length; i++) {
                    var parts = lines[i].split("|")
                    if (parts.length < 4) continue
                    var mac = parts[0]
                    if (!mac || seen[mac]) continue
                    seen[mac] = {
                        mac: mac,
                        name: parts[1] || mac,
                        connected: (parts[2] || "").trim() === "yes",
                        paired:    (parts[3] || "").trim() === "yes",
                        trusted:   (parts[4] || "").trim() === "yes"
                    }
                }
                var devices = []
                for (var k in seen) devices.push(seen[k])
                // Sort: connected > paired > non-paired (discovered), then name.
                devices.sort(function(a,b){
                    if (a.connected !== b.connected) return a.connected ? -1 : 1
                    if (a.paired    !== b.paired)    return a.paired ? -1 : 1
                    return a.name.localeCompare(b.name)
                })
                root.btDevices = devices
            }
        }
    }

    // Process for Bluetooth scanning.
    Process {
        id: btScanProc
        command: ["sh","-c","bluetoothctl --timeout 30 scan on"]
        running: false
    }
    // Stop the automatic scan after 30s.
    Timer {
        id: btScanStopTimer
        interval: 30000
        repeat: false
        onTriggered: { root.btScanning = false }
    }
    // Poll more frequently while scanning.
    Timer {
        interval: 1500
        running: root.btScanning && root.open
        repeat: true
        onTriggered: pollBt.running = true
    }

    // ── Process for executing actions ──
    Process { id: actProc; command: ["sh","-c","true"]; running: false }

    // Refresh state when changing slots.
    onSlotChanged: {
        cancelWifiPrompt()
        if (slot === "top")    { wifiService.refresh(); pollBt.running = true }
        if (slot === "bottom") {
            pollAudio.running = true
            root.loadBrightness()
        }
        if (slot === "right")  {
            pollNotifsHistory.running = true
            pollNotifsDnd.running = true
        }
    }
    onSubChanged: {
        cancelWifiPrompt()
        if (sub && slot !== "center") {
            var next = Object.assign({}, lastSubs)
            next[slot] = sub
            lastSubs = next
        }
    }
    onLevelChanged: { if (level !== 3) cancelWifiPrompt() }
    onOpenChanged: {
        if (!open) cancelWifiPrompt()
        else { loadBrightness(); keyboardNavigation = false; gpuRequest("status") }
    }

    // Cancel the Wi-Fi prompt cleanly (close TextInput and reset key-handler focus).
    function cancelWifiPrompt() {
        if (wifiPromptSSID === "") return
        wifiPromptSSID = ""
        wifiPasswordInput = ""
        wifiError = ""
    }

    function firstSub(s) { var l = subList(s); return lastSubs[s] || (l.length ? l[0].key : "") }
    function firstAction() { var l = actList(); return l.length ? l[0].key : "" }

    // ── Button action dispatcher ──
    function dispatchAction(slotKey, subKey, actionKey) {
        console.log("[ControlCenter] action:", slotKey + "." + subKey + "." + actionKey)
        var cmd = ""

        // GPU selection never changes the running desktop or logs out the user.
        if (slotKey === "bottom" && subKey === "gpu") {
            if (gpuBusy) return
            if (actionKey === "refresh") gpuRequest("status")
            else if (actionKey === "save") gpuRequest("save")
            else if (actionKey.indexOf("select:") === 0) {
                var choice = actionKey.substring(7)
                if (choice === "auto" || gpuStatus.gpus.some(function(gpu) { return gpu.id === choice })) {
                    gpuSelection = choice
                    if (!gpuFailed) gpuMessage = ""
                }
            }
            return
        }

        // ── Wi-Fi ──
        if (slotKey === "top" && subKey === "wifi") {
            if (actionKey === "toggle") {
                wifiService.toggle()
                return
            } else if (actionKey.indexOf("connect:") === 0) {
                var ssid = actionKey.substring(8)
                // Find the network in the list to check its security.
                var net = null
                for (var i = 0; i < wifiNetworks.length; i++) {
                    if (wifiNetworks[i].ssid === ssid) { net = wifiNetworks[i]; break }
                }
                // Disconnect if already active.
                if (net && net.active) {
                    wifiService.disconnect(ssid)
                    return
                }
                // Connect directly if the network is open.
                else if (net && (net.security === "" || net.security === "--")) {
                    wifiService.connectOpen(ssid)
                    return
                }
                // Open the prompt for a secured network.
                else {
                    wifiPromptSSID = ssid
                    wifiError = ""
                    return
                }
            } else if (actionKey === "submit-password") {
                // The service writes the secret to stdin after startup, then clears it.
                wifiService.connectWithPassword(wifiPromptSSID)
                return
            } else if (actionKey === "cancel-prompt") {
                wifiPromptSSID = ""
                wifiPasswordInput = ""
                wifiError = ""
                return
            }
        }
        // ── Bluetooth ──
        else if (slotKey === "top" && subKey === "bluetooth") {
            if (actionKey === "toggle") {
                cmd = "bluetoothctl power " + (btEnabled ? "off" : "on")
            } else if (actionKey === "scan") {
                btScanning = !btScanning
                if (btScanning) {
                    btScanProc.running = true
                    btScanStopTimer.restart()
                } else {
                    actProc.command = ["sh","-c","bluetoothctl --timeout 1 scan off"]
                    actProc.running = true
                }
                return
            } else if (actionKey.indexOf("connect:") === 0) {
                var mac = actionKey.substring(8)
                cmd = "bluetoothctl trust " + mac + " 2>/dev/null; bluetoothctl connect " + mac
            } else if (actionKey.indexOf("disconnect:") === 0) {
                var mac2 = actionKey.substring(11)
                cmd = "bluetoothctl disconnect " + mac2
            } else if (actionKey.indexOf("pair:") === 0) {
                var mac3 = actionKey.substring(5)
                cmd = "bluetoothctl pair " + mac3 + " && bluetoothctl trust " + mac3 + " && sleep 0.5 && bluetoothctl connect " + mac3
            } else if (actionKey.indexOf("remove:") === 0) {
                var mac4 = actionKey.substring(7)
                cmd = "bluetoothctl disconnect " + mac4 + " 2>/dev/null; bluetoothctl remove " + mac4
            }
        }
        // ── Audio Output ──
        else if (slotKey === "bottom" && subKey === "output") {
            if (actionKey.indexOf("set-sink:") === 0) {
                var sink = actionKey.substring(9)
                cmd = "pactl set-default-sink '" + sink + "'"
            }
        }
        // ── Audio Volume ──
        else if (slotKey === "bottom" && subKey === "volume") {
            if (actionKey === "mute-toggle") {
                cmd = "pactl set-sink-mute @DEFAULT_SINK@ toggle"
            } else if (actionKey.indexOf("set-volume:") === 0) {
                var vol = actionKey.substring(11)
                root.setAudioPercent(Number(vol))
                return
            }
        }
        // ── Quickshare Send (qshare.py) ──
        else if (slotKey === "left" && subKey === "send") {
            if (actionKey === "pick-file") {
                // The picker waits for the close animation to release focus.
                filePickerProc.running = true
                // Close the Control Center so the picker can receive focus.
                close()
                return
            } else if (actionKey === "clear-file") {
                pendingFilePath = ""
                return
            } else if (actionKey === "toggle-tunnel") {
                qshareTunnel = !qshareTunnel
                return
            } else if (actionKey === "toggle-keepalive") {
                qshareKeepAlive = !qshareKeepAlive
                return
            } else if (actionKey === "start-send") {
                if (pendingFilePath === "") return
                root.startQshare("send", pendingFilePath)
                return
            }
        }
        // ── Quickshare Receive (qshare.py) ──
        else if (slotKey === "left" && subKey === "receive") {
            if (actionKey === "toggle-tunnel") {
                qshareTunnel = !qshareTunnel
                return
            } else if (actionKey === "toggle-keepalive") {
                qshareKeepAlive = !qshareKeepAlive
                return
            } else if (actionKey === "cycle-output") {
                var dirs = qshareOutputDirs
                var idx = dirs.indexOf(qshareOutputDir)
                qshareOutputDir = dirs[(idx + 1) % dirs.length]
                return
            } else if (actionKey === "start-recv") {
                root.startQshare("recv", "")
                return
            }
        }
        // ── Notifications History ──
        else if (slotKey === "right" && subKey === "history") {
            if (actionKey === "clear-all") {
                dismissAllNotifs()
                return
            } else if (actionKey.indexOf("notif:") === 0) {
                var idx = parseInt(actionKey.substring(6))
                invokeNotif(idx)
                return
            } else if (actionKey === "none") {
                return
            }
        }
        // ── Notifications DND ──
        else if (slotKey === "right" && subKey === "dnd") {
            if (actionKey === "toggle-dnd") {
                setDnd(!dndEnabled)
                return
            }
        }

        if (cmd) {
            actProc.command = ["sh","-c", cmd]
            actProc.running = true
            // Refresh state after one second.
            refreshTimer.restart()
            // Repeat refreshes for BT pair/connect/disconnect/remove actions.
            if (slotKey === "top" && subKey === "bluetooth" && actionKey !== "toggle" && actionKey !== "scan") {
                btRepeatRefresh.count = 0
                btRepeatRefresh.running = true
            }
        }
    }
    Timer {
        id: refreshTimer
        interval: 800; repeat: false
        onTriggered: { wifiService.refresh(); pollBt.running = true }
    }
    // Repeat BT refreshes after pair/connect actions (may take 5–10s).
    Timer {
        id: btRepeatRefresh
        interval: 1500
        repeat: true
        property int count: 0
        onTriggered: {
            pollBt.running = true
            count += 1
            if (count >= 6) { running = false; count = 0 }
        }
    }

    function activateCurrent() {
        if (level === 1 && slot !== "center") {
            sub = firstSub(slot); level = 3; action = firstAction()
            return
        }
        if (level === 3 && action) {
            // Notification special case: first Enter expands, second invokes.
            if (slot === "right" && sub === "history" && action.indexOf("notif:") === 0) {
                var idx = parseInt(action.substring(6))
                if (expandedNotifIdx === idx) {
                    invokeNotif(idx)
                } else {
                    expandedNotifIdx = idx
                }
                return
            }
            dispatchAction(slot, sub, action)
        }
    }

    // ── Toggle / IPC ──
    function toggle() {
        if (open || closing) close()
        else {
            open = true; closing = false
            level = 1; slot = "center"; sub = ""; action = ""
        }
    }
    function close() {
        if (!open) return
        // Phase 1: reset level to 1 (slot=center) and start closing.
        // Slots return to center while the center remains visible.
        level = 1; slot = "center"; sub = ""; action = ""
        closing = true
        closeTimer.start()
    }
    function back()  {
        if (level === 3) { level = 1; sub = ""; action = "" }
        else close()
    }

    // Timer that finalizes closing after the slots return to center.
    Timer {
        id: closeTimer
        interval: 290  // Wait for the slot animation to finish (250ms + margin).
        repeat: false
        onTriggered: {
            // Phase 2: hide completely (fade the panel opacity to 0).
            open = false
            closing = false
        }
    }

    IpcHandler {
        target: "ctrl"
        function toggle(): void { root.toggle() }
        function show(): void   { if (!root.open) root.toggle() }
        function hide(): void   { root.close() }
    }

    // ── Navigation ──
    function navigate(dir) {
        keyboardNavigation = true
        if (level === 1) {
            if (slot === "center") {
                var t = ({up:"top",down:"bottom",left:"left",right:"right"})[dir]
                if (t) { slot = t; level = 3; sub = firstSub(slot); action = firstAction() }
                return
            }
            var same = ((dir === "up"    && slot === "top")    ||
                        (dir === "down"  && slot === "bottom") ||
                        (dir === "left"  && slot === "left")   ||
                        (dir === "right" && slot === "right"))
            if (same) { level = 3; sub = firstSub(slot); action = firstAction(); return }
            var opp = ((dir === "down"  && slot === "top")    ||
                       (dir === "up"    && slot === "bottom") ||
                       (dir === "right" && slot === "left")   ||
                       (dir === "left"  && slot === "right"))
            if (opp) { slot = "center"; return }
            var t2 = ({up:"top",down:"bottom",left:"left",right:"right"})[dir]
            if (t2 && t2 !== slot) slot = t2
        }
        else if (level === 3) {
            if (slot === "bottom" && sub === "volume"
                    && (dir === "left" || dir === "right")) {
                setAudioPercent(audioVolume * 100 + (dir === "right" ? 5 : -5))
                return
            }
            if (slot === "bottom" && sub === "brightness"
                    && (dir === "left" || dir === "right")) {
                var brightnessStep = dir === "right" ? 5 : -5
                root.setBrightnessPercent(brightnessRequestedPercent + brightnessStep)
                return
            }
            var subs = subList(slot)
            var subKeys = subs.map(function(s){ return s.key })
            var subIdx = subKeys.indexOf(sub)
            var acts = actList()
            var actKeys = acts.map(function(a){ return a.key })
            var actIdx = actKeys.indexOf(action)

            if (dir === "up" || dir === "down") {
                if (dir === "up") {
                    if (subIdx > 0) { sub = subKeys[subIdx - 1]; action = firstAction() }
                    else            { level = 1; sub = ""; action = ""; slot = "center" }
                } else {
                    if (subIdx < subKeys.length - 1) { sub = subKeys[subIdx + 1]; action = firstAction() }
                    else                              { level = 1; sub = ""; action = ""; slot = "center" }
                }
            } else if (dir === "left" || dir === "right") {
                var towardsDetail = "right"
                if (dir === towardsDetail) {
                    if (actIdx < actKeys.length - 1) action = actKeys[actIdx + 1]
                } else {
                    if (actIdx > 0) action = actKeys[actIdx - 1]
                    else { level = 1; sub = ""; action = ""; slot = "center" }
                }
            }
        }
    }

    // ── Active screen detection ──
    property string activeMonitor: ""
    onActiveMonitorChanged: {
        root.brightnessAvailable = false
        if (root.open)
            root.loadBrightness()
    }
    Process {
        id: getMonitorProc
        running: root.open
        command: ["sh","-c","hyprctl cursorpos -j | python3 -c \"\nimport sys,json,subprocess\npos=json.load(sys.stdin)\nmons=json.loads(subprocess.check_output(['hyprctl','monitors','-j']))\nfor m in mons:\n    x,y=m['x'],m['y']\n    scale=float(m.get('scale') or 1)\n    w,h=m['width']/scale,m['height']/scale\n    if int(m.get('transform',0)) % 2:\n        w,h=h,w\n    if x<=pos['x']<x+w and y<=pos['y']<y+h:\n        print(m['name'])\n        break\n\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var n = this.text.trim()
                if (n !== "") root.activeMonitor = n
            }
        }
    }

    // ═══════════════════════════════════
    //   PANEL
    // ═══════════════════════════════════

    // The available hardware brightness interfaces do not visibly affect both
    // panels, so each screen gets the same input-transparent dimming surface.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            visible: root.monitorBrightness(modelData.name) < 0.999
            implicitWidth: modelData.width
            implicitHeight: modelData.height
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "tsugumori-brightness-dimmer"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region { width: 0; height: 0 }

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 1.0 - root.monitorBrightness(modelData.name)
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: controlPanel
            required property var modelData
            screen: modelData
            anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitWidth: modelData.width
            implicitHeight: modelData.height
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.open && modelData.name === root.activeMonitor)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            visible: root.open || root.closing
            readonly property bool isActive: modelData.name === root.activeMonitor

            // Dim background.
            Rectangle {
                anchors.fill: parent
                color: "#0a0a0a"
                opacity: (root.open && !root.closing) ? 0.6 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }

            // ── Keyboard container and cross ──
            Item {
                id: keyHandler
                anchors.fill: parent
                visible: isActive
                opacity: (root.open && !root.closing) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                // Give focus to the Wi-Fi TextInput when the prompt opens.
                focus: root.open && !root.closing && isActive && root.wifiPromptSSID === ""

                // Restore keyboard focus when the Wi-Fi prompt closes.
                Connections {
                    target: root
                    function onWifiPromptSSIDChanged() {
                        if (root.wifiPromptSSID === "") {
                            keyHandler.forceActiveFocus()
                        }
                    }
                }

                Keys.onPressed: function(e) {
                    var k = e.key
                    if (root.qshareUrl !== "" || qrOverlay.blocking) {
                        if (k === Qt.Key_Escape && root.qshareUrl !== "") root.stopQshare()
                        e.accepted = true
                        return
                    }
                    if (k === Qt.Key_Escape)                          { root.back();          e.accepted = true }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                        root.activateCurrent(); e.accepted = true
                    }
                    else if (k === Qt.Key_W || k === Qt.Key_Up)       { root.navigate("up");    e.accepted = true }
                    else if (k === Qt.Key_S || k === Qt.Key_Down)     { root.navigate("down");  e.accepted = true }
                    else if (k === Qt.Key_A || k === Qt.Key_Left)     { root.navigate("left");  e.accepted = true }
                    else if (k === Qt.Key_D || k === Qt.Key_Right)    { root.navigate("right"); e.accepted = true }
                }

                ControlCenterView {
                    id: controlView
                    controller: root
                    enabled: !qrOverlay.blocking
                    width: Math.max(280, Math.min(936, parent.width - 80))
                    height: implicitHeight
                    availableHeight: parent.height - 80
                    reducedMotion: root.reducedMotion
                    anchors.centerIn: parent
                }

                // ═══════════════════════════════════════════════════════
                //   qshare QR modal (visible when qshareUrl !== "")
                // ═══════════════════════════════════════════════════════
                QuickshareOverlay {
                    id: qrOverlay
                    controller: root
                    anchors.fill: parent
                    z: 100
                    requestedOpen: root.qshareUrl !== "" && controlPanel.isActive && root.open && !root.closing
                    onBlockingChanged: {
                        if (!blocking && root.open && !root.closing && controlPanel.isActive && root.wifiPromptSSID === "")
                            keyHandler.forceActiveFocus()
                    }
                }
            }
        }
    }

}
