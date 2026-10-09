import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Burl.Config
import qs.components
import qs.components.widgets
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property HyprlandToplevel client

    implicitWidth: child.implicitWidth
    implicitHeight: screen.height * Tokens.sizes.winfo.heightMult

    RowLayout {
        id: child

        anchors.fill: parent
        anchors.margins: Tokens.padding.large

        spacing: Tokens.spacing.medium

        Preview {
            screen: root.screen
            client: root.client
        }

        ColumnLayout {
            spacing: Tokens.spacing.medium

            Layout.preferredWidth: Tokens.sizes.winfo.detailsWidth
            Layout.fillHeight: true

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true

                color: Woodland.surface(Colours.tPalette.m3surfaceContainer, Colours.light)
                radius: Tokens.rounding.large
                clip: true

                OccultFrame { anchors.fill: parent; radius: parent.radius }

                Details {
                    client: root.client
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: buttons.implicitHeight

                color: Woodland.surface(Colours.tPalette.m3surfaceContainer, Colours.light)
                radius: Tokens.rounding.large

                OccultFrame { anchors.fill: parent; radius: parent.radius }

                Buttons {
                    id: buttons

                    client: root.client
                }
            }
        }
    }
}
