import QtQuick
import QtQuick.Layouts
import qs.components
import qs.components.controls
import qs.services
import Burl.Config

ColumnLayout {
    id: root
    implicitWidth: 360
    spacing: Tokens.spacing.medium
    Component.onCompleted: Tasks.countdownWatchers++
    Component.onDestruction: Tasks.countdownWatchers--

    StyledText {
        text: qsTr("FOCUS & REST")
        font.pixelSize: 12
        font.letterSpacing: 2
        color: Woodland.brass
    }
    Item {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 170
        implicitHeight: 170

        CelestialSeal {
            anchors.fill: parent
            star: false
            ink: Woodland.brass
            opacity: 0.5
        }
        CircularProgress {
            anchors.fill: parent
            anchors.margins: 14
            strokeWidth: 3
            value: Tasks.pomodoro.enabled ? 1 - Tasks.livePercent / 100 : 1
            fgColour: Tasks.onBreak ? Colours.palette.m3tertiary : Woodland.brass
            bgColour: Qt.alpha(Woodland.brass, 0.12)
        }
        Column {
            anchors.centerIn: parent
            spacing: 6
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tasks.pomodoro.enabled ? Tasks.liveTime : qsTr("OFF")
                font.family: "monospace"
                font.pixelSize: 30
                color: Woodland.ivory
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tasks.onBreak ? qsTr("REST") : Tasks.pomodoro.enabled ? qsTr("FOCUS") : qsTr("REMINDERS")
                font.pixelSize: 10
                font.letterSpacing: 2
                color: Woodland.brass
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: Tasks.pomodoro.task ?? qsTr("No active task")
        wrapMode: Text.Wrap
    }
    RowLayout {
        TextButton {
            text: Tasks.onBreak ? qsTr("End break") : qsTr("Take a break")
            onClicked: Tasks.onBreak ? Tasks.endBreak() : Tasks.startBreak()
        }
        TextButton {
            text: qsTr("Open tasks")
            onClicked: Tasks.openTasks()
        }
    }
}
