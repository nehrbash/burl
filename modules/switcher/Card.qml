pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    required property HyprlandToplevel client
    required property bool selected
    // Only the selected card streams. A live ScreencopyView per window is a
    // per-frame compositor capture each; a dozen of them stalls the shell on
    // the machines this is most useful on.
    required property bool live

    signal activated
    signal closeRequested

    readonly property string appClass: client?.lastIpcObject?.class ?? ""
    readonly property string wsName: {
        const n = root.client?.workspace?.name ?? "";
        return n.startsWith("special:") ? n.slice(8) : n;
    }

    WoodPanel {
        anchors.fill: parent

        radius: Tokens.rounding.large
        framed: root.selected
        fill: root.selected ? Woodland.mix(Woodland.barkLit, Woodland.parchment, 0.18) : Woodland.rimShadow
    }

    StyledClippingRect {
        id: shot

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: footer.top
        anchors.margins: Tokens.padding.small

        radius: Tokens.rounding.small
        color: Woodland.rimShadow

        ScreencopyView {
            anchors.centerIn: parent

            captureSource: root.client?.wayland ?? null // qmllint disable unresolved-type
            live: root.live

            constraintSize.width: shot.width
            constraintSize.height: shot.height
        }
    }

    Item {
        id: footer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.small

        implicitHeight: Math.max(icon.height, title.implicitHeight)

        CachingIconImage {
            id: icon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            implicitSize: Tokens.font.label.large.pixelSize * 1.6
            source: Icons.getAppIcon(root.appClass, "image-missing")
        }

        StyledText {
            id: title

            anchors.left: icon.right
            anchors.right: ws.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacing.small
            anchors.rightMargin: Tokens.spacing.small

            text: root.client?.title ?? ""
            elide: Text.ElideRight
            maximumLineCount: 1
            color: root.selected ? Woodland.creamPrimary : Woodland.creamSecondary
            font: Tokens.font.label.medium
        }

        StyledText {
            id: ws

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            width: Math.min(implicitWidth, parent.width * 0.22)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: root.wsName
            color: Woodland.oliveLight
            font: Tokens.font.label.small
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                root.closeRequested();
            else
                root.activated();
        }
    }

    scale: root.selected ? 1 : 0.94
    opacity: root.selected ? 1 : 0.75

    Behavior on scale {
        Anim {}
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
