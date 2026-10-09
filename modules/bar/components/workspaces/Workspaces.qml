pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import Burl.Config

Item {
    id: root

    required property ShellScreen screen

    readonly property int activeWsId: GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen).activeWorkspace?.id ?? 1) : Hypr.activeWsId
    readonly property bool isFocusedMonitor: Hypr.focusedMonitor === Hypr.monitorFor(screen)

    readonly property var occupied: {
        // toplevels.values is kept accurate by Quickshell core on every
        // openwindow/closewindow event. lastIpcObject.windows only updates
        // on a full refreshWorkspaces fetch, which forced an IPC+rebind
        // cascade on every workspace switch — multi-second stalls.
        const occ = {};
        for (const ws of Hypr.workspaces.values)
            occ[ws.id] = ws.toplevels.values.length > 0;
        return occ;
    }
    // Always show workspaces 1..shown; never page to the next group when
    // the active workspace exceeds it (only 1-7 are used on this setup).
    readonly property int groupOffset: 0

    readonly property var monitorColors: [
        Colours.palette.m3primary,
        Colours.palette.m3secondary,
        Colours.palette.m3tertiary,
    ]

    readonly property var otherMonitors: {
        const thisMonName = Hypr.monitorFor(screen)?.name ?? "";
        return Hypr.monitors.values.filter(m => m.name !== thisMonName);
    }

    readonly property var otherMonitorWs: {
        const map = {};
        for (const mon of root.otherMonitors) {
            const wsId = mon.activeWorkspace?.id;
            const monIdx = Hypr.monitors.values.indexOf(mon);
            if (wsId)
                map[wsId] = root.monitorColors[monIdx % root.monitorColors.length] ?? Colours.palette.m3secondary;
        }
        return map;
    }

    readonly property var specialWsList: Hypr.workspaces.values.filter(w => w.name.startsWith("special:") && (!GlobalConfig.bar.workspaces.perMonitorWorkspaces || w.monitor === Hypr.monitorFor(screen)))

    // Hit-test for Bar.checkPopout — y in this item's coordinate space.
    // Covers normal and special workspaces; returns [wsId, centerY in this
    // item's space] or null.
    function workspaceInfoAt(y: real): var {
        const w = layout.childAt(layout.width / 2, root.mapToItem(layout, 0, y).y) as Workspace;
        if (w)
            return [w.ws, w.mapToItem(root, 0, w.size / 2).y];

        if (specialWs.item) {
            const sy = root.mapToItem(specialWs, 0, y).y;
            const s = specialWs.item.wsAt(sy);
            if (s)
                return [s[0], specialWs.mapToItem(root, 0, s[1]).y];
        }
        return null;
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: column.implicitHeight

    Flickable {
        id: workspaceScroll

        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight * column.scale
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height + 1

        ScrollBar.vertical: ScrollBar {
            id: scrollBar
            policy: workspaceScroll.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            background: null
            contentItem: Rectangle {
                implicitWidth: 2
                radius: 1
                color: "#b59a69"
                opacity: scrollBar.active ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }

        ColumnLayout {
            id: column
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.implicitWidth
            height: implicitHeight
            transformOrigin: Item.Top
            scale: Math.max(0.65, Math.min(1, root.height / Math.max(1, implicitHeight)))
            spacing: Tokens.spacing.medium

            Item {
                id: normalArea

                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Tokens.sizes.bar.innerWidth
                implicitHeight: layout.implicitHeight + Tokens.padding.small * 2

                // Behind the column, so the pill reads as a groove the occupied
                // workspaces sit in rather than a badge over them.
                Loader {
                    anchors.fill: layout
                    asynchronous: true
                    active: Config.bar.workspaces.occupiedBg

                    sourceComponent: OccupiedBg {
                        workspaces: workspaces
                        occupied: root.occupied
                        groupOffset: root.groupOffset
                    }
                }

                ColumnLayout {
                    id: layout

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.medium

                    Repeater {
                        id: workspaces

                        model: Config.bar.workspaces.shown

                        Workspace {
                            activeWsId: root.activeWsId
                            occupied: root.occupied
                            groupOffset: root.groupOffset
                            otherMonitorWs: root.otherMonitorWs
                        }
                    }
                }

                MouseArea {
                    anchors.fill: layout

                    // Coalesce rapid clicks. Hypr.activeWsId updates async (event ->
                    // refreshWorkspaces IPC), so within a few hundred ms of spamming,
                    // it lags behind reality and the "skip if already active" guard
                    // misses. Track our own last-dispatched target to drop redundant
                    // dispatches before they reach Hyprland.
                    property int lastDispatchedWs: -1
                    property double lastDispatchTime: 0

                    onClicked: event => {
                        const ws = (layout.childAt(event.x, event.y) as Workspace)?.ws;
                        if (!ws) return;
                        if (Hypr.activeWsId === ws) {
                            ShellState.selectWorkspace([]);
                            return;
                        }
                        const now = Date.now();
                        if (lastDispatchedWs === ws && now - lastDispatchTime < 400) {
                            ShellState.selectWorkspace([]);
                            return;
                        }
                        lastDispatchedWs = ws;
                        lastDispatchTime = now;
                        const mon = Hypr.monitorFor(root.screen);
                        const wsObj = Hypr.workspaces.values.find(w => w.id === ws);
                        const reqs = [];
                        if (wsObj && wsObj.monitor && wsObj.monitor !== mon)
                            reqs.push(`moveworkspacetomonitor ${ws} ${mon?.name ?? ""}`);
                        reqs.push(`workspace ${ws}`);
                        ShellState.selectWorkspace(reqs);
                    }
                }
            }

            Loader {
                id: specialWs

                asynchronous: true
                active: root.specialWsList.length > 0
                visible: active

                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Tokens.sizes.bar.innerWidth
                Layout.preferredHeight: item?.implicitHeight ?? 0

                sourceComponent: SpecialWorkspaces { screen: root.screen }
            }
        }
    }
}
