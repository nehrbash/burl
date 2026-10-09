import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.effects
import qs.components.widgets
import qs.services

Item {
    id: root

    required property Props props
    required property ScreenState screenState

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true

            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerLow

            WoodPanel {
                anchors.fill: parent
                framed: true
            }

            NotifDock {
                objectName: "sidebarNotifications"

                props: root.props
                screenState: root.screenState
            }
        }

        GrooveDivider {
            Layout.topMargin: Tokens.padding.large - layout.spacing
            Layout.fillWidth: true
        }
    }
}
