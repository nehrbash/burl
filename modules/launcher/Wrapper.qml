pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Burl
import Burl.Config
import qs.components
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState visibilities
    required property var panels

    // Both rooms share one surface so their camera transition stays continuous.
    readonly property bool shouldBeActive: (visibilities.launcher || visibilities.dashboard) && Config.launcher.enabled

    property real offsetScale: shouldBeActive ? 0 : 1

    // Retain the warm scene between opens outside Performance mode.
    property bool loaderActive: false

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            loaderActive = true;
            refreshPending = true;
            Qt.callLater(root.reloadWhenReady);
        } else {
            refreshPending = false;
        }
    }

    property bool refreshPending: false
    readonly property bool readyForReload: root.shouldBeActive && sceneLoader.item !== null
        && sceneLoader.item.revealP > 0.99 && (sceneLoader.item.atTree || sceneLoader.item.atSky)
    onReadyForReloadChanged: Qt.callLater(root.reloadWhenReady)

    // Source refreshes can change graph structure; keep them outside the pan.
    function reloadWhenReady(): void {
        if (!refreshPending || !readyForReload)
            return;
        refreshPending = false;
        CalendarSources.reload();
        EmacsSources.reload();
        if (!SpotifySources.authed)
            SpotifySources.reload();
    }

    // Outlast Content's close pan before hiding the surface.
    visible: offsetScale < 1
    anchors.fill: parent

    Component.onCompleted: {
        Qt.callLater(() => Apps);
    }

    Timer {
        id: preloadTimer
        interval: 4000
        // Multiple monitor graphs must not compete with the first opening.
        running: !GameMode.enabled && !root.loaderActive && root.screen.name === Hypr.focusedMonitor?.name
        repeat: false
        onTriggered: root.loaderActive = true
    }

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Loader {
        id: sceneLoader
        anchors.fill: parent
        // Finish the close animation before releasing the scene.
        active: root.loaderActive && (!GameMode.enabled || root.shouldBeActive || root.offsetScale < 1)
        // Parsing the scene must not block the opening animation.
        asynchronous: true

        sourceComponent: Content {
            visibilities: root.visibilities
            panels: root.panels
        }
    }
}
