import QtQuick
import Quickshell
import qs.modules.bar.popouts

Item {
    id: root
    property int step: 0
    property real tallTop: 0
    property real tallHeight: 0

    ClipWrapper {
        id: panel
        screen: Quickshell.screens[0]
        borderThickness: 0
        content.animLength: 0
        content.currentCenter: 700
        content.currentName: "network"
        content.hasCurrent: true
    }

    function check(condition, message) {
        if (!condition) throw new Error(message);
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            const page = panel.content.current;
            if (!page && root.step < 3) return;
            switch (++root.step) {
            case 1:
                page.implicitHeight = 650;
                break;
            case 2:
                root.tallTop = panel.y;
                root.tallHeight = panel.height;
                page.view = "wireless";
                page.implicitHeight = 150;
                break;
            case 3:
                root.check(panel.height < root.tallHeight - 400, "Panel must shrink to the shorter page");
                root.check(Math.abs(panel.y - root.tallTop) < 1, "Tab row must stay under the pointer when shrinking");
                root.check(panel.content.hasCurrent, "Resizing must keep the popout open");
                panel.content.hasCurrent = false;
                break;
            case 5:
                panel.content.hasCurrent = true;
                break;
            case 7:
                root.check(panel.placementHeight < root.tallHeight, "Reopening must discard the previous size");
                root.check(panel.y > root.tallTop, "Reopening must center the new page normally");
                console.log("POPOUT-RESIZE-PASS");
                stop();
                break;
            }
        }
    }
}
