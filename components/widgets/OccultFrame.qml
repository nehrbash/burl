pragma ComponentBehavior: Bound

import QtQuick
import qs.components

Item {
    id: root
    property color ink: Woodland.brass
    property real radius: 12
    property real inset: 6

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.color: Qt.alpha(root.ink, 0.45)
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.inset
        radius: Math.max(2, root.radius - root.inset)
        color: "transparent"
        border.color: Qt.alpha(root.ink, 0.14)
    }
    Repeater {
        model: 4
        Item {
            required property int index
            x: index % 2 ? root.width - 18 : 18
            y: index > 1 ? root.height - 18 : 18
            Rectangle {
                anchors.centerIn: parent
                width: 3
                height: 3
                rotation: 45
                color: root.ink
                opacity: 0.75
            }
        }
    }
}
