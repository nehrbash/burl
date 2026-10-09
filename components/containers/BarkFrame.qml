import QtQuick
import Burl.Config
import qs.components

Item {
    id: root

    property real radius: Tokens.rounding.large
    property real frameWidth: 1
    // socket: a light upper rim + a dark lower cut, so the surface reads as a
    // boss set INTO wood rather than a plate laid on top of it.
    property bool socket: false
    property color outer: Woodland.midnight
    property color mid: Qt.alpha(Woodland.brass, 0.5)
    property color inner: Qt.alpha(Woodland.brass, 0.15)

    Rectangle {
        visible: !root.socket
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: root.outer
    }

    Rectangle {
        visible: !root.socket
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.width: Math.min(1, root.frameWidth)
        border.color: root.mid
    }

    Rectangle {
        visible: !root.socket
        anchors.fill: parent
        anchors.margins: 1 + root.frameWidth
        radius: Math.max(0, root.radius - 1 - root.frameWidth)
        color: "transparent"
        border.width: 1
        border.color: root.inner
    }

    Rectangle {
        visible: root.socket
        anchors.fill: parent
        anchors.topMargin: 1
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Woodland.rimLight
    }

    Rectangle {
        visible: root.socket
        anchors.fill: parent
        anchors.bottomMargin: 1
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Woodland.rimShadow
    }
}
