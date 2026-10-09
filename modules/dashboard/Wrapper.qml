pragma ComponentBehavior: Bound

import QtQuick
import Burl
import Burl.Config
import qs.components
import qs.components.filedialog

Item {
    id: root

    required property ScreenState screenState
    readonly property FileDialog facePicker: FacePicker {}

    readonly property real nonAnimHeight: (content.item as Content)?.nonAnimHeight ?? 0
    readonly property bool shouldBeActive: screenState.dashboard && Config.dashboard.enabled
    // navStyle "living": full-bleed, no slide/fade — the tree's own growth IS
    // the reveal. Geometry (anchors.fill vs. horizontalCenter+top) is switched
    // externally by Panels.qml, which owns this instance's anchoring; this
    // file only has to stop sliding/fading.
    readonly property bool useLiving: Config.dashboard.navStyle === "living"
    // Read defensively off the mounted Content/LivingTree: an unpublished
    // growProgress falls back to the boolean, so the dashboard still shows
    // immediately.
    readonly property real growProgress: root.useLiving ? ((content.item)?.growProgress ?? (root.shouldBeActive ? 1 : 0)) : 0
    property real offsetScale: shouldBeActive ? 0 : 1

    // Living mode is ALWAYS visible: the dormant sprout at the bottom edge is the
    // trigger affordance, so the surface has to be on screen with nothing grown.
    // Safe because the input mask subtracts nothing until the tree grows (see
    // Regions.qml's zero-area MaskSlots), so empty canopy passes clicks through.
    // It also breaks a binding loop: visible was read by the content Loader's
    // `active`, whose item fed growProgress, which fed visible.
    visible: root.useLiving ? true : offsetScale < 1
    anchors.topMargin: root.useLiving ? 0 : (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 854 // Hard coded fallback for first open
    opacity: root.useLiving ? 1 : (1 - offsetScale)

    Behavior on offsetScale {
        enabled: !root.useLiving

        Anim {}
    }

    Loader {
        id: content

        // Living: fill the whole full-bleed Wrapper via the four
        // edges rather than `anchors.fill` — kept as individual edges so
        // `anchors.bottom` can stay set unconditionally without ever
        // colliding with `anchors.horizontalCenter` in the non-living branch.
        anchors.top: root.useLiving ? parent.top : undefined
        anchors.left: root.useLiving ? parent.left : undefined
        anchors.right: root.useLiving ? parent.right : undefined
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: root.useLiving ? undefined : parent.horizontalCenter

        // Living mode keeps the host loaded while dormant — it draws the sprout and
        // owns the growth scalar; destroying it on close would delete the trigger
        // and re-enter the loop described above. Its per-section cluster Loaders
        // stay inactive until their bough grows, so a dormant tree is a trunk stub
        // and a seed, not five instantiated panes.
        active: root.useLiving ? true : (root.shouldBeActive || root.visible)

        sourceComponent: Content {
            screenState: root.screenState
            facePicker: root.facePicker
            // In living mode the TREE lives in the launcher's surface (mounted
            // there as a guest), so this instance is only ever the dormant
            // sprout at the bottom edge: the seed and the hover strip that
            // ask for it. This avoids two full trees, one of them unreachable
            // from the sky graph.
            sproutOnly: root.useLiving
        }
    }
}
