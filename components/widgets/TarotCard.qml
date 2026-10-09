import QtQuick
import Quickshell
import qs.components

Item {
    id: root
    property int cardIndex: 0
    property bool selected: false
    property string badge: ""
    property color monitorAccent: "transparent"
    readonly property int card: ((cardIndex % 10) + 10) % 10
    implicitWidth: 40
    implicitHeight: implicitWidth * 1.5

    Rectangle {
        x: 1
        y: 1
        width: parent.width
        height: parent.height
        color: "#660b0907"
    }

    Item {
        anchors.fill: parent
        clip: true
        Image {
            x: -(root.card % 5) * root.width
            y: -Math.floor(root.card / 5) * root.height
            width: root.width * 5
            height: root.height * 2
            source: Quickshell.shellPath("assets/images/tarot/deck.png")
            asynchronous: true
            mipmap: true
        }
    }
    Rectangle {
        visible: root.monitorAccent.a > 0
        anchors.right: parent.right
        anchors.rightMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: root.height * 0.4
        radius: 1
        color: Woodland.rimShadow
        Rectangle {
            anchors.centerIn: parent
            width: 1
            height: parent.height - 2
            radius: 1
            color: root.monitorAccent
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: root.selected
        anchors.margins: 3
        color: "transparent"
        antialiasing: true
        border.width: 1.5
        border.color: "#fff0be"
    }
    Rectangle {
        visible: root.badge.length > 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 4
        anchors.bottomMargin: 4
        width: Math.max(11, label.implicitWidth + 4)
        height: 12
        color: root.selected ? "#dd211728" : "#dd15121c"
        Text {
            id: label
            anchors.centerIn: parent
            text: root.badge
            color: root.selected ? "#fff0be" : "#e8c87d"
            font.pixelSize: 10
            font.bold: true
        }
    }
}
