import QtQuick
import Burl.Config
import qs.components
import qs.components.controls
import qs.components.widgets
import qs.services as Services

Item {
    id: root
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: 76
    readonly property color ink: Services.Pomodoro.onBreak ? "#8abdb5" : Woodland.brass
    Component.onCompleted: void Services.Pomodoro.active

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: pointer.containsMouse ? "#e0262228" : "#bf161418"
        border.color: Qt.alpha(root.ink, 0.6)
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 7
        text: Services.Pomodoro.onBreak ? qsTr("BREAK") : qsTr("FOCUS")
        font.pixelSize: 8
        font.letterSpacing: 0.6
        color: root.ink
    }
    CircularProgress {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 21
        width: 28; height: 28
        strokeWidth: 2
        value: Services.Pomodoro.active ? 1 - Services.Pomodoro.progress : 1
        fgColour: root.ink
        bgColour: "#352d36"
        MaterialIcon {
            anchors.centerIn: parent
            text: Services.Pomodoro.running ? "pause" : "play_arrow"
            fontStyle: Tokens.font.icon.small
            color: Woodland.ivory
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 54
        text: Services.Pomodoro.remainingStr
        color: Woodland.ivory
        font.family: "monospace"
        font.pixelSize: 10
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Services.Pomodoro.toggle()
        Accessible.role: Accessible.Button
        Accessible.name: Services.Pomodoro.running ? qsTr("Pause focus timer") : Services.Pomodoro.active ? qsTr("Resume focus timer") : qsTr("Start focus timer")
    }
}
