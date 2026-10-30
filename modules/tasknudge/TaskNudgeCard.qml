pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.components.widgets
import qs.components.controls
import qs.components.tasks
import qs.services
import Burl.Config

FocusScope {
    id: root
    focus: true

    signal clockInRequested(var task)
    signal dismissed
    signal stopRemindersRequested

    property string query: ""
    readonly property var availableTasks: (Tasks.tasks ?? []).filter(task =>
        !task.projectHeading && !["PROJECT", "DONE", "HOLD", "CANCELLED"].includes(task.state))
    readonly property var matchingTasks: {
        const words = query.toLowerCase().trim().split(/\s+/).filter(Boolean);
        return availableTasks.filter(task => {
            const text = [task.title, task.project, ...(task.tags ?? [])].join(" ").toLowerCase();
            return words.every(word => text.includes(word));
        });
    }

    function chooseSelected(): void {
        if (Tasks.clockInPending)
            return;
        if (Tasks.onBreak)
            Tasks.endBreak();
        else if (taskList.currentIndex >= 0 && taskList.currentIndex < matchingTasks.length)
            clockInRequested(matchingTasks[taskList.currentIndex]);
    }

    function moveSelection(delta: int): void {
        if (Tasks.onBreak || !matchingTasks.length)
            return;
        taskList.currentIndex = Math.max(0, Math.min(matchingTasks.length - 1, taskList.currentIndex + delta));
        taskList.positionViewAtIndex(taskList.currentIndex, ListView.Contain);
    }

    onMatchingTasksChanged: taskList.currentIndex = matchingTasks.length ? 0 : -1
    Component.onCompleted: {
        if (Tasks.onBreak)
            root.forceActiveFocus();
        else
            search.forceActiveFocus();
    }

    Keys.onEscapePressed: {
        if (Tasks.onBreak)
            Tasks.endBreak();
        else
            root.dismissed();
    }
    Keys.onUpPressed: root.moveSelection(-1)
    Keys.onDownPressed: root.moveSelection(1)
    Keys.onReturnPressed: root.chooseSelected()
    Keys.onEnterPressed: root.chooseSelected()

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Woodland.midnight, 0.72)
        MouseArea {
            anchors.fill: parent
            onClicked: if (!Tasks.onBreak) root.dismissed()
        }
    }

    StyledRect {
        id: panel
        objectName: "taskNudgePanel"
        anchors.centerIn: parent
        width: Math.min(840, parent.width - 48)
        height: Math.min(Tasks.onBreak ? 520 : 820, parent.height - 48)
        radius: Tokens.rounding.large
        color: Woodland.velvet

        OccultFrame { anchors.fill: parent; radius: parent.radius }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.large

                Item {
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: 92
                    CelestialSeal {
                        anchors.fill: parent
                        star: false
                        ink: Woodland.brass
                        opacity: 0.5
                    }
                    CircularProgress {
                        anchors.fill: parent
                        anchors.margins: 8
                        strokeWidth: 2
                        value: Tasks.pomodoro.enabled ? 1 - Tasks.livePercent / 100 : 1
                        fgColour: Tasks.onBreak ? Woodland.seal : Woodland.brass
                        bgColour: Qt.alpha(Woodland.brass, 0.12)
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: Tasks.pomodoro.enabled ? Tasks.liveTime : qsTr("FOCUS")
                        font.family: "monospace"
                        font.pixelSize: Tasks.pomodoro.enabled ? 20 : 13
                        color: Woodland.ivory
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: Tasks.onBreak ? qsTr("REST & REFLECT") : qsTr("CHOOSE YOUR TASK")
                        font.letterSpacing: 2
                        font.pointSize: Tokens.font.label.medium.pointSize
                        color: Woodland.brass
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Tasks.onBreak ? qsTr("Take a break") : Tasks.clockedIn ? qsTr("Switch your focus") : qsTr("Begin a focus session")
                        font: Tokens.font.headline.small
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Tasks.onBreak ? qsTr("Relax your hands. %1 remaining.").arg(Tasks.liveTime)
                            : Tasks.clockedIn ? qsTr("Current: %1").arg(Tasks.pomodoro.task ?? "")
                            : qsTr("Search tasks or projects, then press Enter to clock in.")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !Tasks.onBreak
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("%1 of %2 available tasks").arg(root.matchingTasks.length).arg(root.availableTasks.length)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                NavigationTabs {
                    model: [{text: "@work"}, {text: "@personal"}]
                    currentIndex: Tasks.filter === "@personal" ? 1 : 0
                    onActivated: index => Tasks.setFilter(model[index].text)
                }
            }

            StyledTextField {
                id: search
                objectName: "taskNudgeSearch"
                Layout.fillWidth: true
                visible: !Tasks.onBreak
                leadingIcon: "search"
                placeholderText: qsTr("Search tasks, projects or tags")
                onTextChanged: root.query = text
                onAccepted: root.chooseSelected()
                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onDownPressed: root.moveSelection(1)
            }

            ListView {
                id: taskList
                objectName: "taskNudgeList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !Tasks.onBreak
                clip: true
                spacing: 4
                model: root.matchingTasks
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: StyledScrollBar { flickable: taskList }

                delegate: StyledRect {
                    id: taskRow
                    required property var modelData
                    required property int index
                    width: taskList.width - 12
                    height: taskInfo.implicitHeight + 22
                    radius: Tokens.rounding.small
                    color: ListView.isCurrentItem ? Colours.palette.m3secondaryContainer
                        : rowMouse.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"
                    border.width: ListView.isCurrentItem ? 1 : 0
                    border.color: Qt.alpha(Woodland.brass, 0.4)

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            taskList.currentIndex = taskRow.index;
                            root.chooseSelected();
                        }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 14
                        StyledText {
                            Layout.preferredWidth: 64
                            text: taskRow.modelData.state
                            font: Tokens.font.label.small
                            color: Woodland.brass
                        }
                        ColumnLayout {
                            id: taskInfo
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                text: taskRow.modelData.title
                                font: Tokens.font.body.medium
                                elide: Text.ElideRight
                                color: taskRow.ListView.isCurrentItem ? Colours.palette.m3onSecondaryContainer : Woodland.ivory
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: [taskRow.modelData.project, ...(taskRow.modelData.tags ?? [])].filter(Boolean).join(" · ")
                                visible: text.length > 0
                                font: Tokens.font.body.small
                                color: taskRow.ListView.isCurrentItem ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                        MaterialIcon {
                            text: "play_arrow"
                            color: Woodland.brass
                            font: Tokens.font.icon.small
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    visible: taskList.count === 0
                    text: root.query ? qsTr("No matching tasks") : qsTr("No available tasks in %1").arg(Tasks.filter)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Flickable {
                id: reportFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Tasks.onBreak
                contentWidth: width
                contentHeight: report.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: StyledScrollBar { flickable: reportFlick }
                WorklogReport {
                    id: report
                    width: reportFlick.width - 12
                    report: Tasks.dailyData
                    loading: Tasks.dailyLoading
                    error: Tasks.dailyError
                }
            }

            StyledTextField {
                id: addField
                Layout.fillWidth: true
                visible: !Tasks.onBreak
                leadingIcon: "add"
                placeholderText: qsTr("New task in %1").arg(Tasks.filter)
                onAccepted: {
                    const title = text.trim();
                    if (title) {
                        Tasks.addTask("", title);
                        text = "";
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                visible: !Tasks.onBreak
                spacing: Tokens.spacing.small
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

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.alpha(Woodland.brass, 0.24)
            }

            StyledText {
                Layout.fillWidth: true
                visible: Tasks.clockInError.length > 0
                text: Tasks.clockInError
                color: Colours.palette.m3error
                font: Tokens.font.body.small
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Flow {
                objectName: "taskNudgeActions"
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                spacing: Tokens.spacing.small
                TextButton {
                    visible: !Tasks.onBreak
                    enabled: root.matchingTasks.length > 0 && !Tasks.clockInPending
                    text: Tasks.clockInPending ? qsTr("Clocking in…") : Tasks.clockedIn ? qsTr("Switch task") : qsTr("Clock in")
                    onClicked: root.chooseSelected()
                }
                TextButton {
                    visible: !Tasks.onBreak && Tasks.clockedIn
                    text: qsTr("Clock out")
                    onClicked: Tasks.clockOut()
                }
                TextButton {
                    visible: !Tasks.onBreak
                    text: GlobalConfig.tasknudge.deferMinutes > 0 ? qsTr("Defer %1 min (Esc)").arg(GlobalConfig.tasknudge.deferMinutes) : qsTr("Dismiss (Esc)")
                    onClicked: root.dismissed()
                }
                TextButton {
                    visible: !Tasks.onBreak && Tasks.clockInReminders
                    text: qsTr("Stop reminders")
                    onClicked: root.stopRemindersRequested()
                }
                TextButton {
                    visible: Tasks.onBreak
                    text: qsTr("End break & stop")
                    onClicked: Tasks.stopPomodoro()
                }
                TextButton {
                    visible: Tasks.onBreak
                    text: qsTr("End break & restart")
                    onClicked: Tasks.endBreak()
                }
            }
        }
    }
}
