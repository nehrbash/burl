pragma Singleton

import QtQuick
import Quickshell

// Woodland theme constants ("carved hollow & parchment").
// These fixed tones are CHROME ONLY — interactive state (hover/press/selection/
// toggles) must keep Colours.palette.m3* so wallpaper-driven palettes stay alive.
// Pure constants + pure functions: no qs.services import, so it is safe to use
// from anywhere (including services/Colours.qml) without an import cycle.
Singleton {
    id: root

    readonly property color midnight: "#111319"
    readonly property color velvet: "#1b1e26"
    readonly property color brass: "#b49a67"
    readonly property color ivory: "#efe3ca"
    readonly property color seal: "#927ea8"

    // Bark chrome (trunk bar, frames, anything baked into the wood)
    readonly property color barkLit: "#6b5040"
    readonly property color barkShaded: "#4a3425"
    readonly property color barkEdge: "#2f2117"

    // Olive accents (affirmative/active glyphs only)
    readonly property color oliveDark: "#46602c"
    readonly property color olive: "#567436"
    readonly property color oliveLight: "#688a41"

    // Parchment content (menus, popouts, tooltips)
    readonly property color parchment: "#f3e7c9"
    readonly property color parchmentMid: "#ead9b5"
    readonly property color parchmentEdge: "#d9c391"

    // Text on parchment / on bark
    readonly property color inkPrimary: barkEdge
    readonly property color inkSecondary: Qt.alpha(barkShaded, 0.8)
    readonly property color creamPrimary: parchment
    readonly property color creamSecondary: Qt.alpha(parchment, 0.7)

    // Section dividers on parchment: carved groove, not hairline grey
    readonly property color groove: Qt.alpha(barkShaded, 0.4)

    // Carved relief: light catches an upper rim, shadow pools in the lower cut.
    // Used by BarkFrame's socket mode and GrooveDivider's highlight line.
    readonly property color rimLight: Qt.alpha(parchmentEdge, 0.20)
    readonly property color rimShadow: Qt.alpha(barkEdge, 0.55)
    readonly property color grooveHighlight: Qt.alpha(parchmentEdge, 0.25)

    // Warm drop shadow for floating parchment (not yet wired into Elevation).
    readonly property color shadowWarm: Qt.alpha(barkEdge, 0.70)

    // Foliage decoration (LeafEdge fills, VineGrow strokes). Decoration only:
    // never used for text, never used for interaction state.
    readonly property color leafFill: Qt.alpha(olive, 0.55)
    readonly property color leafFillDeep: Qt.alpha(oliveDark, 0.60)
    readonly property color vineStroke: Qt.alpha(oliveDark, 0.65)

    // Mix base toward tint by k, PRESERVING base's alpha (Qt.tint does not).
    function mix(base: color, tint: color, k: real): color {
        return Qt.rgba(base.r + (tint.r - base.r) * k, base.g + (tint.g - base.g) * k, base.b + (tint.b - base.b) * k, base.a);
    }

    // Woodland take on a wallpaper-derived surface colour: warm it toward
    // shaded bark (dark schemes) or mid parchment (light schemes). Alpha is
    // preserved so transparency layering / blur rules keyed to it still hold.
    function surface(base: color, light: bool): color {
        return mix(base, light ? parchmentMid : velvet, light ? 0.5 : 0.88);
    }
}
