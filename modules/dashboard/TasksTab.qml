pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.widgets
import qs.components.tasks
import "dash" as Dash
import qs.services
import Burl.Config

Item {
    id: root

    property string subTab: Tasks.requestedTab
    property bool _addProjectOpen: false
    // Living-tree mode: rows are a translucent m3surfaceContainer wash, legible
    // only against Content.qml's WoodPanel — bare parchment washes titles out.
    // Same contract as Dash/Media/Performance/WeatherTab's `living`.
    property bool living: false
    readonly property bool folio: taskBackdrop.folio

    readonly property color cardColour: Qt.alpha(Colours.palette.m3scrim, folio ? 0.14 : 0.035)
    readonly property color grooveColour: Qt.alpha(Colours.palette.m3onSurface, 0.14)
    readonly property color headerColour: Qt.alpha(Colours.palette.m3primary, 0.065)

    focus: true
    property bool needsKeyboard: subTab === "tasks"
    property int selectedIndex: 0

    // Flat list of navigable (non-PROJECT) tasks within expanded groups,
    // in document order. Keyboard selection indexes into this.
    readonly property var _navTasks: {
        const out = [];
        for (const g of _groups) {
            if (!_isExpanded(g.key))
                continue;
            for (const t of (g.tasks ?? []))
                out.push({
                    project: g.project,
                    title: t.title,
                    state: t.state,
                    key: g.key + "\u0000" + t.title
                });
        }
        return out;
    }
    readonly property string selectedKey: _navTasks[selectedIndex]?.key ?? ""

    function moveSelection(delta: int): void {
        const n = _navTasks.length;
        if (n === 0)
            return;
        selectedIndex = Math.max(0, Math.min(n - 1, selectedIndex + delta));
    }

    function clockInSelected(): void {
        Tasks.clockInTask(root._navTasks[root.selectedIndex]);
    }

    function selectByKey(key: string): void {
        for (let i = 0; i < _navTasks.length; i++)
            if (_navTasks[i].key === key) {
                selectedIndex = i;
                return;
            }
    }

    Keys.onUpPressed: root.moveSelection(-1)
    Keys.onDownPressed: root.moveSelection(1)
    Keys.onReturnPressed: root.clockInSelected()
    Keys.onEnterPressed: root.clockInSelected()

    implicitWidth: 1000
    implicitHeight: 700

    // One plate behind the whole pane, not per-row opacity fixes: rows, headers
    // and the pomodoro strip were designed against one dark surface. Sibling
    // with negative z, not a wrapper, so the layout below doesn't have to move.
    BarkCard {
        id: taskBackdrop
        anchors.fill: parent
        z: -1
        visible: root.living
        opaque: true
        radius: root.folio ? 2 : Tokens.rounding.large
        grainSeed: 41
    }

    onSubTabChanged: if (subTab === "tasks")
        forceActiveFocus()

    Component.onDestruction: Tasks.countdownWatchers--

    Component.onCompleted: {
        Tasks.countdownWatchers++;
        Tasks.refresh();
        Tasks.fetchReport("today");
        Tasks.fetchReport("thisweek");
        forceActiveFocus();
    }

    Connections {
        function onViewRequested(tab: string): void { root.subTab = tab; }

        function onSnapshotUpdated(): void {
            const n = root._navTasks.length;
            if (root.selectedIndex >= n)
                root.selectedIndex = Math.max(0, n - 1);
        }

        target: Tasks
    }

    Flickable {
        id: taskScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: layout.implicitHeight + Tokens.padding.large * 2
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        StyledScrollBar.vertical: StyledScrollBar { flickable: taskScroll }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.topMargin: Tokens.padding.large

        spacing: Tokens.spacing.medium

        NavigationTabs {
            Layout.fillWidth: true
            model: [
                { id: "tasks", text: qsTr("Tasks") },
                { id: "calendar", text: qsTr("Calendar") },
                { id: "today", text: qsTr("Today") },
                { id: "thisweek", text: qsTr("This week") }
            ]
            currentIndex: model.findIndex(tab => tab.id === root.subTab)
            onActivated: index => {
                root.subTab = model[index].id;
                if (root.subTab === "calendar") Agenda.refresh();
                else if (root.subTab === "today" || root.subTab === "thisweek") Tasks.fetchReport(root.subTab);
            }
        }

        WorklogReport {
            Layout.fillWidth: true
            visible: root.subTab === "today" || root.subTab === "thisweek"
            report: root.subTab === "today" ? Tasks.dailyData : Tasks.weeklyData
            loading: root.subTab === "today" ? Tasks.dailyLoading : Tasks.weeklyLoading
            error: root.subTab === "today" ? Tasks.dailyError : Tasks.weeklyError
        }

        Dash.CalendarAgenda {
            Layout.fillWidth: true
            visible: root.subTab === "calendar"
        }

        StyledRect {
            Layout.fillWidth: true
            visible: root.subTab === "tasks"
            color: root.cardColour
            border.width: 1
            border.color: root.grooveColour
            radius: root.folio ? 2 : Tokens.rounding.large
            implicitHeight: pomoRow.implicitHeight + Tokens.padding.large * 2

            WoodPanel {
                visible: !root.folio
                anchors.fill: parent
                radius: parent.radius
            }

            RowLayout {
                id: pomoRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                Item {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 96

                    CircularProgress {
                        anchors.fill: parent
                        strokeWidth: 6
                        value: (root.displayPercent) / 100
                        fgColour: Tasks.onBreak ? Colours.palette.m3tertiary : Colours.palette.m3primary
                        bgColour: Colours.palette.m3secondaryContainer
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Tasks.pomodoro.enabled || Tasks.onBreak ? root.displayTime : "—"
                            font.family: "monospace"
                            font.pixelSize: 22
                            color: Woodland.ivory
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Tasks.onBreak ? qsTr("REST") : Tasks.pomodoro.enabled ? qsTr("FOCUS") : qsTr("OFF")
                            font.pixelSize: 11
                            font.letterSpacing: 1.5
                            color: Woodland.brass
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("TASK BREAK REMINDER")
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                        color: Woodland.brass
                    }
                    StyledText {
                        text: Tasks.onBreak ? qsTr("Rest now · break ends in %1").arg(root.displayTime)
                            : Tasks.pomodoro.enabled ? qsTr("Next break in %1").arg(root.displayTime)
                            : qsTr("Reminders are off · your task clock is separate")
                        font.pixelSize: 12
                        color: Woodland.parchmentMid
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Tasks.pomodoro.task ?? "No Active Task"
                        wrapMode: Text.Wrap
                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                    }

                    PomoButton {
                        icon: Tasks.pomodoro.enabled ? "notifications_off" : "notifications_active"
                        label: Tasks.pomodoro.enabled ? qsTr("Turn reminders off") : qsTr("Enable break reminders")
                        onActivated: Tasks.toggleBreakReminders()
                    }

                    RowLayout {
                        spacing: Tokens.spacing.small

                        PomoButton {
                            icon: "pause"
                            label: qsTr("Clock out")
                            btnEnabled: Tasks.clockedIn
                            onActivated: Tasks.clockOut()
                        }

                        PomoButton {
                            icon: "check_circle"
                            label: qsTr("Done")
                            btnEnabled: Tasks.clockedIn
                            onActivated: Tasks.markDone()
                        }

                        PomoButton {
                            icon: Tasks.onBreak ? "play_arrow" : "coffee"
                            label: Tasks.onBreak ? qsTr("End break") : qsTr("Take a break")
                            onActivated: Tasks.onBreak ? Tasks.endBreak() : Tasks.startBreak()
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.subTab === "tasks"
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Projects · %1 tasks").arg(Tasks.totalCount)
                font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
            }

            Item {
                Layout.fillWidth: true
            }

            NavigationTabs {
                model: [{text: "@work"}, {text: "@personal"}]
                currentIndex: Tasks.filter === "@personal" ? 1 : 0
                onActivated: index => Tasks.setFilter(model[index].text)
            }

            TaskFilterPill {
                label: qsTr("+ Project")
                active: root._addProjectOpen
                onActivated: root._addProjectOpen = !root._addProjectOpen
            }
        }

        AddInline {
            Layout.fillWidth: true
            visible: root.subTab === "tasks" && root._addProjectOpen
            placeholder: qsTr("New project in %1…").arg(Tasks.filter)
            onSubmitted: title => {
                Tasks.addProject(title);
                root._addProjectOpen = false;
            }
        }

        Repeater {
            model: root.subTab === "tasks" ? root._groups : []

            delegate: ColumnLayout {
                id: groupCol

                required property var modelData

                readonly property string projectTitle: modelData.project ?? ""
                readonly property var tasks: modelData.tasks ?? []
                readonly property bool expanded: root._isExpanded(modelData.key)
                // Exposed for taskDelegate (a separate Component, outside groupGrow's
                // id-scope) to read via its runtime `parent` reference instead of the
                // unresolvable bare id.
                readonly property real growProgress: groupGrow.progress

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.medium
                spacing: Tokens.spacing.small

                onExpandedChanged: if (expanded)
                    groupGrow.grow()

                GrowIn {
                    id: groupGrow
                }

                StyledRect {
                    id: header

                    Layout.fillWidth: true
                    radius: Tokens.rounding.small
                    // State layer sits above the bark chrome (below the label) so
                    // hover isn't muted by the decoration.
                    color: root.headerColour
                    implicitHeight: headerRow.implicitHeight + Tokens.padding.small * 2

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Colours.palette.m3primary
                        opacity: headerMouse.containsMouse ? 0.1 : 0

                        // Matches StateLayer's own hover fade
                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    MouseArea {
                        id: headerMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._toggle(groupCol.modelData.key)
                    }

                    RowLayout {
                        id: headerRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: groupCol.expanded ? "expand_more" : "chevron_right"
                            color: Woodland.olive
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: groupCol.projectTitle.length > 0 ? groupCol.projectTitle : qsTr("Inbox")
                            elide: Text.ElideRight
                            font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: {
                                const done = groupCol.tasks.filter(t => t.state === "DONE" || t.state === "CANCELLED").length;
                                return `${done}/${groupCol.tasks.length}`;
                            }
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                GrooveDivider {
                    Layout.fillWidth: true
                    Layout.leftMargin: Tokens.padding.medium
                    Layout.rightMargin: Tokens.padding.medium
                }

                Repeater {
                    model: groupCol.expanded ? groupCol.tasks.map(t => ({
                                title: t.title,
                                state: t.state,
                                tags: t.tags,
                                project: groupCol.projectTitle,
                                key: groupCol.modelData.key + "\u0000" + t.title
                            })) : []

                    delegate: taskDelegate
                }

                AddInline {
                    Layout.fillWidth: true
                    visible: groupCol.expanded
                    placeholder: qsTr("Add task to %1…").arg(groupCol.projectTitle.length > 0 ? groupCol.projectTitle : qsTr("Inbox"))
                    onSubmitted: title => Tasks.addTask(groupCol.projectTitle, title)
                }
            }
        }

        Component {
            id: taskDelegate

            Item {
                id: taskItem

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: rowRect.implicitHeight

                // Rows extend from the twig outward, staggered off ONE animated scalar.
                transform: Scale {
                    origin.x: 0
                    origin.y: 0
                    // groupGrow is out of this Component's id-scope, so `parent.growProgress`
                    // is used instead (see groupCol.growProgress).
                    // Delay is capped at the 0.5 lead-in: uncapped, rows past the 13th
                    // stayed permanently scaled to 0.
                    xScale: Math.max(0, Math.min(1, (taskItem.parent?.growProgress ?? 1) * 1.5 - Math.min(0.5, taskItem.index * 0.06)))
                }

                // A vertical groove running the row's height with a stub reaching
                // out to the row, so the task list reads as growth off the project bough.
                GrooveDivider {
                    id: twig

                    vertical: true
                    x: Tokens.padding.medium
                    y: 0
                    height: parent.height
                    highlightOpacity: 0.6
                }

                GrooveDivider {
                    x: twig.x + 2
                    width: Tokens.spacing.small
                    y: Math.round(parent.height / 2) - 1
                    highlightOpacity: 0.6
                }

                StyledRect {
                    id: rowRect

                    readonly property bool inactive: modelData.state === "DONE" || modelData.state === "HOLD" || modelData.state === "CANCELLED"
                    readonly property bool selected: root.selectedKey.length > 0 && root.selectedKey === modelData.key

                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.medium + Tokens.spacing.small + 2
                    anchors.right: parent.right
                    radius: Tokens.rounding.small
                    readonly property real dimOpacity: inactive ? 0.5 : 1
                    color: rowRect.selected ? Colours.palette.m3secondaryContainer : (taskMouse.containsMouse && !rowRect.inactive ? Qt.alpha(Colours.palette.m3primary, 0.08) : "transparent")
                    implicitHeight: taskRow.implicitHeight + Tokens.padding.small * 2

                    MouseArea {
                        id: taskMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !rowRect.inactive
                        cursorShape: rowRect.inactive ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onEntered: root.selectByKey(modelData.key)
                        onClicked: Tasks.clockIn(modelData.title)
                    }

                    RowLayout {
                        id: taskRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: modelData.state
                            opacity: rowRect.dimOpacity
                            font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                            Layout.preferredWidth: 96
                            color: {
                                switch (modelData.state) {
                                case "ACTIVE":
                                    return Colours.palette.m3primary;
                                case "TODO":
                                    return Colours.palette.m3tertiary;
                                case "HOLD":
                                case "DELEGATED":
                                case "DONE":
                                case "CANCELLED":
                                    return Colours.palette.m3outline;
                                default:
                                    return Colours.palette.m3onSurface;
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.title
                            opacity: rowRect.dimOpacity
                            wrapMode: Text.Wrap
                            font.strikeout: modelData.state === "DONE" || modelData.state === "CANCELLED"
                        }

                        Repeater {
                            model: modelData.tags ?? []

                            delegate: StyledRect {
                                required property string modelData

                                radius: Tokens.rounding.full
                                opacity: rowRect.dimOpacity
                                color: Colours.palette.m3secondaryContainer
                                implicitHeight: tagText.implicitHeight + Tokens.padding.small
                                implicitWidth: tagText.implicitWidth + Tokens.padding.medium

                                StyledText {
                                    id: tagText

                                    anchors.centerIn: parent
                                    text: modelData
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSecondaryContainer
                                }
                            }
                        }

                        RowActionIcon {
                            visible: rowRect.inactive
                            icon: "restart_alt"
                            tooltip: qsTr("Resume")
                            onActivated: Tasks.setState(modelData.title, "TODO")
                        }

                        RowActionIcon {
                            visible: !rowRect.inactive
                            icon: "check_circle"
                            tooltip: qsTr("Done")
                            onActivated: Tasks.setState(modelData.title, "DONE")
                        }

                        RowActionIcon {
                            visible: !rowRect.inactive
                            icon: "pause_circle"
                            tooltip: qsTr("Hold")
                            onActivated: Tasks.setState(modelData.title, "HOLD")
                        }

                        RowActionIcon {
                            icon: "archive"
                            tooltip: qsTr("Cancel & archive")
                            onActivated: Tasks.archive(modelData.title)
                        }
                    }
                }
            }
        }

    }

    }

    readonly property var _groups: {
        const out = [];
        for (const task of (Tasks.tasks ?? [])) {
            const key = task.projectKey || "inbox";
            let group = out.find(g => g.key === key);
            if (!group) {
                group = {key, project: task.project || "", tasks: []};
                out.push(group);
            }
            if (!task.projectHeading && task.state !== "PROJECT")
                group.tasks.push(task);
        }
        return out;
    }

    // Project containing the clocked-in (ACTIVE) task — used as the auto-expand default.
    readonly property string _activeProject: {
        for (const g of _groups)
            for (const t of g.tasks)
                if (t.state === "ACTIVE")
                    return g.key;
        return "";
    }

    // User-toggled overrides. Keys are project titles; values are bool.
    // Absent keys fall back to the auto-default (only `_activeProject` open).
    property var _expandedOverrides: ({})

    function _isExpanded(project: string): bool {
        if (_expandedOverrides.hasOwnProperty(project))
            return _expandedOverrides[project];
        return project === _activeProject;
    }

    function _toggle(project: string): void {
        const next = Object.assign({}, _expandedOverrides);
        next[project] = !_isExpanded(project);
        _expandedOverrides = next;
    }

    readonly property string displayTime: Tasks.liveTime
    readonly property real displayPercent: 100 - Tasks.livePercent

    component AddInline: StyledRect {
        id: addRoot

        property string placeholder

        signal submitted(title: string)

        radius: Tokens.rounding.small
        color: root.cardColour
        border.width: 1
        border.color: root.grooveColour
        implicitHeight: addRowInner.implicitHeight + Tokens.padding.medium * 2

        function focusField(): void {
            field.forceActiveFocus();
        }

        onVisibleChanged: if (visible)
            focusField()

        WoodPanel {
            visible: !root.folio
            anchors.fill: parent
            radius: parent.radius
        }

        RowLayout {
            id: addRowInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "add"
                color: Colours.palette.m3primary
            }

            StyledTextField {
                id: field

                Layout.fillWidth: true
                placeholderText: addRoot.placeholder

                onAccepted: {
                    const t = text.trim();
                    if (t.length === 0)
                        return;
                    addRoot.submitted(t);
                    text = "";
                }
            }
        }
    }

    component RowActionIcon: Item {
        id: actionIcon

        property string icon
        property string tooltip

        signal activated

        implicitWidth: 28
        implicitHeight: 28

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: actionMouse.containsMouse ? Qt.alpha(Colours.palette.m3primary, 0.12) : "transparent"
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: actionIcon.icon
            color: Colours.palette.m3onSurfaceVariant
        }

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // Stop click from propagating to the row's clock-in MouseArea.
            preventStealing: true
            onClicked: mouse => {
                mouse.accepted = true;
                actionIcon.activated();
            }

            ToolTip.text: actionIcon.tooltip
            ToolTip.visible: containsMouse && actionIcon.tooltip.length > 0
            ToolTip.delay: 600
        }
    }

    component PomoButton: StyledRect {
        id: btn

        property string icon
        property string label
        property bool btnEnabled: true

        signal activated

        radius: Tokens.rounding.full
        color: btn.btnEnabled ? (ma.containsMouse ? Colours.layer(Colours.palette.m3primaryContainer, 2) : Colours.palette.m3primaryContainer) : "transparent"
        opacity: btn.btnEnabled ? 1 : 0.4
        implicitHeight: inner.implicitHeight + Tokens.padding.small * 2
        implicitWidth: inner.implicitWidth + Tokens.padding.medium * 2

        MouseArea {
            id: ma

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.btnEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.btnEnabled)
                btn.activated()
        }

        RowLayout {
            id: inner

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: btn.icon
                color: Colours.palette.m3onPrimaryContainer
            }

            StyledText {
                text: btn.label
                font: Tokens.font.body.small
                color: Colours.palette.m3onPrimaryContainer
            }
        }
    }


}
