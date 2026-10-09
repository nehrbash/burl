import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.containers
import qs.services
import "center"

Item {
    id: root
    required property var lock

    ColumnLayout {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.hourStr + ":" + Time.minuteStr
            color: Woodland.ivory
            font.family: "serif"
            font.pixelSize: Math.min(96, root.height * 0.13)
            font.letterSpacing: 6
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.format("dddd • d MMMM").toUpperCase()
            color: Woodland.parchmentEdge
            font.pixelSize: 13
            font.letterSpacing: 3
        }
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: Math.min(280, root.width * 0.21)
        spacing: 12
        visible: root.width > 1100

        WeatherInfo {
            Layout.fillWidth: true
            rootHeight: 300
            WoodPanel { anchors.fill: parent }
        }
        Media {
            Layout.fillWidth: true
            lock: root.lock
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Math.min(430, root.width * 0.45)
        spacing: 12

        ProfilePic {
            Layout.alignment: Qt.AlignHCenter
            centerWidth: 90
        }
        PasswordInput {
            Layout.alignment: Qt.AlignHCenter
            centerScale: 0.95
            centerWidth: Math.min(430, root.width * 0.45)
            lock: root.lock
        }
        StateMessage {
            Layout.fillWidth: true
            pam: root.lock.pam
        }
        SessionActions { Layout.fillWidth: true }
    }

    ColumnLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.min(280, root.width * 0.21)
        spacing: 12
        visible: root.width > 1100

        Resources { Layout.fillWidth: true }
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: Math.min(280, root.height * 0.32)
            radius: 12
            color: Woodland.surface(Colours.palette.m3surfaceContainer, Colours.light)
            WoodPanel { anchors.fill: parent }
            NotifDock { lock: root.lock }
        }
    }
}
