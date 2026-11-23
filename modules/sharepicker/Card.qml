pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.images
import qs.services

Item {
    id: root

    // A ShellScreen or a Wayland Toplevel; null shows the icon alone.
    required property var source
    required property string title
    required property string detail
    // A resolved icon URL.
    required property string icon
    required property bool selected

    signal activated
    signal hovered

    WoodPanel {
        anchors.fill: parent

        radius: Tokens.rounding.large
        framed: root.selected
        fill: root.selected ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
    }

    StyledClippingRect {
        id: shot

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: footer.top
        anchors.margins: Tokens.padding.small

        radius: Tokens.rounding.small
        color: Colours.palette.m3surfaceContainerLowest

        ScreencopyView {
            anchors.centerIn: parent

            visible: root.source !== null
            captureSource: root.source // qmllint disable unresolved-type
            // Only the selected card streams; the rest keep their first frame.
            live: root.selected

            constraintSize.width: shot.width
            constraintSize.height: shot.height
        }

        CachingIconImage {
            anchors.centerIn: parent

            visible: root.source === null
            implicitSize: Math.min(shot.width, shot.height) * 0.4
            source: root.icon
        }
    }

    Item {
        id: footer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.small

        implicitHeight: Math.max(appIcon.height, title.implicitHeight)

        CachingIconImage {
            id: appIcon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            implicitSize: Tokens.font.label.large.pixelSize * 1.6
            source: root.icon
        }

        StyledText {
            id: title

            anchors.left: appIcon.right
            anchors.right: detail.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacing.small
            anchors.rightMargin: Tokens.spacing.small

            text: root.title
            elide: Text.ElideRight
            maximumLineCount: 1
            color: root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            font: Tokens.font.label.medium
        }

        StyledText {
            id: detail

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            width: Math.min(implicitWidth, parent.width * 0.4)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: root.detail
            color: root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered()
        onClicked: root.activated()
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
