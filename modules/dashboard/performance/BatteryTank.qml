import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Burl.Config
import Burl.Services
import qs.components
import qs.components.containers
import qs.services

BarkCard {
    id: root

    property real animPerc: UPower.displayDevice.percentage

    // Base tone uses the secondary container, not surface, so the tank reads as
    // an empty vessel rather than a plate. The fill stays m3secondary since it's
    // a functional gauge reading, not chrome.
    color: Woodland.mix(Colours.palette.m3secondaryContainer, Colours.light ? Woodland.parchmentEdge : Woodland.barkLit, 0.4)
    radius: Tokens.rounding.large
    grainSeed: 16

    implicitWidth: Config.dashboard.performance.showCpu || (Config.dashboard.performance.showGpu && Gpu.type !== Gpu.None) || Config.dashboard.performance.showStorage || Config.dashboard.performance.showMemory ? Tokens.sizes.dashboard.perfBattWidth : Tokens.sizes.dashboard.perfBattWidthSingle
    implicitHeight: Tokens.sizes.dashboard.perfBattHeight

    Behavior on animPerc {
        Anim {}
    }

    Contents {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium

        accentColour: Colours.palette.m3primary
        textColour: Colours.palette.m3onSurface
        subTextColour: Colours.palette.m3onSurfaceVariant
    }

    // BarkCard does not clip (cards must be free to overhang), so the rising
    // level gets its own clipper to keep its corners inside the tank's radius.
    // NOTE: ClippingRectangle reparents children, hence `root.` not `parent.`.
    StyledClippingRect {
        anchors.fill: parent

        radius: root.radius

        StyledRect {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            implicitHeight: root.height * root.animPerc

            color: Colours.palette.m3secondary
            radius: Tokens.rounding.extraSmall
            clip: true

            // The level must paint over the card (covering its unfilled labels), so
            // it carries its own grain/rim copy offset into card coordinates —
            // otherwise the tank read textured above the waterline, flat below.
            // Grain is colour-free black alpha (tile mean 0.07), so it adds fissures
            // without touching the m3secondary reading.
            BarkGrain {
                visible: !root.folio
                y: -root.height * (1 - root.animPerc)

                plateWidth: root.width
                plateHeight: root.height
                horizontal: root.grainHorizontal
                phaseX: root.grainPhaseX
                phaseY: root.grainPhaseY
                strength: root.grainOpacity
            }

            BarkFrame {
                visible: !root.folio
                y: -root.height * (1 - root.animPerc)

                width: root.width
                height: root.height
                socket: true
                radius: root.radius
            }

            Contents {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: layout.anchors.margins
                height: layout.height

                accentColour: Colours.palette.m3primaryContainer
                textColour: Colours.palette.m3onSecondary
                subTextColour: Colours.palette.m3secondaryContainer
            }
        }
    }

    component Contents: ColumnLayout {
        id: contents

        required property color accentColour
        required property color textColour
        required property color subTextColour
        readonly property bool charging: [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state)

        spacing: 0

        MaterialIcon {
            Layout.leftMargin: -Tokens.padding.extraSmall
            text: "battery_full"
            color: contents.accentColour
            fontStyle: Tokens.font.icon.large
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Battery")
            color: contents.textColour
            font: Tokens.font.body.medium
        }

        Item {
            Layout.fillHeight: true
        }

        StyledText {
            Layout.alignment: Qt.AlignRight
            text: {
                if (UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
                    return qsTr("Full");

                if (contents.charging)
                    return qsTr("Charging");

                const s = UPower.displayDevice.timeToEmpty;
                if (s === 0)
                    return qsTr("...");

                const hr = Math.floor(s / 3600);
                const min = Math.floor((s % 3600) / 60);
                if (hr > 0)
                    return `${hr}h ${min}m`;

                return `${min}m`;
            }
            color: contents.subTextColour
            font: Tokens.font.body.small
            animate: true
        }

        RowLayout {
            Layout.topMargin: -Tokens.padding.extraSmall
            Layout.bottomMargin: -Tokens.padding.small
            Layout.rightMargin: -Tokens.padding.extraSmall
            Layout.alignment: Qt.AlignRight
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                text: "bolt"
                color: contents.accentColour
                fontStyle: Tokens.font.icon.large
                fill: 1

                scale: contents.charging ? 1 : 0
                opacity: contents.charging ? 1 : 0

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
            }

            StyledText {
                text: `${Math.round(UPower.displayDevice.percentage * 100)}%`
                color: contents.accentColour
                font: Tokens.font.headline.medium
            }
        }
    }
}
