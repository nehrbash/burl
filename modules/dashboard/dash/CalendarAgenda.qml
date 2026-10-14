pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.components.controls
import qs.services
import Burl.Config

ColumnLayout {
    id: root
    spacing: Tokens.spacing.medium
    readonly property var days: {
        const days = [];
        const now = Agenda.now;
        for (let i = 0; i < 7; i++) {
            const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
            const end = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i + 1);
            days.push({date: start, events: Agenda.events.filter(e => e.start < end.getTime() && e.end > start.getTime())});
        }
        return days;
    }
    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: qsTr("Next seven days")
            font: Tokens.font.title.large
        }
        TextButton { text: qsTr("Refresh"); onClicked: Agenda.refresh() }
    }
    Repeater {
        model: root.days
        delegate: ColumnLayout {
            id: day
            required property var modelData
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            StyledText {
                text: Qt.formatDate(day.modelData.date, "dddd, MMMM d")
                font: Tokens.font.title.medium
                color: Colours.palette.m3primary
            }
            StyledText {
                visible: day.modelData.events.length === 0
                text: qsTr("Nothing scheduled")
                color: Colours.palette.m3onSurfaceVariant
            }
            Repeater {
                model: day.modelData.events
                delegate: Rectangle {
                    id: event
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: details.implicitHeight + 24
                    radius: 2
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.22)
                    color: Qt.alpha(event.modelData.calendar === "work" ? Colours.palette.m3tertiary : Colours.palette.m3primary, 0.1)
                    RowLayout {
                        id: details
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 12
                        spacing: 16
                        StyledText {
                            Layout.preferredWidth: 125
                            text: event.modelData.allDay ? qsTr("All day") : Qt.formatTime(new Date(event.modelData.start), "h:mm AP") + "\n" + Qt.formatTime(new Date(event.modelData.end), "h:mm AP")
                            font: Tokens.font.body.large
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: event.modelData.title
                                wrapMode: Text.Wrap
                                font: Tokens.font.body.large
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: event.modelData.calendar + (event.modelData.location ? " · " + event.modelData.location : "")
                                wrapMode: Text.Wrap
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                        TextButton {
                            visible: event.modelData.link.length > 0
                            text: qsTr("Join")
                            onClicked: Quickshell.execDetached(["xdg-open", event.modelData.link])
                        }
                    }
                }
            }
        }
    }
}
