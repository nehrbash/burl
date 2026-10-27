import QtQuick
import qs.modules.bar.components.workspaces

Item {
    id: root

    Workspace {
        id: card
        anchors.centerIn: parent
        index: 0
        activeWsId: 1
        occupied: ({})
        groupOffset: 0
        otherMonitorWs: ({})
        focusedMonitor: true
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            const sigil = card.children.find(child => child.objectName === "monitorFocusSigil");
            if (!sigil || !sigil.visible)
                throw new Error("Focused active workspace must show its eye");
            card.focusedMonitor = false;
            if (sigil.visible)
                throw new Error("Unfocused monitor must hide its eye");
            card.focusedMonitor = true;
            card.activeWsId = 2;
            if (sigil.visible)
                throw new Error("Inactive workspace must hide its eye");
            card.activeWsId = 1;
            if (!sigil.visible)
                throw new Error("Returning focus must restore the eye");
            console.log("MONITOR-FOCUS-PASS");
        }
    }
}
