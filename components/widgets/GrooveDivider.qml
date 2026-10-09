import QtQuick
import Burl
import qs.components

// A carved cut, not a grey hairline: one groove line plus a lit lip below it.
//
//   GrooveDivider { Layout.fillWidth: true }
//   GrooveDivider { vertical: true; Layout.fillHeight: true }
//
// Optionally NOTCHED: set notchWidth > 0 and the cut breaks open at notchX, so
// the panel above reads as open to whatever sits under the gap. notchWidth 0 —
// the default — leaves the leading segment spanning the whole divider and the
// trailing one empty, i.e. an unbroken line.
//
//   GrooveDivider { notchX: someTipX; notchWidth: Tokens.spacing.extraLarge }
//
// Four Rectangles (two per lane, one either side of the notch). Zero idle cost:
// the notch animates through Behaviors on notchX/notchWidth, and the segment
// geometry is derived, so nothing here ticks on its own.
Item {
    id: root

    property bool vertical: false
    property color groove: Woodland.groove
    property color highlight: Woodland.grooveHighlight
    // Set 0 to drop the lit lip (e.g. on a dark bark strip).
    property real highlightOpacity: 1
    // Centre and width of the gap, measured along the divider.
    property real notchX
    property real notchWidth

    readonly property real span: root.vertical ? root.height : root.width
    readonly property real leadLength: root.notchWidth <= 0 ? root.span : CUtils.clamp(root.notchX - root.notchWidth / 2, 0, root.span)
    readonly property real tailOffset: root.notchWidth <= 0 ? root.span : CUtils.clamp(root.notchX + root.notchWidth / 2, 0, root.span)
    readonly property real tailLength: Math.max(0, root.span - root.tailOffset)

    implicitWidth: root.vertical ? 2 : 0
    implicitHeight: root.vertical ? 0 : 2

    // The cut itself, either side of the notch.
    Rectangle {
        x: 0
        y: 0
        width: root.vertical ? 1 : root.leadLength
        height: root.vertical ? root.leadLength : 1
        color: root.groove
    }

    Rectangle {
        x: root.vertical ? 0 : root.tailOffset
        y: root.vertical ? root.tailOffset : 0
        width: root.vertical ? 1 : root.tailLength
        height: root.vertical ? root.tailLength : 1
        color: root.groove
    }

    // The lit lip, one pixel below (or right of) the cut.
    Rectangle {
        x: root.vertical ? 1 : 0
        y: root.vertical ? 0 : 1
        width: root.vertical ? 1 : root.leadLength
        height: root.vertical ? root.leadLength : 1
        color: root.highlight
        opacity: root.highlightOpacity
    }

    Rectangle {
        x: root.vertical ? 1 : root.tailOffset
        y: root.vertical ? root.tailOffset : 1
        width: root.vertical ? 1 : root.tailLength
        height: root.vertical ? root.tailLength : 1
        color: root.highlight
        opacity: root.highlightOpacity
    }

    Behavior on notchX {
        Anim {}
    }

    Behavior on notchWidth {
        Anim {}
    }
}
