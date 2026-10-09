import QtQuick
import qs.components

Rectangle {
    radius: width / 2
    color: "#281b12"
    border.color: "#19120d"

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: -1
        radius: width / 2
        z: -1
        color: Woodland.barkLit
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: width / 2
        border.color: Qt.alpha(Woodland.parchmentEdge, 0.25)
        gradient: Gradient {
            GradientStop { position: 0; color: "#17130f" }
            GradientStop { position: 0.4; color: "#30251b" }
            GradientStop { position: 1; color: "#4c3825" }
        }
    }
}
