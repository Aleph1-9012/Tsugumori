pragma Singleton
import QtQuick

// ╔══════════════════════════════════════════════════════════════╗
// ║  SETTINGS — Tsugumori shell configuration options            ║
// ║  Edit these values to customize shell behavior.                ║
// ╚══════════════════════════════════════════════════════════════╝

QtObject {

    // ── GLOBAL SCALE ────────────────────────────────────────────

    // Global multiplier applied to all sizes.
    // 1.0 = normal, 1.25 = 25% larger, 0.8 = 20% smaller.
    readonly property real scale: 1

    // Clipboard palette: false matches the notification white; true uses charcoal.
    readonly property bool clipboardDark: false

    // Scaled unit — applies scale to the base size.
    // Usage: Settings.s(320) = 320 * scale.
    function s(px)   { return Math.round(px * scale) }

    // ── PLAYER ──────────────────────────────────────────────────

    // Player background: true = opaque dark background / false = transparent.
    readonly property bool playerBackground: true

    // Background color (used only when playerBackground = true).
    readonly property color playerBgColor: "#0a0a0a"

    // Vertical alignment in the free space: 0.0 = top, 0.5 = centre, 1.0 = bottom.
    readonly property real playerPositionY: 0.5

    // Distance from the right edge in pixels.
    readonly property int playerMarginRight: s(20)

    // Player width in pixels (scaled automatically).
    readonly property int playerWidth: s(680)

    // ── ANIMATIONS ──────────────────────────────────────────────

    readonly property color curtainColor: "#cc1515"  // Red stencil curtain.

    // Reveal duration (ms).
    readonly property int revealDuration: 460

    // Hide duration (ms).
    readonly property int hideDuration: 380

    // ── WAYBAR ──────────────────────────────────────────────────

    // Waybar bar height in pixels.
    readonly property int waybarHeight: 28


    // ── SHORTCUTS (also declared in hyprland.lua) ───────────────
    //   SUPER+RETURN        →  qs ipc call tsugumoriShell togglePlayer  (show/hide player)
    //   SUPER+SHIFT+RETURN  →  qs ipc call tsugumoriShell toggleFront   (front/back)

}
