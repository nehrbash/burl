import QtQuick
import Quickshell
import qs.components
import qs.components.widgets
import qs.services

Item {
    id: root
    property real arrival: 0
    clip: true

    Rectangle { anchors.fill: parent; color: Woodland.midnight }
    AstralScene {
        anchors.fill: parent
        scene: "dream"
        camera: 1 - root.arrival
        active: root.visible
        scale: 1 + (1 - root.arrival) * 1.8
        opacity: 0.25 + root.arrival * 0.75
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#b0111319" }
            GradientStop { position: 0.22; color: "#30111319" }
            GradientStop { position: 0.4; color: "#00111319" }
            GradientStop { position: 1; color: "#90111319" }
        }
    }
    NumberAnimation on arrival {
        from: 0
        to: 1
        duration: Ambience.grow && !GameMode.enabled ? 2200 : 0
        easing.type: Easing.OutCubic
        running: true
    }
}
