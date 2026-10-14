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
    readonly property color ink: Services.Tasks.onBreak ? "#8abdb5" : Woodland.brass
    Component.onCompleted: Services.Tasks.countdownWatchers++
    Component.onDestruction: Services.Tasks.countdownWatchers--

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: pointer.containsMouse ? "#e0262228" : "#bf161418"
        border.color: Qt.alpha(root.ink, 0.6)
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 7
        text: Services.Tasks.onBreak ? qsTr("BREAK") : qsTr("FOCUS")
        font.pixelSize: 8
        font.letterSpacing: 0.6
        color: root.ink
    }
    CircularProgress {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 21
        width: 28; height: 28
        strokeWidth: 2
        value: Services.Tasks.pomodoro.enabled ? 1 - Services.Tasks.livePercent / 100 : 0
        fgColour: root.ink
        bgColour: "#352d36"
        MaterialIcon {
            anchors.centerIn: parent
            text: "schedule"
            fontStyle: Tokens.font.icon.small
            color: Woodland.ivory
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 54
        text: Services.Tasks.pomodoro.enabled ? Services.Tasks.liveTime : qsTr("OFF")
        color: Woodland.ivory
        font.family: "monospace"
        font.pixelSize: 10
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Services.Tasks.openTasks()
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Open tasks")
    }
}
