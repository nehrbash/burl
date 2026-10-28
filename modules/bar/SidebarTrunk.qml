import QtQuick
import QtQuick.Effects
import Quickshell

Item {
    id: root
    required property var bar

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
}
