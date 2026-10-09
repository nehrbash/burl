import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Burl.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.bottomMargin: -Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            z: 1

            MaterialIcon {
                Layout.topMargin: Math.round(fontInfo.pointSize * 0.12)
                text: "lyrics"
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Lyrics")
                font: Tokens.font.title.medium
            }

            LyricsInfo {}
        }

        LyricList {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        SplitButton {
            Layout.alignment: Qt.AlignHCenter

            type: SplitButton.Tonal
            disabled: !Players.list.length
            active: menuItems.find(m => m.modelData === Players.active) ?? menuItems[0] ?? null
            menu.onItemSelected: item => Players.manualActive = (item as PlayerItem).modelData

            menuItems: playerList.instances
            fallbackIcon: "music_off"
            fallbackText: qsTr("No players")

            minLeftWidth: layout.width - expandBtn.implicitWidth - spacing
            label.Layout.maximumWidth: minLeftWidth - iconLabel.implicitWidth - textRow.spacing - textRow.anchors.horizontalCenterOffset / 2 - horizontalPadding * 2
            label.elide: Text.ElideRight

            stateLayer.disabled: true
            menuOnTop: true

            Variants {
                id: playerList

                model: Players.list

                PlayerItem {}
            }
        }

        SplitButton {
            Layout.alignment: Qt.AlignHCenter

            type: SplitButton.Tonal
            disabled: !Audio.outputs.length
            active: menuItems.find(m => (m as OutputItem).modelData === Audio.sink) ?? menuItems[0] ?? null
            menu.onItemSelected: item => Audio.selectOutput((item as OutputItem).modelData)

            menuItems: outputList.instances
            fallbackIcon: "volume_off"
            fallbackText: qsTr("No outputs")

            minLeftWidth: layout.width - expandBtn.implicitWidth - spacing
            label.Layout.maximumWidth: minLeftWidth - iconLabel.implicitWidth - textRow.spacing - textRow.anchors.horizontalCenterOffset / 2 - horizontalPadding * 2
            label.elide: Text.ElideRight

            stateLayer.disabled: true
            menuOnTop: true

            Variants {
                id: outputList

                model: Audio.outputs

                OutputItem {}
            }
        }
    }

    component PlayerItem: MenuItem {
        required property MprisPlayer modelData

        icon: modelData === Players.active ? "check" : ""
        text: Players.getIdentity(modelData)
        activeIcon: "animated_images"
    }

    component OutputItem: MenuItem {
        required property var modelData

        readonly property bool offline: modelData.address !== undefined

        icon: offline ? "bluetooth" : modelData === Audio.sink ? "check" : ""
        text: Audio.outputName(modelData)
        activeIcon: "speaker"
    }
}
