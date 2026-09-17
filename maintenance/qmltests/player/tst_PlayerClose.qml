import QtQuick
import QtTest
import Quickshell
import "../../../config/quickshell/widgets"

Item {
    width: 800; height: 900
    Player {
        id: player
        width: 680; height: implicitHeight
        localTracks: ["/test/one.ogg", "/test/two.ogg", "/test/three.ogg"]
    }
    TestCase {
        name: "PlayerClose"
        when: windowShown
        property var drawer
        function initTestCase() {
            drawer = findChild(player, "trackDrawer")
            verify(drawer !== null)
        }
        function init() {
            Quickshell.reduceMotion = false
            player.requestedVisible = false
            tryCompare(player, "revealProgress", 0, 1500)
            tryCompare(drawer, "height", 0, 500)
            player.requestedVisible = true
            tryCompare(player, "revealProgress", 1, 1500)
        }
        function openDrawer() {
            player.showTrackList = true
            tryCompare(drawer, "height", player.drawerNaturalHeight, 700)
        }
        function test_drawer_collapses_before_player_hides() {
            openDrawer()
            var x = player.x, y = player.y
            player.requestedVisible = false
            compare(player.showTrackList, false)
            verify(!drawer.enabled)
            verify(!findChild(player, "libraryToggle").enabled)
            if (!player.reducedMotion) {
                verify(player.waitingForDrawerClose)
                wait(80)
                verify(drawer.height > 0 && drawer.height < player.drawerNaturalHeight)
                compare(player.revealProgress, 1)
            }
            compare(player.x, x); compare(player.y, y)
            tryCompare(drawer, "height", 0, 700)
            tryCompare(player, "revealProgress", 0, 1200)
            verify(!player.shown)
            verify(!player.waitingForDrawerClose)
            player.requestedVisible = true
            tryCompare(player, "revealProgress", 1, 1200)
            compare(drawer.height, 0)
        }
        function test_manual_drawer_close_leaves_player_open() {
            openDrawer()
            player.showTrackList = false
            tryCompare(drawer, "height", 0, 700)
            wait(600)
            compare(player.revealProgress, 1)
            verify(player.shown)
        }
        function test_reopen_cancels_pending_close() {
            openDrawer()
            player.requestedVisible = false
            wait(50)
            player.requestedVisible = true
            tryCompare(player, "revealProgress", 1, 1200)
            wait(900)
            compare(player.revealProgress, 1)
            verify(player.shown)
            verify(!player.waitingForDrawerClose)
            compare(drawer.height, 0)
        }
        function test_close_while_drawer_is_opening() {
            player.showTrackList = true
            wait(60)
            player.requestedVisible = false
            tryCompare(drawer, "height", 0, 700)
            tryCompare(player, "revealProgress", 0, 1200)
            compare(player.showTrackList, false)
        }
        function test_close_with_drawer_already_closed() {
            player.requestedVisible = false
            verify(!player.waitingForDrawerClose)
            tryCompare(player, "revealProgress", 0, 1200)
            compare(drawer.height, 0)
        }
        function test_reduced_motion_closes_both_immediately() {
            Quickshell.reduceMotion = true
            openDrawer()
            player.requestedVisible = false
            tryCompare(drawer, "height", 0, 100)
            tryCompare(player, "revealProgress", 0, 100)
            verify(!player.waitingForDrawerClose)
            verify(!player.shown)
        }
    }
}
