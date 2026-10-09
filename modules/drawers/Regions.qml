pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Burl.Config
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness
    // navStyle "living" replaces the panel-height-based dashboard `R` below
    // with the fixed-slot mask subtree at the bottom of this file. "tabs"/
    // "tree" are untouched.
    readonly property bool livingNav: win.contentItem.Config.dashboard.navStyle === "living"
    // Committed once per user action (grow/fold/emphasise/close), never per
    // animation frame — LivingTree.qml writes dashboardTreeGrown/
    // dashboardMaskRects/dashboardTrunkRect on ScreenState only at those
    // moments. The slot/trunk rects below only contribute to the mask while
    // this is true.
    readonly property bool livingGrown: root.livingNav && root.panels.screenState.dashboardTreeGrown

    x: bar.clampedWidth + win.dragMaskPadding
    y: clampedThickness + win.dragMaskPadding
    width: win.width - bar.clampedWidth - clampedThickness - win.dragMaskPadding * 2
    height: win.height - clampedThickness * 2 - win.dragMaskPadding * 2
    intersection: Intersection.Xor

    R {
        panel: root.panels.dashboard
        y: 0
        height: root.livingNav ? 0 : panel.height * (1 - root.panels.dashboard.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.borderThickness
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: root.win.width - width
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.osdWrapper
        x: root.win.width - width
        width: panel.width * (1 - root.panels.osd.offsetScale) + root.borderThickness + sidebarRegion.width
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.borderThickness
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.popoutsWrapper
        width: panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
    }

    // Living-tree mask: fixed slots, no Repeater/Instantiator. Region is a
    // QtObject, not an Item; dynamically appending to its default `regions`
    // list via Repeater/Instantiator is untested here and not worth
    // discovering at deploy time, so eight slots are declared literally —
    // "sections" tops out at 5 today and the band's own labelling maths
    // already caps at 8. `dashboardMaskRects`/`dashboardTrunkRect` are
    // published by LivingTree.qml onto ScreenState; a zero-area Region
    // contributes nothing, which is how an unused slot (or "tabs"/"tree" nav,
    // or the tree not currently grown) drops out of the mask for free.
    //
    // The living tree now publishes a SINGLE full-surface rect in slot 0
    // rather than one rect per node, so the eight-slot limit no longer bounds
    // how many nodes it can carry, and empty canopy dismisses on click rather
    // than passing clicks through.

    MaskSlot {
        slotIndex: 0
    }
    MaskSlot {
        slotIndex: 1
    }
    MaskSlot {
        slotIndex: 2
    }
    MaskSlot {
        slotIndex: 3
    }
    MaskSlot {
        slotIndex: 4
    }
    MaskSlot {
        slotIndex: 5
    }
    MaskSlot {
        slotIndex: 6
    }
    MaskSlot {
        slotIndex: 7
    }

    Region {
        id: trunkSlot

        readonly property var rect: root.livingGrown ? root.panels.screenState.dashboardTrunkRect : null

        x: (rect?.x ?? 0) + root.bar.implicitWidth
        y: (rect?.y ?? 0) + root.borderThickness
        width: rect ? rect.width : 0
        height: rect ? rect.height : 0
        intersection: Intersection.Subtract
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.bar.implicitWidth
        y: panel.y + root.borderThickness
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }

    component MaskSlot: Region {
        required property int slotIndex

        readonly property var rect: (root.livingGrown && root.panels.screenState.dashboardMaskRects.length > slotIndex) ? root.panels.screenState.dashboardMaskRects[slotIndex] : null

        x: (rect?.x ?? 0) + root.bar.implicitWidth
        y: (rect?.y ?? 0) + root.borderThickness
        width: rect ? rect.width : 0
        height: rect ? rect.height : 0
        intersection: Intersection.Subtract
    }
}
