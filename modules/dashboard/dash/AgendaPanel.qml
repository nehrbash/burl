pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Burl.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    readonly property int maxRows: 3
    readonly property var following: Agenda.upcoming.slice(1)
    readonly property var next: Agenda.next
    readonly property bool nextIsToday: next !== null && next.start < Agenda.dayEnd

    function colourFor(cal: string): color {
        return cal === "work" ? Colours.palette.m3tertiary : Colours.palette.m3primary;
    }

    function clock(ms: real): string {
        return Qt.formatTime(new Date(ms), GlobalConfig.services.useTwelveHourClock ? "h:mm AP" : "hh:mm");
    }

    function mins(ms: real): int {
        return Math.max(1, Math.ceil(ms / 60000));
    }

    function span(minutes: int): string {
        if (minutes < 60)
            return qsTr("%1 min").arg(minutes);
        const h = Math.floor(minutes / 60), m = minutes % 60;
        return m ? qsTr("%1 h %2 min").arg(h).arg(m) : qsTr("%1 h").arg(h);
    }

    function countdown(e: var): string {
        const now = Agenda.now.getTime();
        if (e.start <= now)
            return qsTr("now · %1 left").arg(span(mins(e.end - now)));
        if (e.start < Agenda.dayEnd)
            return qsTr("in %1").arg(span(mins(e.start - now)));
        if (e.start < Agenda.tomorrowEnd)
            return qsTr("tomorrow %1").arg(clock(e.start));
        return Qt.formatDate(new Date(e.start), "ddd d MMM") + " · " + clock(e.start);
    }

    function place(e: var): string {
        return e.location ? e.location.split(",")[0] : "";
    }

    spacing: Tokens.spacing.small

    Rectangle {
        id: nextRow

        Layout.fillWidth: true
        implicitHeight: nextContent.implicitHeight + Tokens.padding.medium * 2
        radius: 2
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.25)
        color: Qt.alpha(root.next ? root.colourFor(root.next.calendar) : Colours.palette.m3onSurface, 0.12)

        RowLayout {
            id: nextContent

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            Rectangle {
                visible: root.next !== null
                implicitWidth: 10
                implicitHeight: 10
                radius: 5
                color: root.next ? root.colourFor(root.next.calendar) : "transparent"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.next ? root.next.title : qsTr("Nothing coming up")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: {
                        if (!root.next)
                            return qsTr("No more events today");
                        const p = root.place(root.next);
                        return root.countdown(root.next) + (p ? " · " + p : "");
                    }
                    color: root.next && root.next.start <= Agenda.now.getTime() ? root.colourFor(root.next.calendar) : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            TextButton {
                visible: root.next !== null && root.next.link !== ""
                text: qsTr("Join")
                type: TextButton.Filled
                activeColour: root.next ? root.colourFor(root.next.calendar) : Colours.palette.m3primary
                onClicked: Quickshell.execDetached(["xdg-open", root.next.link])
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.next !== null && !root.nextIsToday
        text: qsTr("No more events today")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledText {
        Layout.fillWidth: true
        visible: Agenda.allDayToday.length > 0
        elide: Text.ElideRight
        text: qsTr("All day · %1").arg(Agenda.allDayToday.map(e => e.title).join(", "))
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    Repeater {
        model: root.following.slice(0, root.maxRows)

        RowLayout {
            id: row

            required property var modelData

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Rectangle {
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: root.colourFor(row.modelData.calendar)
            }

            StyledText {
                Layout.preferredWidth: Math.max(100, timeMetric.implicitWidth)
                text: (row.modelData.start >= Agenda.dayEnd ? Qt.formatDate(new Date(row.modelData.start), "ddd d MMM") + "\n" : "") + root.clock(row.modelData.start)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: row.modelData.title
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.small
            }

            MaterialIcon {
                visible: row.modelData.link !== "" || row.modelData.location !== ""
                text: row.modelData.link !== "" ? "videocam" : "location_on"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.icon.small
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.following.length > root.maxRows
        text: qsTr("+%1 more upcoming").arg(root.following.length - root.maxRows)
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledText {
        id: timeMetric

        visible: false
        text: root.clock(new Date(2000, 0, 1, 12, 30).getTime())
        font: Tokens.font.body.small
    }
}
