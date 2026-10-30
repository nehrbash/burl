pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.services
import Burl.Config

Scope {
    id: root

    property bool deferred: true
    property bool manuallyOpen
    property bool breakDismissed: false

    readonly property bool needsClockIn: !Tasks.clockedIn && !Tasks.onBreak && Tasks.clockInReminders
    readonly property bool shouldShow: GlobalConfig.tasknudge.enabled && ((Tasks.onBreak && !breakDismissed) || manuallyOpen || (needsClockIn && !deferred))

    function dismiss(): void {
        root.breakDismissed = Tasks.onBreak;
        root.manuallyOpen = false;
        root.deferred = true;
    }

    function stopClockInReminders(): void {
        if (Tasks.clockInReminders)
            Tasks.toggleClockInReminders();
        root.manuallyOpen = false;
        root.deferred = true;
    }

    function openPicker(): void {
        root.manuallyOpen = true;
        root.deferred = false;
        Tasks.clockInError = "";
        Tasks.refresh();
    }

    onShouldShowChanged: Tasks.countdownWatchers += shouldShow ? 1 : -1

    Timer {
        interval: Math.max(1, GlobalConfig.tasknudge.deferMinutes) * 60 * 1000
        running: root.deferred && GlobalConfig.tasknudge.deferMinutes > 0
        onTriggered: root.deferred = false
    }

    Connections {
        function onPickerRequested(): void {
            root.openPicker();
        }

        function onClockInSucceeded(): void {
            root.manuallyOpen = false;
            root.deferred = false;
        }

        function onBreakDismissed(): void {
            root.dismiss();
        }

        function onSnapshotUpdated(): void {
            if (!Tasks.onBreak)
                root.breakDismissed = false;
            if (Tasks.clockedIn || Tasks.onBreak)
                root.deferred = false;
            if (Tasks.onBreak && !root._fetchedForBreak) {
                Tasks.fetchReport("today");
                root._fetchedForBreak = true;
            } else if (!Tasks.onBreak) {
                root._fetchedForBreak = false;
            }
        }

        target: Tasks
    }

    property bool _fetchedForBreak: false

    IpcHandler {
        function toggle(): void {
            root.manuallyOpen = !root.manuallyOpen;
            if (root.manuallyOpen)
                root.openPicker();
        }

        function open(): void {
            root.openPicker();
        }

        function close(): void {
            root.dismiss();
        }

        target: "taskNudge"
    }

    LazyLoader {
        active: root.shouldShow

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "task-nudge"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.exclusionMode: ExclusionMode.Ignore

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                TaskNudgeCard {
                    anchors.fill: parent
                    onClockInRequested: task => Tasks.clockInTask(task)
                    onDismissed: root.dismiss()
                    onStopRemindersRequested: root.stopClockInReminders()
                }
            }
        }
    }
}
