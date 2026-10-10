pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
// Aliased so the Pomodoro *component* can be named unambiguously: a bare
// `Pomodoro` resolves to the qs.services singleton of the same name
import "components" as Components
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import Burl.Config

ColumnLayout {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    readonly property int vPadding: Tokens.padding.large + 30

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        for (let i = 0; i < repeater.count; i++) {
            const tray = (repeater.itemAt(i) as EntryWrapper).item as Tray;
            if (tray)
                tray.expanded = false;
        }
    }

    function checkPopout(y: real): void {
        const ch = childAt(width / 2, y) as EntryWrapper;

        if (ch?.entryId !== "tray")
            closeTray();

        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const id = ch.entryId;
        const top = ch.y;

        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const icon = items.childAt(items.width / 2, mapToItem(items, 0, y).y);
            if (icon) {
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => icon.mapToItem(root, 0, icon.implicitHeight / 2).y);
                popouts.hasCurrent = true;
            }
        } else if (id === "pomodoro") {
            popouts.currentName = "focustimer";
            popouts.currentCenter = ch.mapToItem(root, 0, ch.implicitHeight / 2).y;
            popouts.hasCurrent = true;
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            if (!Config.bar.tray.compact || (tray.expanded && !tray.expandIcon.contains(mapToItem(tray.expandIcon, tray.implicitWidth / 2, y)))) {
                const index = Math.floor(((y - top - tray.padding * 2 + tray.spacing) / tray.layout.implicitHeight) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    popouts.currentName = `traymenu${index}`;
                    popouts.currentCenter = Qt.binding(() => trayItem.mapToItem(root, 0, trayItem.implicitHeight / 2).y);
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else if (id === "activeWindow" && Config.bar.activeWindow.showOnHover) {
            popouts.currentName = "activewindow";
            popouts.currentCenter = Qt.binding(() => ch.mapToItem(root, 0, ch.implicitHeight / 2).y);
            popouts.hasCurrent = true;
        } else if (id === "workspaces") {
            // Branch popout with the workspace's other windows (the active
            // one is already shown under the card; special workspaces
            // show all their windows)
            const wsComp = ch.item as Workspaces;
            const info = wsComp.workspaceInfoAt(mapToItem(ch.item, 0, y).y);
            const minCount = info && info[0] < 0 ? 1 : 2;
            const count = info ? Hypr.toplevels.values.filter(c => c.workspace?.id === info[0]).length : 0;
            if (count >= minCount) {
                popouts.workspaceId = info[0];
                popouts.currentName = "workspaceapps";
                popouts.currentCenter = wsComp.mapToItem(root, 0, info[1]).y;
                popouts.hasCurrent = true;
            } else {
                popouts.hasCurrent = false;
            }
        }
    }

    function handleWheel(y: real, angleDelta: point): void {
        const ch = childAt(width / 2, y) as EntryWrapper;
        if (ch?.entryId === "workspaces" && Config.bar.scrollActions.workspaces) {
            const mon = (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                ShellState.selectWorkspace([Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`]);
            else {
                const active = GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (mon.activeWorkspace?.id ?? 1) : Hypr.activeWsId;
                // Clamp scroll to the shown group (1..shown) — no drifting past it
                if (angleDelta.y > 0 ? active > 1 : active < Config.bar.workspaces.shown)
                    ShellState.selectWorkspace([Hypr.usingLua ? `hl.dsp.focus({ workspace = "r${angleDelta.y > 0 ? "-" : "+"}1" })` : `workspace r${angleDelta.y > 0 ? "-" : "+"}1`]);
            }
        } else if (y < screen.height / 2 && Config.bar.scrollActions.volume) {
            if (angleDelta.y > 0)
                Audio.incrementVolume();
            else if (angleDelta.y < 0)
                Audio.decrementVolume();
        } else if (Config.bar.scrollActions.brightness) {
            const monitor = Brightness.getMonitorForScreen(screen);
            if (angleDelta.y > 0)
                monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
            else if (angleDelta.y < 0)
                monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
        }
    }

    spacing: Tokens.spacing.medium

    // Tree decorations are in BarWrapper.qml to avoid interfering
    // with childAt() popout detection in checkPopout()

    Repeater {
        id: repeater

        model: ScriptModel {
            values: root.Config.bar.entries.filter(e => e.id !== "settings" && (e.enabled ?? true))
        }

        DelegateChooser {
            role: "id"

            DelegateChoice {
                roleValue: "spacer"
                delegate: EntryWrapper {
                    Layout.fillHeight: true
                    Layout.maximumHeight: Tokens.sizes.bar.innerWidth
                }
            }
            DelegateChoice {
                roleValue: "logo"
                delegate: EntryWrapper {
                    OsIcon {
                        objectName: "taskbarLogo"
                    }
                }
            }
            DelegateChoice {
                roleValue: "workspaces"
                delegate: EntryWrapper {
                    Workspaces {
                        objectName: "taskbarWorkspaces"
                        screen: root.screen
                        height: parent.height
                    }
                }
            }
            DelegateChoice {
                roleValue: "tray"
                delegate: EntryWrapper {
                    Tray {
                        objectName: "taskbarTray"
                    }
                }
            }
            DelegateChoice {
                roleValue: "clock"
                delegate: EntryWrapper {
                    Clock {
                        objectName: "taskbarClock"
                    }
                }
            }
            DelegateChoice {
                roleValue: "statusIcons"
                delegate: EntryWrapper {
                    StatusIcons {
                        objectName: "taskbarStatusIcons"
                    }
                }
            }
            DelegateChoice {
                roleValue: "activeWindow"
                delegate: EntryWrapper {
                    Components.ActiveWindow {
                        objectName: "taskbarActiveWindow"
                        bar: root
                        monitor: Brightness.getMonitorForScreen(root.screen)
                    }
                }
            }
            DelegateChoice {
                roleValue: "pomodoro"
                delegate: EntryWrapper {
                    Components.Pomodoro {
                        objectName: "taskbarPomodoro"
                    }
                }
            }
        }
    }

    component EntryWrapper: Item {
        required property var modelData
        required property int index
        default property Item item
        readonly property string entryId: modelData.id

        Layout.topMargin: index === 0 ? 24 : 0
        Layout.bottomMargin: index === repeater.count - 1 ? root.vPadding : 0
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumHeight: implicitHeight
        Layout.minimumHeight: entryId === "workspaces" || entryId === "spacer" ? 0 : implicitHeight
        Layout.fillHeight: entryId === "workspaces"

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item
    }
}
