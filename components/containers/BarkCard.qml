pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Burl.Config
import qs.components
import qs.components.widgets
import qs.services

StyledRect {
    id: root

    readonly property bool folio: {
        let ancestor = parent;
        while (ancestor) {
            if (ancestor.bookSurface !== undefined)
                return ancestor.bookSurface;
            ancestor = ancestor.parent;
        }
        return false;
    }

    Binding {
        target: root
        property: "radius"
        when: root.folio
        value: 2
        restoreMode: Binding.RestoreBindingOrValue
    }

    // Moss crust along the top edge. Opt in on at most one card per tab.
    property bool moss: false
    // Living-tree mode pins alpha to 1.0 regardless of the shell's global
    // transparency setting: `Colours.tPalette.*` runs every tone through
    // `Colours.layer()`, which applies `transparency.base`/`transparency.layers`
    // — exactly the see-through behaviour a card floating over bare wallpaper
    // cannot afford (there is no WoodPanel behind it to blur/tint the wallpaper
    // uniformly). `Colours.palette.*` is the same tone before that layering, so
    // switching the colour SOURCE rather than post-multiplying alpha keeps
    // `Woodland.mix`'s alpha-preserving contract intact and needs no hex.
    property bool opaque: false

    // Explicit backing alpha, independent of appearance.transparency.enabled.
    // Negative = follow the palette (every pre-existing call site). The living
    // tree needs genuinely see-through cards even though this user has global
    // transparency OFF, so tPalette would hand back an opaque colour.
    property real backingAlpha: -1
    // Tile phase selector — see GRAIN PHASE above. Distinct per card.
    property int grainSeed: 0
    // Rotate the grain 90° for cards that are much wider than they are tall.
    property bool grainHorizontal: false
    // Grain strength. 0.55 on bark: the tile peaks at alpha 0.55 itself, so
    // anything higher stops being texture and starts halving the card tone
    // behind 11-13px labels. Halved again on light parchment tones, where the
    // same black would fight 12px ink.
    property real grainOpacity: Colours.light ? 0.45 : 0.55
    // The crust's shallow skirt down the card's face.
    property real mossHeight: Tokens.padding.medium
    // How far the crust's lobes rise ABOVE the card's top line — its main
    // amplitude, and the edge that reads, since that is the side with contrast.
    // Paints outside the card, so it is bounded by whatever room the card's own
    // container leaves above it: a top-row card in the scroll has about 28px of
    // page padding, and more than that gets clipped flat — which is the straight
    // line all over again.
    property real mossCrest: 8
    // Knuth multiplicative hash of the seed, split into two offsets. Pure
    // function of `grainSeed`: same seed, same phase, every reload. 251 and 241
    // are primes just under the 256px tile, so consecutive seeds land far apart
    // instead of marching. Public because a subclass that has to re-lay the
    // grain (see BarkGrain.qml) must match the card's phase exactly.
    // `real`, not `int`: the hash runs to 2^32 and a QML int is 32-bit signed,
    // so an int here would wrap negative and hand out negative offsets.
    readonly property real _grainHash: Math.floor(((root.grainSeed + 1) * 2654435761) % 4294967296)
    readonly property int grainPhaseX: root._grainHash % 251
    readonly property int grainPhaseY: Math.floor(root._grainHash / 251) % 241
    // Moss phase, from the bits the grain phase does NOT consume (251 * 241 =
    // 60491). Same guarantee as the grain: a pure function of grainSeed, so two
    // adjacent cards never grow the same crust and it never reshuffles.
    readonly property int mossSeed: Math.floor(root._grainHash / 60491) % 9973

    color: {
        if (root.folio)
            return Qt.alpha(Colours.palette.m3scrim, Colours.light ? 0.035 : 0.13);
        const surface = root.opaque ? Colours.palette.m3surfaceContainer : Colours.tPalette.m3surfaceContainer;
        return root.backingAlpha >= 0 ? Qt.alpha(surface, root.backingAlpha) : surface;
    }
    radius: Tokens.rounding.large
    border.width: 1
    border.color: root.folio ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : Colours.light ? Woodland.groove : Qt.alpha(Woodland.barkEdge, 0.5)

    Rectangle {
        visible: root.folio
        anchors.fill: parent
        anchors.margins: 1
        radius: 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Colours.palette.m3scrim, 0.16) }
            GradientStop { position: 0.09; color: "transparent" }
            GradientStop { position: 0.85; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha(Woodland.parchmentEdge, 0.055) }
        }
    }

    Rectangle {
        visible: root.folio
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 1
        color: Qt.alpha(Woodland.parchmentEdge, 0.22)
    }

    // Everything textural is clipped to the card's own radius. NOTE:
    // ClippingRectangle reparents its children, so nothing in here may reach for
    // `parent.<card property>` — use `root.` instead.
    StyledClippingRect {
        visible: !root.folio
        anchors.fill: parent
        radius: root.radius

        BarkGrain {
            plateWidth: root.width
            plateHeight: root.height

            horizontal: root.grainHorizontal
            phaseX: root.grainPhaseX
            phaseY: root.grainPhaseY
            strength: root.grainOpacity
        }
    }

    // Carved relief over the grain. Two transparent bordered Rectangles, shared
    // with every other socket in the shell. NOTE: socket mode is RECESSED — the
    // dark cap sits at the top and the lit one at the bottom (see BarkFrame,
    // whose own header says this the other way round; the code is right).
    BarkFrame {
        visible: !root.folio
        anchors.fill: parent

        socket: true
        radius: root.radius
    }

    // Moss crust. Declared AFTER the rim on purpose: moss grows OVER a carved
    // lip, and the rim's own straight top line was half of what made the old
    // crust read as a stripe. Outside the clipper too — `mossCrest` rides above
    // the card's top edge, which the clipper would cut off flat, so MossCrust
    // carries the card's corner radius itself instead.
    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -root.mossCrest

        height: root.mossHeight + root.mossCrest
        active: root.moss && !root.folio
        asynchronous: true

        sourceComponent: MossCrust {
            depth: root.mossHeight
            crest: root.mossCrest
            cornerRadius: root.radius
            seed: root.mossSeed
        }
    }
}
