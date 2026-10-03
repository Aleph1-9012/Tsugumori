import QtQuick
import Quickshell
import Quickshell.Io
import "WifiParser.js" as WifiParser

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
        command: ["env", "LC_ALL=C", "sh", "-c",
            "echo \"$(nmcli radio wifi 2>/dev/null)\"; " +
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi 2>/dev/null | head -40"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = WifiParser.parse(this.text)
                service.enabled = result.enabled
                service.networks = result.networks
                service.currentSsid = result.currentSsid
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
