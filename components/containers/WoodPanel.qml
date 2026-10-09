import QtQuick
import Quickshell
import Burl.Config
import qs.components
import qs.components.widgets

Item {
    id: root

    property real radius: Tokens.rounding.large
    property url texture: Quickshell.shellPath("assets/images/ui/parchment-menu.png")
    // Keep grain very low-contrast so 12-14px text stays readable
    property real grainOpacity: 0.035
    property alias fillMode: grain.fillMode
    property color fill: "transparent"
    property bool framed: false
    property real frameWidth: 5

    StyledClippingRect {
        anchors.fill: parent
        radius: root.radius
        color: root.fill

        Image {
            id: grain

            anchors.fill: parent
            source: root.texture
            fillMode: Image.PreserveAspectCrop
            opacity: root.grainOpacity
            asynchronous: true
            visible: status === Image.Ready
        }
    }

    OccultFrame {
        anchors.fill: parent
        radius: root.radius
        opacity: root.framed ? 1 : 0.6
    }
}
