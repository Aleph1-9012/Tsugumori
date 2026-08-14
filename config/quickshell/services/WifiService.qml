import QtQuick
import Quickshell
import Quickshell.Io

// NetworkManager adapter for the Control Center.  This keeps command execution,
// polling, and nmcli output parsing out of the presentation component.
Scope {
    id: service

    required property string helperPath
    property bool active: false

    property bool enabled: false
    property string currentSsid: ""
    property var networks: [] // [{ssid, signal, security, active}]
    property string passwordInput: ""

    signal passwordConnectionFinished(bool success)
    signal passwordConsumed()

    function refresh() {
        if (!pollWifi.running)
            pollWifi.running = true
    }

    function toggle() {
        wifiActionProc.command = ["nmcli", "radio", "wifi", enabled ? "off" : "on"]
        wifiActionProc.running = true
    }

    function connectOpen(ssid) {
        wifiActionProc.command = ["python3", helperPath, "connect", "--ssid=" + ssid]
        wifiActionProc.running = true
    }

    function disconnect(ssid) {
        wifiActionProc.command = ["python3", helperPath, "disconnect", "--ssid=" + ssid]
        wifiActionProc.running = true
    }

    function connectWithPassword(ssid) {
        if (wifiSubmitProc.running)
            return false

        wifiSubmitProc.command = ["python3", helperPath, "connect", "--ssid=" + ssid, "--password-stdin"]
        wifiSubmitProc.running = true
        return true
    }

    Timer {
        interval: 3000
        running: service.active
        repeat: true
        triggeredOnStart: true
        onTriggered: service.refresh()
    }

    Process {
        id: pollWifi
        command: ["sh", "-c",
            "echo \"$(nmcli radio wifi 2>/dev/null)\"; " +
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi 2>/dev/null | head -40"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                service.enabled = (lines[0] || "").trim() === "enabled"
                var seen = ({})
                var current = ""
                for (var i = 1; i < lines.length; i++) {
                    var parts = lines[i].split(":")
                    if (parts.length < 4) continue
                    var inUse = parts[0] === "*"
                    var ssid = parts[1]
                    var signal = parseInt(parts[2]) || 0
                    var security = parts[3] || "Open"
                    if (!ssid) continue
                    if (inUse) current = ssid
                    if (seen[ssid]) {
                        if (seen[ssid].active) continue
                        if (seen[ssid].signal >= signal && !inUse) continue
                    }
                    seen[ssid] = {ssid: ssid, signal: signal, security: security, active: inUse}
                }

                var result = []
                for (var key in seen) result.push(seen[key])
                result.sort(function(a, b) {
                    if (a.active && !b.active) return -1
                    if (!a.active && b.active) return 1
                    return b.signal - a.signal
                })
                service.networks = result
                service.currentSsid = current
            }
        }
    }

    Process {
        id: wifiActionProc
        running: false
        onExited: serviceRefreshTimer.restart()
    }

    Process {
        id: wifiSubmitProc
        running: false
        stdinEnabled: true
        onStarted: {
            write(service.passwordInput + "\n")
            service.passwordInput = ""
            service.passwordConsumed()
        }
        onExited: (exitCode, exitStatus) => {
            service.passwordConnectionFinished(exitCode === 0)
            serviceRefreshTimer.restart()
        }
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    Timer {
        id: serviceRefreshTimer
        interval: 800
        repeat: false
        onTriggered: service.refresh()
    }
}
