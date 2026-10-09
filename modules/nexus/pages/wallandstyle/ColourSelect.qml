pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Colours")
    isSubPage: true
    Component.onCompleted: Schemes.refresh()

    ColumnLayout {
        width: root.cappedWidth
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Colour schemes change panels, text and controls. Painted trees, books and tarot cards keep their original colours.")
            wrapMode: Text.WordWrap
            color: Colours.palette.m3onSurfaceVariant
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Dark theme")
            subtext: Schemes.modes.length === 1 ? qsTr("This scheme has one appearance.") : ""
            checked: !Colours.light
            enabled: !Schemes.busy && Schemes.modes.length > 1
            onToggled: Schemes.setMode(checked ? "dark" : "light")
        }

        StyledText {
            Layout.fillWidth: true
            visible: Schemes.error !== ""
            text: Schemes.error
            color: Colours.palette.m3error
            wrapMode: Text.WordWrap
        }

        StyledText {
            visible: Schemes.busy
            text: qsTr("Loading colours…")
        }

        Repeater {
            model: Schemes.entries

            RowLayout {
                id: entry
                required property var modelData
                readonly property bool selected: Colours.scheme === modelData.name && Colours.flavour === modelData.flavour
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                IconTextButton {
                    Layout.fillWidth: true
                    icon: entry.selected ? "check_circle" : "palette"
                    text: entry.modelData.name + " · " + entry.modelData.flavour
                    type: entry.selected ? IconTextButton.Filled : IconTextButton.Tonal
                    disabled: Schemes.busy
                    onClicked: Schemes.select(entry.modelData.name, entry.modelData.flavour)
                }

                Repeater {
                    model: ["surface", "primary", "secondary", "tertiary"]
                    Rectangle {
                        required property string modelData
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        color: "#" + entry.modelData.colours[modelData]
                        border.width: 1
                        border.color: Colours.palette.m3outline
                    }
                }
            }
        }
    }
}
