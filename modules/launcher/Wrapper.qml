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
    readonly property bool shouldBeActive: visibilities.worldOpen && Config.launcher.enabled

    property real offsetScale: shouldBeActive ? 0 : 1

    // Dismissal must be available before the asynchronous scene is ready.
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.shouldBeActive
        onActivated: {
            if (sceneLoader.item) sceneLoader.item.handleEscape();
            else root.visibilities.closeWorld("escape");
        }
    }

    // Retain the warm scene between opens outside Performance mode.
    property bool loaderActive: false

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            loaderActive = true;
            refreshPending = true;
            Qt.callLater(root.reloadWhenReady);
        } else {
            sceneLoader.item?.saveContext();
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
        running: !GameMode.releaseScenes && !root.loaderActive && root.screen.name === Hypr.focusedMonitor?.name
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
        active: root.loaderActive && (!GameMode.releaseScenes || root.shouldBeActive || root.offsetScale < 1)
        // Parsing the scene must not block the opening animation.
        asynchronous: true
        onStatusChanged: {
            if (status === Loader.Error && root.shouldBeActive) {
                console.warn("World scene failed to load");
                root.visibilities.closeWorld("load-error");
            }
        }

        sourceComponent: Content {
            visibilities: root.visibilities
            panels: root.panels
        }
    }
}
