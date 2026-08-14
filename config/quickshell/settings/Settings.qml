pragma Singleton
import QtQuick
import Quickshell

// ╔══════════════════════════════════════════════════════════════╗
// ║  SETTINGS — options de configuration du rice NieR           ║
// ║  Modifie les valeurs ici pour personnaliser le comportement  ║
// ╚══════════════════════════════════════════════════════════════╝

QtObject {

    // ── SCALE GLOBAL ────────────────────────────────────────────

    // Multiplicateur global appliqué à toutes les tailles
    // 1.0 = taille normale, 1.25 = 25% plus grand, 0.8 = 20% plus petit
    readonly property real scale: 1

    // Dimensions de l'écran principal (équivalent 100vw / 100vh)
    readonly property real screenW: Quickshell.screens.length > 0
                                    ? Quickshell.screens[0].width  : 1920
    readonly property real screenH: Quickshell.screens.length > 0
                                    ? Quickshell.screens[0].height : 1080

    // Unités relatives — usage : Settings.vw(5) = 5% de la largeur écran
    // Équivalent CSS : 5vw
    function vw(pct) { return Math.round(screenW * pct / 100) }
    function vh(pct) { return Math.round(screenH * pct / 100) }

    // Unité scalée — applique scale en plus de la taille de base
    // Usage : Settings.s(320) = 320 * scale
    function s(px)   { return Math.round(px * scale) }

    // ── PLAYER ──────────────────────────────────────────────────

    // Fond du player : true = fond sombre opaque / false = transparent
    readonly property bool playerBackground: true

    // Couleur du fond (utilisée seulement si playerBackground = true)
    readonly property color playerBgColor: "#000000"

    // Position verticale du player (0.0 = haut, 1.0 = bas de l'écran)
    readonly property real playerPositionY: 0.39

    // Distance du bord droit en pixels
    readonly property int playerMarginRight: s(20)

    // Largeur du player en pixels (scalée automatiquement)
    readonly property int playerWidth: s(700)


    // ── COMPANIONS ──────────────────────────────────────────────

    readonly property bool companionsEnabled: false  // Afficher les compagnons

    // Distance du bord droit en pixels
    readonly property int companionsMarginRight: s(20)

    // Taille des sprites
    readonly property int companionsSpriteSize: s(128)


    // ── COULEURS GLOBALES ────────────────────────────────────────

    // Palette sépia NieR (ne pas modifier sauf si tu changes de thème)
    readonly property color fg:   "#e8e8e8"      // texte principal
    readonly property color bg:   "#0a0a0a"      // fond principal
    readonly property color a1:   "#c87060"      // accent rouge
    readonly property color a2:   "#60a880"      // accent vert
    readonly property color a3:   "#6090c8"      // accent bleu
    readonly property color a4:   "#9e1010"      // accent or
    readonly property color ln:   Qt.rgba(232/255, 232/255, 232/255, 0.12)  // bordure fine
    readonly property color lnm:  Qt.rgba(232/255, 232/255, 232/255, 0.22) // bordure medium
    readonly property color curtainColor: "#e8e8e8"  // couleur du rideau wipe


    // ── ANIMATIONS ──────────────────────────────────────────────

    // Durée du reveal (ms)
    readonly property int revealDuration: 460

    // Durée du hide (ms)
    readonly property int hideDuration: 380

    // Durée de la transition cover blocky (ms par étape)
    readonly property int coverTransitionStep: 30


    // ── WAYBAR ──────────────────────────────────────────────────

    // Hauteur de la barre Waybar en pixels
    readonly property int waybarHeight: 28


    // ── RACCOURCIS (à déclarer aussi dans hyprland.conf) ────────
    //   SUPER+RETURN        →  qs ipc call tsugumoriShell togglePlayer  (afficher/cacher player)
    //   SUPER+SHIFT+RETURN  →  qs ipc call tsugumoriShell toggleFront   (premier plan / arrière)

}
