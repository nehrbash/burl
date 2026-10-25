pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Burl.Config
import qs.components
import qs.services
import qs.modules.drawers
import qs.modules.bar

Item {
    id: root
    property string room: "launcher"
    property bool marker: false

    Config.screen: Quickshell.screens[0].name
    Tokens.screen: Quickshell.screens[0].name

    ScreenState { id: state; modelData: Quickshell.screens[0] }
    Panels {
        id: panels
        popoutLayer: popoutOverlay
        screen: Quickshell.screens[0]
        screenState: state
        bar: bar
        borderThickness: 0
    }
    BarWrapper {
        id: bar
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        screen: Quickshell.screens[0]
        screenState: state
        popouts: panels.popouts
        fullscreen: false
    }
    Item {
        id: popoutOverlay
        x: panels.x
        y: panels.y
        width: panels.width
        height: panels.height
    }
    Rectangle {
        id: coverageProbe
        parent: panels.popouts
        x: 12
        y: 80
        visible: root.marker && parent !== null
        width: 50
        height: 100
        color: "#ff00ff"
        z: 1000
    }
    Timer {
        interval: 200
        running: true
        onTriggered: {
            state.openRoom(root.room, "test");
            panels.popouts.currentCenter = root.height * 0.65;
            panels.popouts.currentName = "focustimer";
            panels.popouts.pinned = true;
            panels.popouts.hasCurrent = true;
        }
    }
    Timer {
        interval: 3500
        running: true
        onTriggered: {
            const panel = panels.popouts;
            const current = panel.current;
            const point = coverageProbe.mapToItem(root, 0, 0);
            const origin = panel.mapToItem(root, 0, 0);
            console.log("POPOUT-PROBE", point.x, point.y, origin.x, origin.y, panel.width, panel.height, Colours.palette.m3surface);
            if (!current || panel.width < 100 || panel.height < 100) console.error("POPOUT-FAIL: panel did not open");
        }
    }
}
