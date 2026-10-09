pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services

Rectangle {
    id: root

    property color accent: Colours.palette.m3primary
    property bool ticks: true

    radius: width / 2
    border.color: Qt.alpha(Woodland.parchmentEdge, 0.32)
    gradient: Gradient {
        GradientStop { position: 0; color: Woodland.mix(Colours.palette.m3surface, Colours.palette.m3scrim, 0.48) }
        GradientStop { position: 0.7; color: Woodland.mix(Colours.palette.m3surface, root.accent, 0.06) }
        GradientStop { position: 1; color: Woodland.mix(Colours.palette.m3surface, Woodland.parchmentEdge, 0.13) }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: width / 2
        color: "transparent"
        border.color: Qt.alpha(root.accent, 0.18)
    }

    Repeater {
        model: root.ticks ? 21 : 0
        delegate: Rectangle {
            required property int index
            readonly property real angle: (135 + index * 13.5) * Math.PI / 180
            x: root.width / 2 + Math.cos(angle) * (root.width / 2 - 9) - width / 2
            y: root.height / 2 + Math.sin(angle) * (root.height / 2 - 9) - height / 2
            width: index % 5 === 0 ? 5 : 2
            height: 1
            rotation: 135 + index * 13.5
            color: Qt.alpha(Woodland.parchmentEdge, index % 5 === 0 ? 0.65 : 0.3)
        }
    }
}
