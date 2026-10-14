pragma ComponentBehavior: Bound

import "dash"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services

Flickable {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker
    property bool living: false

    implicitWidth: 1000
    implicitHeight: 620
    contentWidth: width
    contentHeight: page.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: ScrollBar {}

    Component.onCompleted: Weather.reload()

    ColumnLayout {
        id: page
        x: 16
        y: 16
        width: Math.max(0, root.width - 32)
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 20

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Time.format("dddd")
                    color: Colours.palette.m3primary
                    font: Tokens.font.headline.medium
                }
                StyledText {
                    text: Time.format("d MMMM yyyy")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 4

                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: Time.format(GlobalConfig.services.useTwelveHourClock ? "h:mm AP" : "HH:mm")
                    font: Tokens.font.headline.medium
                    color: Colours.palette.m3primary
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8
                    MaterialIcon {
                        text: Weather.icon
                        color: Colours.palette.m3secondary
                    }
                    StyledText {
                        text: Weather.temp + " · " + Weather.description
                        font: Tokens.font.body.medium
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.alpha(Colours.palette.m3primary, 0.35)
        }

        Calendar {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            screenState: root.screenState
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            TextButton {
                text: qsTr("Tasks")
                onClicked: Tasks.openTasks("tasks")
            }
            TextButton {
                text: qsTr("Performance")
                type: TextButton.Text
                onClicked: root.screenState.growDashboardSection("performance")
            }
            TextButton {
                text: qsTr("Weather")
                type: TextButton.Text
                onClicked: root.screenState.growDashboardSection("weather")
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.alpha(Colours.palette.m3primary, 0.35)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            IconButton {
                icon: "music_note"
                type: IconButton.Text
                onClicked: root.screenState.growDashboardSection("media")
                Accessible.name: qsTr("Open media")
                ToolTip.text: qsTr("Open media")
                ToolTip.visible: hovered
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: Players.active?.trackTitle || qsTr("Nothing playing")
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3primary
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Players.active?.trackArtist || qsTr("Open Media to choose a player")
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
            IconButton {
                icon: "skip_previous"
                type: IconButton.Text
                disabled: !Players.active?.canGoPrevious
                onClicked: Players.active?.previous()
                Accessible.name: qsTr("Previous track")
                ToolTip.text: qsTr("Previous track")
                ToolTip.visible: hovered
            }
            IconButton {
                icon: Players.active?.isPlaying ? "pause" : "play_arrow"
                disabled: !Players.active?.canTogglePlaying
                onClicked: Players.active?.togglePlaying()
                Accessible.name: Players.active?.isPlaying ? qsTr("Pause") : qsTr("Play")
                ToolTip.text: Accessible.name
                ToolTip.visible: hovered
            }
            IconButton {
                icon: "skip_next"
                type: IconButton.Text
                disabled: !Players.active?.canGoNext
                onClicked: Players.active?.next()
                Accessible.name: qsTr("Next track")
                ToolTip.text: qsTr("Next track")
                ToolTip.visible: hovered
            }
        }
    }
}
