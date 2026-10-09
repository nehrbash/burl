pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services

Item {
    id: root
    property bool active: true
    property real phase: 0
    readonly property bool moving: active && visible && opacity > 0.001 && Ambience.sway && !GameMode.enabled
    readonly property var positions: [[0.06, 0.2], [0.17, 0.73], [0.87, 0.18], [0.94, 0.6], [0.3, 0.1], [0.76, 0.85], [0.08, 0.88], [0.74, 0.32]]
    enabled: false

    Repeater {
        model: root.positions.length
        delegate: Item {
            id: shard
            required property int index
            readonly property real offset: index * 2.39996
            x: root.width * root.positions[index][0] + Math.sin(root.phase + offset) * (8 + index * 2)
            y: root.height * root.positions[index][1] + Math.cos(root.phase * (1 + index % 2) + offset) * (12 + index * 2)
            height: Math.min(root.height * (0.04 + index % 3 * 0.017), 100)
            width: height
            rotation: index * 37 - 80 + Math.sin(root.phase + offset) * 12
            opacity: 0.45 + index % 3 * 0.15
            Image {
                anchors.fill: parent
                sourceClipRect: Qt.rect((shard.index % 4) * 443.5, Math.floor(shard.index / 4) * 443.5, 443.5, 443.5)
                source: Quickshell.shellPath("assets/images/nocturne/astral-glass.png")
                asynchronous: true
                mipmap: true
            }
        }
    }
    NumberAnimation on phase {
        from: 0
        to: Math.PI * 2
        duration: 96000
        loops: Animation.Infinite
        running: root.moving
    }
}
