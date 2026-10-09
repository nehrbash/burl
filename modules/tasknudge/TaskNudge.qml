pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.components.widgets
import qs.components.containers
import qs.components.controls
import qs.components.tasks
import qs.services
import Burl.Config

Scope {
    id: root

    property bool deferred: true
    property bool manuallyOpen

    readonly property bool needsClockIn: !Tasks.clockedIn && !Tasks.onBreak && Tasks.clockInReminders
    readonly property bool shouldShow: GlobalConfig.tasknudge.enabled && (Tasks.onBreak || manuallyOpen || (needsClockIn && !deferred))

    // Keyboard selection into `_taskSlice`.
    property int selectedIndex: 0

    function clampSelection(): void {
        const n = _taskSlice.length;
        if (n === 0)
            selectedIndex = 0;
        else if (selectedIndex >= n)
            selectedIndex = n - 1;
        else if (selectedIndex < 0)
            selectedIndex = 0;
    }

    function onBreakOrClockIn(): void {
        if (Tasks.onBreak)
            Tasks.endBreak();
        else
            clockInSelected();
    }

    function clockInSelected(): void {
        // Straight through, like the Tasks tab — no Qt.callLater wrapper.
        if (Tasks.clockInTask(root._taskSlice[root.selectedIndex])) {
            root.manuallyOpen = false;
            root.deferred = false;
        }
    }

    // The nudge is the only view of Tasks' live countdown, and its windows stay
    // mounted after the first show, so subscribe/unsubscribe here rather than
    // from the loaded content — that is what keeps the 1Hz tick off while the
    // overlay is down.
    onShouldShowChanged: {
        Tasks.countdownWatchers += shouldShow ? 1 : -1;
        if (shouldShow)
            selectedIndex = 0;
    }

    // Re-arm the deferral. This overlay takes the whole screen and keyboard,
    // so a short interval reads as harassment rather than a nudge. 0 makes a
    // dismissal final until you clock in or restart the shell.
    Timer {
        interval: Math.max(1, GlobalConfig.tasknudge.deferMinutes) * 60 * 1000
        running: root.deferred && GlobalConfig.tasknudge.deferMinutes > 0
        onTriggered: root.deferred = false
    }

    Connections {
        function onSnapshotUpdated(): void {
            root.clampSelection();
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
            if (root.manuallyOpen) {
                root.deferred = false;
                Tasks.refresh();
            }
        }

        function open(): void {
            root.manuallyOpen = true;
            root.deferred = false;
            Tasks.refresh();
        }

        function close(): void {
            root.manuallyOpen = false;
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
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                WlrLayershell.exclusionMode: ExclusionMode.Ignore

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    id: dim

                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.55)
                    focus: true

                    Component.onCompleted: forceActiveFocus()
                    onVisibleChanged: if (visible)
                        forceActiveFocus()

                    Keys.onEscapePressed: {
                        if (Tasks.onBreak)
                            return;
                        root.manuallyOpen = false;
                        root.deferred = true;
                    }

                    Keys.onUpPressed: {
                        if (Tasks.onBreak)
                            return;
                        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                    }
                    Keys.onDownPressed: {
                        if (Tasks.onBreak)
                            return;
                        root.selectedIndex = Math.min(root._taskSlice.length - 1, root.selectedIndex + 1);
                    }

                    Keys.onReturnPressed: root.onBreakOrClockIn()
                    Keys.onEnterPressed: root.onBreakOrClockIn()

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (Tasks.onBreak)
                                return;
                            root.manuallyOpen = false;
                            root.deferred = true;
                        }
                    }

                    StyledRect {
                        anchors.centerIn: parent
                        implicitWidth: Math.min(720, parent.width - 80)
                        implicitHeight: card.implicitHeight + Tokens.padding.large * 2
                        radius: Tokens.rounding.large
                        color: Colours.palette.m3surfaceContainer

                        OccultFrame { anchors.fill: parent; radius: parent.radius }

                        // Eat clicks so background MouseArea doesn't dismiss
                        MouseArea {
                            anchors.fill: parent
                        }

                        ColumnLayout {
                            id: card

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.medium

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.medium

                                Item {
                                    Layout.preferredWidth: 96
                                    Layout.preferredHeight: 96

                                    CircularProgress {
                                        anchors.fill: parent
                                        strokeWidth: 6
                                        value: Tasks.livePercent / 100
                                        fgColour: Tasks.onBreak ? Colours.palette.m3tertiary : Colours.palette.m3primary
                                        bgColour: Colours.palette.m3secondaryContainer
                                    }

                                    Image {
                                        anchors.centerIn: parent
                                        width: 56
                                        height: 56
                                        source: Quickshell.shellPath(Tasks.liveTime !== "00:00" ? "assets/images/pomodoro/tomato.png" : "assets/images/pomodoro/tomato-sad.png")
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }

                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: -4
                                        text: Tasks.liveTime
                                        font.pointSize: Tokens.font.body.small.pointSize
                                        font.weight: 500
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.small

                                    StyledText {
                                        text: Tasks.onBreak ? qsTr("Take a break") : qsTr("Not clocked in")
                                        font.pointSize: Tokens.font.body.large.pointSize
                                        font.weight: 500
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Tasks.onBreak ? qsTr("Relax your hands. Timer ends in %1.").arg(Tasks.liveTime) : qsTr("↑↓ to choose, Enter to clock in, Esc to defer 5 min.")
                                        color: Colours.palette.m3outline
                                        wrapMode: Text.Wrap
                                    }

                                    StyledText {
                                        visible: Tasks.pomodoro.task && Tasks.pomodoro.task !== "No Active Task" && Tasks.pomodoro.task !== "Take a break - relax your hands"
                                        text: qsTr("Last task: %1").arg(Tasks.pomodoro.task ?? "")
                                        color: Colours.palette.m3outline
                                        font.pointSize: Tokens.font.body.small.pointSize
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.spacing.small
                                visible: !Tasks.onBreak
                                spacing: Tokens.spacing.small

                                StyledText {
                                    text: qsTr("Agenda")
                                    font.weight: 500
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                TaskFilterPill {
                                    label: "@work"
                                    active: Tasks.filter === "@work"
                                    onActivated: Tasks.setFilter("@work")
                                }

                                TaskFilterPill {
                                    label: "@personal"
                                    active: Tasks.filter === "@personal"
                                    onActivated: Tasks.setFilter("@personal")
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: !Tasks.onBreak
                                spacing: Tokens.spacing.small

                                StyledText {
                                    text: qsTr("Options")
                                    font.weight: 500
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                TaskFilterPill {
                                    label: qsTr("Pomodoro on clock-in")
                                    active: Tasks.pomodoroOnClockIn
                                    onActivated: Tasks.togglePomodoroOnClockIn()
                                }

                                TaskFilterPill {
                                    label: qsTr("Clock-in reminders")
                                    active: Tasks.clockInReminders
                                    onActivated: Tasks.toggleClockInReminders()
                                }
                            }

                            Repeater {
                                model: Tasks.onBreak ? [] : root._taskSlice

                                delegate: Item {
                                    id: rowItem
                                    required property var modelData
                                    required property int index
                                    readonly property bool selected: index === root.selectedIndex
                                    Layout.fillWidth: true
                                    implicitHeight: rowRect.implicitHeight

                                    StyledRect {
                                        id: rowRect
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        radius: Tokens.rounding.small
                                        color: rowItem.selected ? Colours.palette.m3secondaryContainer : (rowMouse.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent")
                                        implicitHeight: rowInner.implicitHeight + Tokens.padding.medium * 2

                                        MouseArea {
                                            id: rowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: root.selectedIndex = rowItem.index
                                            onClicked: {
                                                root.selectedIndex = rowItem.index;
                                                root.clockInSelected();
                                            }
                                        }

                                        RowLayout {
                                            id: rowInner
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: Tokens.padding.medium
                                            anchors.rightMargin: Tokens.padding.medium
                                            spacing: Tokens.spacing.small

                                            StyledText {
                                                text: rowItem.modelData.state
                                                font.pointSize: Tokens.font.body.small.pointSize
                                                font.weight: 500
                                                Layout.preferredWidth: 96
                                                color: Colours.palette.m3primary
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: rowItem.modelData.title
                                                elide: Text.ElideRight
                                            }

                                            Repeater {
                                                model: rowItem.modelData.tags ?? []

                                                delegate: StyledRect {
                                                    required property string modelData

                                                    radius: Tokens.rounding.full
                                                    color: Colours.layer(Colours.palette.m3surfaceContainer, 3)
                                                    implicitHeight: tagText.implicitHeight + Tokens.padding.small
                                                    implicitWidth: tagText.implicitWidth + Tokens.padding.medium

                                                    StyledText {
                                                        id: tagText
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        font.pointSize: Tokens.font.body.small.pointSize
                                                        color: Colours.palette.m3onSurfaceVariant
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            StyledRect {
                                Layout.fillWidth: true
                                visible: !Tasks.onBreak
                                radius: Tokens.rounding.small
                                color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
                                implicitHeight: addRow.implicitHeight + Tokens.padding.medium * 2

                                RowLayout {
                                    id: addRow

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.padding.medium
                                    anchors.rightMargin: Tokens.padding.medium
                                    spacing: Tokens.spacing.small

                                    MaterialIcon {
                                        text: "add"
                                        font.pointSize: Tokens.font.body.medium.pointSize
                                        color: Colours.palette.m3primary
                                    }

                                    StyledTextField {
                                        id: addField

                                        Layout.fillWidth: true
                                        placeholderText: qsTr("New task in %1…").arg(Tasks.filter)

                                        function submit(): void {
                                            const t = text.trim();
                                            if (t.length === 0)
                                                return;
                                            Tasks.addTask("", t);
                                            text = "";
                                        }

                                        onAccepted: submit()
                                        // Arrow keys should still drive list selection.
                                        Keys.onUpPressed: ev => {
                                            root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                                            ev.accepted = true;
                                        }
                                        Keys.onDownPressed: ev => {
                                            root.selectedIndex = Math.min(root._taskSlice.length - 1, root.selectedIndex + 1);
                                            ev.accepted = true;
                                        }
                                    }
                                }
                            }

                            StyledRect {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 200
                                visible: Tasks.onBreak
                                radius: Tokens.rounding.medium
                                color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

                                Flickable {
                                    id: summaryFlick

                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.medium
                                    contentWidth: summaryText.implicitWidth
                                    contentHeight: summaryText.implicitHeight
                                    clip: true
                                    flickableDirection: Flickable.HorizontalAndVerticalFlick

                                    StyledText {
                                        id: summaryText

                                        text: Tasks.dailyReport && Tasks.dailyReport.length > 0 ? Tasks.dailyReport : qsTr("No clocked time today yet.")
                                        wrapMode: Text.NoWrap
                                        font: Tokens.font.mono.small
                                        textFormat: Text.PlainText
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.spacing.medium
                                spacing: Tokens.spacing.small

                                Item {
                                    Layout.fillWidth: true
                                }

                                ActionButton {
                                    visible: Tasks.onBreak
                                    icon: "stop_circle"
                                    label: qsTr("End break & stop")
                                    onActivated: Tasks.stopPomodoro()
                                }

                                ActionButton {
                                    visible: Tasks.onBreak
                                    primary: true
                                    icon: "restart_alt"
                                    label: qsTr("End break & restart")
                                    onActivated: Tasks.endBreak()
                                }

                                // The overlay had NO clock-in button: the only
                                // ways in were clicking a task row or Enter, and
                                // a click anywhere else dismissed it and
                                // re-nagged, which reads as "clock in is
                                // broken". This is the affirmative action.
                                ActionButton {
                                    visible: !Tasks.onBreak && !Tasks.clockedIn
                                    enabled: root._taskSlice.length > 0
                                    opacity: enabled ? 1 : 0.5
                                    primary: true
                                    icon: "play_arrow"
                                    label: root._taskSlice.length > 0 ? qsTr("Clock in") : qsTr("No tasks")
                                    onActivated: if (root._taskSlice.length > 0)
                                        root.clockInSelected()
                                }

                                ActionButton {
                                    visible: !Tasks.onBreak && Tasks.clockedIn
                                    icon: "pause"
                                    label: qsTr("Clock out")
                                    onActivated: Qt.callLater(() => Tasks.clockOut())
                                }

                                ActionButton {
                                    visible: !Tasks.onBreak
                                    icon: "schedule"
                                    label: GlobalConfig.tasknudge.deferMinutes > 0 ? qsTr("Defer %1 min (Esc)").arg(GlobalConfig.tasknudge.deferMinutes) : qsTr("Dismiss (Esc)")
                                    onActivated: {
                                        root.deferred = true;
                                        root.manuallyOpen = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property var _taskSlice: {
        const out = [];
        const src = Tasks.tasks ?? [];
        for (let i = 0; i < src.length && out.length < 8; i++) {
            const t = src[i];
            if (t.state !== "PROJECT")
                out.push(t);
        }
        return out;
    }


    component ActionButton: StyledRect {
        id: abtn

        property string icon
        property string label
        property bool primary

        signal activated

        radius: Tokens.rounding.full
        color: {
            const base = abtn.primary ? Colours.palette.m3primary : Colours.palette.m3primaryContainer;
            return abtnMa.containsMouse ? Colours.layer(base, 2) : base;
        }
        implicitHeight: abtnRow.implicitHeight + Tokens.padding.medium * 2
        implicitWidth: abtnRow.implicitWidth + Tokens.padding.large * 2

        MouseArea {
            id: abtnMa

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: abtn.activated()
        }

        RowLayout {
            id: abtnRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: abtn.icon
                font.pointSize: Tokens.font.body.medium.pointSize
                color: abtn.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onPrimaryContainer
            }

            StyledText {
                text: abtn.label
                color: abtn.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onPrimaryContainer
            }
        }
    }
}
