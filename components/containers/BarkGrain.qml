import QtQuick
import Quickshell

// One plate of tiled bark grain, sized and phased to a CARD rather than to
// itself. BarkCard lays one down under its own rim; a card whose content must
// paint OVER the card (BatteryTank's rising level has to cover the unfilled
// card's labels) re-lays an identical plate inside its own clip, offset back
// into card coordinates, so the fissures run straight across the seam instead
// of restarting there:
//
//     BarkGrain {
//         y: -(root.height - <clip height>)   // card top, in clip coords
//         plateWidth: root.width; plateHeight: root.height
//         horizontal: root.grainHorizontal
//         phaseX: root.grainPhaseX; phaseY: root.grainPhaseY
//         strength: root.grainOpacity
//     }
//
// The inner carrier swaps width/height before rotating, so a horizontal plate
// still covers the card exactly and the card's own geometry is never touched.
// Rotation is 0 (free) unless `horizontal` is set.
//
// This is a FILE, not an inline `component Grain:` inside BarkCard, and must
// stay one: BarkCard declares `pragma ComponentBehavior: Bound`, and Qt refuses
// to instantiate a bound inline component from another file — "Cannot
// instantiate bound inline component in different file".
Item {
    id: plate

    required property real plateWidth
    required property real plateHeight
    required property bool horizontal
    required property int phaseX
    required property int phaseY
    required property real strength

    width: plate.plateWidth
    height: plate.plateHeight

    Item {
        anchors.centerIn: parent

        width: plate.horizontal ? plate.plateHeight : plate.plateWidth
        height: plate.horizontal ? plate.plateWidth : plate.plateHeight
        rotation: plate.horizontal ? 90 : 0

        Image {
            // Pulling the tiled image up and left by the hashed phase (and
            // growing it by the same amount, so the card stays covered) is
            // what breaks the shared tile origin. The overhang is clipped by
            // whichever clipper the plate lives in.
            x: -plate.phaseX
            y: -plate.phaseY
            width: parent.width + plate.phaseX
            height: parent.height + plate.phaseY

            source: Quickshell.shellPath("assets/images/tree/bark-grain.png")
            // Tile at half the source's pixel size: the fissures land at
            // card scale instead of looking zoomed, and because the tile is
            // drawn at its sourceSize (never stretched) there is no moire.
            sourceSize: Qt.size(256, 256)
            fillMode: Image.Tile
            mipmap: true
            opacity: plate.strength
            asynchronous: true
            visible: status === Image.Ready
        }
    }
}
