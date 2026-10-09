import QtQuick
import QtQuick.Layouts
import Burl.Config
import Burl.Services
import qs.components
import qs.components.controls
import qs.components.widgets
import qs.services

Item {
    id: root

    anchors.top: parent.top
    anchors.bottom: parent.bottom

    implicitWidth: layout.implicitWidth + layout.anchors.margins * 2

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    ColumnLayout {
        id: layout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        Resource {
            icon: "memory"
            value: Cpu.percentage
        }

        Resource {
            icon: "memory_alt"
            value: Memory.percentage
            fgColour: Colours.palette.m3tertiary
        }

        Resource {
            icon: "hard_disk"
            value: Storage.percentage
            fgColour: Colours.palette.m3secondary
        }
    }
    component Resource: Item {
        id: res

        required property string icon
        property alias value: progress.value
        property alias fgColour: progress.fgColour

        Layout.fillHeight: true
        implicitWidth: glyph.implicitWidth + Tokens.padding.large * 2 + progress.strokeWidth * 2
        implicitHeight: implicitWidth

        CircularProgress {
            id: progress

            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            strokeWidth: Tokens.sizes.dashboard.resourceProgressThickness

            InsetDial {
                anchors.fill: parent
                anchors.margins: -5
                visible: progress.folio
                accent: progress.fgColour
                ticks: false
                z: -1
            }

            Behavior on clampedVal {
                Anim {}
            }

            MaterialIcon {
                id: glyph

                anchors.centerIn: parent
                text: res.icon
                font: Tokens.font.icon.large
                color: progress.fgColour
            }
        }
    }
}
