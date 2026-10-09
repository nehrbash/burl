import QtQuick
import qs.components
import qs.components.widgets
import Burl.Config

Item {
    id: root

    signal openRequested

    implicitWidth: Tokens.sizes.bar.innerWidth * 0.92
    implicitHeight: implicitWidth

    BarkSocket {
        anchors.fill: parent
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: "settings"
        color: Woodland.parchmentEdge
        fontStyle: Tokens.font.icon.small
        rotation: interaction.containsMouse ? 30 : 0
        Behavior on rotation { Anim {} }
    }

    StateLayer {
        id: interaction
        radius: width / 2
        onClicked: root.openRequested()
    }
}
