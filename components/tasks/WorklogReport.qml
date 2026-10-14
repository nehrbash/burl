pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import Burl.Config
import qs.services

ColumnLayout {
    id: root
    property var report: ({rows: []})
    property bool loading: false
    property string error
    spacing: Tokens.spacing.medium

    function duration(seconds: real): string {
        const minutes = Math.round(seconds / 60);
        return minutes >= 60 ? qsTr("%1h %2m").arg(Math.floor(minutes / 60)).arg(minutes % 60) : qsTr("%1m").arg(minutes);
    }
    readonly property var groups: {
        const groups = [];
        for (const row of (report.rows ?? [])) {
            let group = groups.find(g => g.day === row.day && g.tag === row.tag);
            if (!group) {
                group = {day: row.day, tag: row.tag, seconds: 0, rows: []};
                groups.push(group);
            }
            group.rows.push(row);
            group.seconds += row.seconds;
        }
        return groups;
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.loading || root.error.length > 0 || root.groups.length === 0
        text: root.loading ? qsTr("Loading time…") : root.error || qsTr("No recorded time in this period.")
        wrapMode: Text.Wrap
    }
    Repeater {
        model: root.groups
        delegate: ColumnLayout {
            id: dayGroup
            required property var modelData
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: Qt.formatDate(new Date(dayGroup.modelData.day + "T12:00:00"), "dddd, MMM d") + " · " + (dayGroup.modelData.tag === "@work" ? qsTr("Work") : qsTr("Personal"))
                    font: Tokens.font.title.medium
                    wrapMode: Text.Wrap
                }
                StyledText {
                    text: root.duration(dayGroup.modelData.seconds)
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3primary
                }
            }
            Repeater {
                model: dayGroup.modelData.rows
                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: content.implicitHeight + 24
                    radius: 2
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.22)
                    color: Qt.alpha(Colours.palette.m3primary, 0.07)
                    RowLayout {
                        id: content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 12
                        spacing: 20
                        ColumnLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.title
                                wrapMode: Text.Wrap
                                font: Tokens.font.body.large
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: entry.modelData.project !== entry.modelData.title
                                text: entry.modelData.project
                                wrapMode: Text.Wrap
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                        StyledText {
                            text: root.duration(entry.modelData.seconds)
                            font: Tokens.font.title.medium
                            color: Colours.palette.m3primary
                        }
                    }
                }
            }
        }
    }
}
