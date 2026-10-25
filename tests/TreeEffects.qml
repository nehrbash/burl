pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.components.widgets

Item {
    id: root
    property int step: 0
    property int arrivals: 0

    function check(value: bool, message: string): void {
        if (!value) {
            console.error("TREE-EFFECTS-FAIL", message);
            Qt.quit();
        }
    }

    TreeEmbers {
        id: embers
        anchors.fill: parent
        pointAt: t => ({ x: 0.5, y: 1 - t })
        onArrived: root.arrivals++
    }
    BarkRunes {
        id: runes
        anchors.fill: parent
        sites: [{ x: 0.5, y: 0.5 }]
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            switch (++root.step) {
            case 1:
                embers.active = true;
                break;
            case 3:
                root.check(embers.running, "selection starts a procession");
                break;
            case 20:
                root.check(!embers.running && root.arrivals === 1, "procession finishes exactly once");
                break;
            case 24:
                root.check(!embers.running && root.arrivals === 1, "selection does not loop");
                embers.ignite();
                break;
            case 25:
                embers.visible = false;
                root.check(!embers.running, "hidden embers stop immediately");
                runes.light = 0.7;
                runes.visible = false;
                root.check(!runes.awake && runes.light === 0, "hidden runes clear their light");
                embers.animated = false;
                embers.visible = true;
                embers.ignite();
                root.check(!embers.running, "disabled motion cannot restart embers");
                break;
            case 28:
                embers.animated = true;
                root.check(embers.running, "visible active selection can restart");
                embers.active = false;
                root.check(!embers.running, "changing selection cancels old embers");
                Ambience.master = false;
                embers.active = true;
                runes.visible = true;
                root.check(!embers.running && !runes.awake, "reduced motion disables both effects");
                console.log("TREE-EFFECTS-PASS");
                stop();
                break;
            }
        }
    }
}
