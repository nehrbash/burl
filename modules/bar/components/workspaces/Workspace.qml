pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Burl.Config
import qs.components
import qs.components.widgets
import qs.services
import qs.utils

Item {
    id: root

    required property int index
    required property int activeWsId
    required property var occupied
    required property int groupOffset
    required property var otherMonitorWs

    readonly property bool isWorkspace: true
    readonly property int size: Math.ceil(cardHeight + (hasWindows ? windowLoader.height * 0.55 : 0))

    readonly property int ws: groupOffset + index + 1
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied && Config.bar.workspaces.showWindows
    readonly property var otherMonOnThis: otherMonitorWs[ws] ?? null
    readonly property bool isActive: activeWsId === ws

    readonly property real cardHeight: Tokens.sizes.bar.innerWidth * 1.5

    readonly property real activeAmount: isActive ? grow.progress : 0

    onIsActiveChanged: {
        // Performance mode must not animate desktop chrome.
        if (isActive && !GameMode.enabled)
            grow.grow();
        else
            grow.snap();
    }

    Layout.alignment: Qt.AlignHCenter
    Layout.preferredHeight: size

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: cardHeight

    GrowIn {
        id: grow
    }

    TarotCard {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Tokens.sizes.bar.innerWidth
        height: root.cardHeight
        cardIndex: root.ws - 1
        selected: root.isActive
        badge: String(root.ws)
        monitorAccent: root.otherMonOnThis ?? "transparent"
        anchors.horizontalCenterOffset: -2
        scale: root.isActive ? 0.97 + root.activeAmount * 0.03 : 0.94
    }

    Loader {
        id: windowLoader
        x: 0
        y: root.cardHeight - height * 0.45
        width: Tokens.sizes.bar.innerWidth * 0.55
        height: width
        visible: active
        active: root.hasWindows
        asynchronous: true

        sourceComponent: BarkSocket {
            id: appSeal
            readonly property string activeClass: {
                const tls = Hypr.toplevels.values.filter(c => c.workspace?.id === root.ws);
                const active = tls.find(t => t.activated) ?? tls[0];
                return active ? (active.lastIpcObject?.class ?? active.wayland?.appId ?? "") : "";
            }

            IconImage {
                anchors.fill: parent
                anchors.margins: parent.width * 0.16
                source: Icons.getAppIcon(appSeal.activeClass, "application-x-executable")
                asynchronous: true
            }
        }
    }

    Behavior on Layout.preferredHeight {
        Anim {}
    }
}
