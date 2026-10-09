pragma ComponentBehavior: Bound

import QtQuick
import qs.components

Item {
    id: root
    property color ink: Woodland.brass
    property bool star: true

    Repeater {
        model: [0.98, 0.88, 0.65]
        Rectangle {
            required property real modelData
            anchors.centerIn: parent
            width: root.width * modelData
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Qt.alpha(root.ink, 0.55)
        }
    }
    Repeater {
        model: 12
        Rectangle {
            required property int index
            readonly property real angle: index * Math.PI / 6
            x: root.width / 2 + Math.cos(angle) * root.width * 0.465 - width / 2
            y: root.height / 2 + Math.sin(angle) * root.width * 0.465 - height / 2
            width: index % 3 === 0 ? 7 : 3
            height: 1
            rotation: index * 30
            color: root.ink
        }
    }
    Rectangle {
        anchors.centerIn: parent
        width: root.width * 0.48
        height: width
        rotation: 45
        color: "transparent"
        border.color: Qt.alpha(root.ink, 0.5)
    }
    Text {
        anchors.centerIn: parent
        visible: root.star
        text: "✦"
        color: root.ink
        font.pixelSize: root.width * 0.4
    }
}
