import QtQuick
import Quickshell.Widgets
import qs.components
import qs.components.images
import qs.components.widgets
import qs.services
import qs.utils

Item {
    id: root
    required property int centerWidth
    implicitWidth: Math.round(centerWidth * 0.7)
    implicitHeight: implicitWidth

    CelestialSeal {
        anchors.fill: parent
        star: pfp.status !== Image.Ready
    }
    ClippingRectangle {
        anchors.centerIn: parent
        width: parent.width * 0.60
        height: width
        radius: width / 2
        color: "transparent"
        CachingImage {
            id: pfp
            anchors.fill: parent
            path: `${Paths.home}/.face`
        }
    }
}
