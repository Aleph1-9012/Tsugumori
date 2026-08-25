pragma Singleton
import QtQuick
import Quickshell

// ╔══════════════════════════════════════════════════════════════╗
// ║  SETTINGS — Tsugumori shell configuration options            ║
// ║  Edit these values to customize shell behavior.                ║
// ╚══════════════════════════════════════════════════════════════╝

QtObject {

    // ── GLOBAL SCALE ────────────────────────────────────────────

    // Global multiplier applied to all sizes.
    // 1.0 = normal, 1.25 = 25% larger, 0.8 = 20% smaller.
    readonly property real scale: 1

    // Main screen dimensions (equivalent to 100vw / 100vh).
    readonly property real screenW: Quickshell.screens.length > 0
                                    ? Quickshell.screens[0].width  : 1920
    readonly property real screenH: Quickshell.screens.length > 0
                                    ? Quickshell.screens[0].height : 1080

    // Relative units — Settings.vw(5) = 5% of the screen width.
    // CSS equivalent: 5vw.
    function vw(pct) { return Math.round(screenW * pct / 100) }
    function vh(pct) { return Math.round(screenH * pct / 100) }

    // Scaled unit — applies scale to the base size.
    // Usage: Settings.s(320) = 320 * scale.
    function s(px)   { return Math.round(px * scale) }

    // ── PLAYER ──────────────────────────────────────────────────

    // Player background: true = opaque dark background / false = transparent.
    readonly property bool playerBackground: true

    // Background color (used only when playerBackground = true).
    readonly property color playerBgColor: "#000000"

    // Player vertical position (0.0 = top, 1.0 = bottom of the screen).
    readonly property real playerPositionY: 0.39

    // Distance from the right edge in pixels.
    readonly property int playerMarginRight: s(20)

    // Player width in pixels (scaled automatically).
    readonly property int playerWidth: s(700)

    // ── GLOBAL COLORS ───────────────────────────────────────────

    // Sidonia sepia palette (change only when changing the theme).
    readonly property color fg:   "#e8e8e8"      // Primary text.
    readonly property color bg:   "#0a0a0a"      // Main background.
    readonly property color a1:   "#c87060"      // Red accent.
    readonly property color a2:   "#60a880"      // Green accent.
    readonly property color a3:   "#6090c8"      // Blue accent.
    readonly property color a4:   "#9e1010"      // Gold accent.
    readonly property color ln:   Qt.rgba(232/255, 232/255, 232/255, 0.12)  // Thin border.
    readonly property color lnm:  Qt.rgba(232/255, 232/255, 232/255, 0.22) // Medium border.
    readonly property color curtainColor: "#e8e8e8"  // Wipe curtain color.


    // ── ANIMATIONS ──────────────────────────────────────────────

    // Reveal duration (ms).
    readonly property int revealDuration: 460

    // Hide duration (ms).
    readonly property int hideDuration: 380

    // Blocky cover transition duration (ms per step).
    readonly property int coverTransitionStep: 30


    // ── WAYBAR ──────────────────────────────────────────────────

    // Waybar bar height in pixels.
    readonly property int waybarHeight: 28


    // ── SHORTCUTS (also declared in hyprland.lua) ───────────────
    //   SUPER+RETURN        →  qs ipc call tsugumoriShell togglePlayer  (show/hide player)
    //   SUPER+SHIFT+RETURN  →  qs ipc call tsugumoriShell toggleFront   (front/back)

}
