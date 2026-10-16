pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

MouseArea {
    id: root

    required property ScreenState screenState

    property date currentDate: screenState.dashboardDate
    readonly property int currMonth: currentDate.getMonth()
    readonly property int currYear: currentDate.getFullYear()
    readonly property int nonAnimCurrMonth: screenState.dashboardDate.getMonth()
    readonly property int nonAnimCurrYear: screenState.dashboardDate.getFullYear()

    readonly property int animDirection: screenState.dashboardDate > currentDate ? -1 : 1
    property real animTranslate
    property real animOpacity: 1

    onWheel: event => event.accepted = false

    implicitHeight: outer.implicitHeight + outer.anchors.margins * 2

    acceptedButtons: Qt.MiddleButton
    onClicked: root.screenState.setDashboardDate(new Date())

    Anim {
        id: trOutAnim

        running: false
        target: root
        property: "animTranslate"
        to: Tokens.padding.extraLarge * root.animDirection
        type: Anim.FastSpatial
    }

    Behavior on currentDate {
        SequentialAnimation {
            ParallelAnimation {
                ScriptAction {
                    script: Qt.callLater(() => trOutAnim.start())
                }
                Anim {
                    target: root
                    property: "animOpacity"
                    to: 0
                    type: Anim.FastEffects
                }
            }
            ScriptAction {
                script: {
                    trOutAnim.complete();
                    root.animTranslate = Tokens.padding.extraLarge * -root.animDirection;
                }
            }
            PropertyAction {}
            ParallelAnimation {
                Anim {
                    target: root
                    property: "animTranslate"
                    to: 0
                    type: Anim.DefaultSpatial
                }
                Anim {
                    target: root
                    property: "animOpacity"
                    to: 1
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    GridLayout {
        id: outer
        columns: width >= 480 ? 2 : 1

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        columnSpacing: Tokens.spacing.large
        rowSpacing: Tokens.spacing.large

        ColumnLayout {
            id: inner

            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.minimumWidth: 230
            Layout.preferredWidth: 320
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                id: monthNavigationRow

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                IconButton {
                    isRound: true
                    icon: "chevron_left"
                    type: IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.small
                    onClicked: root.screenState.setDashboardDate(new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth - 1, 1))
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    implicitWidth: monthYearDisplay.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: monthYearDisplay.implicitHeight + Tokens.padding.extraSmall * 2

                    StateLayer {
                        color: Colours.palette.m3primary
                        radius: pressed ? Tokens.rounding.small : height / 2
                        disabled: {
                            const now = new Date();
                            return root.nonAnimCurrMonth === now.getMonth() && root.nonAnimCurrYear === now.getFullYear();
                        }
                        onClicked: root.screenState.setDashboardDate(new Date())

                        Behavior on radius {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    StyledText {
                        id: monthYearDisplay

                        opacity: root.animOpacity
                        transform: Translate {
                            x: root.animTranslate
                        }

                        anchors.centerIn: parent
                        text: grid.title
                        color: Colours.palette.m3primary
                        font: Tokens.font.title.builders.small.capitalisation(Font.Capitalize).build()
                    }
                }

                IconButton {
                    isRound: true
                    icon: "chevron_right"
                    type: IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.small
                    onClicked: root.screenState.setDashboardDate(new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth + 1, 1))
                }
            }

            DayOfWeekRow {
                id: daysRow

                Layout.fillWidth: true
                // DayOfWeekRow reports a 12px implicitHeight for an 18px delegate,
                // clipping the weekday names. The minimum (same day-glyph metric as
                // the month grid below) keeps the row from shrinking when the card
                // comes in a few px short (Dash's scatterH nudges it ±6px).
                Layout.preferredHeight: dayMetric.implicitHeight + Tokens.padding.extraSmall * 2
                Layout.minimumHeight: daysRow.Layout.preferredHeight
                locale: grid.locale

                delegate: StyledText {
                    required property var model

                    horizontalAlignment: Text.AlignHCenter
                    text: model.narrowName
                    font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
                }
            }

            Item {
                id: gridBox

                // MonthGrid reports a bogus implicit size (0x15 for a full
                // six-week month), so binding to it crammed all six weeks into
                // 15px with dates drawn on top of each other. Size cells
                // explicitly instead, clamped so a wide card doesn't blow days up.
                readonly property real dayMin: dayMetric.implicitHeight + Tokens.padding.small
                readonly property real dayCell: Math.max(gridBox.dayMin, Math.min(gridBox.dayMin * 1.35, (gridBox.width - grid.spacing * 6) / 7))

                Layout.fillWidth: true
                implicitHeight: gridBox.dayCell * 6 + grid.spacing * 5
                Layout.minimumHeight: gridBox.implicitHeight

                // Measures a day cell the same way the grid delegate builds one
                // (text.implicitHeight + padding.small).
                StyledText {
                    id: dayMetric

                    visible: false
                    text: "30"
                    font: Tokens.font.body.small
                }

                opacity: root.animOpacity
                transform: Translate {
                    x: root.animTranslate
                }

                MonthGrid {
                    id: grid

                    month: root.currMonth
                    year: root.currYear

                    anchors.fill: parent

                    spacing: 3
                    locale: Qt.locale()

                    delegate: Item {
                        id: dayItem

                        required property var model

                        implicitWidth: implicitHeight
                        implicitHeight: text.implicitHeight + Tokens.padding.small

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.max(0, Math.min(parent.width, parent.height) - 2)
                            height: width
                            radius: width / 2
                            visible: dayItem.model.today
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            id: text

                            anchors.centerIn: parent

                            horizontalAlignment: Text.AlignHCenter
                            text: grid.locale.toString(dayItem.model.day)
                            color: {
                                if (dayItem.model.today)
                                    return Colours.palette.m3onPrimary;
                                const dayOfWeek = dayItem.model.date.getDay();
                                if (dayOfWeek === 0 || dayOfWeek === 6)
                                    return Colours.palette.m3tertiary;

                                return Colours.palette.m3onSurfaceVariant;
                            }
                            opacity: dayItem.model.today || dayItem.model.month === grid.month ? 1 : 0.4
                            font: Tokens.font.body.small
                        }
                    }
                }


            }
        }

        ColumnLayout {
            id: agenda
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.minimumWidth: outer.columns === 2 ? 200 : 0
            StyledText {
                text: qsTr("AGENDA")
                color: Colours.palette.m3primary
                font: Tokens.font.title.small
            }
            AgendaPanel { Layout.fillWidth: true }
            TextButton {
                text: qsTr("Open calendar")
                onClicked: Tasks.openTasks("calendar")
            }
        }
    }
}
