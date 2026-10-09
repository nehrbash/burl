import QtQuick
import Burl.Config
import qs.components
import qs.services

// Agenda filter pill (@work / @personal). Single definition shared by
// TaskNudge.qml and dashboard/TasksTab.qml — keep them from drifting apart.
StyledRect {
    id: pill

    property string label
    property bool active

    signal activated

    radius: Tokens.rounding.full
    color: pill.active ? Colours.palette.m3secondaryContainer : "transparent"
    border.color: Colours.palette.m3outline
    border.width: pill.active ? 0 : 1
    implicitHeight: pillText.implicitHeight + Tokens.padding.small * 2
    implicitWidth: pillText.implicitWidth + Tokens.padding.medium * 2

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.activated()
    }

    StyledText {
        id: pillText

        anchors.centerIn: parent
        text: pill.label
        font: Tokens.font.body.small
        color: pill.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
    }
}
