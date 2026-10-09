import QtQuick
import QtQuick.Layouts
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root
    implicitWidth: 340
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 14

        StyledText {
            text: qsTr("FOCUS TIMER")
            color: Woodland.brass
            font.pixelSize: 12
            font.letterSpacing: 2
        }
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 150
            implicitHeight: 150
            CelestialSeal { anchors.fill: parent; star: false; ink: Woodland.brass; opacity: 0.45 }
            CircularProgress {
                anchors.fill: parent
                anchors.margins: 12
                strokeWidth: 3
                value: Pomodoro.active ? 1 - Pomodoro.progress : 1
                fgColour: Pomodoro.onBreak ? "#8abdb5" : Woodland.brass
                bgColour: "#352d36"
            }
            Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Pomodoro.remainingStr
                    font.family: "monospace"
                    font.pixelSize: 30
                    color: Woodland.ivory
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !Pomodoro.active ? qsTr("READY") : Pomodoro.paused ? qsTr("PAUSED") : Pomodoro.onBreak ? qsTr("BREAK") : qsTr("FOCUS")
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    color: Woodland.brass
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            TextButton {
                objectName: "focusTimerToggle"
                text: Pomodoro.running ? qsTr("Pause") : Pomodoro.active ? qsTr("Resume") : qsTr("Start focus")
                onClicked: Pomodoro.toggle()
            }
            TextButton {
                objectName: "focusTimerReset"
                text: qsTr("Reset")
                disabled: !Pomodoro.active
                disabledColour: "#29232d"
                disabledOnColour: "#9c8c88"
                type: TextButton.Tonal
                onClicked: Pomodoro.reset()
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("%1 focus sessions completed").arg(Pomodoro.sessionsCompleted)
            color: Woodland.parchmentMid
            font.pixelSize: 12
        }
        StyledText {
            Layout.fillWidth: true
            text: qsTr("%1 minutes of focus, then a %2-minute break. Repeats until paused or reset.").arg(Pomodoro.workMinutes).arg(Pomodoro.breakMinutes)
            wrapMode: Text.WordWrap
            color: Woodland.parchmentMid
            font.pixelSize: 12
        }
        StyledText {
            Layout.fillWidth: true
            text: qsTr("Task clocking and its break reminders are separate.")
            wrapMode: Text.WordWrap
            color: Woodland.parchmentMid
            font.pixelSize: 11
        }
    }
}
