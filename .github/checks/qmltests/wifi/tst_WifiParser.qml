import QtQuick
import QtTest
import "../../../../config/quickshell/services/WifiParser.js" as WifiParser

TestCase {
    name: "WifiParser"

    function test_escaped_network_names() {
        const result = WifiParser.parse("enabled\n*:Cafe\\:Guest:72:WPA2\n:Home\\\\Office:61:WPA3\n")
        compare(result.enabled, true)
        compare(result.currentSsid, "Cafe:Guest")
        compare(result.networks, [
            {ssid: "Cafe:Guest", signal: 72, security: "WPA2", active: true},
            {ssid: "Home\\Office", signal: 61, security: "WPA3", active: false}
        ])
    }

    function test_duplicate_access_points_keep_active_or_strongest() {
        const result = WifiParser.parse("enabled\n:Guest:90:WPA2\n*:Guest:50:WPA2\n:Guest:100:WPA3\n:Other:10:WPA2\n:Other:40:WPA2\n")
        compare(result.networks, [
            {ssid: "Guest", signal: 50, security: "WPA2", active: true},
            {ssid: "Other", signal: 40, security: "WPA2", active: false}
        ])
    }

    function test_names_do_not_collide_with_object_properties() {
        const result = WifiParser.parse("enabled\n:__proto__:55:WPA2\n:constructor:20:WPA2\n")
        compare(result.networks.length, 2)
        compare(result.networks[0].ssid, "__proto__")
        compare(result.networks[1].ssid, "constructor")
    }

    function test_empty_hidden_and_malformed_rows() {
        compare(WifiParser.parse("disabled\n"), {enabled: false, currentSsid: "", networks: []})
        const result = WifiParser.parse("enabled\n*: :77:\n::10:WPA2\ninvalid\n:broken:20:WPA2:extra\n")
        compare(result.currentSsid, " ")
        compare(result.networks, [{ssid: " ", signal: 77, security: "Open", active: true}])
    }

    function test_escaped_slash_before_separator_and_unicode() {
        const result = WifiParser.parse("enabled\n*:東亜\\\\\\: guest:88:WPA2 WPA3\n")
        compare(result.currentSsid, "東亜\\: guest")
        compare(result.networks[0].security, "WPA2 WPA3")
    }
}
