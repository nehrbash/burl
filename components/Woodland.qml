pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property color midnight: Colours.palette.m3surfaceContainerLowest
    readonly property color velvet: Colours.palette.m3surfaceContainer
    readonly property color brass: Colours.palette.m3primary
    readonly property color ivory: Colours.palette.m3onSurface
    readonly property color seal: Colours.palette.m3tertiary

    // Bark chrome (trunk bar, frames, anything baked into the wood)
    readonly property color barkLit: "#6b5040"
    readonly property color barkShaded: "#4a3425"
    readonly property color barkEdge: "#2f2117"

    readonly property color oliveDark: "#46602c"
    readonly property color olive: "#567436"
    readonly property color oliveLight: "#688a41"

    readonly property color parchment: "#f3e7c9"
    readonly property color parchmentMid: "#ead9b5"
    readonly property color parchmentEdge: "#d9c391"

    readonly property color inkPrimary: barkEdge
    readonly property color inkSecondary: Qt.alpha(barkShaded, 0.8)
    readonly property color creamPrimary: Colours.palette.m3onSurface
    readonly property color creamSecondary: Colours.palette.m3onSurfaceVariant

    // Section dividers on parchment: carved groove, not hairline grey
    readonly property color groove: Qt.alpha(barkShaded, 0.4)

    // Carved relief: light catches an upper rim, shadow pools in the lower cut.
    // Used by BarkFrame's socket mode and GrooveDivider's highlight line.
    readonly property color rimLight: Qt.alpha(parchmentEdge, 0.20)
    readonly property color rimShadow: Qt.alpha(barkEdge, 0.55)
    readonly property color grooveHighlight: Qt.alpha(parchmentEdge, 0.25)

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
}
