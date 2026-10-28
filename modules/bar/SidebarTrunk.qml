import QtQuick
import QtQuick.Effects
import Quickshell
import qs.components.widgets

Item {
    id: root
    required property var bar
    property bool runesAnimated: true

    x: bar?.trunkX ?? 0
    width: bar?.trunkWidth ?? 0
    visible: bar?.visible ?? false
    Image {
        width: parent.width
        height: parent.height * 0.91
        source: Quickshell.shellPath("assets/images/tree/rendered/sidebar-grown.png")
        sourceClipRect: Qt.rect(0, 0, 724, 1800)
        fillMode: Image.Stretch
        mipmap: true
        layer.enabled: true
        layer.effect: MultiEffect {
            brightness: -0.16
            saturation: -0.35
        }
    }
    Image {
        y: parent.height * 0.91
        width: parent.width
        height: parent.height - y
        source: Quickshell.shellPath("assets/images/tree/rendered/sidebar-grown.png")
        sourceClipRect: Qt.rect(0, 1800, 724, 372)
        fillMode: Image.Stretch
        mipmap: true
        layer.enabled: true
        layer.effect: MultiEffect {
            brightness: -0.16
            saturation: -0.35
        }
    }
    BarkRunes {
        anchors.fill: parent
        runeSize: 16
        animated: root.runesAnimated
        sites: [{ x: 0.24, y: 0.12, angle: -8 }, { x: 0.28, y: 0.34, angle: 6 },
            { x: 0.25, y: 0.58, angle: -5 }, { x: 0.32, y: 0.82, angle: 12 }]
    }
}
